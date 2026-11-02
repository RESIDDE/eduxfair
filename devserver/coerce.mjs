// Type fidelity between PGlite and real PostgREST.
//
// Two differences would otherwise reach the clients as crashes rather than as
// anything debuggable:
//
//   * `numeric` arrives from Postgres as a string, to preserve precision.
//     PostgREST serialises it as a JSON number, and the Dart models do
//     `(value as num).toDouble()` — which throws on a String. So every numeric
//     column has to become a number here.
//
//   * PGlite parses `date` into a JS Date, which JSON.stringify renders as a
//     full UTC timestamp. PostgREST returns a bare `YYYY-MM-DD`. Both parse in
//     Dart, but a date-only column should not acquire a time and a timezone.
//
//   * PGlite parses `text[]` but not an array of a user-defined enum, such as
//     `study_level[]` — it has no OID for it, so the raw literal
//     `{undergraduate}` comes through as a string. `Passport.fromMap` then
//     casts it to a List and throws. Any array-typed column still holding a
//     string gets parsed here.
//
// Nested embeds need no treatment: to_jsonb() already produces JSON arrays and
// JSON numbers.

import { typeOf } from './introspect.mjs';

const NUMERIC = 1700;
const INT8 = 20;
const DATE = 1082;

export function coerceResult(result, table) {
  const fields = result.fields ?? [];
  if (fields.length === 0) return result.rows;

  const fixers = new Map();
  for (const field of fields) {
    if (field.dataTypeID === NUMERIC || field.dataTypeID === INT8) {
      fixers.set(field.name, toNumber);
    } else if (field.dataTypeID === DATE) {
      fixers.set(field.name, toDateOnly);
    } else if (table && typeOf(table, field.name).endsWith('[]')) {
      fixers.set(field.name, toArray);
    }
  }

  if (fixers.size === 0) return result.rows;

  return result.rows.map((row) => {
    const copy = { ...row };
    for (const [name, fix] of fixers) {
      if (name in copy) copy[name] = fix(copy[name]);
    }
    return copy;
  });
}

function toNumber(value) {
  if (value === null || value === undefined) return value;
  if (typeof value === 'number') return value;
  if (typeof value === 'bigint') {
    // Outside the safe range a number would lose precision; a string is the
    // lesser evil, and nothing in this schema has ids that large.
    return value <= Number.MAX_SAFE_INTEGER ? Number(value) : value.toString();
  }
  const parsed = Number(value);
  return Number.isNaN(parsed) ? value : parsed;
}

/**
 * Parses a Postgres array literal: `{a,b}`, `{"a b","c,d"}`, `{}`, `{NULL}`.
 *
 * Only reached when PGlite left the value as a string, which happens for
 * arrays of user-defined enums.
 */
function toArray(value) {
  if (value === null || value === undefined) return value;
  if (Array.isArray(value)) return value;
  if (typeof value !== 'string') return value;

  const body = value.trim();
  if (!body.startsWith('{') || !body.endsWith('}')) return value;

  const inner = body.slice(1, -1);
  if (inner.length === 0) return [];

  const items = [];
  let current = '';
  let quoted = false;
  let escaped = false;

  for (const char of inner) {
    if (escaped) {
      current += char;
      escaped = false;
    } else if (char === '\\') {
      escaped = true;
    } else if (char === '"') {
      quoted = !quoted;
    } else if (char === ',' && !quoted) {
      items.push(current);
      current = '';
    } else {
      current += char;
    }
  }
  items.push(current);

  // An unquoted NULL is the null element; a quoted "NULL" is the string.
  return items.map((item) => (item === 'NULL' ? null : item));
}

function toDateOnly(value) {
  if (value === null || value === undefined) return value;
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  if (typeof value === 'string') return value.slice(0, 10);
  return value;
}

/**
 * Coerces a filter value to the column's own type before binding it.
 *
 * PostgREST receives every filter as text. PGlite infers the parameter type
 * from context and then hands the string to that type's serialiser, so
 * `is_active=eq.true` reaches the boolean serialiser as the string "true" and
 * is rejected. Converting here, using the catalog's type, is what makes
 * `eq.true` and `gte.40` work.
 */
export function coerceFilterValue(type, value) {
  const base = String(type ?? 'text').toLowerCase();

  if (base === 'boolean') {
    if (value === 'true' || value === 't') return true;
    if (value === 'false' || value === 'f') return false;
    return Boolean(value);
  }

  if (
    base.startsWith('int') ||
    base === 'smallint' ||
    base === 'bigint' ||
    base === 'numeric' ||
    base === 'real' ||
    base === 'double precision'
  ) {
    const parsed = Number(value);
    return Number.isNaN(parsed) ? value : parsed;
  }

  return value;
}
