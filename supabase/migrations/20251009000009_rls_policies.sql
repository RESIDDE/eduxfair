-- Lekkside Connect — row-level security policies.
--
-- Read this as the authorization spec for the whole platform; there is no
-- other one. The shape repeats: students own their rows, institution staff
-- reach their own institution's rows plus students who have shared, admin is
-- unrestricted, and nobody else sees anything.
--
-- Two rules worth stating up front because the rest depends on them:
--   1. A student's IDENTITY (name, contact, documents, passport detail) is
--      gated on institution_can_see_student(). Pseudonymous rows keyed by
--      student uuid are not — institutions need a stable handle to shortlist
--      and invite someone they cannot yet name. That is reverse admission.
--   2. application_events has no update or delete policy for anyone, admin
--      included. An editable decision history is not a decision history.

alter table profiles                       enable row level security;
alter table institutions                   enable row level security;
alter table institution_members            enable row level security;
alter table educators                      enable row level security;
alter table fields_of_study                enable row level security;
alter table student_passports              enable row level security;
alter table passport_documents             enable row level security;
alter table passport_shares                enable row level security;
alter table programs                       enable row level security;
alter table match_scores                   enable row level security;
alter table institution_interests          enable row level security;
alter table student_interests              enable row level security;
alter table availability_slots             enable row level security;
alter table appointments                   enable row level security;
alter table conversations                  enable row level security;
alter table conversation_participants      enable row level security;
alter table messages                       enable row level security;
alter table applications                   enable row level security;
alter table application_events             enable row level security;
alter table application_documents          enable row level security;
alter table application_document_requests  enable row level security;
alter table fairs                          enable row level security;
alter table fair_registrations             enable row level security;
alter table fair_exhibitors                enable row level security;
alter table booth_visits                   enable row level security;
alter table verifications                  enable row level security;
alter table notifications                  enable row level security;
alter table institution_subscriptions      enable row level security;

-- ================================================================= profiles

create policy profiles_select_self on profiles
  for select using (id = auth.uid());

create policy profiles_select_admin on profiles
  for select using (is_admin());

-- Institution staff see a student's profile only after a share.
create policy profiles_select_shared_student on profiles
  for select using (role = 'student' and my_institution_can_see_student(id));

-- Staff and educator names are visible to signed-in users: a student must be
-- able to see who they are being messaged by.
create policy profiles_select_public_staff on profiles
  for select using (
    auth.uid() is not null
    and role in ('institution_member', 'educator')
  );

create policy profiles_update_self on profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

create policy profiles_update_admin on profiles
  for update using (is_admin());

-- ============================================================= institutions

-- The institution directory is open to any signed-in user; the badge, not
-- visibility, is what verification controls.
create policy institutions_select_authenticated on institutions
  for select using (auth.uid() is not null);

-- Creation goes through create_institution(), which also makes the caller an
-- owner. No direct insert, or an account could create an orphan listing.
create policy institutions_update_member on institutions
  for update using (is_member_of(id)) with check (is_member_of(id));

create policy institutions_all_admin on institutions
  for all using (is_admin()) with check (is_admin());

-- ====================================================== institution_members

create policy institution_members_select_own on institution_members
  for select using (profile_id = auth.uid() or is_member_of(institution_id));

create policy institution_members_select_admin on institution_members
  for select using (is_admin());

-- Seat management is an owner action.
create policy institution_members_insert_owner on institution_members
  for insert with check (is_owner_of(institution_id));

create policy institution_members_delete_owner on institution_members
  for delete using (is_owner_of(institution_id));

create policy institution_members_all_admin on institution_members
  for all using (is_admin()) with check (is_admin());

-- ================================================================ educators

create policy educators_select_authenticated on educators
  for select using (auth.uid() is not null);

create policy educators_write_self on educators
  for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());

create policy educators_all_admin on educators
  for all using (is_admin()) with check (is_admin());

-- ========================================================== fields_of_study

create policy fields_select_all on fields_of_study
  for select using (true);

create policy fields_write_admin on fields_of_study
  for all using (is_admin()) with check (is_admin());

-- ======================================================== student_passports

create policy passports_select_self on student_passports
  for select using (profile_id = auth.uid());

create policy passports_select_admin on student_passports
  for select using (is_admin());

-- The consent gate. Without a live share this returns nothing at all.
create policy passports_select_shared on student_passports
  for select using (my_institution_can_see_student(profile_id));

