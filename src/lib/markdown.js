/**
 * Remove any `## Heading` section (and its contents up to the next `## `)
 * from a markdown string so a caller can rewrite its own sections.
 */
function stripSections(md, headings) {
  if (!md) return '';
  let out = md;
  for (const h of headings) {
    const re = new RegExp(
      `(^|\\n)##\\s+${h.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\$&')}\\b[\\s\\S]*?(?=\\n##\\s|$)`,
      'g'
    );
    out = out.replace(re, '');
  }
  return out.replace(/\n{3,}/g, '\n\n').trim();
}

module.exports = { stripSections };
