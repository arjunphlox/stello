/**
 * Spread a set of items over a date range with about the same number per week, each at a
 * random moment inside its week. Used to back-date a bulk import (scripts/backdate-import.mjs)
 * so it sits under the real recent saves instead of on top of them.
 */

const DAY = 24 * 60 * 60 * 1000;
const WEEK = 7 * DAY;

/** Seeded PRNG (mulberry32), so a plan run and the apply run give the same dates. */
export function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * 7-day buckets from `from` (inclusive) to `to` (exclusive), epoch ms. The last one may be shorter.
 * Returns [{ start, end }].
 */
export function weeks(from, to) {
  const out = [];
  for (let s = from; s < to; s += WEEK) out.push({ start: s, end: Math.min(s + WEEK, to) });
  return out;
}

/**
 * n dates (epoch ms), sorted, spread so each week holds a share of n in step with its length
 * (a full week ~n/weeks, a short last week fewer). Counts per week differ by at most one
 * for equal-length weeks. Each date is uniform inside its week.
 */
export function spreadDates(n, from, to, random) {
  const buckets = weeks(from, to);
  const total = to - from;
  // Largest-remainder split of n by bucket length.
  const exact = buckets.map((b) => (n * (b.end - b.start)) / total);
  const counts = exact.map(Math.floor);
  let left = n - counts.reduce((a, b) => a + b, 0);
  const order = exact.map((x, i) => [x - Math.floor(x), random(), i]).sort((a, b) => b[0] - a[0] || a[1] - b[1]);
  for (let k = 0; left > 0; k++, left--) counts[order[k % order.length][2]]++;
  const dates = [];
  buckets.forEach((b, i) => {
    for (let k = 0; k < counts[i]; k++) dates.push(b.start + Math.floor(random() * (b.end - b.start)));
  });
  return dates.sort((a, b) => a - b);
}

/** Fisher-Yates shuffle (copy). */
export function shuffle(list, random) {
  const a = [...list];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}
