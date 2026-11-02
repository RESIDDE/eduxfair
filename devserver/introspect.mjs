// Catalog introspection: foreign keys and column types.
//
// PostgREST resolves an embedded select like `programs(name)` through the
// foreign keys between the two tables, and needs column types to coerce a JSON
// body into a row. Both come from the catalog at startup rather than being
// hardcoded, so the schema stays the single source of truth.

let relationships = [];
let columnTypes = new Map();
let setReturning = new Set();

export async function introspect(db) {
  const fks = await db.query(`
    select
      con.conname                                as name,
      src.relname                                as src_table,
      tgt.relname                                as tgt_table,
      (select array_agg(a.attname order by k.ord)
         from unnest(con.conkey) with ordinality k(attnum, ord)
         join pg_attribute a
           on a.attrelid = con.conrelid and a.attnum = k.attnum) as src_columns,
      (select array_agg(a.attname order by k.ord)
         from unnest(con.confkey) with ordinality k(attnum, ord)
         join pg_attribute a
           on a.attrelid = con.confrelid and a.attnum = k.attnum) as tgt_columns
      from pg_constraint con
      join pg_class src on src.oid = con.conrelid
      join pg_class tgt on tgt.oid = con.confrelid
      join pg_namespace n on n.oid = src.relnamespace
     where con.contype = 'f' and n.nspname = 'public'
  `);

  relationships = fks.rows.map((row) => ({
    name: row.name,
    srcTable: row.src_table,
    tgtTable: row.tgt_table,
    srcColumn: row.src_columns[0],
    tgtColumn: row.tgt_columns[0],
  }));

  const columns = await db.query(`
    select c.relname as table_name,
           a.attname as column_name,
           format_type(a.atttypid, a.atttypmod) as type,
           a.attgenerated <> '' as generated,
           a.attidentity <> '' as identity
      from pg_attribute a
      join pg_class c on c.oid = a.attrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind in ('r', 'v')
       and a.attnum > 0
       and not a.attisdropped
  `);

  // Set-returning functions have to be called as `select * from fn(...)` and
  // return an array, the way PostgREST does it. Calling one as a scalar yields
  // a composite value the client cannot read.
  const functions = await db.query(`
    select p.proname as name
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proretset
  `);
  setReturning = new Set(functions.rows.map((r) => r.name));

  columnTypes = new Map();
  for (const row of columns.rows) {
    if (!columnTypes.has(row.table_name)) columnTypes.set(row.table_name, new Map());
    columnTypes.get(row.table_name).set(row.column_name, {
      type: row.type,
      // Generated columns cannot be written to at all, so a client that sends
      // one must have it dropped rather than get a confusing error.
      generated: row.generated,
    });
  }

  return { relationships, columnTypes };
}

/** Whether an RPC returns a set, and so must be selected from. */
export function returnsSet(name) {
  return setReturning.has(name);
}

export function columnsOf(table) {
  return columnTypes.get(table) ?? new Map();
}

export function typeOf(table, column) {
  return columnsOf(table).get(column)?.type ?? 'text';
}

export function isGenerated(table, column) {
  return columnsOf(table).get(column)?.generated ?? false;
}

/**
 * Finds how `child` hangs off `parent`.
 *
 * `hint` is PostgREST's disambiguator — the FK column or constraint name —
 * and is required when two foreign keys point at the same table. That is a
 * real situation here: `appointments` references `profiles` twice, as
 * student_id and host_profile_id.
 */
export function findRelationship(parent, child, hint) {
  const forward = relationships.filter(
    (r) =>
      r.srcTable === parent &&
      r.tgtTable === child &&
      (!hint || r.srcColumn === hint || r.name === hint),
  );
  const reverse = relationships.filter(
    (r) =>
      r.srcTable === child &&
      r.tgtTable === parent &&
      (!hint || r.srcColumn === hint || r.name === hint),
  );

  const candidates = [
    ...forward.map((r) => ({ ...r, kind: 'to-one' })),
    ...reverse.map((r) => ({ ...r, kind: 'to-many' })),
  ];

  if (candidates.length === 0) {
    const error = new Error(
      `Could not find a relationship between '${parent}' and '${child}'` +
        (hint ? ` using the hint '${hint}'` : '') +
        ' in the schema cache',
    );
    error.status = 400;
    error.code = 'PGRST200';
    throw error;
  }

  if (candidates.length > 1) {
    const hints = candidates.map((c) => c.srcColumn).join(', ');
    const error = new Error(
      `Could not embed because more than one relationship was found for ` +
        `'${parent}' and '${child}'. Disambiguate with one of: ${hints} ` +
        `(e.g. ${child}!${candidates[0].srcColumn})`,
    );
    error.status = 300;
    error.code = 'PGRST201';
    throw error;
  }

  return candidates[0];
}
