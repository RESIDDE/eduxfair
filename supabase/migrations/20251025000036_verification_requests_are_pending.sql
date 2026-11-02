-- A subject may ask for review. It may not write its own answer in the box.
--
-- `verifications_insert_subject` let the subject insert a row for itself, which
-- is right — 20251009000008 says so: "Students and institutions can *request*
-- verification (by inserting into `verifications`) but never award it to
-- themselves." The policy enforced the first half and not the second: nothing
-- constrained `status`, so an institution could insert a row already saying
-- 'verified'.
--
-- What saved it is an accident rather than a rule. apply_verification_decision()
-- is a `before update of status` trigger, so a row INSERTED as 'verified'
-- propagates nothing and the badge does not move. Found by trying it against
-- the real project: the institution stayed `unverified`, as it should.
--
-- But the row is still there, and the admin queue reads `status` to decide what
-- to show. A self-inserted 'verified' row appears under the Verified filter as
-- though somebody had approved it. Nobody did. That is a reviewer being misled
-- by the queue they are meant to trust, which is worth more than the fact that
-- the badge itself held.
--
-- So the policy now says what the comment always claimed. `status` has a
-- default of 'pending', so every honest caller is unaffected — the clients
-- never send it, and `verifications_all_admin` is untouched, which is what
-- leaves admin free to insert a decided row when resolving by hand.

drop policy if exists verifications_insert_subject on verifications;

create policy verifications_insert_subject on verifications
  for insert with check (
    status = 'pending'
    and (
      (subject_type = 'passport'  and subject_id = auth.uid())
      or (subject_type = 'educator' and subject_id = auth.uid())
      or (subject_type = 'document'
          and exists (select 1 from passport_documents d
                       where d.id = subject_id and d.profile_id = auth.uid()))
      or (subject_type = 'institution' and is_member_of(subject_id))
    )
  );
