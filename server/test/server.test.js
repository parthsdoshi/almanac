import assert from 'node:assert/strict';
import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { tick } from '../src/scheduler.js';
import { createServer } from '../src/server.js';
import { JsonStore } from '../src/store.js';

const API_KEY = 'test-key-0123456789abcdef';
const quiet = { info() {}, warn() {}, error() {} };
let server, base, store, file;

const body = {
  pushToStartToken: 'ab'.repeat(32),
  apnsEnvironment: 'development',
  timeZone: 'America/New_York',
  sendHour: 9,
  occasions: [
    { id: 'abcdabcdabcdabcd', kind: 'birthday', names: ['Priya'], month: 11, day: 4, lastName: 'Shah', year: 1990 },
  ],
  phone: '+15551234567',
};

before(async () => {
  file = join(await mkdtemp(join(tmpdir(), 'occasions-')), 'state.json');
  store = await new JsonStore(file).load();
  server = createServer({ store, apiKey: API_KEY, apns: null, log: quiet });
  await new Promise((r) => server.listen(0, r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

const put = (id, payload, key = API_KEY) => fetch(`${base}/v1/devices/${id}`, {
  method: 'PUT',
  headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
  body: JSON.stringify(payload),
});

test('health check is open', async () => {
  assert.equal((await fetch(`${base}/healthz`)).status, 200);
});

test('rejects a wrong key', async () => {
  assert.equal((await put('device-123', body, 'nope')).status, 401);
});

test('stores only first names and dates, persisted to disk', async () => {
  assert.equal((await put('device-123', body)).status, 204);
  const saved = JSON.parse(await readFile(file, 'utf8')).devices['device-123'];
  assert.deepEqual(saved.occasions, [{ id: 'abcdabcdabcdabcd', kind: 'birthday', names: ['Priya'], month: 11, day: 4 }]);
  assert.equal(saved.phone, undefined);
});

test('validates input', async () => {
  assert.equal((await put('device-123', { ...body, timeZone: 'Mars/Base' })).status, 400);
  assert.equal((await put('device-123', { ...body, sendHour: 25 })).status, 400);
  assert.equal((await put('device-123', { ...body, occasions: [{ ...body.occasions[0], names: [] }] })).status, 400);
});

test('test push needs APNs configured', async () => {
  const res = await fetch(`${base}/v1/devices/device-123/test`, { method: 'POST', headers: { authorization: `Bearer ${API_KEY}` } });
  assert.equal(res.status, 503);
});

test('tick sends once per day and marks dead tokens', async () => {
  const sent = [];
  const apns = { send: async (args) => { sent.push(args); return { status: 200 }; } };
  const now = new Date('2026-11-04T14:30:00Z');
  await tick({ store, apns, now, log: quiet });
  await tick({ store, apns, now, log: quiet });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].env, 'development');
  assert.equal(sent[0].payload.aps.attributes.names[0], 'Priya');
  assert.equal(store.device('device-123').sent.abcdabcdabcdabcd, '2026-11-04');

  const dead = { send: async () => ({ status: 410, reason: 'Unregistered' }) };
  await tick({ store, apns: dead, now: new Date('2027-11-04T14:30:00Z'), log: quiet });
  assert.equal(store.device('device-123').tokenInvalid, true);
  // A fresh sync clears it.
  await put('device-123', body);
  assert.equal(store.device('device-123').tokenInvalid, false);
});

test('delete removes the device', async () => {
  const res = await fetch(`${base}/v1/devices/device-123`, { method: 'DELETE', headers: { authorization: `Bearer ${API_KEY}` } });
  assert.equal(res.status, 204);
  assert.equal(store.device('device-123'), undefined);
});
