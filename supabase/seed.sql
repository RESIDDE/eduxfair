-- Lekkside Connect — development seed data.
--
-- Run by `supabase db reset` against a local or hosted project. NOT run by the
-- PGlite test harness in supabase/tests, which builds its own fixture (the
-- harness shims auth.users minimally and cannot host real GoTrue identities).
--
-- Every account below uses the password:  Lekkside123!
--
-- !! DEVELOPMENT ONLY. Do not run against production: it creates sign-in-able
-- !! accounts with a published password.

-- GoTrue needs both an auth.users row and a matching auth.identities row before
-- email/password sign-in works, so this wraps the pair up.
create or replace function seed_user(
  p_email text,
  p_role  text,
  p_name  text
)
returns uuid
language plpgsql
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
    p_email, extensions.crypt('Lekkside123!', extensions.gen_salt('bf')),
    now(), '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('role', p_role, 'full_name', p_name),
    now(), now()
  );

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider, last_sign_in_at,
    created_at, updated_at
  ) values (
    gen_random_uuid(), v_id, v_id::text,
    jsonb_build_object('sub', v_id::text, 'email', p_email, 'email_verified', true),
    'email', now(), now(), now()
  );

  return v_id;
end;
$$;

do $seed$
declare
  v_admin   uuid;
  v_ownerCA uuid;
  v_ownerUK uuid;
  v_ownerUS uuid;
  v_officer uuid;
  v_instCA  uuid;
  v_instUK  uuid;
  v_instUS  uuid;
  v_fair    uuid;
  v_student uuid;
  v_prog    uuid;
  r         record;
