// A PostgREST subset: enough of the protocol for both apps to run unchanged.
//
// Implemented because mocking the client would mean mocking authorization too,
// and the whole value of testing locally is that RLS, the guard triggers and
// the matching engine are the real ones. Every query here becomes SQL executed
// as the signed-in role.
//
// Supported: select with nested embeds and `!inner`, FK hints, aliases,
// eq/neq/gt/gte/lt/lte/like/ilike/is/in filters including on embedded tables,
// multi-column order with nulls placement, limit/offset and Range, exact
// counts, insert/update/upsert/delete with `return=representation`, and RPC.
//
// Not supported, because nothing in these apps uses it: `or=`, full-text
// search, `select` on ordering of embeds, range types, or computed columns.

import { coerceFilterValue } from './coerce.mjs';
import { findRelationship, isGenerated, returnsSet, typeOf } from './introspect.mjs';

// ── Select parsing ──────────────────────────────────────────────────────────

/**
 * Parses a PostgREST `select` into a tree.
 *
 * Grammar, as used here:
 *   item      := [alias ':'] name ['!' hint] [ '(' list ')' ]
 *   list      := item [',' list]
 */
export function parseSelect(select) {
  const source = (select ?? '*').trim();
  const { items } = parseList(source, 0);
  return items;
}

function parseList(source, start) {
  const items = [];
  let i = start;
  let token = '';
  let depth = 0;

  const flush = (raw) => {
    const trimmed = raw.trim();
    if (trimmed) items.push(parseItem(trimmed));
  };

  while (i < source.length) {
    const char = source[i];

    if (char === '(') {
      depth += 1;
      token += char;
    } else if (char === ')') {
      if (depth === 0) {
        // Closing paren of the enclosing embed: we are done with this list.
        flush(token);
        return { items, end: i };
      }
      depth -= 1;
      token += char;
    } else if (char === ',' && depth === 0) {
      flush(token);
      token = '';
    } else {
      token += char;
    }
    i += 1;
  }

  flush(token);
  return { items, end: i };
}

function parseItem(raw) {
  let text = raw;
  let alias = null;

  // An alias, but not the `::` of a cast.
  const colon = text.indexOf(':');
  if (colon > 0 && text[colon + 1] !== ':') {
    alias = text.slice(0, colon).trim();
    text = text.slice(colon + 1).trim();
  }

  const open = text.indexOf('(');
  if (open === -1) {
    const { name } = parseHead(text);
    return { kind: 'column', name, alias: alias ?? name };
  }

  const close = text.lastIndexOf(')');
  const { name, hint, isInner } = parseHead(text.slice(0, open).trim());

  return {
    kind: 'embed',
    name,
    alias: alias ?? name,
    hint,
    isInner,
    children: parseSelect(text.slice(open + 1, close)),
  };
}

/**
 * Splits `table!inner!student_id` into its parts.
 *
 * `!inner` is the join modifier; anything else after `!` is a foreign-key
 * hint, which PostgREST requires when two keys point at the same table. That
 * is a real case here: `appointments` references `profiles` twice.
 */
function parseHead(text) {
  const parts = String(text)
    .split('!')
    .map((p) => p.trim())
    .filter((p) => p.length > 0);

  const name = parts.shift();
  let hint;
  let isInner = false;

  for (const part of parts) {
    if (part === 'inner') isInner = true;
    else if (part === 'left') isInner = false;
    else hint = part;
  }

  return { name, hint, isInner };
}

// ── SQL building ────────────────────────────────────────────────────────────

class Params {
  constructor() {
    this.values = [];
  }

  add(value) {
    this.values.push(value);
    return `$${this.values.length}`;
  }
}

let aliasCounter = 0;
const nextAlias = () => `t${(aliasCounter = (aliasCounter + 1) % 100000)}`;

const quoteIdent = (name) => `"${String(name).replace(/"/g, '""')}"`;

