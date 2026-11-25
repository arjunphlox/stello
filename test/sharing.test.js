import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { Hono } from 'hono';
import { makeD1, SCHEMA } from './d1-shim.js';
import { pullChanges, applyChanges, mergeChange } from '../src/lib/sync.js';
import {
  normalizeSharing, mergeSharing, isVisible, visibleAudienceIds, viewerLocation, cleanFilter,
  linkToken, DEFAULT_AUDIENCES,
} from '../src/lib/sharing.js';
import mountSharing, { resolveLink } from '../src/routes/sharing.js';

const A = '11111111-1111-4111-8111-111111111111';
const B = '22222222-2222-4222-8222-222222222222';
const SHARING_SQL = readFileSync(new URL('../migrations/0003_sharing.sql', import.meta.url), 'utf8');
const FULL_SCHEMA = SCHEMA + `
CREATE TABLE user_settings (user_id TEXT NOT NULL, setting_key TEXT NOT NULL, setting_value TEXT NOT NULL, PRIMARY KEY (user_id, setting_key));
` + SHARING_SQL;

function makeApp(userId = 'u1') {
  const db = makeD1(FULL_SCHEMA);
  const app = new Hono();
  mountSharing(app, { requireUser: async () => userId });
  const env = { DB: db, SHARE_SECRET: 'test-secret' };
  const call = async (method, path, body) => {
    const res = await app.request(`https://stello.test${path}`, {
      method, headers: { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body),
    }, env);
    return { status: res.status, json: await res.json() };
  };
  return { db, env, call };
}

// ---------------------------------------------------------------- rules

test('every account starts with the four default circles at clock 0', () => {
  const s = normalizeSharing(null);
  assert.deepEqual(s.audiences.map((a) => a.id), DEFAULT_AUDIENCES.map((a) => a.id));
  assert.equal(s.audiences[0].clock.name, 0);
  assert.deepEqual(s.private_places, { value: [], clock: 0 });
});

test('audience fields merge last-write-wins, ties keep the server value', () => {
  let { sharing } = mergeSharing(null, { audiences: [{ id: 'family', name: 'Fam', clock: 100 }] }, 1000);
  assert.equal(sharing.audiences.find((a) => a.id === 'family').name, 'Fam');
  ({ sharing } = mergeSharing(sharing, { audiences: [{ id: 'family', name: 'Older', clock: 50 }] }, 1000));
  assert.equal(sharing.audiences.find((a) => a.id === 'family').name, 'Fam');
  const tie = mergeSharing(sharing, { audiences: [{ id: 'family', name: 'Tie', clock: 100 }] }, 1000);
  assert.equal(tie.changed, false);
});

test('a new list is created with a fixed kind; lists never take a rank', () => {
  const { sharing } = mergeSharing(null, { audiences: [{ id: 'japan-trip', kind: 'list', name: 'Japan trip', rank: 1, location: 'city' }] });
  const a = sharing.audiences.find((x) => x.id === 'japan-trip');
  assert.equal(a.kind, 'list');
  assert.equal(a.rank, null);
  assert.equal(a.location, 'city');
});

test('future clocks are clamped to now + 5 minutes', () => {
  const now = 1_000_000;
  const { sharing } = mergeSharing(null, { audiences: [{ id: 'public', name: 'Everyone', clock: now * 10 }] }, now);
  assert.equal(sharing.audiences.find((a) => a.id === 'public').clock.name, now + 5 * 60 * 1000);
});

test('circles nest: inner circles see outer items, lists only see themselves', () => {
  const { sharing } = mergeSharing(null, { audiences: [{ id: 'trip', kind: 'list', name: 'Trip' }] });
  assert.equal(isVisible(['close-friends'], 'family', sharing), true);
  assert.equal(isVisible(['close-friends'], 'close-friends', sharing), true);
  assert.equal(isVisible(['close-friends'], 'acquaintances', sharing), false);
  assert.equal(isVisible(['public'], 'acquaintances', sharing), true);
  assert.equal(isVisible(['trip'], 'family', sharing), false);
  assert.equal(isVisible(['trip'], 'trip', sharing), true);
  assert.equal(isVisible(['public'], 'trip', sharing), false);
  assert.equal(isVisible([], 'public', sharing), false);
  assert.deepEqual(visibleAudienceIds('close-friends', sharing).sort(), ['acquaintances', 'close-friends', 'public']);
  assert.deepEqual(visibleAudienceIds('trip', sharing), ['trip']);
});

