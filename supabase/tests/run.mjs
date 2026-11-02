// Applies the Lekkside Connect migrations to a throwaway Postgres and runs the
// RLS assertions against them.
//
// Why PGlite rather than `supabase start`: the local Supabase stack needs
// Docker, which is not available on every machine. PGlite is real Postgres 17
// compiled to WASM and runs as a plain npm dependency, so the schema gets
// genuinely executed — syntax, constraints, triggers and policies all run — in
// a couple of seconds and with nothing to install.
//
// What it does NOT cover: GoTrue's real signup flow, PostgREST's request
// handling, and Storage's HTTP layer. Those still need a hosted project.
//
//   npm test                 migrations + RLS assertions
//   npm run test:schema      migrations only

import { PGlite } from '@electric-sql/pglite';
import { btree_gist } from '@electric-sql/pglite/contrib/btree_gist';
import { citext } from '@electric-sql/pglite/contrib/citext';
import { readFile, readdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(here, '..', 'migrations');
const schemaOnly = process.argv.includes('--schema-only');

const red = (s) => `\x1b[31m${s}\x1b[0m`;
const green = (s) => `\x1b[32m${s}\x1b[0m`;
const dim = (s) => `\x1b[2m${s}\x1b[0m`;

const db = await PGlite.create({ extensions: { btree_gist, citext } });

// ---------------------------------------------------------------- migrations

async function apply(label, sql) {
  try {
    await db.exec(sql);
    console.log(`  ${green('ok')}  ${label}`);
  } catch (err) {
    console.log(`  ${red('FAIL')}  ${label}`);
    console.log(red(`        ${err.message}`));
    if (err.position && typeof err.position === 'string') {
      const at = Number(err.position);
      const upto = sql.slice(0, at);
      const line = upto.split('\n').length;
      console.log(dim(`        at line ${line}: ${sql.split('\n')[line - 1]?.trim()}`));
    }
    process.exit(1);
  }
}

console.log('\nSupabase shim');
await apply('00_supabase_shim.sql', await readFile(join(here, '00_supabase_shim.sql'), 'utf8'));

console.log('\nMigrations');
const files = (await readdir(migrationsDir)).filter((f) => f.endsWith('.sql')).sort();
if (files.length === 0) {
  console.log(red('  no migrations found'));
  process.exit(1);
}
for (const f of files) {
  await apply(f, await readFile(join(migrationsDir, f), 'utf8'));
}

// --------------------------------------------------------------- schema facts
// A cheap guard against the whole authorization model being silently absent:
// a table with RLS enabled but zero policies denies everything, and a table
// with RLS *disabled* allows everything. Both are bugs worth failing on.

const rlsCheck = await db.query(`
  select c.relname                                       as table_name,
         c.relrowsecurity                                 as rls_enabled,
         (select count(*) from pg_policy p where p.polrelid = c.oid) as policies
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
   order by c.relname
`);

// A table may legitimately have zero policies when nothing but the service role
// should ever touch it (domain-verification tokens, for instance). That has to
// be declared in the table's COMMENT, so it is a visible decision rather than
// an oversight that looks identical.
const comments = await db.query(`
  select c.relname as table_name, obj_description(c.oid, 'pg_class') as comment
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
`);
const serviceRoleOnly = new Set(
  comments.rows
    .filter((r) => (r.comment ?? '').includes('SERVICE-ROLE ONLY'))
    .map((r) => r.table_name),
);

const unprotected = rlsCheck.rows.filter((r) => !r.rls_enabled);
const policyless = rlsCheck.rows.filter(
  (r) => r.rls_enabled && Number(r.policies) === 0 && !serviceRoleOnly.has(r.table_name),
);

console.log('\nRLS coverage');
console.log(`  ${rlsCheck.rows.length} tables, ` +
            `${rlsCheck.rows.filter((r) => r.rls_enabled).length} with RLS enabled`);

if (unprotected.length) {
  console.log(red(`  FAIL  RLS not enabled on: ${unprotected.map((r) => r.table_name).join(', ')}`));
  process.exit(1);
}
if (policyless.length) {
  console.log(red(`  FAIL  RLS enabled but no policies on: ` +
                  policyless.map((r) => r.table_name).join(', ')));
  process.exit(1);
}
console.log(`  ${green('ok')}  every public table has RLS enabled and at least one policy`);
if (serviceRoleOnly.size) {
  console.log(dim(`        (${[...serviceRoleOnly].join(', ')}: ` +
                  `service-role only, no policies by design)`));
}

if (schemaOnly) {
  console.log(green('\nSchema applied cleanly.\n'));
  process.exit(0);
}

// ------------------------------------------------------------------ RLS tests

const { runAssertions } = await import('./rls_test.mjs');

let failures;
try {
  failures = await runAssertions(db, { red, green, dim });
} catch (err) {
  // Keep the report readable: a raw PGlite error prints the whole WASM module.
  console.log(red(`\n  ERROR  the suite could not finish: ${err.message}`));
  if (err.where) console.log(dim(`         ${err.where}`));
  if (err.query) console.log(dim(`         query: ${String(err.query).slice(0, 200)}`));
  process.exit(1);
}

if (failures > 0) {
  console.log(red(`\n${failures} assertion(s) failed.\n`));
  process.exit(1);
}
console.log(green('\nAll assertions passed.\n'));
