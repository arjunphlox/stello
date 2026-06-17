#!/usr/bin/env node
/**
 * Stello — assemble the static-assets dir for Cloudflare Workers.
 *
 * The repo root doubles as a knowledge-base (dozens of topic .md files +
 * directories) and holds tooling (api/, scripts/, commands/, .claude/).
 * None of that should be served. This copies ONLY the frontend allowlist
 * into dist/, which wrangler.jsonc points `assets.directory` at.
 *
 * Allowlist over denylist on purpose: the content set at root grows, an
 * allowlist can't accidentally leak a new note file.
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const DIST = path.join(ROOT, 'dist');

const FILES = [
  'index.html',
  'detail.html',
  'login.html',
  'reset-password.html',
  'app.js',
  'desktop-context.js',
  'supabase-client.js',
  'style.css',
  'theme.css',
  'version.json',
];
const DIRS = ['fonts', 'icons'];

fs.rmSync(DIST, { recursive: true, force: true });
fs.mkdirSync(DIST, { recursive: true });

let copied = 0;
for (const f of FILES) {
  const src = path.join(ROOT, f);
  if (fs.existsSync(src)) { fs.copyFileSync(src, path.join(DIST, f)); copied++; }
  else console.warn('[build-assets] missing (skipped):', f);
}
for (const d of DIRS) {
  const src = path.join(ROOT, d);
  if (fs.existsSync(src)) { fs.cpSync(src, path.join(DIST, d), { recursive: true }); copied++; }
}

console.log(`[build-assets] dist/ ready — ${copied} entries copied`);