/**
 * Builds the select list for one level, recursing into embeds.
 *
 * Embeds become correlated subqueries that aggregate to JSON. They run as the
 * same role, so RLS applies inside them exactly as PostgREST would have it —
 * an embedded institution a caller may not see comes back null, not leaked.
 */
function buildSelectList(table, alias, items, params, innerJoins) {
  const pieces = [];

  for (const item of items) {
    if (item.kind === 'column') {
      if (item.name === '*') {
        pieces.push(`${alias}.*`);
      } else if (item.alias !== item.name) {
        pieces.push(`${alias}.${quoteIdent(item.name)} as ${quoteIdent(item.alias)}`);
      } else {
        pieces.push(`${alias}.${quoteIdent(item.name)}`);
      }
      continue;
    }

    const relationship = findRelationship(table, item.name, item.hint);
    const childAlias = nextAlias();
    const childList = buildSelectList(
      relationship.kind === 'to-one' ? relationship.tgtTable : relationship.srcTable,
      childAlias,
      item.children,
      params,
      // Nested `!inner` applies within the subquery, not to the outer row.
      [],
    );

    if (relationship.kind === 'to-one') {
      const join =
        `${relationship.tgtTable} ${childAlias} ` +
        `where ${childAlias}.${quoteIdent(relationship.tgtColumn)} = ` +
        `${alias}.${quoteIdent(relationship.srcColumn)}`;

      pieces.push(
        `(select to_jsonb(sub) from (select ${childList} from ${join} limit 1) sub) ` +
          `as ${quoteIdent(item.alias)}`,
      );

      if (item.isInner) {
        innerJoins.push(
          `exists (select 1 from ${relationship.tgtTable} ${childAlias}_x ` +
            `where ${childAlias}_x.${quoteIdent(relationship.tgtColumn)} = ` +
            `${alias}.${quoteIdent(relationship.srcColumn)})`,
        );
      }
    } else {
      const join =
        `${relationship.srcTable} ${childAlias} ` +
        `where ${childAlias}.${quoteIdent(relationship.srcColumn)} = ` +
        `${alias}.${quoteIdent(relationship.tgtColumn)}`;

      pieces.push(
        `(select coalesce(jsonb_agg(sub), '[]'::jsonb) from ` +
          `(select ${childList} from ${join}) sub) as ${quoteIdent(item.alias)}`,
      );

      if (item.isInner) {
        innerJoins.push(
          `exists (select 1 from ${relationship.srcTable} ${childAlias}_x ` +
            `where ${childAlias}_x.${quoteIdent(relationship.srcColumn)} = ` +
            `${alias}.${quoteIdent(relationship.tgtColumn)})`,
        );
      }
    }
  }

  return pieces.length > 0 ? pieces.join(', ') : `${alias}.*`;
}

// ── Filters ─────────────────────────────────────────────────────────────────

const OPERATORS = {
  eq: '=',
  neq: '<>',
  gt: '>',
  gte: '>=',
  lt: '<',
  lte: '<=',
  like: 'like',
  ilike: 'ilike',
};

const RESERVED = new Set([
  'select', 'order', 'limit', 'offset', 'on_conflict', 'columns', 'apikey',
]);

