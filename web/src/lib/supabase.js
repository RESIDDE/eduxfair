import { createClient } from '@supabase/supabase-js';

// Both from env, unlike consult-app's version which hardcoded the project URL —
// that made pointing a build at staging a code change.
const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;

export const isConfigured = Boolean(SUPABASE_URL && SUPABASE_ANON_KEY);

if (!isConfigured && import.meta.env.DEV) {
  console.error(
    'Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY. Copy web/.env.example ' +
      'to web/.env.local and fill them in.',
  );
}

// The anon key is safe in a browser bundle: row-level security is what protects
// the data. The service-role key must never appear here.
export const supabase = createClient(SUPABASE_URL ?? '', SUPABASE_ANON_KEY ?? '', {
  auth: { persistSession: true, autoRefreshToken: true },
});

/**
 * Turns a Postgres error into something worth showing an admissions officer.
 *
 * P0001 is raise_exception — our own guard triggers, whose messages are already
 * written for people. Everything else gets translated, because "new row
 * violates row-level security policy" tells a user nothing actionable.
 */
export function describeError(error) {
  if (!error) return null;

  if (error.code === 'P0001') return error.message;

  switch (error.code) {
    case '23505':
      return friendlyConstraint(error.message);
    case '23514':
      return friendlyConstraint(error.message);
    case '42501':
      return 'You do not have access to that.';
    case 'PGRST116':
      return 'That record could not be found.';
    default:
      break;
  }

  if (error.message?.includes('row-level security')) {
    return 'You do not have access to that.';
  }
  return error.message ?? 'Something went wrong.';
}

function friendlyConstraint(message = '') {
  if (message.includes('availability_no_overlap')) {
    return 'That time overlaps a slot you have already published.';
  }
  if (message.includes('fair_exhibitors')) {
    return 'That booth code is already used at this fair.';
  }
  if (message.includes('institution_interests')) {
    return 'You have already recorded that for this student.';
  }
  if (message.includes('applications_one_live')) {
    return 'This student already has an open application for that program.';
  }
  if (message.includes('programs_tuition_order')) {
    return 'The minimum tuition cannot be higher than the maximum.';
  }
  if (message.includes('programs_min_grade_needs_scheme')) {
    return 'Choose which grading scheme the minimum grade is in.';
  }
  if (message.includes('institutions_email_domain_is_bare')) {
    return 'Enter the bare domain only, e.g. utoronto.ca — no https:// or path.';
  }
  return 'That value is not valid.';
}