create policy passports_insert_self on student_passports
  for insert with check (profile_id = auth.uid());

create policy passports_update_self on student_passports
  for update using (profile_id = auth.uid()) with check (profile_id = auth.uid());

create policy passports_delete_self on student_passports
  for delete using (profile_id = auth.uid());

-- ======================================================= passport_documents

create policy documents_select_self on passport_documents
  for select using (profile_id = auth.uid());

create policy documents_select_admin on passport_documents
  for select using (is_admin());

create policy documents_select_shared on passport_documents
  for select using (my_institution_can_see_student(profile_id));

create policy documents_insert_self on passport_documents
  for insert with check (profile_id = auth.uid());

-- A student may replace or remove their own documents. Institutions never
-- write here, and the review columns are moved only by the verification queue.
create policy documents_update_self on passport_documents
  for update using (profile_id = auth.uid()) with check (profile_id = auth.uid());

create policy documents_delete_self on passport_documents
  for delete using (profile_id = auth.uid());

create policy documents_all_admin on passport_documents
  for all using (is_admin()) with check (is_admin());

-- ========================================================== passport_shares

create policy shares_select_self on passport_shares
  for select using (profile_id = auth.uid());

-- The institution can see that it has been granted access (and by whom), which
-- is what drives "N students have shared their passport with you".
create policy shares_select_institution on passport_shares
  for select using (is_member_of(institution_id));

create policy shares_select_admin on passport_shares
  for select using (is_admin());

-- Only the student grants, and only the student revokes.
create policy shares_insert_self on passport_shares
  for insert with check (profile_id = auth.uid());

create policy shares_update_self on passport_shares
  for update using (profile_id = auth.uid()) with check (profile_id = auth.uid());

create policy shares_all_admin on passport_shares
  for all using (is_admin()) with check (is_admin());

-- ================================================================= programs

create policy programs_select_active on programs
  for select using (auth.uid() is not null and is_active);

-- Staff see their own drafts too.
create policy programs_select_own on programs
  for select using (is_member_of(institution_id));

create policy programs_write_member on programs
  for all using (is_member_of(institution_id)) with check (is_member_of(institution_id));

create policy programs_all_admin on programs
  for all using (is_admin()) with check (is_admin());

-- ============================================================= match_scores

create policy matches_select_self on match_scores
  for select using (student_id = auth.uid());

-- Pseudonymous by design: the institution gets scores and a student uuid for
-- its own programs, but can resolve that uuid to a person only after a share.
create policy matches_select_own_programs on match_scores
  for select using (
    exists (select 1 from programs g
             where g.id = program_id and is_member_of(g.institution_id))
  );

create policy matches_select_admin on match_scores
  for select using (is_admin());

-- Scores are written only by refresh_matches_for_*(), which is SECURITY DEFINER.

-- ===================================================== institution_interests

-- Reverse admission. The student is told when they are INVITED, and never
-- learns they were shortlisted or passed over — those are internal notes.
create policy interests_select_invited_student on institution_interests
  for select using (profile_id = auth.uid() and kind = 'invited');

create policy interests_select_institution on institution_interests
  for select using (is_member_of(institution_id));

create policy interests_select_admin on institution_interests
  for select using (is_admin());

create policy interests_write_institution on institution_interests
  for all using (is_member_of(institution_id)) with check (is_member_of(institution_id));

create policy interests_all_admin on institution_interests
  for all using (is_admin()) with check (is_admin());

-- ========================================================= student_interests

create policy student_interests_select_self on student_interests
  for select using (profile_id = auth.uid());

-- An institution seeing "a student saved this program" is pseudonymous, same
-- reasoning as match_scores.
create policy student_interests_select_institution on student_interests
  for select using (
    exists (select 1 from programs g
             where g.id = program_id and is_member_of(g.institution_id))
  );

create policy student_interests_write_self on student_interests
  for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());

create policy student_interests_select_admin on student_interests
  for select using (is_admin());

-- ======================================================== availability_slots

create policy slots_select_authenticated on availability_slots
  for select using (auth.uid() is not null);

create policy slots_write_member on availability_slots
  for all using (is_member_of(institution_id)) with check (is_member_of(institution_id));

create policy slots_all_admin on availability_slots
  for all using (is_admin()) with check (is_admin());

