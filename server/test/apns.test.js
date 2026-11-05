import assert from 'node:assert/strict';
import { generateKeyPairSync, verify } from 'node:crypto';
import { test } from 'node:test';
import { makeJwt } from '../src/apns.js';

test('JWT is ES256 with raw signature and the right claims', () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });
  const jwt = makeJwt({ keyId: 'KEY1234567', teamId: 'TEAM123456', privateKey: pem }, 1_700_000_000_000);
  const [h, c, s] = jwt.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(h, 'base64url')), { alg: 'ES256', kid: 'KEY1234567' });
  assert.deepEqual(JSON.parse(Buffer.from(c, 'base64url')), { iss: 'TEAM123456', iat: 1_700_000_000 });
  const sig = Buffer.from(s, 'base64url');
  assert.equal(sig.length, 64);
  assert.ok(verify('sha256', Buffer.from(`${h}.${c}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, sig));
});

test('retries the other APNs environment on BadDeviceToken', async () => {
  const { sendWithFallback } = await import('../src/apns.js');
  const calls = [];
  const apns = {
    send: async ({ env }) => {
      calls.push(env);
      return env === 'production' ? { status: 400, reason: 'BadDeviceToken' } : { status: 200 };
    },
  };
  const res = await sendWithFallback(apns, { deviceToken: 'ab', env: 'production', payload: {} });
  assert.deepEqual(calls, ['production', 'development']);
  assert.equal(res.status, 200);
  assert.equal(res.env, 'development');
});
