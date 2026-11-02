-- Appointed moderators: the enum labels, and nothing else.
--
-- This file is one `alter type` per line and no functions, which looks like an
-- arbitrary split and is not. Postgres refuses to let a label added by ALTER
-- TYPE be *used* in the same transaction that added it, and every runner this
-- project has — the Supabase CLI, and supabase/tests/run.mjs — applies one
-- migration file per transaction. So the labels land here and the functions
-- that read them land in 20261029000048, which is the next transaction.
--
-- Why a `moderator` role rather than reusing `cohost`: the schema already
-- spells "staff of the hosting institution" as `role in ('host', 'cohost')` in
-- six places, and two of them — space_roster.shared_name and
-- space_room_grant.display_name — publish that person's real full name on the
-- strength of it. Appointing an attendee into `cohost` would therefore have
-- unmasked them to the room as a side effect of being handed a mute button.
-- A separate label leaves every one of those checks meaning exactly what it
-- meant before.

alter type space_role add value if not exists 'moderator' after 'cohost';

alter type space_moderation_action add value if not exists 'camera_muted'       after 'muted';
alter type space_moderation_action add value if not exists 'muted_everyone'     after 'camera_muted';
alter type space_moderation_action add value if not exists 'moderator_granted'  after 'muted_everyone';
alter type space_moderation_action add value if not exists 'moderator_revoked'  after 'moderator_granted';