-- ============================================================= appointments

create policy appointments_select_student on appointments
  for select using (student_id = auth.uid());

create policy appointments_select_institution on appointments
  for select using (is_member_of(institution_id));

create policy appointments_select_admin on appointments
  for select using (is_admin());

-- A student books for themselves only.
create policy appointments_insert_student on appointments
  for insert with check (student_id = auth.uid());

create policy appointments_insert_institution on appointments
  for insert with check (is_member_of(institution_id));

-- Either side may update: the student to reschedule or cancel, the institution
-- to confirm and attach the meeting link.
create policy appointments_update_student on appointments
  for update using (student_id = auth.uid()) with check (student_id = auth.uid());

create policy appointments_update_institution on appointments
  for update using (is_member_of(institution_id))
  with check (is_member_of(institution_id));

create policy appointments_all_admin on appointments
  for all using (is_admin()) with check (is_admin());

-- ============================================================ conversations

create policy conversations_select_party on conversations
  for select using (student_id = auth.uid() or is_member_of(institution_id));

create policy conversations_select_admin on conversations
  for select using (is_admin());

create policy conversations_insert_student on conversations
  for insert with check (student_id = auth.uid());

create policy conversations_insert_institution on conversations
  for insert with check (is_member_of(institution_id));

create policy conversations_update_party on conversations
  for update using (student_id = auth.uid() or is_member_of(institution_id))
  with check (student_id = auth.uid() or is_member_of(institution_id));

-- ================================================ conversation_participants

create policy participants_select_party on conversation_participants
  for select using (can_access_conversation(conversation_id));

-- Read state is per person: you may only write your own.
create policy participants_write_self on conversation_participants
  for all using (profile_id = auth.uid() and can_access_conversation(conversation_id))
  with check (profile_id = auth.uid() and can_access_conversation(conversation_id));

-- ================================================================= messages

create policy messages_select_party on messages
  for select using (can_access_conversation(conversation_id));

create policy messages_select_admin on messages
  for select using (is_admin());

-- Sender must be the caller, and the caller must be on the thread. Without the
-- second half, anyone could post into any conversation as themselves.
create policy messages_insert_party on messages
  for insert with check (
    sender_id = auth.uid() and can_access_conversation(conversation_id));

-- No update or delete policy: a message log that can be rewritten is useless
-- when a student disputes what an institution told them.

-- ============================================================= applications

create policy applications_select_student on applications
  for select using (profile_id = auth.uid());

create policy applications_select_institution on applications
  for select using (is_member_of(institution_id));

create policy applications_select_admin on applications
  for select using (is_admin());

create policy applications_insert_student on applications
  for insert with check (profile_id = auth.uid());

-- Both sides may update; which STAGES each may set is enforced by
-- guard_application_stage() in 20251009000008, not by RLS.
create policy applications_update_student on applications
  for update using (profile_id = auth.uid()) with check (profile_id = auth.uid());

create policy applications_update_institution on applications
  for update using (is_member_of(institution_id))
  with check (is_member_of(institution_id));

create policy applications_all_admin on applications
  for all using (is_admin()) with check (is_admin());

-- ======================================================= application_events

create policy application_events_select_party on application_events
  for select using (can_access_application(application_id));

create policy application_events_select_admin on application_events
  for select using (is_admin());

-- Notes may be appended by either party. Stage transitions are written by the
-- SECURITY DEFINER trigger. There is deliberately NO update or delete policy
-- here for any role, admin included — see the header.
create policy application_events_insert_party on application_events
  for insert with check (can_access_application(application_id));

-- ==================================================== application_documents

create policy application_documents_select_party on application_documents
  for select using (can_access_application(application_id));

-- The student chooses which of their documents to attach.
create policy application_documents_write_student on application_documents
  for all using (
    exists (select 1 from applications a
             where a.id = application_id and a.profile_id = auth.uid())
  )
  with check (
    exists (select 1 from applications a
             where a.id = application_id and a.profile_id = auth.uid())
    and exists (select 1 from passport_documents d
                 where d.id = document_id and d.profile_id = auth.uid())
  );

create policy application_documents_select_admin on application_documents
  for select using (is_admin());

-- ============================================ application_document_requests

create policy document_requests_select_party on application_document_requests
  for select using (can_access_application(application_id));

