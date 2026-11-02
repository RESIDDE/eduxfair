// Bulk / scheduled recomputation of match_scores.
//
// Day-to-day matching is kept current by database triggers (see
// 20251009000013_match_refresh_triggers.sql), so this function is NOT on the
// hot path. It exists for the cases triggers cannot cover:
//
//   - the scoring weights changed and every score is now stale
//   - a backfill after importing programs or passports in bulk
//   - a scheduled sweep to catch anything missed
//
// Scope one of: { student_id } | { program_id } | { institution_id } | { all: true }
// Only an admin may request a wide recompute; a student may refresh their own.

import { adminClient, json, preflight, requireUser } from '../_shared/deps.ts';

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  const user = await requireUser(req);
  if (!user) return json({ error: 'authentication required' }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'expected a JSON body' }, 400);
  }

  const db = adminClient();

  // The caller's role decides how wide a recompute they may ask for.
  const { data: profile } = await db
    .from('profiles').select('role').eq('id', user.id).single();
  const isAdmin = profile?.role === 'admin';

  const started = Date.now();

  try {
    // ---- one student -------------------------------------------------------
    if (typeof body.student_id === 'string') {
      if (body.student_id !== user.id && !isAdmin) {
        return json({ error: 'you may only refresh your own matches' }, 403);
      }
      const { data, error } = await db.rpc('refresh_matches_for_student', {
        target: body.student_id,
      });
      if (error) throw error;
      return json({ scope: 'student', matched: data, ms: Date.now() - started });
    }

    // ---- one program ------------------------------------------------------
    if (typeof body.program_id === 'string') {
      if (!isAdmin) {
        // Staff may refresh a program their own institution owns.
        const { data: prog } = await db
          .from('programs').select('institution_id').eq('id', body.program_id).single();
        const { data: member } = await db
          .from('institution_members')
          .select('id')
          .eq('profile_id', user.id)
          .eq('institution_id', prog?.institution_id ?? '')
          .maybeSingle();
        if (!member) return json({ error: 'not your program' }, 403);
      }
      const { data, error } = await db.rpc('refresh_matches_for_program', {
        target: body.program_id,
      });
      if (error) throw error;
      return json({ scope: 'program', matched: data, ms: Date.now() - started });
    }

    // ---- every program at one institution ---------------------------------
    if (typeof body.institution_id === 'string') {
      if (!isAdmin) {
        const { data: member } = await db
          .from('institution_members')
          .select('id')
          .eq('profile_id', user.id)
          .eq('institution_id', body.institution_id)
          .maybeSingle();
        if (!member) return json({ error: 'not your institution' }, 403);
      }
      const { data: programs, error: progErr } = await db
        .from('programs').select('id').eq('institution_id', body.institution_id)
        .eq('is_active', true);
      if (progErr) throw progErr;

      let matched = 0;
      for (const p of programs ?? []) {
        const { data, error } = await db.rpc('refresh_matches_for_program', { target: p.id });
        if (error) throw error;
        matched += Number(data ?? 0);
      }
      return json({
        scope: 'institution', programs: programs?.length ?? 0, matched,
        ms: Date.now() - started,
      });
    }

    // ---- everything -------------------------------------------------------
    if (body.all === true) {
      if (!isAdmin) return json({ error: 'admin only' }, 403);

      const { data: programs, error: progErr } = await db
        .from('programs').select('id').eq('is_active', true);
      if (progErr) throw progErr;

      // Program-by-program rather than student-by-student: each call is one
      // set-based statement over all eligible passports, so this is the cheaper
      // direction whenever there are more students than programs.
      let matched = 0;
      for (const p of programs ?? []) {
        const { data, error } = await db.rpc('refresh_matches_for_program', { target: p.id });
        if (error) throw error;
        matched += Number(data ?? 0);
      }
      return json({
        scope: 'all', programs: programs?.length ?? 0, matched,
        ms: Date.now() - started,
      });
    }

    return json(
      { error: 'specify student_id, program_id, institution_id, or all: true' },
      400,
    );
  } catch (err) {
    console.error('compute-matches failed:', err);
    return json({ error: (err as Error).message }, 500);
  }
});
