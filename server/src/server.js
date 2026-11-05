import { createHash, timingSafeEqual } from 'node:crypto';
import http from 'node:http';
import { sendWithFallback } from './apns.js';
import { pushToStartPayload } from './payload.js';
import { endOfLocalDay, isValidTimeZone } from './schedule.js';

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const DEVICE_PATH = /^\/v1\/devices\/([A-Za-z0-9-]{8,64})(\/test)?$/;

/**
 * Keeps only what the server needs: push token, time zone, send hour, and per
 * occasion an opaque id, kind, first names and month/day. Anything else the
 * client sends is dropped.
 */
export function validateDevice(body) {
  const fail = (msg) => { throw new HttpError(400, msg); };
  if (!body || typeof body !== 'object') fail('body must be an object');

  const { pushToStartToken, apnsEnvironment, timeZone, sendHour, occasions } = body;
  if (typeof pushToStartToken !== 'string' || !/^[0-9a-f]{32,512}$/i.test(pushToStartToken)) fail('bad pushToStartToken');
  if (!['development', 'production'].includes(apnsEnvironment)) fail('bad apnsEnvironment');
  if (typeof timeZone !== 'string' || !isValidTimeZone(timeZone)) fail('bad timeZone');
  if (!Number.isInteger(sendHour) || sendHour < 0 || sendHour > 23) fail('bad sendHour');
  if (!Array.isArray(occasions) || occasions.length > 2000) fail('bad occasions');

  return {
    pushToStartToken: pushToStartToken.toLowerCase(),
    apnsEnvironment,
    timeZone,
    sendHour,
    occasions: occasions.map((o, i) => {
      const where = `occasions[${i}]`;
      if (!o || typeof o !== 'object') fail(`${where} must be an object`);
      if (typeof o.id !== 'string' || !/^[0-9a-f]{8,64}$/.test(o.id)) fail(`${where}.id`);
      if (!['birthday', 'anniversary'].includes(o.kind)) fail(`${where}.kind`);
      if (!Array.isArray(o.names) || o.names.length < 1 || o.names.length > 4
        || !o.names.every((n) => typeof n === 'string' && n.trim().length > 0 && n.length <= 40)) fail(`${where}.names`);
      if (!Number.isInteger(o.month) || o.month < 1 || o.month > 12) fail(`${where}.month`);
      if (!Number.isInteger(o.day) || o.day < 1 || o.day > 31) fail(`${where}.day`);
      return { id: o.id, kind: o.kind, names: o.names.map((n) => n.trim()), month: o.month, day: o.day };
    }),
  };
}

function isAuthorized(req, apiKey) {
  const header = req.headers.authorization ?? '';
  const given = header.startsWith('Bearer ') ? header.slice(7) : '';
  // Hash both sides so the comparison is constant-time regardless of length.
  const a = createHash('sha256').update(given).digest();
  const b = createHash('sha256').update(apiKey).digest();
  return given.length > 0 && timingSafeEqual(a, b);
}

async function readJson(req, limit = 256 * 1024) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limit) throw new HttpError(413, 'body too large');
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new HttpError(400, 'invalid JSON');
  }
}

function send(res, status, body) {
  if (body === undefined) {
    res.writeHead(status).end();
  } else {
    res.writeHead(status, { 'content-type': 'application/json' }).end(JSON.stringify(body));
  }
}

export function createServer({ store, apiKey, apns, log = console }) {
  return http.createServer(async (req, res) => {
    try {
      const { pathname } = new URL(req.url, 'http://localhost');
      if (req.method === 'GET' && pathname === '/healthz') return send(res, 200, { ok: true });

      const match = pathname.match(DEVICE_PATH);
      if (!match) throw new HttpError(404, 'not found');
      if (!isAuthorized(req, apiKey)) throw new HttpError(401, 'unauthorized');
      const [, deviceId, isTest] = match;

      if (isTest) {
        if (req.method !== 'POST') throw new HttpError(405, 'method not allowed');
        return await sendTest({ store, apns, deviceId, res });
      }

      if (req.method === 'PUT') {
        const device = validateDevice(await readJson(req));
        await store.mutate((d) => {
          const previous = d.devices[deviceId];
          d.devices[deviceId] = {
            ...device,
            sent: previous?.sent ?? {},
            tokenInvalid: false,
            updatedAt: new Date().toISOString(),
          };
        });
        log.info(`device ${deviceId}: synced ${device.occasions.length} occasions`);
        return send(res, 204);
      }

      if (req.method === 'DELETE') {
        await store.mutate((d) => { delete d.devices[deviceId]; });
        return send(res, 204);
      }

      throw new HttpError(405, 'method not allowed');
    } catch (err) {
      if (err instanceof HttpError) return send(res, err.status, { error: err.message });
      log.error(err);
      return send(res, 500, { error: 'internal error' });
    }
  });
}

/** Push-starts a Live Activity right now, for checking the whole setup end to end. */
async function sendTest({ store, apns, deviceId, res }) {
  if (!apns) throw new HttpError(503, 'APNs is not configured on the server');
  const device = store.device(deviceId);
  if (!device) throw new HttpError(404, 'device not registered yet');
  const occasion = device.occasions[0] ?? { id: '0000000000000000', kind: 'birthday', names: ['Test'] };
  const now = new Date();
  const result = await sendWithFallback(apns, {
    deviceToken: device.pushToStartToken,
    env: device.apnsEnvironment,
    payload: pushToStartPayload(occasion, { now }),
    expiration: endOfLocalDay(now, device.timeZone),
  });
  if (result.status !== 200) throw new HttpError(502, `APNs said ${result.status} ${result.reason ?? ''}`.trim());
  if (result.env !== device.apnsEnvironment) {
    await store.mutate((d) => { if (d.devices[deviceId]) d.devices[deviceId].apnsEnvironment = result.env; });
  }
  return send(res, 200, { ok: true });
}
