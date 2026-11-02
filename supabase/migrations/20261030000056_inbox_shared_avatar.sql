-- A face in the institution's inbox, once there is one to show.
--
-- The inbox has never carried an avatar. That was right while the only thing
-- it could show was a generic silhouette on every row — but it stayed wrong
-- after a student shared their passport, when the institution has their name
-- and a picture and sees neither.
--
-- Gated on institution_can_see_student, exactly like `shared_name`, and that
-- is not belt-and-braces. `profiles.avatar_url` points into the public
-- `avatars` bucket and the same image is on the student's handle profile, so
-- an avatar on an UNSHARED row would be a way to match an anonymous thread to
-- a public handle — which is precisely what the match token exists to
-- prevent. No share, no face: the lock stays.
--
-- `profiles.avatar_url` rather than `social_profiles.avatar_url`: the share
-- grants access to the passport identity, and `shared_name` already comes
-- from `profiles`. Two sources would eventually disagree about who somebody is.

create or replace view institution_inbox
with (security_barrier = true)
as
select
  c.id            as conversation_id,
  c.institution_id,
  c.subject,
  c.last_message_at,
  c.created_at,

  match_token_for(c.student_id, c.institution_id) as token,
  institution_can_see_student(c.institution_id, c.student_id) as is_shared,
  case when institution_can_see_student(c.institution_id, c.student_id)
       then (select pr.full_name from profiles pr where pr.id = c.student_id)
  end as shared_name,

  (select case when m.deleted_at is not null then 'Message deleted' else m.body end
     from messages m
    where m.conversation_id = c.id
    order by m.created_at desc limit 1)            as last_message_body,
  (select m.sender_id = c.student_id from messages m
    where m.conversation_id = c.id
    order by m.created_at desc limit 1)            as last_message_from_student,
  (select count(*) from messages m
    where m.conversation_id = c.id
      and m.sender_id = c.student_id
      and m.created_at > coalesce(
            (select cp.last_read_at from conversation_participants cp
              where cp.conversation_id = c.id and cp.profile_id = auth.uid()),
            '-infinity'::timestamptz))::int        as unread_count,

  (select cp.pinned_at from conversation_participants cp
    where cp.conversation_id = c.id and cp.profile_id = auth.uid())
                                                   as pinned_at,
  (select cp.archived_at from conversation_participants cp
    where cp.conversation_id = c.id and cp.profile_id = auth.uid())
                                                   as archived_at,

  -- Appended rather than sitting beside `shared_name` where it belongs:
  -- CREATE OR REPLACE VIEW can add a column at the end and cannot insert one
  -- in the middle, and dropping the view to reorder it would take its grants
  -- with it for no gain anyone can see.
  case when institution_can_see_student(c.institution_id, c.student_id)
       then (select pr.avatar_url from profiles pr where pr.id = c.student_id)
  end as shared_avatar_url

from conversations c
where is_member_of(c.institution_id) or is_admin();

comment on view institution_inbox is
  'An institution''s conversations, keyed by match token rather than account '
  'id. `shared_name` and `shared_avatar_url` are null until the student shares '
  'their passport, so the inbox works for anonymous students without leaking '
  'who they are — an avatar is as identifying as a name here, because the '
  'same image is on their public handle profile. `pinned_at` and '
  '`archived_at` are the CALLER''s, not the institution''s.';

revoke all on institution_inbox from public;
grant select on institution_inbox to authenticated;
