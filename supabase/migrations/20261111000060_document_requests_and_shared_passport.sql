-- Lekkside Connect — answering a document request, and reading a shared passport.
--
-- Two things that were half-built:
--
-- 1. An institution could ask a student for a document, but the student had no
--    way to answer. The request appeared on their application as text with no
--    action, nothing told them it had arrived, and nothing told the institution
--    when (if) it was sent. `fulfil_document_request()` makes the answer one
--    atomic step, and both directions now notify.
--
-- 2. A student who shared their passport with an institution had, in the
--    database, given it every right to read that passport — but the
--    institution's screens are keyed by match token, never by student id, so
--    there was no way to open it. `institution_student_passport()` takes the
--    token the screens already hold and returns the whole passport, but only
--    while a live share exists. Without one it returns just the documents the
--    student chose to send, which is the consent they gave by sending them.

-- ───────────────────────────────────────── 1a. telling the student they were asked

create or replace function request_application_document(
  p_application_id uuid,
  p_kind           document_kind,
  p_note           text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institution uuid;
  v_student     uuid;
  v_name        text;
  v_id          uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select institution_id, profile_id into v_institution, v_student
    from applications where id = p_application_id;

  if v_institution is null then
    raise exception 'no such application';
  end if;
  if not is_member_of(v_institution) and not is_admin() then
    raise exception 'that application was not made to your institution';
  end if;

  insert into application_document_requests
    (application_id, kind, note, requested_by)
  values (p_application_id, p_kind, nullif(trim(p_note), ''), auth.uid())
  returning id into v_id;

  select name into v_name from institutions where id = v_institution;

  -- The app already routes this kind to the applications screen; nothing in
  -- the database had ever sent it.
  insert into notifications (profile_id, kind, title, body, payload)
  values (
    v_student,
    'documents_requested',
    coalesce(v_name, 'An institution') || ' needs a document from you',
    nullif(trim(p_note), ''),
    jsonb_build_object(
      'application_id', p_application_id,
      'request_id', v_id,
      'kind', p_kind,
      'institution_id', v_institution)
  );

  return v_id;
end;
$$;

revoke all on function request_application_document(uuid, document_kind, text) from public;
grant execute on function request_application_document(uuid, document_kind, text) to authenticated;

-- ────────────────────────────────────────────── 1b. the student answers

create or replace function fulfil_document_request(
  p_request_id  uuid,
  p_document_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request     application_document_requests;
  v_application applications;
  v_doc         passport_documents;
  v_student     text;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select * into v_request from application_document_requests where id = p_request_id;
  if not found then
    raise exception 'no such request';
  end if;

  select * into v_application from applications where id = v_request.application_id;
  if v_application.profile_id <> auth.uid() then
    raise exception 'that request was not made to you';
  end if;

  select * into v_doc from passport_documents where id = p_document_id;
  if not found or v_doc.profile_id <> auth.uid() then
    raise exception 'that document is not yours';
  end if;

  -- Attaching is what makes the file readable by the institution (see the
  -- policies below), so it happens in the same statement block as the mark.
  insert into application_documents (application_id, document_id)
  values (v_application.id, v_doc.id)
  on conflict do nothing;

  update application_document_requests
     set fulfilled_at = coalesce(fulfilled_at, now())
   where id = p_request_id;

  select full_name into v_student from profiles where id = auth.uid();

  -- Every officer at the institution, because whoever asked may be away and
  -- the application should not stall on one inbox.
  insert into notifications (profile_id, kind, title, body, payload)
  select m.profile_id,
         'document_received',
         coalesce(v_student, 'A student') || ' sent the document you asked for',
         v_doc.file_name,
         jsonb_build_object(
           'application_id', v_application.id,
           'request_id', p_request_id,
           'document_id', v_doc.id,
           'kind', v_request.kind)
    from institution_members m
   where m.institution_id = v_application.institution_id;
end;
$$;

revoke all on function fulfil_document_request(uuid, uuid) from public;
grant execute on function fulfil_document_request(uuid, uuid) to authenticated;

-- ───────────────────────── 1c. a document sent to an institution is readable by it

-- Before this, an attached document was readable only through a full passport
-- share. A student who answered a request and later revoked the share would
-- leave the institution holding a request marked "sent" and a file it could
-- not open. Attaching is a narrower consent than sharing — this one file, to
-- this institution — and detaching withdraws it.

create or replace function institution_received_document(p_document_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from application_documents ad
      join applications a on a.id = ad.application_id
     where ad.document_id = p_document_id
       and is_member_of(a.institution_id));
$$;

drop policy if exists documents_select_attached on passport_documents;
create policy documents_select_attached on passport_documents
  for select using (institution_received_document(id));

drop policy if exists passport_docs_select_attached on storage.objects;
create policy passport_docs_select_attached on storage.objects
  for select to authenticated
  using (
    bucket_id = 'passport-docs'
    and exists (
      select 1 from passport_documents d
       where d.storage_path = name
         and institution_received_document(d.id))
  );

-- ───────────────────────────────────────── 2. the shared passport, in one call

create or replace function institution_student_passport(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  -- Raises unless the caller staffs the institution the token was issued to.
  v_student     uuid := student_for_match_token(p_token);
  v_institution uuid;
  v_shared      boolean;
  v_share       passport_shares;
  v_result      jsonb;
begin
  select institution_id into v_institution from match_tokens where token = p_token;
  v_shared := institution_can_see_student(v_institution, v_student);

  select * into v_share from passport_shares
   where profile_id = v_student and institution_id = v_institution and revoked_at is null
   order by granted_at desc limit 1;

  v_result := jsonb_build_object(
    'token', p_token,
    'shared', v_shared,
    'share', case when v_shared then jsonb_build_object(
               'granted_at', v_share.granted_at, 'reason', v_share.reason) end,

    -- Their applications here, with what was asked for and what was sent.
    -- Visible either way: the student made these to this institution.
    'applications', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', a.id,
               'program_name', pg.name,
               'program_level', pg.level,
               'intake', a.intake,
               'stage', a.stage,
               'submitted_at', a.submitted_at,
               'requests', coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'id', r.id, 'kind', r.kind, 'note', r.note,
                          'fulfilled_at', r.fulfilled_at, 'created_at', r.created_at)
                          order by r.created_at)
                   from application_document_requests r where r.application_id = a.id), '[]'::jsonb),
               'document_ids', coalesce((
                 select jsonb_agg(ad.document_id)
                   from application_documents ad where ad.application_id = a.id), '[]'::jsonb))
             order by a.created_at desc)
        from applications a
        left join programs pg on pg.id = a.program_id
       where a.profile_id = v_student and a.institution_id = v_institution), '[]'::jsonb),

    -- With a share, every document in the passport. Without one, only what
    -- they attached to an application here.
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', d.id, 'kind', d.kind, 'file_name', d.file_name,
               'mime', d.mime, 'size_bytes', d.size_bytes,
               'storage_path', d.storage_path,
               'verification_status', d.verification_status,
               'created_at', d.created_at)
             order by d.created_at desc)
        from passport_documents d
       where d.profile_id = v_student
         and (v_shared or exists (
               select 1 from application_documents ad
                 join applications a on a.id = ad.application_id
                where ad.document_id = d.id and a.institution_id = v_institution))), '[]'::jsonb)
  );

  if not v_shared then
    return v_result;
  end if;

  return v_result || jsonb_build_object(
    'student', (
      select jsonb_build_object(
               'full_name', p.full_name,
               'avatar_url', p.avatar_url,
               'country', p.country,
               'phone', p.phone,
               'email', u.email,
               'handle', sp.handle,
               'member_since', p.created_at)
        from profiles p
        left join auth.users u on u.id = p.id
        left join social_profiles sp on sp.profile_id = p.id
       where p.id = v_student),
    'passport', (
      select to_jsonb(sp) - 'verified_by'
        from student_passports sp where sp.profile_id = v_student)
  );
end;
$$;

revoke all on function institution_student_passport(text) from public;
grant execute on function institution_student_passport(text) to authenticated;

comment on function institution_student_passport(text) is
  'The full passport, contact details and documents of a student who shared '
  'with the caller''s institution, by match token. Without a live share: only '
  'their applications here and the documents they sent.';
