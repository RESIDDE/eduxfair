// The database behind the dev server: PGlite running the project's real
// migrations.
//
// Using the actual migrations rather than a mock is the whole point — RLS, the
// guard triggers, the matching engine and the consent gate all behave exactly
// as they will in production, so a bug found here is a real bug.
//
// PGlite is a single connection, so every statement has to be serialised. The
// mutex below is not optional: two interleaved transactions would otherwise
// corrupt each other's `SET LOCAL ROLE`, and a request would silently run as
// the wrong user.

import { PGlite } from '@electric-sql/pglite';
import { btree_gist } from '@electric-sql/pglite/contrib/btree_gist';
import { citext } from '@electric-sql/pglite/contrib/citext';
import { readdir, readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(here, '..', 'supabase', 'migrations');
const testShim = join(here, '..', 'supabase', 'tests', '00_supabase_shim.sql');
const extraShim = join(here, 'shim_extra.sql');

let db;

/** Serialises access, so one transaction finishes before the next begins. */
let queue = Promise.resolve();

function serialise(work) {
  const result = queue.then(work, work);
  // Keep the chain alive even when a request throws.
  queue = result.then(
    () => undefined,
    () => undefined,
  );
  return result;
}

export async function initDatabase({ log = console.log } = {}) {
  db = await PGlite.create({ extensions: { btree_gist, citext } });

  log('  applying the Supabase shim…');
  await db.exec(await readFile(testShim, 'utf8'));
  await db.exec(await readFile(extraShim, 'utf8'));

  const files = (await readdir(migrationsDir)).filter((f) => f.endsWith('.sql')).sort();
  log(`  applying ${files.length} migrations…`);
  for (const file of files) {
    try {
      await db.exec(await readFile(join(migrationsDir, file), 'utf8'));
    } catch (err) {
      throw new Error(`migration ${file} failed: ${err.message}`);
    }
  }

  return db;
}

/**
 * Runs `work` inside a transaction as the given user, with RLS enforced.
 *
 * Exactly how hosted Supabase behaves: the role becomes `authenticated` (or
 * `anon`) and the verified JWT claims go into the `request.jwt.claims` GUC that
 * auth.uid() reads. Because the role is not a superuser, every policy applies.
 */
export function asRole(claims, work) {
  return serialise(async () => {
    const role = claims?.role === 'service_role' ? 'service_role' : claims?.sub ? 'authenticated' : 'anon';

    await db.exec('begin');
    try {
      // set_config's third argument is `is_local`: scoped to this transaction,
      // so nothing leaks into the next request on this shared connection.
      await db.query('select set_config($1, $2, true)', [
        'request.jwt.claims',
        claims ? JSON.stringify(claims) : '',
      ]);
      await db.exec(`set local role ${role}`);

      const result = await work({
        query: (sql, params) => db.query(sql, params),
        exec: (sql) => db.exec(sql),
      });

      await db.exec('commit');
      return result;
    } catch (err) {
      try {
        await db.exec('rollback');
      } catch {
        // A failed rollback means the transaction already aborted; the next
        // `begin` recovers.
      }
      throw err;
    }
  });
}

/** Unrestricted access, for seeding and for the auth endpoints. */
export function asService(work) {
  return serialise(async () => {
    await db.exec('begin');
    try {
      const result = await work({
        query: (sql, params) => db.query(sql, params),
        exec: (sql) => db.exec(sql),
      });
      await db.exec('commit');
      return result;
    } catch (err) {
      try {
        await db.exec('rollback');
      } catch {
        // as above
      }
      throw err;
    }
  });
}

/** Outside any transaction — for DDL and seeding scripts. */
export function raw() {
  return serialise(async () => db);
}
