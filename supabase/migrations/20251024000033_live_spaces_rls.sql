-- Lekkside Connect — access rules for Live Spaces.
--
-- Read with 20251009000009 open: the shape repeats, and the policy names follow
-- the same <table>_<action>_<who> convention. The one departure worth stating up
-- front is space_participants, which has NO institution policy at all. That is
-- not an omission — see the table's comment in 20251024000032.

alter table spaces                  enable row level security;
alter table space_participants      enable row level security;
alter table space_messages          enable row level security;
alter table space_moderation_events enable row level security;

-- =================================================================== spaces
--
-- Readable by anyone signed in: a scheduled session is an advertisement, and
-- the Spaces tab is how a student finds one. `anon` sees nothing, as
-- everywhere else, which the RLS suite's unauthenticated section asserts.

create policy spaces_select_signed_in on spaces
  for select using (auth.uid() is not null);

create policy spaces_write_member on spaces
  for all using (is_member_of(institution_id))
  with check (is_member_of(institution_id));

create policy spaces_all_admin on spaces
  for all using (is_admin()) with check (is_admin());

-- `status` is moved by space_set_status(), which records the transition. The
-- member policy above also allows a direct update: the function exists for the
-- audit row, not for the permission. The same arrangement `applications` has
-- with set_application_stage().

-- ======================================================= space_participants
--
-- Self and admin only. Staff join through join_space(), act through
-- space_moderate(), and read space_roster.
--
-- Note what is NOT here: no insert, update or delete for the subject
-- themselves. A student who could UPDATE their own row would set
-- admission = 'admitted' and walk past the waiting room, or role = 'speaker'
-- and hold the floor without the passport share that is the entire consent
-- model. Those two columns are precisely why this table is read-only to the
-- person it is about.

create policy space_participants_select_self on space_participants
  for select using (profile_id = auth.uid());

create policy space_participants_all_admin on space_participants
  for all using (is_admin()) with check (is_admin());

-- =========================================================== space_messages

create policy space_messages_select_participant on space_messages
  for select using (my_space_participant(space_id) is not null);

create policy space_messages_select_institution on space_messages
  for select using (
    exists (select 1 from spaces s
             where s.id = space_id and is_member_of(s.institution_id)));

create policy space_messages_select_admin on space_messages
  for select using (is_admin());

-- The sender must be a participant who may speak, posting as themselves.
--
-- my_speaking_participant() is what makes "posting in the chat identifies you"
-- true rather than merely intended: a listener's id is not returned by it, so
-- there is nothing for the check to match and the insert is refused. The client
-- calls identify_in_space() first; this policy is what happens when it does not.
create policy space_messages_insert_speaker on space_messages
  for insert with check (participant_id = my_speaking_participant(space_id));

-- No update and no delete policy for anyone. A host retracts a message with
-- remove_space_message(), which soft-deletes it and records why — a different
-- act from editing one. The same reasoning `messages` gives for having neither.

-- ================================================== space_moderation_events

create policy space_moderation_events_select_institution on space_moderation_events
  for select using (
    exists (select 1 from spaces s
             where s.id = space_id and is_member_of(s.institution_id)));

-- The person it was done to may read it. Being removed from a room with no way
-- to see that it happened, or why, is how a platform loses an argument it
-- should win.
create policy space_moderation_events_select_subject on space_moderation_events
  for select using (is_my_space_participant(subject_participant_id));

create policy space_moderation_events_select_admin on space_moderation_events
  for select using (is_admin());

-- No insert, update or delete policy for any role, admin included. Rows arrive
-- only from the SECURITY DEFINER functions in 20251024000032, which run as the
-- owner and are not subject to these policies at all.
