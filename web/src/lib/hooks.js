import { useCallback, useEffect, useState } from 'react';
import { supabase, describeError } from './supabase';

/**
 * Runs a Supabase query and tracks loading and error state.
 *
 * `queryFn` receives the client and returns the PostgREST promise. Deps work
 * like useEffect's. Returns a `reload` so a mutation can refresh without the
 * caller holding its own flag.
 */
export function useQuery(queryFn, deps = []) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const run = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data: rows, error: queryError } = await queryFn(supabase);
      if (queryError) throw queryError;
      setData(rows);
    } catch (err) {
      setError(describeError(err));
    } finally {
      setLoading(false);
    }
  // queryFn is recreated per render by design; deps are what actually matter.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  useEffect(() => {
    run();
  }, [run]);

  return { data, loading, error, reload: run };
}

/**
 * The controlled field-of-study vocabulary.
 *
 * Always loaded rather than hardcoded: matching compares a student's
 * `target_fields` against `programs.field_of_study`, so a subject typed in by
 * hand would make a program unmatchable and nothing would visibly break.
 */
export function useFieldsOfStudy() {
  const { data, loading } = useQuery(
    (client) => client.from('fields_of_study').select('*').order('sort_order'),
    [],
  );
  return { fields: data ?? [], loading };
}

/** A map of slug -> label, for rendering a stored field value. */
export function useFieldLabels() {
  const { fields } = useFieldsOfStudy();
  return Object.fromEntries(fields.map((f) => [f.slug, f.label]));
}
