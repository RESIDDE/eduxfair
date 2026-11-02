-- Lekkside Connect — prospectus access, storage, and the one-call read.
--
-- The prospectus is public-facing by design: it is the page an institution
-- wants students to read. So the rule is the same for all seven tables —
-- any signed-in user reads, only the institution's own staff write — which is
-- applied as one loop rather than seven near-identical blocks.

do $$
declare
  t text;
begin
  foreach t in array array[
    'institution_profiles', 'institution_media', 'institution_intakes',
    'institution_scholarships', 'institution_entry_requirements',
    'institution_contacts', 'institution_faqs'
  ] loop
    execute format('alter table %I enable row level security', t);

    execute format(
      'create policy %I on %I for select using (auth.uid() is not null)',
      t || '_select_authenticated', t);

    execute format(
      'create policy %I on %I for all
         using (is_member_of(institution_id))
         with check (is_member_of(institution_id))',
      t || '_write_member', t);

    execute format(
      'create policy %I on %I for all using (is_admin()) with check (is_admin())',
      t || '_all_admin', t);
  end loop;
end
$$;

-- ------------------------------------------------------------------ storage

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('institution-media', 'institution-media', true, 10485760,  -- 10 MB
   array['image/jpeg', 'image/png', 'image/webp', 'image/heic',
         'application/pdf'])
on conflict (id) do nothing;

-- Path convention: institution-media/<institution_uuid>/<file>, matching the
-- CHECK on institution_media.storage_path, so a policy can authorize on the
-- first path segment without joining back to the row.
create policy institution_media_read on storage.objects
  for select using (bucket_id = 'institution-media');

create policy institution_media_write_member on storage.objects
  for all to authenticated
  using (
    bucket_id = 'institution-media'
    and is_member_of(((storage.foldername(name))[1])::uuid)
  )
  with check (
    bucket_id = 'institution-media'
    and is_member_of(((storage.foldername(name))[1])::uuid)
  );

-- ------------------------------------------- the prospectus, in one request
--
-- Seven tables behind one call. A student opening an institution page on a
-- Lagos mobile connection should not wait on seven sequential round trips, and
-- PostgREST cannot express "the requirements that apply to me" as an embed.

create or replace function institution_prospectus(
  p_institution_id uuid,
  p_from_country   text default null,
  p_level          study_level default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_country text := p_from_country;
  v_result  jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  -- Default to the caller's own passport, so the client does not have to pass
  -- what the server already knows.
  if v_country is null then
    select coalesce(current_country, nationality) into v_country
      from student_passports where profile_id = auth.uid();
  end if;

  select jsonb_build_object(
    'institution', (
      select to_jsonb(i) - 'email_domain'
        from institutions i where i.id = p_institution_id),

    'profile', (
      select to_jsonb(p)
        from institution_profiles p where p.institution_id = p_institution_id),

    'media', (
      select coalesce(jsonb_agg(to_jsonb(m) order by m.ord, m.created_at), '[]'::jsonb)
        from institution_media m where m.institution_id = p_institution_id),

    'intakes', (
      select coalesce(jsonb_agg(to_jsonb(n) order by n.ord, n.term_starts), '[]'::jsonb)
        from institution_intakes n where n.institution_id = p_institution_id),

    'scholarships', (
      select coalesce(jsonb_agg(to_jsonb(s) order by s.ord), '[]'::jsonb)
        from institution_scholarships s where s.institution_id = p_institution_id),

    'contacts', (
      select coalesce(jsonb_agg(to_jsonb(c) order by c.ord), '[]'::jsonb)
        from institution_contacts c where c.institution_id = p_institution_id),

    'faqs', (
      select coalesce(jsonb_agg(to_jsonb(f) order by f.ord), '[]'::jsonb)
        from institution_faqs f where f.institution_id = p_institution_id),

    -- Requirements that apply to this student: their own country first, then
    -- the general rule. Ordered so the client can take the first match per
    -- level without re-deriving the precedence.
    'requirements', (
      select coalesce(jsonb_agg(to_jsonb(r) order by
               (r.from_country is null),   -- a country-specific rule wins
               (r.level is null),
               r.ord), '[]'::jsonb)
        from institution_entry_requirements r
       where r.institution_id = p_institution_id
         and (r.from_country is null or r.from_country = v_country)
         and (r.level is null or p_level is null or r.level = p_level)),

    'programs', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', g.id, 'institution_id', g.institution_id,
               'name', g.name, 'level', g.level,
               'field_of_study', g.field_of_study,
               'tuition_min', g.tuition_min, 'tuition_max', g.tuition_max,
               'tuition_currency', g.tuition_currency,
               'duration_months', g.duration_months,
               'intakes', g.intakes,
               'scholarship_available', g.scholarship_available
             ) order by g.level, g.name), '[]'::jsonb)
        from programs g
       where g.institution_id = p_institution_id and g.is_active),

    'resolved_for_country', v_country
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function institution_prospectus(uuid, text, study_level) from public;
grant execute on function institution_prospectus(uuid, text, study_level)
  to authenticated;

comment on function institution_prospectus is
  'The whole institution page in one call, with entry requirements narrowed to '
  'the calling student''s own country. Seven sequential round trips on a mobile '
  'connection is a visible wait.';