function buildFilters(table, alias, searchParams, params) {
  const clauses = [];

  for (const [rawKey, rawValue] of searchParams.entries()) {
    if (RESERVED.has(rawKey)) continue;

    // `embeddedtable.column=eq.x` filters the parent by the embedded row.
    const dot = rawKey.indexOf('.');
    if (dot > 0) {
      const childName = rawKey.slice(0, dot);
      const childColumn = rawKey.slice(dot + 1);
      const relationship = findRelationship(table, childName, undefined);
      const childAlias = nextAlias();

      const childTableName =
        relationship.kind === 'to-one' ? relationship.tgtTable : relationship.srcTable;
      const condition = buildCondition(
        childTableName, childAlias, childColumn, rawValue, params);
      const correlation =
        relationship.kind === 'to-one'
          ? `${childAlias}.${quoteIdent(relationship.tgtColumn)} = ` +
            `${alias}.${quoteIdent(relationship.srcColumn)}`
          : `${childAlias}.${quoteIdent(relationship.srcColumn)} = ` +
            `${alias}.${quoteIdent(relationship.tgtColumn)}`;

      clauses.push(
        `exists (select 1 from ${childTableName} ${childAlias} ` +
          `where ${correlation} and ${condition})`,
      );
      continue;
    }

    clauses.push(buildCondition(table, alias, rawKey, rawValue, params));
  }

  return clauses;
}

function buildCondition(table, alias, column, rawValue, params) {
  const column_ = `${alias}.${quoteIdent(column)}`;
  const dot = rawValue.indexOf('.');
  const op = dot === -1 ? 'eq' : rawValue.slice(0, dot);
  const value = dot === -1 ? rawValue : rawValue.slice(dot + 1);

  if (op === 'is') {
    if (value === 'null') return `${column_} is null`;
    if (value === 'not.null') return `${column_} is not null`;
    return `${column_} is ${value === 'true' ? 'true' : 'false'}`;
  }

  if (op === 'not') {
    // `not.is.null` and friends.
    return `not (${buildCondition(table, alias, column, value, params)})`;
  }

  if (op === 'in') {
    const list = value
      .replace(/^\(/, '')
      .replace(/\)$/, '')
      .split(',')
      .map((v) => v.trim().replace(/^"|"$/g, ''))
      .filter((v) => v.length > 0);
    // Compared as text so one code path covers uuid, enum and numeric columns.
    // Index use does not matter at dev-server scale.
    return `${column_}::text = any(${params.add(list)}::text[])`;
  }

  const sqlOp = OPERATORS[op];
  if (!sqlOp) {
    const error = new Error(`Unsupported operator '${op}' in the dev server`);
    error.status = 400;
    error.code = 'PGRST100';
    throw error;
  }

  // PostgREST uses `*` as the wildcard in like/ilike.
  const bound =
    op === 'like' || op === 'ilike' ? value.replace(/\*/g, '%') : value;

  // Coerced to the column's own type: a bare "true" would otherwise reach the
  // boolean serialiser as a string and be rejected.
  const typed =
    op === 'like' || op === 'ilike'
      ? bound
      : coerceFilterValue(typeOf(table, column), bound);

  return `${column_} ${sqlOp} ${params.add(typed)}`;
}

// ── Ordering, paging ────────────────────────────────────────────────────────

function buildOrder(alias, searchParams) {
  const raw = searchParams.getAll('order');
  if (raw.length === 0) return '';

  const terms = raw
    .flatMap((group) => group.split(','))
    .map((term) => term.trim())
    .filter(Boolean)
    .map((term) => {
      const [column, ...modifiers] = term.split('.');
      const descending = modifiers.includes('desc');
      const nullsFirst = modifiers.includes('nullsfirst');
      const nullsLast = modifiers.includes('nullslast');

      let sql = `${alias}.${quoteIdent(column)} ${descending ? 'desc' : 'asc'}`;
      if (nullsFirst) sql += ' nulls first';
      else if (nullsLast) sql += ' nulls last';
      return sql;
    });

  return terms.length > 0 ? ` order by ${terms.join(', ')}` : '';
}

function buildRange(searchParams, headers) {
  let limit = searchParams.has('limit') ? Number(searchParams.get('limit')) : null;
  let offset = searchParams.has('offset') ? Number(searchParams.get('offset')) : 0;

  // supabase-js's .range() becomes a Range header, not query params.
  const range = headers.get?.('range') ?? headers.range;
  if (range && limit === null) {
    const match = /^(\d+)-(\d*)$/.exec(String(range));
    if (match) {
      offset = Number(match[1]);
      if (match[2] !== '') limit = Number(match[2]) - offset + 1;
    }
  }

  return { limit, offset };
}

