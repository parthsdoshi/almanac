import assert from 'node:assert/strict';
import { test } from 'node:test';
import { headline, joinNames, pushToStartPayload } from '../src/payload.js';

test('names join like the app', () => {
  assert.equal(joinNames(['Priya']), 'Priya');
  assert.equal(joinNames(['Alex', 'Sam']), 'Alex & Sam');
  assert.equal(joinNames(['A', 'B', 'C']), 'A, B & C');
  assert.equal(headline('anniversary', ['Alex', 'Sam']), "Alex & Sam's anniversary");
});

test('push-to-start payload matches OccasionAttributes', () => {
  const now = new Date('2026-11-04T14:00:00Z');
  const p = pushToStartPayload({ id: 'abcdabcdabcdabcd', kind: 'birthday', names: ['Priya'], month: 11, day: 4 }, { now });
  assert.deepEqual(p, {
    aps: {
      timestamp: 1793800800,
      event: 'start',
      'attributes-type': 'OccasionAttributes',
      attributes: { occasionID: 'abcdabcdabcdabcd', kind: 'birthday', names: ['Priya'] },
      'content-state': { headline: "Priya's birthday" },
      alert: { title: "Priya's birthday", body: 'Wish Priya a happy birthday.' },
    },
  });
});