begin
  -- -------------------------------------------------------------- people
  v_admin   := seed_user('admin@lekkside.com',        'student',            'Lekkside Admin');
  v_ownerCA := seed_user('admissions@maplecrest.ca',  'institution_member', 'Amara Okonkwo');
  v_officer := seed_user('officer@maplecrest.ca',     'institution_member', 'Daniel Chen');
  v_ownerUK := seed_user('admissions@northgate.ac.uk','institution_member', 'Priya Raman');
  v_ownerUS := seed_user('admissions@lakeshore.edu',  'institution_member', 'Jordan Ellis');

  -- 'admin' is deliberately not self-assignable at signup, so grant it here.
  update profiles set role = 'admin' where id = v_admin;

  -- -------------------------------------------------- institutions + programs
  insert into institutions (name, slug, country, city, website, email_domain,
                            description, verification_status, verified_at)
  values ('Maplecrest University', 'maplecrest-university', 'CA', 'Toronto',
          'https://maplecrest.ca', 'maplecrest.ca',
          'Research university with strong co-op placement in technology and engineering.',
          'verified', now())
  returning id into v_instCA;

  insert into institutions (name, slug, country, city, website, email_domain,
                            description, verification_status, verified_at)
  values ('Northgate College London', 'northgate-college-london', 'GB', 'London',
          'https://northgate.ac.uk', 'northgate.ac.uk',
          'Business and computing college in central London with January and September intakes.',
          'verified', now())
  returning id into v_instUK;

  insert into institutions (name, slug, country, city, website, email_domain,
                            description, verification_status)
  values ('Lakeshore State University', 'lakeshore-state-university', 'US', 'Chicago',
          'https://lakeshore.edu', 'lakeshore.edu',
          'Public university with merit scholarships for international undergraduates.',
          'pending')
  returning id into v_instUS;

  insert into institution_members (institution_id, profile_id, member_role) values
    (v_instCA, v_ownerCA, 'owner'),
    (v_instCA, v_officer, 'admissions_officer'),
    (v_instUK, v_ownerUK, 'owner'),
    (v_instUS, v_ownerUS, 'owner');

  insert into institution_subscriptions (institution_id, tier, seats) values
    (v_instCA, 'enterprise', 5),
    (v_instUK, 'professional', 2),
    (v_instUS, 'basic', 1);

  insert into programs (institution_id, name, level, field_of_study,
                        tuition_min, tuition_max, tuition_currency, duration_months,
                        intakes, min_grade_value, min_grade_scheme, min_english_band,
                        scholarship_available, is_active)
  values
    (v_instCA, 'BSc Computer Science', 'undergraduate', 'computer-science',
     18000, 24000, 'USD', 48, array['Fall 2026','Winter 2027'], 65, 'percentage', 6.5, true, true),
    (v_instCA, 'MSc Data Science', 'postgraduate', 'data-science',
     22000, 28000, 'USD', 16, array['Fall 2026'], 70, 'percentage', 6.5, true, true),
    (v_instCA, 'BEng Mechanical Engineering', 'undergraduate', 'engineering',
     19000, 25000, 'USD', 48, array['Fall 2026'], 65, 'percentage', 6.0, false, true),
    (v_instUK, 'BSc Business Management', 'undergraduate', 'business',
     13000, 16000, 'USD', 36, array['January 2027','September 2026'], 60, 'percentage', 6.0, false, true),
    (v_instUK, 'MSc Computing', 'postgraduate', 'computer-science',
     15000, 19000, 'USD', 12, array['September 2026'], 65, 'percentage', 6.5, true, true),
    (v_instUK, 'Foundation in Business', 'foundation', 'business',
     9000, 11000, 'USD', 12, array['January 2027'], 50, 'percentage', 5.5, false, true),
    (v_instUS, 'BS Nursing', 'undergraduate', 'nursing',
     26000, 32000, 'USD', 48, array['Fall 2026'], 70, 'percentage', 6.5, true, true),
    (v_instUS, 'BS Cybersecurity', 'undergraduate', 'cybersecurity',
     24000, 30000, 'USD', 48, array['Fall 2026','Spring 2027'], 65, 'percentage', 6.0, true, true);

  -- ------------------------------------------------------------- students
  -- Spread across countries, budgets and fields so the matching engine and the
  -- demand dashboard both have something non-trivial to show. The demand view
  -- suppresses cells below 5 students, so several share each target.
  for r in
    select * from (values
      ('chidi.okeke@example.com',     'Chidi Okeke',       'NG', 78, 7.0, array['CA','GB'], 'computer-science', 30000),
      ('amina.bello@example.com',     'Amina Bello',       'NG', 82, 7.5, array['CA','US'], 'computer-science', 35000),
      ('tunde.adebayo@example.com',   'Tunde Adebayo',     'NG', 71, 6.5, array['GB'],      'business',         20000),
      ('ngozi.eze@example.com',       'Ngozi Eze',         'NG', 88, 8.0, array['CA','GB'], 'data-science',     40000),
      ('kwame.mensah@example.com',    'Kwame Mensah',      'GH', 75, 6.5, array['CA'],      'engineering',      28000),
      ('akosua.darko@example.com',    'Akosua Darko',      'GH', 69, 6.0, array['GB'],      'business',         18000),
      ('wanjiku.kamau@example.com',   'Wanjiku Kamau',     'KE', 84, 7.0, array['US','CA'], 'nursing',          33000),
      ('brian.otieno@example.com',    'Brian Otieno',      'KE', 73, 6.5, array['CA','GB'], 'cybersecurity',    30000),
      ('fatima.sow@example.com',      'Fatima Sow',        'NG', 66, 6.0, array['GB'],      'computer-science', 16000),
      ('emeka.nwosu@example.com',     'Emeka Nwosu',       'NG', 79, 7.0, array['CA'],      'computer-science', 26000),
      ('zainab.yusuf@example.com',    'Zainab Yusuf',      'NG', 91, 8.0, array['US','GB'], 'medicine',         45000),
      ('samuel.mwangi@example.com',   'Samuel Mwangi',     'KE', 68, 6.0, array['CA','GB'], 'business',         19000)
    ) as t(email, name, country, grade, ielts, targets, field, budget)
  loop
    v_student := seed_user(r.email, 'student', r.name);

    insert into student_passports (
      profile_id, date_of_birth, nationality, current_country,
      highest_qualification, grade_value, grade_scheme,
      english_test_name, english_score,
      target_countries, target_levels, target_fields,
      budget_min, budget_max, budget_currency, intended_intake, bio
    ) values (
      v_student, date '2004-01-01' + (random() * 700)::int,
      r.country, r.country,
      case when r.country = 'NG' then 'WASSCE' else 'Senior Secondary Certificate' end,
      r.grade, 'percentage', 'ielts', r.ielts,
      r.targets,
      case when r.field in ('data-science', 'medicine')
           then array['postgraduate']::study_level[]
           else array['undergraduate']::study_level[] end,
      array[r.field],
      5000, r.budget, 'USD', 'Fall 2026',
      'Seeking a place for Fall 2026. Happy to discuss scholarships.'
    );
  end loop;

  -- ---------------------------------------------------------------- the fair
  insert into fairs (name, slug, city, country, venue, starts_at, ends_at)
  values ('Lekkside International Education Fair — Lagos 2026', 'lagos-2026',
          'Lagos', 'NG', 'Eko Convention Centre, Victoria Island',
          now() + interval '45 days', now() + interval '46 days')
  returning id into v_fair;

  insert into fair_exhibitors (fair_id, institution_id, booth_code, booth_label, package) values
    (v_fair, v_instCA, 'A01', 'Maplecrest University',      'booth_plus_platform'),
    (v_fair, v_instUK, 'A02', 'Northgate College London',   'booth_plus_platform'),
    (v_fair, v_instUS, 'B01', 'Lakeshore State University', 'booth_only');

  -- Register every seeded student, so each has a scannable Fair Passport.
  insert into fair_registrations (fair_id, profile_id)
  select v_fair, id from profiles where role = 'student';

  -- -------------------------------------------------- one worked-through case
  -- A student mid-pipeline, so the institution dashboard is not empty on first
  -- load and the student app has a timeline to render.
  select id into v_student from profiles where full_name = 'Chidi Okeke';
  select id into v_prog from programs
   where institution_id = v_instCA and name = 'BSc Computer Science';

  insert into applications (profile_id, institution_id, program_id, intake, stage, student_note)
  values (v_student, v_instCA, v_prog, 'Fall 2026', 'under_review',
          'I have completed WASSCE with 78% average and IELTS 7.0.');

  insert into institution_interests (institution_id, program_id, profile_id, kind, note, created_by)
  values (v_instCA, v_prog, v_student, 'invited',
          'Strong match for our co-op stream.', v_ownerCA);

  insert into availability_slots (institution_id, host_profile_id, starts_at, ends_at)
  select v_instCA, v_ownerCA,
         date_trunc('hour', now()) + (n || ' days')::interval + interval '10 hours',
         date_trunc('hour', now()) + (n || ' days')::interval + interval '10 hours 30 minutes'
    from generate_series(3, 12) as n;

  raise notice 'Seed complete. All accounts use the password: Lekkside123!';
  raise notice 'Admin: admin@lekkside.com | Institution: admissions@maplecrest.ca';
  raise notice 'Student: chidi.okeke@example.com';
end
$seed$;

drop function seed_user(text, text, text);
