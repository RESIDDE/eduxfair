-- Lekkside Connect — App Review 1.2 for direct messages, and 5.1.1(v) for staff.
--
-- Guideline 1.2 asks any app with user-generated content for a way to report
-- objectionable content and to block abusive users. Posts, comments and
-- accounts had both. Direct messages — the one place a student and an
-- institution talk privately — had neither, on either side:
--
--   * there was nothing to report a message or a conversation against, and
--   * blocking was person-to-person and never checked when a message was
--     sent, so blocking someone did not stop them messaging you.
--
-- A conversation is between a student and an *institution* (any of its staff
-- may reply), so a person-to-person block cannot express "this institution
-- may not message me". The block here is per conversation and per side, and
-- it is enforced in the insert policy on `messages`, not in the app.
--
-- Guideline 5.1.1(v) asks that every account the app lets you create can be
-- deleted from inside it, with its data. Institution staff create accounts in
-- the app too. Deleting one used to remove the person and leave their
-- institution behind: a public listing with no-one able to manage it, or
-- with no owner if the owner was the one who left.

-- ─────────────────────────────────────────── 1. blocking a conversation

create table if not exists conversation_blocks (
  conversation_id uuid not null references conversations (id) on delete cascade,
  -- Which party blocked: the student, or the institution (any of its staff).
  side            text not null check (side in ('student', 'institution')),
  blocked_by      uuid references profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  primary key (conversation_id, side)
);

alter table conversation_blocks enable row level security;

drop policy if exists conversation_blocks_select_party on conversation_blocks;
create policy conversation_blocks_select_party on conversation_blocks
  for select using (can_access_conversation(conversation_id) or is_admin());
-- No write policies: set_conversation_blocked() is the only way in, so the
-- side is decided by the database rather than claimed by the client.

create or replace function conversation_is_blocked(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from conversation_blocks where conversation_id = p_conversation_id);
$$;