test('a deleted audience shares nothing, even if items still list it', () => {
  const { sharing } = mergeSharing(null, { audiences: [{ id: 'public', deleted_at: 5 }] });
  assert.equal(isVisible(['public'], 'public', sharing), false);
  assert.equal(isVisible(['public'], 'family', sharing), false);
  assert.deepEqual(visibleAudienceIds('public', sharing), []);
});

test('location precision and private places', () => {
  const home = [{ name: 'Home', words: ['sukhumvit 31'] }];
  const loc = 'Blue Tokai, Indiranagar, Bengaluru, India';
  assert.equal(viewerLocation(loc, 'exact'), loc);
  assert.equal(viewerLocation(loc, 'city'), 'Bengaluru, India');
  assert.equal(viewerLocation(loc, 'hidden'), null);
  assert.equal(viewerLocation('Condo, Sukhumvit 31, Bangkok, Thailand', 'exact', home), null);
  assert.equal(viewerLocation(null, 'exact'), null);
});

test('filters keep only known keys and sane values', () => {
  assert.deepEqual(cleanFilter({ kinds: ['Book', 3], tags: ['Japan'], from: '2026-01-01', to: 'nope', evil: 1 }),
    { kinds: ['book'], tags: ['japan'], from: '2026-01-01' });
});

test('tokens are 22 url-safe chars, stable per version, different after rotate', async () => {
  const t1 = await linkToken('s', 'id-1', 1);
  assert.match(t1, /^[A-Za-z0-9_-]{22}$/);
  assert.equal(await linkToken('s', 'id-1', 1), t1);
  assert.notEqual(await linkToken('s', 'id-1', 2), t1);
  assert.notEqual(await linkToken('other', 'id-1', 1), t1);
});

// ---------------------------------------------------------------- items.audiences sync field

test('items.audiences syncs as a sorted, de-duplicated id list with its own clock', async () => {
  const db = makeD1(SCHEMA);
  await applyChanges(db, 'u1', [{ id: A, full: true, fields: { title: 'x', audiences: ['public', 'Family', 'family'] }, clock: 100 }]);
  let [item] = (await pullChanges(db, 'u1', 0)).items;
  assert.deepEqual(item.audiences, ['family', 'public']);
  assert.equal(item.clock.audiences, 100);
  // A tag edit does not touch audiences, and vice versa.
  await applyChanges(db, 'u1', [{ id: A, fields: { tags: [{ name: 'a', category: 'style' }] }, clock: 200 }]);
  [item] = (await pullChanges(db, 'u1', 0)).items;
  assert.deepEqual(item.audiences, ['family', 'public']);
  // Same set in another order is an echo.
  const before = item.seq;
  await applyChanges(db, 'u1', [{ id: A, fields: { audiences: ['public', 'family'] }, clock: 300 }]);
  [item] = (await pullChanges(db, 'u1', 0)).items;
  assert.equal(item.seq, before);
});

test('items.audiences rejects anything but a short list of ids', () => {
  const row = { id: A, seq: 1, field_clock: '{}', audiences: '[]', purged_at: null };
  assert.equal(mergeChange(row, { id: A, fields: { audiences: 'family' }, clock: 5 }).status, 'unchanged');
  assert.equal(mergeChange(row, { id: A, fields: { audiences: ['bad id!'] }, clock: 5 }).status, 'unchanged');
  assert.equal(mergeChange(row, { id: A, fields: { audiences: [] }, clock: 5 }).status, 'unchanged');
  assert.equal(mergeChange(row, { id: A, fields: { audiences: ['family'] }, clock: 5 }).status, 'applied');
});

test('older rows without the field read as private', async () => {
  const db = makeD1(SCHEMA);
  await applyChanges(db, 'u1', [{ id: A, full: true, fields: { title: 'x' }, clock: 1 }]);
  const [item] = (await pullChanges(db, 'u1', 0)).items;
  assert.deepEqual(item.audiences, []);
});

// ---------------------------------------------------------------- routes

