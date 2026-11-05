import assert from 'node:assert/strict';
import { test } from 'node:test';
import { dueOccasions, endOfLocalDay, localParts, observedDay } from '../src/schedule.js';

const device = (overrides = {}) => ({
  timeZone: 'America/New_York',
  sendHour: 9,
  occasions: [
    { id: 'aaaaaaaaaaaaaaaa', kind: 'birthday', names: ['Priya'], month: 11, day: 4 },
    { id: 'bbbbbbbbbbbbbbbb', kind: 'birthday', names: ['Sam'], month: 11, day: 5 },
  ],
  sent: {},
  ...overrides,
});

test('nothing before the local send hour', () => {
  // 08:30 in New York
  const r = dueOccasions(device(), new Date('2026-11-04T13:30:00Z'));
  assert.deepEqual(r.due, []);
});

test("today's occasions after the send hour", () => {
  const r = dueOccasions(device(), new Date('2026-11-04T14:05:00Z')); // 09:05 NY
  assert.equal(r.localDate, '2026-11-04');
  assert.deepEqual(r.due.map((o) => o.id), ['aaaaaaaaaaaaaaaa']);
});

test('already sent today is skipped, last year is not', () => {
  const now = new Date('2026-11-04T15:00:00Z');
  assert.deepEqual(dueOccasions(device({ sent: { aaaaaaaaaaaaaaaa: '2026-11-04' } }), now).due, []);
  assert.equal(dueOccasions(device({ sent: { aaaaaaaaaaaaaaaa: '2025-11-04' } }), now).due.length, 1);
});

test('uses the phone time zone, so travel works', () => {
  // 14:05Z is 19:35 on Nov 4 in Mumbai: due. 04:00Z on Nov 5 is 09:30 Nov 5 in Mumbai.
  const mumbai = device({ timeZone: 'Asia/Kolkata' });
  assert.equal(dueOccasions(mumbai, new Date('2026-11-04T14:05:00Z')).due[0].id, 'aaaaaaaaaaaaaaaa');
  assert.equal(dueOccasions(mumbai, new Date('2026-11-05T04:00:00Z')).due[0].id, 'bbbbbbbbbbbbbbbb');
});

test('does not start late at night after an outage', () => {
  assert.deepEqual(dueOccasions(device(), new Date('2026-11-05T02:30:00Z')).due, []); // 21:30 NY
});

test('Feb 29 is observed on Feb 28 in non-leap years', () => {
  assert.equal(observedDay(2, 29, 2027), 28);
  assert.equal(observedDay(2, 29, 2028), 29);
  assert.equal(observedDay(4, 31, 2027), 30);
  const leap = device({ occasions: [{ id: 'cccccccccccccccc', kind: 'birthday', names: ['Jo'], month: 2, day: 29 }] });
  assert.equal(dueOccasions(leap, new Date('2027-02-28T15:00:00Z')).due.length, 1);
});

test('end of local day', () => {
  const now = new Date('2026-11-04T14:00:00Z'); // 09:00:00 NY
  assert.equal(endOfLocalDay(now, 'America/New_York') - now.getTime() / 1000, 15 * 3600);
  assert.equal(localParts(now, 'America/New_York').hour, 9);
});
