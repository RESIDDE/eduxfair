// Runs every query the React console issues, extracted from its own source.
//
// The browser cannot be driven from here, so this is the next best guarantee:
// the select strings are read out of web/src rather than transcribed, which
// means they cannot drift from what the pages actually send. A broken embed or
// a renamed column fails here.
//
//   node verify-console-queries.mjs   (with the dev server running)

import { readdir, readFile } from 'node:fs/promises';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ANON_KEY } from './auth.mjs';

const BASE = process.env.DEVSERVER_URL ?? 'http://localhost:54321';
// fileURLToPath, not .pathname: the repo path contains a space, which
// .pathname would hand back percent-encoded.
const SOURCE = join(dirname(fileURLToPath(import.meta.url)), '..', 'web', 'src');

const green = (s) => `\x1b[32m${s}\x1b[0m`;
const red = (s) => `\x1b[31m${s}\x1b[0m`;
const dim = (s) => `\x1b[2m${s}\x1b[0m`;

/** Walks the source tree for .jsx and .js files. */
async function sourceFiles(dir) {
  const found = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) found.push(...(await sourceFiles(path)));
    else if (/\.(jsx?|mjs)$/.test(entry.name)) found.push(path);
  }
  return found;
}

/**
 * Pulls `.from('table')…select('…')` pairs out of a file.
 *
 * Handles the adjacent-string concatenation the pages use for long selects,
 * and the `{ count, head }` second argument.
 */
function extractQueries(source, file) {
  const found = [];
  const pattern = /\.from\(\s*'([a-z_]+)'\s*\)/g;

  let match;
  while ((match = pattern.exec(source)) !== null) {
    const table = match[1];
    const after = source.slice(match.index, match.index + 2000);

    const selectAt = after.indexOf('.select(');
    if (selectAt === -1) continue;
    // Only count a select that belongs to this `from`, not a later chain.
    if (after.slice(0, selectAt).includes('.from(', 6)) continue;

    const body = after.slice(selectAt + '.select('.length);

    // A bare `.select()` on an insert takes no argument. Without this the
    // scanner runs on and grabs the next unrelated string literal in the file.
    if (/^\s*\)/.test(body)) continue;

    // Likewise `.select('id', { count: 'exact' })` is fine, but the first
    // literal must come immediately — nothing but whitespace before it.
    if (!/^\s*'/.test(body)) continue;

    const literals = [];
    const stringPattern = /'((?:[^'\\]|\\.)*)'/g;

    // Read adjacent literals joined by `+`, and stop at anything else.
    let cursor = 0;
    let piece;
    while ((piece = stringPattern.exec(body)) !== null) {
      const between = body.slice(cursor, piece.index).trim();
      if (cursor === 0 ? between !== '' : between !== '+') break;
      literals.push(piece[1]);
      cursor = piece.index + piece[0].length;
    }

    if (literals.length === 0) continue;

    found.push({
      table,
      select: literals.join('').replace(/\\'/g, "'"),
      file: relative(SOURCE, file),
    });
  }

  return found;
}

async function signIn(email) {
  const response = await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: ANON_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'Lekkside123!' }),
  });
  if (!response.ok) throw new Error(`sign-in failed for ${email}`);
  return response.json();
}

async function main() {
  const health = await fetch(`${BASE}/health`).catch(() => null);
  if (!health?.ok) {
    console.error(red(`\n  No dev server at ${BASE}. Run \`npm start\` first.\n`));
    process.exit(1);
  }

  const institution = await signIn('admissions@maplecrest.ca');
  const admin = await signIn('admin@lekkside.com');

  const files = await sourceFiles(SOURCE);
  const queries = [];
  for (const file of files) {
    queries.push(...extractQueries(await readFile(file, 'utf8'), file));
  }

  // Deduplicate: several pages read the same shape.
  const unique = new Map();
  for (const query of queries) {
    unique.set(`${query.table}|${query.select}`, query);
  }

  console.log(`\nRunning ${unique.size} distinct queries from web/src\n`);

  let failed = 0;

  for (const query of unique.values()) {
    // Admin for the admin pages, an institution owner for the rest — whichever
    // the page itself is written for.
    const token = query.file.startsWith('routes/admin')
      ? admin.access_token
      : institution.access_token;

    const url =
      `${BASE}/rest/v1/${query.table}` +
      `?select=${encodeURIComponent(query.select)}&limit=1`;

    const response = await fetch(url, {
      headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}` },
    });

    const label = `${query.table} ${dim(`(${query.file})`)}`;

    if (response.ok) {
      console.log(`  ${green('ok')}  ${label}`);
    } else {
      failed += 1;
      const body = await response.text();
      console.log(`  ${red('FAIL')}  ${label}`);
      console.log(red(`        ${response.status} ${body.slice(0, 260)}`));
      console.log(dim(`        select=${query.select.slice(0, 200)}`));
    }
  }

  console.log(`\n${unique.size} queries, ${failed} failed\n`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(red(`\n  Crashed: ${err.message}\n`));
  process.exit(1);
});