// ── Row coercion for writes ─────────────────────────────────────────────────

/**
 * Builds the `jsonb_to_record(...) as x(col type, …)` clause for a write.
 *
 * Going through the catalog's own types is what makes arrays, enums, dates and
 * jsonb all land correctly — the alternative is hand-rolling literal escaping
 * per type and getting `text[]` wrong.
 */
function buildRecordSource(table, rows, params, { recordset = false } = {}) {
  const present = new Set();
  for (const row of rows) {
    for (const key of Object.keys(row)) {
      // A generated column cannot be written to; dropping it quietly matches
      // what a client expects after reading a row back and sending it again.
      if (!isGenerated(table, key)) present.add(key);
    }
  }

  const columns = [...present];
  if (columns.length === 0) {
    const error = new Error('No writable columns in the request body');
    error.status = 400;
    throw error;
  }

  const definition = columns
    .map((column) => `${quoteIdent(column)} ${typeOf(table, column)}`)
    .join(', ');

  const payload = params.add(JSON.stringify(recordset ? rows : rows[0]));
  const fn = recordset ? 'jsonb_to_recordset' : 'jsonb_to_record';

  return {
    columns,
    source: `${fn}(${payload}::jsonb) as x(${definition})`,
  };
}

// ── Public API ──────────────────────────────────────────────────────────────

export function buildSelectQuery(table, searchParams, headers) {
  const params = new Params();
  const alias = nextAlias();
  const innerJoins = [];

  const items = parseSelect(searchParams.get('select'));
  const list = buildSelectList(table, alias, items, params, innerJoins);
  const filters = buildFilters(table, alias, searchParams, params);
  const where = [...filters, ...innerJoins];

  let sql = `select ${list} from ${table} ${alias}`;
  if (where.length > 0) sql += ` where ${where.join(' and ')}`;
  sql += buildOrder(alias, searchParams);

  const { limit, offset } = buildRange(searchParams, headers);
  if (limit !== null) sql += ` limit ${Number(limit)}`;
  if (offset) sql += ` offset ${Number(offset)}`;

  // The count ignores paging, which is what Content-Range reports.
  const countParams = new Params();
  const countAlias = nextAlias();
  const countInner = [];
  // Rebuild so the embeds contributing `!inner` are accounted for.
  buildSelectList(table, countAlias, items, countParams, countInner);
  const countFilters = buildFilters(table, countAlias, searchParams, countParams);
  const countWhere = [...countFilters, ...countInner];
  let countSql = `select count(*)::int as count from ${table} ${countAlias}`;
  if (countWhere.length > 0) countSql += ` where ${countWhere.join(' and ')}`;

  return {
    sql,
    params: params.values,
    countSql,
    countParams: countParams.values,
    limit,
    offset,
  };
}

export function buildInsertQuery(table, body, searchParams, headers, prefer) {
  const rows = Array.isArray(body) ? body : [body];
  const params = new Params();
  const many = rows.length > 1;
  const { columns, source } = buildRecordSource(table, rows, params, {
    recordset: many,
  });

  const columnList = columns.map(quoteIdent).join(', ');
  const selectList = columns.map((c) => `x.${quoteIdent(c)}`).join(', ');

  let sql = `insert into ${table} (${columnList}) select ${selectList} from ${source}`;

  const onConflict = searchParams.get('on_conflict');
  if (prefer.resolution === 'merge-duplicates') {
    const conflictColumns = (onConflict ?? '')
      .split(',')
      .map((c) => c.trim())
      .filter(Boolean);

    if (conflictColumns.length > 0) {
      const updates = columns
        .filter((c) => !conflictColumns.includes(c))
        .map((c) => `${quoteIdent(c)} = excluded.${quoteIdent(c)}`);

      sql += ` on conflict (${conflictColumns.map(quoteIdent).join(', ')})`;
      sql += updates.length > 0 ? ` do update set ${updates.join(', ')}` : ' do nothing';
    } else {
      sql += ' on conflict do nothing';
    }
  } else if (prefer.resolution === 'ignore-duplicates') {
    sql += ' on conflict do nothing';
  }

  return wrapReturning(table, sql, params, searchParams, headers, prefer);
}

