import { readdir, readFile } from 'node:fs/promises';
import { extname, join, relative } from 'node:path';

const root = new URL('../src/', import.meta.url);
const textExtensions = new Set(['.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs']);

const rules = [
  {
    name: 'direct financial table write',
    pattern: /\b(?:insert\s+into|update|delete\s+from)\s+(?:public\.)?ibex_had_[a-z0-9_]+/gi,
    reason: 'Financial writes from the web runtime must go through central PostgreSQL functions.',
  },
  {
    name: 'owner role usage',
    pattern: /\bneondb_owner\b/gi,
    reason: 'The web runtime must never depend on the database owner role.',
  },
];

async function filesUnder(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const target = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await filesUnder(target));
    else if (textExtensions.has(extname(entry.name))) files.push(target);
  }
  return files;
}

const srcPath = new URL(root).pathname;
const violations = [];
for (const file of await filesUnder(srcPath)) {
  const content = await readFile(file, 'utf8');
  for (const rule of rules) {
    rule.pattern.lastIndex = 0;
    const match = rule.pattern.exec(content);
    if (match) {
      const before = content.slice(0, match.index);
      const line = before.split('\n').length;
      violations.push({ file: relative(srcPath, file), line, rule: rule.name, reason: rule.reason, sample: match[0] });
    }
  }
}

if (violations.length > 0) {
  console.error('IBEX runtime boundary audit failed:');
  for (const violation of violations) {
    console.error(`- ${violation.file}:${violation.line} — ${violation.rule}: ${violation.sample}`);
    console.error(`  ${violation.reason}`);
  }
  process.exit(1);
}

console.log('IBEX runtime boundary audit passed.');
