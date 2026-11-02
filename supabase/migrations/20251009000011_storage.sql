-- Lekkside Connect — storage buckets and object policies.
--
-- `passport-docs` holds transcripts and identity documents. Those are the most
-- sensitive objects on the platform, so the bucket is private and every path is
-- prefixed with the owning student's uuid — which is what lets a policy
-- authorize on prefix alone, without a join back to the metadata table.
--
-- Path convention (enforced by a CHECK on passport_documents.storage_path):
--     passport-docs/<student_uuid>/<document_uuid>-<filename>

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('passport-docs', 'passport-docs', false, 20971520,  -- 20 MB
   array['application/pdf', 'image/jpeg', 'image/png', 'image/heic',
         'application/msword',
         'application/vnd.openxmlformats-officedocument.wordprocessingml.document']),
  ('institution-logos', 'institution-logos', true, 2097152,  -- 2 MB, public
   array['image/jpeg', 'image/png', 'image/svg+xml', 'image/webp']),
  ('avatars', 'avatars', true, 2097152,
   array['image/jpeg', 'image/png', 'image/webp', 'image/heic']),
  ('message-attachments', 'message-attachments', false, 20971520,
   array['application/pdf', 'image/jpeg', 'image/png', 'image/heic',
         'application/msword',
         'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict (id) do nothing;

-- --------------------------------------------------------- passport documents

-- The first path segment is the owner's uuid.
create policy passport_docs_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'passport-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy passport_docs_select_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'passport-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy passport_docs_update_own on storage.objects
  for update to authenticated
  using (
    bucket_id = 'passport-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy passport_docs_delete_own on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'passport-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- An institution reads a student's documents only through the same consent gate
-- as the rest of their passport. The uuid in the path is the student id, so the
-- helper can be applied directly to the prefix.
create policy passport_docs_select_shared on storage.objects
  for select to authenticated
  using (
    bucket_id = 'passport-docs'
    and my_institution_can_see_student(((storage.foldername(name))[1])::uuid)
  );

create policy passport_docs_select_admin on storage.objects
  for select to authenticated
  using (bucket_id = 'passport-docs' and is_admin());

-- ------------------------------------------------------------- public buckets

create policy institution_logos_read on storage.objects
  for select using (bucket_id = 'institution-logos');

-- Path convention: institution-logos/<institution_uuid>/<file>
create policy institution_logos_write_member on storage.objects
  for all to authenticated
  using (
    bucket_id = 'institution-logos'
    and is_member_of(((storage.foldername(name))[1])::uuid)
  )
  with check (
    bucket_id = 'institution-logos'
    and is_member_of(((storage.foldername(name))[1])::uuid)
  );

create policy avatars_read on storage.objects
  for select using (bucket_id = 'avatars');

create policy avatars_write_own on storage.objects
  for all to authenticated
  using (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text
  );

-- --------------------------------------------------------- message attachments
--
-- Path convention: message-attachments/<conversation_uuid>/<file>, so access
-- follows the conversation rather than the uploader — both parties need it.

create policy message_attachments_select_party on storage.objects
  for select to authenticated
  using (
    bucket_id = 'message-attachments'
    and can_access_conversation(((storage.foldername(name))[1])::uuid)
  );

create policy message_attachments_insert_party on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'message-attachments'
    and can_access_conversation(((storage.foldername(name))[1])::uuid)
  );
