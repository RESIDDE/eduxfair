// Copies the policy text shipped inside the app into the website.
//
// App Store Connect needs a reachable privacy policy URL, and APP_REVIEW.md
// requires the hosted copy to say exactly what the in-app copy says. Rather
// than keep two texts in step by hand, this reads the Dart source of truth
// (student_app/lib/features/legal/models/policies.dart) and writes
// src/content/policies.json. It runs before every dev start and build.
//
// It is a small parser for the subset of Dart that file uses: constructor
// calls with named arguments, list literals, adjacent string literals
// (concatenated), `${AppConstants.x}` / `$name` interpolation, and top-level
// `const name = 'value'` declarations.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const appLib = resolve(here, '../../student_app/lib');
const src = readFileSync(resolve(appLib, 'features/legal/models/policies.dart'), 'utf8');
const constantsSrc = readFileSync(resolve(appLib, 'core/constants/app_constants.dart'), 'utf8');

// AppConstants.x values that the policies interpolate.
const appConstants = {};
for (const m of constantsSrc.matchAll(/static const String (\w+) =\s*'([^']*)';/g)) {
  appConstants[m[1]] = m[2];
}
// The public brand name is written EduXFair; the constant predates that.
appConstants.appName = 'EduXFair';

// ── Tokenizer ────────────────────────────────────────────────────────────────
function tokenize(text) {
  const tokens = [];
  let i = 0;
  while (i < text.length) {
    const c = text[i];
    if (/\s/.test(c)) { i++; continue; }
    if (text.startsWith('//', i)) { i = text.indexOf('\n', i); if (i < 0) break; continue; }
    if (c === "'" || c === '"') {
      let j = i + 1, raw = '';
      while (text[j] !== c) {
        if (text[j] === '\\') { raw += text[j] + text[j + 1]; j += 2; continue; }
        raw += text[j++];
      }
      tokens.push({ t: 'str', v: raw });
      i = j + 1;
      continue;
    }
    if (/[A-Za-z_$]/.test(c)) {
      let j = i;
      while (/[\w$.]/.test(text[j])) j++;
      tokens.push({ t: 'id', v: text.slice(i, j) });
      i = j;
      continue;
    }
    if (/\d/.test(c)) {
      let j = i;
      while (/\d/.test(text[j])) j++;
      tokens.push({ t: 'num', v: Number(text.slice(i, j)) });
      i = j;
      continue;
    }
    tokens.push({ t: 'p', v: c });
    i++;
  }
  return tokens;
}

const tokens = tokenize(src);
const consts = {};

function interpolate(raw) {
  return raw
    .replace(/\$\{AppConstants\.(\w+)\}/g, (_, k) => appConstants[k] ?? '')
    .replace(/\$\{(\w+)\}/g, (_, k) => String(consts[k] ?? ''))
    .replace(/\$(\w+)/g, (_, k) => String(consts[k] ?? ''))
    .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\n/g, '\n')
    .replace(/\\(.)/g, '$1');
}

let pos = 0;
const peek = () => tokens[pos];
const next = () => tokens[pos++];
const expect = (v) => {
  const tok = next();
  if (tok.v !== v) throw new Error(`Expected ${v}, got ${tok.v} at token ${pos}`);
};

function parseValue() {
  const tok = peek();
  if (tok.t === 'str') {
    let s = '';
    while (peek()?.t === 'str') s += interpolate(next().v);
    return s;
  }
  if (tok.t === 'num') return next().v;
  if (tok.v === '[') {
    next();
    const items = [];
    while (peek().v !== ']') {
      items.push(parseValue());
      if (peek().v === ',') next();
    }
    next();
    return items;
  }
  if (tok.t === 'id') {
    const name = next().v;
    if (peek()?.v === '(') {
      next();
      const obj = { _type: name };
      while (peek().v !== ')') {
        const key = next().v;
        expect(':');
        obj[key] = parseValue();
        if (peek().v === ',') next();
      }
      next();
      return obj;
    }
    return consts[name];
  }
  throw new Error(`Unexpected token ${JSON.stringify(tok)}`);
}

const docs = {};
while (pos < tokens.length) {
  const tok = next();
  if (tok.v === 'const' && tokens[pos + 1]?.v === '=') {
    const name = next().v;
    expect('=');
    const value = parseValue();
    consts[name] = value;
    if (value && value._type === 'LegalDocument') docs[name] = value;
  }
}

const clean = (doc) => ({
  title: doc.title,
  summary: doc.summary,
  lastUpdated: doc.lastUpdated,
  sections: doc.sections.map((s) => ({
    heading: s.heading,
    body: s.body ?? [],
    bullets: s.bullets ?? [],
  })),
});

const out = {
  privacy: clean(docs.privacyPolicy),
  terms: clean(docs.termsOfService),
  guidelines: clean(docs.communityGuidelines),
};

const target = resolve(here, '../src/content/policies.json');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, JSON.stringify(out, null, 2) + '\n');
console.log(
  `policies: ${Object.entries(out).map(([k, d]) => `${k} (${d.sections.length} sections)`).join(', ')}`,
);