create or replace function set_conversation_blocked(
  p_conversation_id uuid,
  p_blocked         boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conv conversations;
  v_side text;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select * into v_conv from conversations where id = p_conversation_id;
  if not found then
    raise exception 'no such conversation';
  end if;

  if v_conv.student_id = auth.uid() then
    v_side := 'student';
  elsif is_member_of(v_conv.institution_id) then
    v_side := 'institution';
  else
    raise exception 'that is not your conversation';
  end if;

  if p_blocked then
    insert into conversation_blocks (conversation_id, side, blocked_by)
    values (p_conversation_id, v_side, auth.uid())
    on conflict (conversation_id, side) do nothing;
  else
    -- Each side lifts only its own block.
    delete from conversation_blocks
     where conversation_id = p_conversation_id and side = v_side;
  end if;
end;
$$;

revoke all on function set_conversation_blocked(uuid, boolean) from public;
grant execute on function set_conversation_blocked(uuid, boolean) to authenticated;

-- The enforcement. A blocked conversation accepts no new messages from either
-- party, and a person-to-person block between the student and the sender
-- counts too — the block a student made on a staff member's handle now means
-- what it says in the inbox as well.
drop policy if exists messages_insert_party on messages;
create policy messages_insert_party on messages
  for insert with check (
    sender_id = auth.uid()
    and can_access_conversation(conversation_id)
    and not conversation_is_blocked(conversation_id)
    and not exists (
      select 1 from conversations c
       where c.id = conversation_id
         and is_blocked_either_way(c.student_id))
  );

-- ───────────────────────────────────── 2. reporting a message or a conversation

alter type report_subject add value if not exists 'message';
alter type report_subject add value if not exists 'conversation';

-- Through a function rather than a plain insert: a report must come from
-- someone who could actually see what they are reporting, and a message id
-- must belong to the conversation it is said to be in. Without the check the
-- reports queue could be filled with ids nobody can open.
create or replace function report_conversation(
  p_conversation_id uuid,
  p_reason          report_reason,
  p_message_id      uuid default null,
  p_note            text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  if not can_access_conversation(p_conversation_id) then
    raise exception 'that is not your conversation';
  end if;
  if p_message_id is not null and not exists (
       select 1 from messages
        where id = p_message_id and conversation_id = p_conversation_id) then
    raise exception 'that message is not in this conversation';
  end if;

  insert into reports (reporter_id, subject_type, subject_id, reason, note)
  values (
    auth.uid(),
    (case when p_message_id is null then 'conversation' else 'message' end)::report_subject,
    coalesce(p_message_id, p_conversation_id),
    p_reason,
    nullif(trim(p_note), ''))
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function report_conversation(uuid, report_reason, uuid, text) from public;
grant execute on function report_conversation(uuid, report_reason, uuid, text) to authenticated;

-- ─────────────────────────────────── 3. deleting a staff account cleanly

-- Was `returns void`; now returns the institutions removed with the account,
-- so the delete-account function can clear their files from storage. The
-- return type cannot change in place.
drop function if exists purge_account(uuid);

create function purge_account(p_profile_id uuid)
returns uuid[]
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member   record;
  v_removed  uuid[] := '{}';
  v_heir     uuid;
begin
  if p_profile_id is null then
    raise exception 'purge_account requires a profile id';
  end if;

  for v_member in
    select institution_id, member_role
      from institution_members where profile_id = p_profile_id
  loop
    if not exists (
         select 1 from institution_members
          where institution_id = v_member.institution_id
            and profile_id <> p_profile_id) then
      -- The last person who could run this institution is leaving, so the
      -- institution goes with them: its page, programmes, posts, and the
      -- applications and conversations made to it. A listing nobody can
      -- answer for is worse for students than no listing.
      delete from institutions where id = v_member.institution_id;
      v_removed := v_removed || v_member.institution_id;

    elsif v_member.member_role = 'owner' and not exists (
         select 1 from institution_members
          where institution_id = v_member.institution_id
            and profile_id <> p_profile_id
            and member_role = 'owner') then
      -- The only owner is leaving a team that carries on. The longest-serving
      -- colleague inherits, so the institution is never left without one.
      select profile_id into v_heir
        from institution_members
       where institution_id = v_member.institution_id
         and profile_id <> p_profile_id
       order by created_at
       limit 1;
      update institution_members set member_role = 'owner'
       where institution_id = v_member.institution_id and profile_id = v_heir;
    end if;
  end loop;

  -- Reports this person filed are detached rather than removed: a report is
  -- evidence about its subject (see 20261109000057).
  update reports set reporter_id = null where reporter_id = p_profile_id;

  delete from profiles where id = p_profile_id;

  return v_removed;
end;
$$;

comment on function purge_account(uuid) is
  'Removes a profile and, by cascade, everything it owns. If it was the last '
  'member of an institution, the institution goes too; if it was the only '
  'owner of one that carries on, the longest-serving member becomes owner. '
  'Returns the ids of institutions removed. Service role only.';

revoke all on function purge_account(uuid) from public, anon, authenticated;

-- What the delete-account screen shows staff before they confirm: whether
-- leaving takes their institution with it.
create or replace function my_deletion_impact()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'institution_id', i.id,
           'name', i.name,
           'removes_institution', not exists (
             select 1 from institution_members o
              where o.institution_id = m.institution_id
                and o.profile_id <> m.profile_id),
           'other_members', (
             select count(*) from institution_members o
              where o.institution_id = m.institution_id
                and o.profile_id <> m.profile_id),
           -- True when they are the only owner of a team that carries on, so
           -- ownership passes to the longest-serving colleague.
           'hands_over_ownership', m.member_role = 'owner'
             and exists (
               select 1 from institution_members o
                where o.institution_id = m.institution_id
                  and o.profile_id <> m.profile_id)
             and not exists (
               select 1 from institution_members o
                where o.institution_id = m.institution_id
                  and o.profile_id <> m.profile_id
                  and o.member_role = 'owner'),
           'applications', (select count(*) from applications a where a.institution_id = i.id),
           'conversations', (select count(*) from conversations c where c.institution_id = i.id))), '[]'::jsonb)
    from institution_members m
    join institutions i on i.id = m.institution_id
   where m.profile_id = auth.uid();
$$;

revoke all on function my_deletion_impact() from public;
grant execute on function my_deletion_impact() to authenticated;
