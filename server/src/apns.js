import { sign } from 'node:crypto';
import http2 from 'node:http2';

const HOSTS = {
  production: 'https://api.push.apple.com',
  development: 'https://api.sandbox.push.apple.com',
};

const b64url = (buf) => Buffer.from(buf).toString('base64url');

/** ES256 provider token for APNs token-based auth. */
export function makeJwt({ keyId, teamId, privateKey }, nowMs = Date.now()) {
  const header = b64url(JSON.stringify({ alg: 'ES256', kid: keyId }));
  const claims = b64url(JSON.stringify({ iss: teamId, iat: Math.floor(nowMs / 1000) }));
  const signature = sign('sha256', Buffer.from(`${header}.${claims}`), {
    key: privateKey,
    dsaEncoding: 'ieee-p1363', // JWT wants raw r||s, not DER
  });
  return `${header}.${claims}.${b64url(signature)}`;
}

/**
 * Sends with the device's reported APNs environment, and if Apple says the
 * token belongs to the other one (BadDeviceToken), retries there. Returns the
 * environment that worked so the caller can remember it.
 */
export async function sendWithFallback(apns, { deviceToken, env, payload, expiration }) {
  const res = await apns.send({ deviceToken, env, payload, expiration });
  if (res.status === 400 && res.reason === 'BadDeviceToken') {
    const other = env === 'development' ? 'production' : 'development';
    const retry = await apns.send({ deviceToken, env: other, payload, expiration });
    if (retry.status === 200) return { ...retry, env: other };
  }
  return { ...res, env };
}

export class ApnsClient {
  #jwt = null;
  #jwtAt = 0;
  #sessions = new Map();

  constructor({ keyId, teamId, privateKey, bundleId }) {
    this.creds = { keyId, teamId, privateKey };
    this.bundleId = bundleId;
  }

  // Apple rejects tokens older than an hour and throttles refreshes more often
  // than every 20 minutes, so reuse one for 50.
  #token() {
    const now = Date.now();
    if (!this.#jwt || now - this.#jwtAt > 50 * 60 * 1000) {
      this.#jwt = makeJwt(this.creds, now);
      this.#jwtAt = now;
    }
    return this.#jwt;
  }

  #session(env) {
    const host = HOSTS[env] ?? HOSTS.production;
    let session = this.#sessions.get(host);
    if (!session || session.closed || session.destroyed) {
      session = http2.connect(host);
      session.on('error', () => this.#sessions.delete(host));
      session.on('goaway', () => this.#sessions.delete(host));
      session.on('close', () => this.#sessions.delete(host));
      session.unref();
      this.#sessions.set(host, session);
    }
    return session;
  }

  /**
   * Sends a Live Activity push. Resolves with { status, reason }; rejects only
   * on network errors.
   */
  send({ deviceToken, env, payload, expiration }) {
    return new Promise((resolve, reject) => {
      const req = this.#session(env).request({
        ':method': 'POST',
        ':path': `/3/device/${deviceToken}`,
        authorization: `bearer ${this.#token()}`,
        'apns-push-type': 'liveactivity',
        'apns-topic': `${this.bundleId}.push-type.liveactivity`,
        'apns-priority': '10',
        ...(expiration ? { 'apns-expiration': String(expiration) } : {}),
        'content-type': 'application/json',
      });
      let status = 0;
      let body = '';
      req.setEncoding('utf8');
      req.on('response', (headers) => { status = headers[':status']; });
      req.on('data', (chunk) => { body += chunk; });
      req.on('end', () => {
        let reason;
        try { reason = body ? JSON.parse(body).reason : undefined; } catch { reason = body; }
        resolve({ status, reason });
      });
      req.on('error', reject);
      req.setTimeout(15_000, () => req.close(http2.constants.NGHTTP2_CANCEL));
      req.end(JSON.stringify(payload));
    });
  }

  close() {
    for (const s of this.#sessions.values()) s.close();
    this.#sessions.clear();
  }
}
