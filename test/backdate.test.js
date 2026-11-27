import { test } from 'node:test';
import assert from 'node:assert/strict';
import { rng, spreadDates, shuffle, weeks } from '../src/lib/backdate.js';

const FROM = Date.parse('2024-01-01T00:00:00Z');
const TO = Date.parse('2026-02-01T00:00:00Z');

test('spreadDates: every date in range, even per week, same seed same dates', () => {
  const a = spreadDates(4141, FROM, TO, rng(1));
  const b = spreadDates(4141, FROM, TO, rng(1));
  assert.deepEqual(a, b);
  assert.equal(a.length, 4141);
  assert.ok(a.every((d) => d >= FROM && d < TO));
  const ws = weeks(FROM, TO);
  const counts = ws.map((w) => a.filter((d) => d >= w.start && d < w.end).length);
  const full = counts.slice(0, -1);
  assert.ok(Math.max(...full) - Math.min(...full) <= 1, `full weeks ${Math.min(...full)}..${Math.max(...full)}`);
  assert.ok(counts.at(-1) <= Math.max(...full));
  assert.equal(counts.reduce((x, y) => x + y, 0), 4141);
});

test('shuffle keeps every element', () => {
  const s = shuffle([1, 2, 3, 4, 5], rng(2));
  assert.deepEqual([...s].sort(), [1, 2, 3, 4, 5]);
});