create policy document_requests_write_institution on application_document_requests
  for all using (
    exists (select 1 from applications a
             where a.id = application_id and is_member_of(a.institution_id))
  )
  with check (
    exists (select 1 from applications a
             where a.id = application_id and is_member_of(a.institution_id))
  );

-- The student marks a request fulfilled once they have uploaded.
create policy document_requests_update_student on application_document_requests
  for update using (
    exists (select 1 from applications a
             where a.id = application_id and a.profile_id = auth.uid())
  )
  with check (
    exists (select 1 from applications a
             where a.id = application_id and a.profile_id = auth.uid())
  );

-- ==================================================================== fairs

create policy fairs_select_authenticated on fairs
  for select using (auth.uid() is not null);

create policy fairs_all_admin on fairs
  for all using (is_admin()) with check (is_admin());

-- ====================================================== fair_registrations

-- Deliberately NOT visible to exhibitors: the attendee list is not a lead
-- list. An exhibitor learns a student exists when the student taps CONNECT.
create policy fair_registrations_select_self on fair_registrations
  for select using (profile_id = auth.uid());

create policy fair_registrations_select_admin on fair_registrations
  for select using (is_admin());

create policy fair_registrations_insert_self on fair_registrations
  for insert with check (profile_id = auth.uid());

create policy fair_registrations_all_admin on fair_registrations
  for all using (is_admin()) with check (is_admin());

-- ========================================================= fair_exhibitors

create policy fair_exhibitors_select_authenticated on fair_exhibitors
  for select using (auth.uid() is not null);

create policy fair_exhibitors_all_admin on fair_exhibitors
  for all using (is_admin()) with check (is_admin());

-- ============================================================ booth_visits

create policy booth_visits_select_student on booth_visits
  for select using (profile_id = auth.uid());

create policy booth_visits_select_exhibitor on booth_visits
  for select using (
    exists (select 1 from fair_exhibitors e
             where e.id = exhibitor_id and is_member_of(e.institution_id))
  );

create policy booth_visits_select_admin on booth_visits
  for select using (is_admin());

-- No insert policy at all: visits are created only by record_booth_visit(),
-- which verifies the pass code and that the scanner staffs that booth. Staff
-- may annotate afterwards.
create policy booth_visits_update_exhibitor on booth_visits
  for update using (
    exists (select 1 from fair_exhibitors e
             where e.id = exhibitor_id and is_member_of(e.institution_id))
  )
  with check (
    exists (select 1 from fair_exhibitors e
             where e.id = exhibitor_id and is_member_of(e.institution_id))
  );

create policy booth_visits_all_admin on booth_visits
  for all using (is_admin()) with check (is_admin());

-- ============================================================ verifications

-- The subject can watch their own request's status.
create policy verifications_select_subject on verifications
  for select using (
    (subject_type = 'passport'  and subject_id = auth.uid())
    or (subject_type = 'educator' and subject_id = auth.uid())
    or (subject_type = 'document'
        and exists (select 1 from passport_documents d
                     where d.id = subject_id and d.profile_id = auth.uid()))
    or (subject_type = 'institution' and is_member_of(subject_id))
  );

-- Requesting review is allowed; awarding it is not (status defaults to
-- 'pending' and only admin may update).
create policy verifications_insert_subject on verifications
  for insert with check (
    (subject_type = 'passport'  and subject_id = auth.uid())
    or (subject_type = 'educator' and subject_id = auth.uid())
    or (subject_type = 'document'
        and exists (select 1 from passport_documents d
                     where d.id = subject_id and d.profile_id = auth.uid()))
    or (subject_type = 'institution' and is_member_of(subject_id))
  );

create policy verifications_all_admin on verifications
  for all using (is_admin()) with check (is_admin());

-- ============================================================ notifications

create policy notifications_select_self on notifications
  for select using (profile_id = auth.uid());

-- Only to mark read; the client cannot rewrite the content.
create policy notifications_update_self on notifications
  for update using (profile_id = auth.uid()) with check (profile_id = auth.uid());

create policy notifications_all_admin on notifications
  for all using (is_admin()) with check (is_admin());

-- Inserts come from Edge Functions on the service-role key, which bypasses RLS.

-- ================================================= institution_subscriptions

create policy subscriptions_select_member on institution_subscriptions
  for select using (is_member_of(institution_id));

create policy subscriptions_all_admin on institution_subscriptions
  for all using (is_admin()) with check (is_admin());