export function buildUpdateQuery(table, body, searchParams, headers, prefer) {
  const params = new Params();
  const { columns, source } = buildRecordSource(table, [body], params);

  const assignments = columns
    .map((c) => `${quoteIdent(c)} = x.${quoteIdent(c)}`)
    .join(', ');

  // The filter alias must be the table itself: `update ... from` cannot alias
  // the target and still be referenced by the embeds below.
  const filters = buildFilters(table, table, searchParams, params);

  let sql = `update ${table} set ${assignments} from ${source}`;
  if (filters.length > 0) sql += ` where ${filters.join(' and ')}`;

  return wrapReturning(table, sql, params, searchParams, headers, prefer);
}

export function buildDeleteQuery(table, searchParams, headers, prefer) {
  const params = new Params();
  const filters = buildFilters(table, table, searchParams, params);

  let sql = `delete from ${table}`;
  if (filters.length > 0) sql += ` where ${filters.join(' and ')}`;

  return wrapReturning(table, sql, params, searchParams, headers, prefer);
}

/**
 * Applies `Prefer: return=representation` by running the mutation in a CTE and
 * selecting from it, so the client's `select` — embeds included — is honoured.
 */
function wrapReturning(table, mutation, params, searchParams, headers, prefer) {
  if (prefer.return !== 'representation') {
    return { sql: mutation, params: params.values, returning: false };
  }

  const alias = nextAlias();
  const innerJoins = [];
  const items = parseSelect(searchParams.get('select'));
  const list = buildSelectList(table, alias, items, params, innerJoins);

  let sql = `with changed as (${mutation} returning *) select ${list} from changed ${alias}`;
  if (innerJoins.length > 0) sql += ` where ${innerJoins.join(' and ')}`;
  sql += buildOrder(alias, searchParams);

  return { sql, params: params.values, returning: true };
}

export function buildRpcQuery(name, body) {
  const params = new Params();
  // A null argument still has to be passed: omitting it silently takes the
  // function's default, which is not what the caller asked for.
  const args = Object.entries(body ?? {});

  // A set-returning function is selected FROM and yields rows; a scalar one is
  // selected and yields a single value. Calling the first as the second gives
  // back a composite the client cannot read.
  const isSet = returnsSet(name);

  const callArgs = args
    .map(([key, value]) => {
      let bound;
      if (value === null || value === undefined) {
        bound = 'null';
      } else if (Array.isArray(value)) {
        // Arrays reach Postgres through jsonb, since PGlite cannot infer an
        // array parameter's element type.
        bound = `array(select jsonb_array_elements_text(` +
          `${params.add(JSON.stringify(value))}::jsonb))`;
      } else if (typeof value === 'object') {
        bound = `${params.add(JSON.stringify(value))}::jsonb`;
      } else {
        bound = params.add(value);
      }
      return `${quoteIdent(key)} => ${bound}`;
    })
    .join(', ');

  const call = `${quoteIdent(name)}(${callArgs})`;

  return {
    sql: isSet ? `select * from ${call}` : `select ${call} as result`,
    params: params.values,
    isSet,
  };
}

export function parsePrefer(headerValue) {
  const parts = String(headerValue ?? '')
    .split(',')
    .map((p) => p.trim())
    .filter(Boolean);

  const prefer = {};
  for (const part of parts) {
    const [key, value] = part.split('=').map((p) => p.trim());
    prefer[key] = value ?? true;
  }
  return prefer;
}
