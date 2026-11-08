// Shared helpers for the page-reader tests (ported from the Mac app's StelloTests).
import assert from 'node:assert/strict';
import { classify as classifyPage } from '../src/lib/readers/classifier.js';

/** Swift `==` on optionals: undefined and null are both nil. */
export function eq(actual, expected, msg) {
  assert.deepEqual(actual ?? null, expected ?? null, msg);
}

/** The StelloTests `classify(_:html:ogType:labels:)` helper. */
export function classify(url, { html = '<html><head></head><body></body></html>', ogType = null, labels = [], title = 'Some page' } = {}) {
  return classifyPage({ html, baseURL: url, domain: new URL(url).hostname, title, ogDescription: null, ogType, collectionLabels: labels });
}

/** Strips the common indentation of a Swift `"""` block. */
export function dedent(s) {
  const lines = s.replace(/^\n/, '').split('\n');
  const indent = Math.min(...lines.filter((l) => l.trim()).map((l) => l.match(/^ */)[0].length));
  return lines.map((l) => l.slice(indent)).join('\n').replace(/\n\s*$/, '');
}

export const FIXED_NOW = new Date(1_790_000_000 * 1000);
