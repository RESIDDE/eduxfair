import { supabase } from './supabase';

/**
 * Helpers for the oversight pages.
 *
 * Names are resolved in one batched read per kind rather than through
 * PostgREST embeds: half the foreign keys point at `profiles`, which has no
 * email, and the console always wants the email beside a name. `admin_people`
 * has both, and returns nothing to anyone who is not an admin.
 */

const uniq = (values) => [...new Set(values.filter(Boolean))];

/** id -> admin_people row. */
export async function lookupPeople(ids) {
  const wanted = uniq(ids);
  if (wanted.length === 0) return {};
  const { data, error } = await supabase
    .from('admin_people')
    .select('id, full_name, email, role, handle, avatar_url, institution_name')
    .in('id', wanted);
  if (error) throw error;
  return Object.fromEntries((data ?? []).map((p) => [p.id, p]));
}

/** id -> institutions row (the fields a chip needs). */
export async function lookupInstitutions(ids) {
  const wanted = uniq(ids);
  if (wanted.length === 0) return {};
  const { data, error } = await supabase
    .from('institutions')
    .select('id, name, logo_url, country, verification_status')
    .in('id', wanted);
  if (error) throw error;
  return Object.fromEntries((data ?? []).map((i) => [i.id, i]));
}

/** id -> programs row. */
export async function lookupPrograms(ids) {
  const wanted = uniq(ids);
  if (wanted.length === 0) return {};
  const { data, error } = await supabase
    .from('programs')
    .select('id, name, level, institution_id')
    .in('id', wanted);
  if (error) throw error;
  return Object.fromEntries((data ?? []).map((p) => [p.id, p]));
}

/**
 * Runs a query and resolves the people, institutions and programs it mentions.
 *
 * Shaped for useQuery: resolves to `{ data, error }`, where data is
 * `{ rows, people, institutions, programs }`.
 */
export async function withLookups(query, {
  people = [], institutions = [], programs = [],
} = {}) {
  const { data: rows, error } = await query;
  if (error) return { data: null, error };
  const list = rows ?? [];
  const pick = (keys) => list.flatMap((row) => keys.map((k) => row[k]));
  try {
    const [p, i, g] = await Promise.all([
      lookupPeople(pick(people)),
      lookupInstitutions(pick(institutions)),
      lookupPrograms(pick(programs)),
    ]);
    return { data: { rows: list, people: p, institutions: i, programs: g }, error: null };
  } catch (lookupError) {
    return { data: null, error: lookupError };
  }
}

/**
 * Opens a private file in a new tab through a short-lived signed URL.
 *
 * Five minutes, because the link is for looking at the file now — a signed URL
 * pasted somewhere else should stop working soon after.
 */
export async function openPrivateFile(bucket, path) {
  // Opened first and pointed at the URL afterwards: a window opened after an
  // await is no longer attached to the click, and popup blockers stop it.
  const tab = window.open('', '_blank');
  const { data, error } = await supabase.storage
    .from(bucket)
    .createSignedUrl(path, 300);
  if (error || !data?.signedUrl) {
    tab?.close();
    return error ?? new Error('Could not open that file.');
  }
  if (tab) tab.location.href = data.signedUrl;
  else window.location.assign(data.signedUrl);
  return null;
}

/** A public bucket's URL for a stored path. */
export function publicFileUrl(bucket, path) {
  if (!path) return null;
  if (/^https?:\/\//.test(path)) return path;
  return supabase.storage.from(bucket).getPublicUrl(path).data.publicUrl;
}

export const formatBytes = (bytes) => {
  const n = Number(bytes) || 0;
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
};
