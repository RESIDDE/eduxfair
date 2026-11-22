-- Lekkside Connect — the super admin sees everything on the platform.
--
-- The console is the operator's view of the whole service: every account,
-- every institution and its prospectus, every passport and document, every
-- application, conversation, post and meeting. Most tables already carried an
-- `is_admin()` read policy. These are the ones that did not, which left the
-- console blind to them:
--
--   blocks, mutes                  — who has shut out whom (safety context)
--   post_bookmarks                 — what a person saved
--   conversation_participants      — read state inside a conversation
--   application_document_requests  — what an institution asked a student for
--   message_reactions, message_hides
--   institution_domain_verifications — the evidence behind a domain badge
--
-- Read-only on purpose. Admin *actions* keep going through the existing
-- policies and RPCs (remove_post, remove_comment, verifications, restrictions),
-- which carry their own guards and audit trails.
--
-- Deliberately NOT opened: `account_otps` and `match_tokens`. They hold
-- one-time secrets; reading them would let an admin sign in as a user, which
-- is impersonation, not oversight.
--
-- The privacy policy in the app says so: authorised staff can access account
-- content for verification, safety, moderation and support.

do $$
declare
  t text;
begin
  foreach t in array array[
    'blocks', 'mutes', 'post_bookmarks', 'conversation_participants',
    'application_document_requests', 'message_reactions', 'message_hides',
    'institution_domain_verifications'
  ] loop
    execute format('drop policy if exists %I on %I', t || '_select_admin', t);
    execute format(
      'create policy %I on %I for select using (is_admin())',
      t || '_select_admin', t);
  end loop;
end
$$;

-- Chat attachments: images, files and voice notes sent in a conversation.
-- Readable by the two parties already; the admin joins them so a reported
-- conversation can be reviewed in full.
drop policy if exists message_attachments_select_admin on storage.objects;
create policy message_attachments_select_admin on storage.objects
  for select using (bucket_id = 'message-attachments' and is_admin());
