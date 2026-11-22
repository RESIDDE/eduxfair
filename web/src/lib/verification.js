import { supabase } from './supabase';

/**
 * Settles a verification for any subject — an institution, a passport, a
 * document or an educator — the one way that keeps the badge and the queue in
 * agreement.
 *
 * Always lands as an UPDATE, never an insert-with-the-answer.
 * `verifications_apply_decision` is a `before update of status` trigger, so a
 * row inserted already saying 'verified' propagates nothing and the subject
 * keeps its old badge. A subject with no open request therefore gets one
 * inserted as 'pending' first, and the decision is a second statement.
 * `verifications_one_open` allows one pending row per subject, which is what
 * makes the maybeSingle() safe.
 *
 * Returns an error, or null.
 */
export async function decideVerification({
  subjectType, subjectId, status, reviewer, note = null,
}) {
  const evidence = {
    method: 'admin_decision',
    decided_by: reviewer?.full_name ?? 'an administrator',
    decided_at: new Date().toISOString(),
    attests: `an Eduxfair administrator reviewed this ${subjectType} by hand`,
    does_not_attest: subjectType === 'institution'
      ? 'accreditation, programme quality, or partnership with Eduxfair'
      : 'anything beyond what the reviewer could see in the upload',
  };

  const { data: open } = await supabase
    .from('verifications')
    .select('id')
    .eq('subject_type', subjectType)
    .eq('subject_id', subjectId)
    .eq('status', 'pending')
    .maybeSingle();

  let rowId = open?.id;

  if (!rowId) {
    const { data: created, error: insertError } = await supabase
      .from('verifications')
      .insert({
        subject_type: subjectType,
        subject_id: subjectId,
        status: 'pending',
        evidence,
      })
      .select('id')
      .single();
    if (insertError) return insertError;
    rowId = created.id;
  }

  const { error } = await supabase
    .from('verifications')
    .update({ status, evidence, reviewer_id: reviewer?.id, review_note: note })
    .eq('id', rowId);
  return error ?? null;
}
