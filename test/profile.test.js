import { test } from 'node:test';
import assert from 'node:assert/strict';
import profileLib from '../src/lib/profile.js';

const { mergeProfile, normalize, MAX_FUTURE_MS } = profileLib;

test('a profile saved before clocks existed loses to any dated write', () => {
  const old = { name: 'Web name', designation: 'Web role', avatar_path: '/img/a.webp' };
  const { profile, changed } = mergeProfile(old, { name: 'Mac name' }, { name: 1 }, 1000);
  assert.equal(changed, true);
  assert.equal(profile.name, 'Mac name');
  assert.equal(profile.designation, 'Web role');
  assert.deepEqual(profile.clock, { name: 1, designation: 0, avatar: 0 });
});

test('per field, the newer edit wins and ties keep the server value', () => {
  const cur = normalize({ name: 'A', designation: 'D', clock: { name: 500, designation: 500, avatar: 0 } });
  let r = mergeProfile(cur, { name: 'older', designation: 'newer' }, { name: 400, designation: 600 }, 1000);
  assert.equal(r.profile.name, 'A');
  assert.equal(r.profile.designation, 'newer');
  r = mergeProfile(r.profile, { name: 'tie' }, { name: 500 }, 1000);
  assert.equal(r.changed, false);
  assert.equal(r.profile.name, 'A');
});

test('a write with no clock counts as now (the web)', () => {
  const cur = normalize({ name: 'A', clock: { name: 500 } });
  const { profile } = mergeProfile(cur, { name: '  B  ' }, undefined, 9000);
  assert.equal(profile.name, 'B');
  assert.equal(profile.clock.name, 9000);
});

test('future clocks are clamped; text is trimmed to 80 characters', () => {
  const { profile } = mergeProfile({}, { name: 'x'.repeat(100) }, { name: 10 ** 15 }, 1000);
  assert.equal(profile.name.length, 80);
  assert.equal(profile.clock.name, 1000 + MAX_FUTURE_MS);
});

test('photo: newer removal clears it, older upload is ignored', () => {
  const cur = normalize({ avatar_path: '/img/new.webp', clock: { avatar: 800 } });
  let r = mergeProfile(cur, { avatar_path: '/img/old.webp' }, { avatar: 700 }, 1000);
  assert.equal(r.changed, false);
  r = mergeProfile(cur, { avatar_path: null }, { avatar: 900 }, 1000);
  assert.equal(r.profile.avatar_path, null);
  assert.equal(r.profile.clock.avatar, 900);
});