test('GET/PUT /api/me/sharing round-trips audiences and private places', async () => {
  const { call } = makeApp();
  let r = await call('GET', '/api/me/sharing');
  assert.equal(r.status, 200);
  assert.equal(r.json.audiences.length, 4);
  r = await call('PUT', '/api/me/sharing', {
    audiences: [{ id: 'japan-trip', kind: 'list', name: 'Japan trip', location: 'city' }],
    private_places: { value: [{ name: 'Home', words: ['Sukhumvit 31'] }] },
  });
  assert.equal(r.status, 200);
  r = await call('GET', '/api/me/sharing');
  assert.ok(r.json.audiences.find((a) => a.id === 'japan-trip'));
  assert.deepEqual(r.json.private_places.value[0].words, ['sukhumvit 31']);
});

test('POST /api/me/sharing/items sets audiences through the sync merge', async () => {
  const { db, call } = makeApp();
  await applyChanges(db, 'u1', [A, B].map((id) => ({ id, full: true, fields: { title: id }, clock: 1 })));
  let r = await call('POST', '/api/me/sharing/items', { ids: [A, B], audiences: ['close-friends'] });
  assert.equal(r.status, 200);
  assert.deepEqual(r.json.results.map((x) => x.status), ['applied', 'applied']);
  const { items } = await pullChanges(db, 'u1', 0);
  assert.deepEqual(items.map((i) => i.audiences), [['close-friends'], ['close-friends']]);
  r = await call('POST', '/api/me/sharing/items', { ids: [A], audiences: ['family', 'public'] });
  assert.equal(r.status, 400, 'two circles');
  r = await call('POST', '/api/me/sharing/items', { ids: [A], audiences: ['nope'] });
  assert.equal(r.status, 400, 'unknown audience');
  r = await call('POST', '/api/me/sharing/items', { ids: [A], audiences: [] });
  assert.equal(r.status, 200, 'back to private');
});

test('share links: create, copy again, rotate, revoke, expire', async () => {
  const { env, call } = makeApp();
  let r = await call('POST', '/api/share-links', { audience_id: 'family', filter: { tags: ['Japan'] } });
  assert.equal(r.status, 201);
  const link = r.json;
  assert.equal(link.label, 'Family');
  assert.deepEqual(link.filter, { tags: ['japan'] });
  assert.match(link.url, /^https:\/\/stello\.test\/s\/[A-Za-z0-9_-]{22}$/);
  const token = link.url.split('/s/')[1];
  assert.equal((await resolveLink(env, token)).id, link.id);

  r = await call('GET', '/api/share-links');
  assert.equal(r.json.links[0].url, link.url, 'the same url can be copied again');

  r = await call('PATCH', `/api/share-links/${link.id}`, { rotate: true, label: 'Family, Japan' });
  const rotated = r.json.url.split('/s/')[1];
  assert.notEqual(rotated, token);
  assert.equal(await resolveLink(env, token), null, 'old url stops working');
  assert.equal((await resolveLink(env, rotated)).label, 'Family, Japan');

  r = await call('PATCH', `/api/share-links/${link.id}`, { expires_at: Date.now() - 1 });
  assert.equal(r.json.active, false);
  assert.equal(await resolveLink(env, rotated), null, 'expired');
  await call('PATCH', `/api/share-links/${link.id}`, { expires_at: null });
  assert.ok(await resolveLink(env, rotated));

  r = await call('DELETE', `/api/share-links/${link.id}`);
  assert.equal(r.json.active, false);
  assert.equal(await resolveLink(env, rotated), null, 'revoked');

  r = await call('POST', '/api/share-links', { audience_id: 'nope' });
  assert.equal(r.status, 400);
});

test('deleting an audience revokes its links', async () => {
  const { env, call } = makeApp();
  const { json: link } = await call('POST', '/api/share-links', { audience_id: 'public' });
  await call('PUT', '/api/me/sharing', { audiences: [{ id: 'public', deleted_at: Date.now() }] });
  assert.equal(await resolveLink(env, link.url.split('/s/')[1]), null);
});

test("links are per user: another account can't read or change them", async () => {
  const one = makeApp('u1');
  const { json: link } = await one.call('POST', '/api/share-links', { audience_id: 'family' });
  const app = new Hono();
  mountSharing(app, { requireUser: async () => 'u2' });
  const res = await app.request(`https://stello.test/api/share-links/${link.id}`, { method: 'DELETE' }, one.env);
  assert.equal(res.status, 404);
});
