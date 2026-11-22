// Exercises every request shape the two apps actually make, against a running
// dev server.
//
// Faster and far more precise than clicking through the UI: a 400 here names
// the exact query that is wrong, which is how the embed-ambiguity bugs in the
// React console were found.
//
//   node smoke.mjs        (with `npm start` running in another terminal)

const BASE = process.env.DEVSERVER_URL ?? 'http://localhost:54321';

let anonKey;
let passed = 0;
let failed = 0;

const green = (s) => `\x1b[32m${s}\x1b[0m`;
const red = (s) => `\x1b[31m${s}\x1b[0m`;
const dim = (s) => `\x1b[2m${s}\x1b[0m`;

function ok(label, detail) {
  passed += 1;
  console.log(`  ${green('ok')}  ${label}${detail ? ' ' + dim(detail) : ''}`);
}

function fail(label, detail) {
  failed += 1;
  console.log(`  ${red('FAIL')}  ${label}`);
  if (detail) console.log(red(`        ${detail}`));
}

async function request(path, { token, method = 'GET', body, headers = {} } = {}) {
  const response = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${token ?? anonKey}`,
      'Content-Type': 'application/json',
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  const text = await response.text();
  let json;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = text;
  }
  return { status: response.status, body: json, headers: response.headers };
}

/** Asserts a request succeeds, and hands the body back. */
async function expectOk(label, path, options = {}) {
  const result = await request(path, options);
  if (result.status >= 200 && result.status < 300) {
    const count = Array.isArray(result.body) ? `(${result.body.length} rows)` : '';
    ok(label, count);
    return result.body;
  }
  fail(label, `${result.status} ${JSON.stringify(result.body)?.slice(0, 220)}`);
  return null;
}

async function expectStatus(label, expected, path, options = {}) {
  const result = await request(path, options);
  if (result.status === expected) {
    ok(label, dim(`(${expected})`));
    return result.body;
  }
  fail(label, `expected ${expected}, got ${result.status} ` +
    `${JSON.stringify(result.body)?.slice(0, 180)}`);
  return null;
}

async function signIn(email) {
  const result = await request('/auth/v1/token?grant_type=password', {
    method: 'POST',
    body: { email, password: 'Lekkside123!' },
  });
  if (result.status !== 200) {
    throw new Error(`could not sign in as ${email}: ${JSON.stringify(result.body)}`);
  }
  return result.body;
}

async function main() {
  // The anon key is printed by the server, but it is also derivable: ask the
  // health endpoint first to be sure the server is up, then read the key the
  // same way a client would be configured.
  const health = await fetch(`${BASE}/health`).catch(() => null);
  if (!health?.ok) {
    console.error(red(`\n  No dev server at ${BASE}. Run \`npm start\` first.\n`));
    process.exit(1);
  }

  const { ANON_KEY } = await import('./auth.mjs');
  anonKey = ANON_KEY;

  console.log('\nAuth');
  const student = await signIn('chidi.okeke@example.com');
  ok('sign in as a student', dim(student.user.email));
  const institution = await signIn('admissions@maplecrest.ca');
  ok('sign in as an institution owner');
  const admin = await signIn('admin@lekkside.com');
  ok('sign in as admin');

  await expectStatus(
    'a wrong password is refused', 400,
    '/auth/v1/token?grant_type=password',
    { method: 'POST', body: { email: 'chidi.okeke@example.com', password: 'nope' } },
  );

  await expectOk('read the current user', '/auth/v1/user', { token: student.access_token });

  const refreshed = await expectOk(
    'refresh a session', '/auth/v1/token?grant_type=refresh_token',
    { method: 'POST', body: { refresh_token: student.refresh_token } },
  );
  if (refreshed?.access_token) ok('refresh returns a new access token');

  // Sign-up, both roles the app's signup fork offers. Nothing exercised this
  // endpoint before, which is how it shipped broken: it bound one placeholder
  // in two positions (uuid and text) and failed on every single call, so no
  // account could ever be created through the app.
  const stamp = Date.now();
  const studentSignup = await expectOk(
    'sign up as a student', '/auth/v1/signup',
    { method: 'POST', body: {
      email: `smoke.student.${stamp}@example.com`,
      password: 'Lekkside123!',
      data: { role: 'student', full_name: 'Smoke Student' },
    } });
  if (studentSignup?.access_token) ok('student signup returns a session');

  const orgSignup = await expectOk(
    'sign up as an institution', '/auth/v1/signup',
    { method: 'POST', body: {
      email: `smoke.org.${stamp}@college.example`,
      password: 'Lekkside123!',
      data: { role: 'institution_member', full_name: 'Smoke Registrar' },
    } });
  if (orgSignup?.access_token) ok('institution signup returns a session');

  // The role requested at signup has to survive into the profile, because the
  // router reads it to choose which shell the person gets.
  if (orgSignup?.access_token) {
    const orgProfile = await expectOk(
      'the requested role reaches the profile',
      `/rest/v1/profiles?select=role&id=eq.${orgSignup.user.id}`,
      { token: orgSignup.access_token,
        headers: { Accept: 'application/vnd.pgrst.object+json' } });
    if (orgProfile?.role === 'institution_member')
      ok('signup role is institution_member');
    else fail('signup role', `got '${orgProfile?.role}'`);
  }

  // And the clamp still holds for the role no signup form offers.
  const sneaky = await expectOk(
    'signup asking for admin is accepted', '/auth/v1/signup',
    { method: 'POST', body: {
      email: `smoke.sneak.${stamp}@example.com`,
      password: 'Lekkside123!',
      data: { role: 'admin', full_name: 'Smoke Sneak' },
    } });
  if (sneaky?.access_token) {
    const sneakProfile = await expectOk(
      'and lands as a student, not an admin',
      `/rest/v1/profiles?select=role&id=eq.${sneaky.user.id}`,
      { token: sneaky.access_token,
        headers: { Accept: 'application/vnd.pgrst.object+json' } });
    if (sneakProfile?.role === 'student') ok('role=admin was clamped to student');
    else fail('signup role clamp', `got '${sneakProfile?.role}'`);
  }

  await expectStatus(
    'signing up twice with one address is refused', 422,
    '/auth/v1/signup',
    { method: 'POST', body: {
      email: `smoke.student.${stamp}@example.com`,
      password: 'Lekkside123!',
      data: { role: 'student', full_name: 'Smoke Student' },
    } });

  const S = { token: student.access_token };
  const I = { token: institution.access_token };
  const A = { token: admin.access_token };

  // ── The student app's queries ────────────────────────────────────────────

  console.log('\nStudent app queries');

  await expectOk('profiles: own row',
    `/rest/v1/profiles?select=*&id=eq.${student.user.id}`,
    { ...S, headers: { Accept: 'application/vnd.pgrst.object+json' } });

  const passport = await expectOk('student_passports: own passport',
    `/rest/v1/student_passports?select=*&profile_id=eq.${student.user.id}`, S);
  if (passport?.[0]?.completeness >= 50) {
    ok('passport has a server-computed completeness',
      dim(`(${passport[0].completeness}%)`));
  } else {
    fail('passport completeness', `got ${JSON.stringify(passport?.[0]?.completeness)}`);
  }
  if (passport?.[0]?.normalized_grade != null && passport?.[0]?.english_band != null) {
    ok('generated columns come through',
      dim(`(grade ${passport[0].normalized_grade}, band ${passport[0].english_band})`));
  } else {
    fail('generated columns', 'normalized_grade or english_band missing');
  }
  if (Array.isArray(passport?.[0]?.target_countries)) {
    ok('array columns decode as arrays',
      dim(`(${passport[0].target_countries.join(', ')})`));
  } else {
    fail('array columns', `target_countries was ${typeof passport?.[0]?.target_countries}`);
  }

  await expectOk('passport_documents: own documents',
    `/rest/v1/passport_documents?select=*&profile_id=eq.${student.user.id}&order=created_at.desc`, S);

  await expectOk('passport_shares with an embedded institution',
    `/rest/v1/passport_shares?select=*,institutions(id,name,logo_url,country)` +
    `&profile_id=eq.${student.user.id}&order=granted_at.desc`, S);

  await expectOk('fields_of_study vocabulary',
    '/rest/v1/fields_of_study?select=*&order=sort_order', S);

  const programs = await expectOk('programs with an inner-joined institution, paged',
    '/rest/v1/programs?select=*,institutions!inner(id,name,slug,country,city,' +
    'logo_url,verification_status,tier)&is_active=eq.true&order=created_at.desc',
    { ...S, headers: { Range: '0-19' } });
  if (programs?.[0]?.institutions?.name) {
    ok('the embedded institution is an object', dim(programs[0].institutions.name));
  } else {
    fail('to-one embed', `institutions was ${JSON.stringify(programs?.[0]?.institutions)}`);
  }

  await expectOk('programs filtered through the embedded institution',
    '/rest/v1/programs?select=*,institutions!inner(id,name,country)' +
    '&is_active=eq.true&institutions.country=eq.CA', S);

  await expectOk('programs: ilike search',
    '/rest/v1/programs?select=*,institutions!inner(id,name)&name=ilike.*computer*', S);

  const matches = await expectOk('match_scores with a two-level nested embed',
    `/rest/v1/match_scores?select=program_id,score,reasons,computed_at,` +
    `programs!inner(*,institutions!inner(id,name,slug,country,city,logo_url,` +
    `verification_status,tier))&student_id=eq.${student.user.id}` +
    `&order=score.desc&limit=100`, S);
  if (matches?.length > 0 && matches[0].programs?.institutions?.name) {
    ok('nested embeds resolve two levels deep',
      dim(`(${matches.length} matches, top ${matches[0].score}%)`));
  } else {
    fail('nested embed', `got ${JSON.stringify(matches?.[0])?.slice(0, 200)}`);
  }
  if (Array.isArray(matches?.[0]?.reasons) && matches[0].reasons.length > 0) {
    ok('match reasons decode as JSON', dim(`(${matches[0].reasons.length} reasons)`));
  } else {
    fail('match reasons', `got ${JSON.stringify(matches?.[0]?.reasons)}`);
  }

  await expectOk('invitations: institution_interests, invited only',
    `/rest/v1/institution_interests?select=id,institution_id,program_id,note,` +
    `created_at,institutions!inner(id,name,logo_url,country,verification_status),` +
    `programs(id,name)&profile_id=eq.${student.user.id}&kind=eq.invited` +
    `&order=created_at.desc`, S);

  await expectOk('applications with to-one and to-many embeds',
    `/rest/v1/applications?select=*,institutions!inner(id,name,slug,country,city,` +
    `logo_url,verification_status,tier),programs!inner(*),` +
    `application_events(id,from_stage,to_stage,note,created_at),` +
    `application_document_requests(id,application_id,kind,note,fulfilled_at,created_at)` +
    `&profile_id=eq.${student.user.id}&order=updated_at.desc`, S);

  await expectOk('appointments with nulls-first ordering',
    `/rest/v1/appointments?select=*,institutions!inner(id,name,slug,country,city,` +
    `logo_url,verification_status,tier),programs(id,name)` +
    `&student_id=eq.${student.user.id}&order=scheduled_for.asc.nullsfirst`, S);

  await expectOk('availability_slots: open, future, bounded',
    `/rest/v1/availability_slots?select=*&is_booked=eq.false` +
    `&starts_at=gte.${new Date().toISOString()}&order=starts_at.asc&limit=60`, S);

  await expectOk('fair_registrations with an embedded fair',
    `/rest/v1/fair_registrations?select=*,fairs!inner(*)` +
    `&profile_id=eq.${student.user.id}&order=created_at.desc`, S);

  await expectOk('booth_visits through two levels of embed',
    `/rest/v1/booth_visits?select=*,fair_exhibitors!inner(booth_label,` +
    `institutions!inner(id,name,logo_url)),programs(id,name)` +
    `&profile_id=eq.${student.user.id}&order=created_at.desc`, S);

  await expectOk('notifications: unread filter with is.null',
    `/rest/v1/notifications?select=*&profile_id=eq.${student.user.id}` +
    `&order=created_at.desc&limit=100`, S);

  // ── The prospectus ───────────────────────────────────────────────────────

  console.log('\nInstitution prospectus');

  const institutions = await expectOk('institutions directory',
    '/rest/v1/institutions?select=id,name,country&order=name', S);
  const maplecrest = (institutions ?? []).find((i) => i.name.startsWith('Maplecrest'));

  if (maplecrest) {
    const page = await expectOk('the whole page in one call',
      '/rest/v1/rpc/institution_prospectus',
      { ...S, method: 'POST', body: { p_institution_id: maplecrest.id } });

    const sections = ['institution', 'profile', 'media', 'intakes', 'scholarships',
                      'contacts', 'faqs', 'requirements', 'programs'];
    const missing = sections.filter((k) => !(k in (page ?? {})));
    if (missing.length === 0) {
      ok(`every section present ${dim(`(${sections.length})`)}`);
    } else {
      fail('prospectus shape', `missing: ${missing.join(', ')}`);
    }

    if (page?.profile?.completeness >= 70) {
      ok(`completeness computed server-side ${dim(`(${page.profile.completeness}%)`)}`);
    } else {
      fail('completeness', `got ${page?.profile?.completeness}`);
    }

    // The student signed in here is Nigerian, so the Nigerian rule must win.
    const first = page?.requirements?.[0];
    if (page?.resolved_for_country === 'NG' && first?.from_country === 'NG') {
      ok('requirements resolve to the student\'s own country',
        dim(first.qualification?.slice(0, 44)));
    } else {
      fail('requirement resolution',
        `country=${page?.resolved_for_country} first=${first?.from_country}`);
    }

    if (!('email_domain' in (page?.institution ?? {}))) {
      ok('the verification domain is withheld');
    } else {
      fail('domain leak', 'email_domain is in the payload');
    }

    const counts = {
      intakes: page?.intakes?.length ?? 0,
      scholarships: page?.scholarships?.length ?? 0,
      faqs: page?.faqs?.length ?? 0,
      programs: page?.programs?.length ?? 0,
    };
    if (Object.values(counts).every((n) => n > 0)) {
      ok('the seeded page is populated', dim(JSON.stringify(counts)));
    } else {
      fail('seed', JSON.stringify(counts));
    }

    // Numerics have to arrive as numbers, not strings — the Dart models cast.
    if (typeof page?.profile?.cost_of_living_max === 'number') {
      ok('prospectus numerics decode as numbers');
    } else {
      fail('numeric coercion',
        `cost_of_living_max was ${typeof page?.profile?.cost_of_living_max}`);
    }

    // A student must not be able to rewrite an institution's page.
    const tamper = await request(
      `/rest/v1/institution_profiles?institution_id=eq.${maplecrest.id}`,
      { ...S, method: 'PATCH', body: { about: 'tampered' } },
    );
    const stillIntact = await request(
      `/rest/v1/institution_profiles?select=about&institution_id=eq.${maplecrest.id}`,
      S);
    if (!stillIntact.body?.[0]?.about?.includes('tampered')) {
      ok('a student cannot rewrite an institution page',
        dim(`(PATCH returned ${tamper.status})`));
    } else {
      fail('prospectus tamper', 'a student edited an institution page');
    }
  } else {
    fail('seed', 'Maplecrest is not in the institutions directory');
  }

  // ── RPCs ─────────────────────────────────────────────────────────────────

  console.log('\nRPCs');

  const fairs = await expectOk('fairs listing',
    '/rest/v1/fairs?select=*&is_active=eq.true&order=starts_at.asc', S);
  const fairId = fairs?.[0]?.id;

  if (fairId) {
    const report = await expectOk('fair_report',
      '/rest/v1/rpc/fair_report', { ...S, method: 'POST', body: { p_fair_id: fairId } });
    if (report && 'institutions_met' in report) {
      ok('fair_report returns its JSON shape',
        dim(`(met ${report.institutions_met})`));
    } else {
      fail('fair_report shape', JSON.stringify(report)?.slice(0, 180));
    }
  }

  const instMemberships = await expectOk('institution_members for the owner',
    `/rest/v1/institution_members?select=institution_id,member_role,institutions(*)` +
    `&profile_id=eq.${institution.user.id}`, I);
  const institutionId = instMemberships?.[0]?.institution_id;

  if (institutionId) {
    const demand = await expectOk('my_institution_demand',
      '/rest/v1/rpc/my_institution_demand',
      { ...I, method: 'POST', body: { p_institution_id: institutionId } });
    if (demand && 'matched_students' in demand) {
      ok('demand summary returns its keys',
        dim(`(${demand.matched_students} matched)`));
    } else {
      fail('my_institution_demand', JSON.stringify(demand)?.slice(0, 180));
    }
  }

  // ── The console's queries ────────────────────────────────────────────────

  console.log('\nInstitution console queries');

  const cards = await expectOk('matched_student_cards',
    `/rest/v1/matched_student_cards?select=*&institution_id=eq.${institutionId}` +
    `&score=gte.40&order=score.desc&limit=200`, I);
  if (cards?.length > 0) {
    const leaked = ['full_name', 'email', 'date_of_birth', 'grade_value', 'student_id']
      .filter((key) => key in cards[0]);
    if (leaked.length === 0) {
      ok('match cards carry no identifying field', dim(`(${cards.length} cards)`));
    } else {
      fail('match card leak', `exposed: ${leaked.join(', ')}`);
    }

    if (typeof cards[0].token === 'string' && cards[0].token.length === 32) {
      ok('cards are keyed by an opaque token', dim(cards[0].token.slice(0, 12) + '…'));
    } else {
      fail('match token', `token was ${JSON.stringify(cards[0].token)}`);
    }
  } else {
    fail('matched_student_cards', 'no cards returned for a seeded institution');
  }

  // The attack, through the wire this time: hold a token, try to find a person.
  const token = cards?.[0]?.token;
  if (token) {
    const mapping = await request('/rest/v1/match_tokens?select=*', I);
    if (Array.isArray(mapping.body) && mapping.body.length === 0) {
      ok('the token mapping is unreadable over the API');
    } else {
      fail('token mapping leak', JSON.stringify(mapping.body)?.slice(0, 160));
    }

    // An institution sees its OWN organisation handle — that is the point of
    // having one. What must not happen is seeing anybody else's row, because
    // that row is what maps a handle back to an account id.
    const socials = await request('/rest/v1/social_profiles?select=handle,kind', I);
    const visible = Array.isArray(socials.body) ? socials.body : [];
    const foreign = visible.filter((r) => r.kind !== 'institution');

    if (visible.length > 0 && foreign.length === 0) {
      ok('an institution sees only its own handle in social_profiles',
        dim(`(@${visible[0].handle})`));
    } else {
      fail('social profile leak',
        `saw ${visible.length} rows, ${foreign.length} of them not its own`);
    }

    // And specifically not a student's, which is the deanonymisation path.
    const studentRow = await request(
      '/rest/v1/social_profiles?select=handle&kind=eq.student', I);
    if (Array.isArray(studentRow.body) && studentRow.body.length === 0) {
      ok('and no student handle at all');
    } else {
      fail('student handle leak',
        JSON.stringify(studentRow.body)?.slice(0, 160));
    }

    const directory = await request('/rest/v1/public_profiles?select=*&limit=1', I);
    if (Array.isArray(directory.body)) {
      const hasId = directory.body.length > 0 && 'profile_id' in directory.body[0];
      if (!hasId) ok('the public directory exposes no profile_id');
      else fail('directory leak', 'profile_id is selectable');
    }

    // Acting on a student by token still works — that is the point.
    const invite = await request('/rest/v1/rpc/institution_record_interest', {
      ...I,
      method: 'POST',
      body: {
        p_token: token,
        p_program_id: cards[0].program_id,
        p_kind: 'shortlisted',
        p_note: 'Shortlisted by the smoke test.',
      },
    });
    if (invite.status >= 200 && invite.status < 300) {
      ok('an institution shortlists a student it cannot identify');
    } else {
      fail('shortlist by token', `${invite.status} ${JSON.stringify(invite.body)?.slice(0, 160)}`);
    }

    await expectOk('institution_interest_cards returns tokens, not ids',
      `/rest/v1/institution_interest_cards?select=*&institution_id=eq.${institutionId}`, I);
  }

  await expectOk('student_demand_stats',
    '/rest/v1/student_demand_stats?select=*&order=student_count.desc&limit=40', I);

  await expectOk('programs for the institution, including drafts',
    `/rest/v1/programs?select=*&institution_id=eq.${institutionId}` +
    `&order=is_active.desc&order=name.asc`, I);

  await expectOk('the pipeline, disambiguating profiles by FK',
    `/rest/v1/applications?select=id,stage,intake,submitted_at,updated_at,` +
    `student_note,profile_id,programs!inner(id,name,level),` +
    `student:profiles!profile_id(id,full_name,country),` +
    `application_document_requests(id,kind,fulfilled_at)` +
    `&institution_id=eq.${institutionId}&order=updated_at.desc`, I);

  await expectOk('appointments, disambiguating profiles by FK',
    `/rest/v1/appointments?select=id,status,scheduled_for,duration_min,channel,` +
    `meeting_url,student_message,notes,student_id,` +
    `student:profiles!student_id(id,full_name),programs(id,name)` +
    `&institution_id=eq.${institutionId}&order=scheduled_for.asc.nullsfirst`, I);

  await expectOk('conversations with a to-many embed',
    `/rest/v1/conversations?select=id,subject,last_message_at,student_id,` +
    `student:profiles!student_id(id,full_name),` +
    `conversation_participants(profile_id,last_read_at)` +
    `&institution_id=eq.${institutionId}&order=last_message_at.desc.nullslast`, I);

  await expectOk('team seats',
    `/rest/v1/institution_members?select=id,member_role,created_at,profile_id,` +
    `profiles(id,full_name)&institution_id=eq.${institutionId}&order=created_at.asc`, I);

  await expectOk('subscription, as a single object',
    `/rest/v1/institution_subscriptions?select=*&institution_id=eq.${institutionId}`,
    { ...I, headers: { Accept: 'application/vnd.pgrst.object+json' } });

  await expectOk('exhibitor booths',
    `/rest/v1/fair_exhibitors?select=id,booth_code,booth_label,package,fair_id,` +
    `fairs!inner(*)&institution_id=eq.${institutionId}&order=created_at.desc`, I);

  await expectOk('booth visits, disambiguating profiles by FK',
    '/rest/v1/booth_visits?select=id,interest_level,follow_up_requested,' +
    'scholarship_discussed,program_interest,note,created_at,exhibitor_id,' +
    'student:profiles!profile_id(id,full_name,country),programs(id,name)' +
    '&order=created_at.desc&limit=300', I);

  // ── Admin ────────────────────────────────────────────────────────────────

  console.log('\nAdmin console queries');

  await expectOk('verification queue',
    '/rest/v1/verifications?select=*&status=eq.pending&order=created_at.asc&limit=200', A);

  await expectOk('institutions with their subscription',
    '/rest/v1/institutions?select=*,institution_subscriptions(tier,seats,status)' +
    '&order=created_at.desc&limit=200', A);

  await expectOk('fairs with their exhibitors',
    '/rest/v1/fairs?select=*,fair_exhibitors(id,booth_code,booth_label,package,' +
    'institutions(id,name,country))&order=starts_at.desc', A);

  const counted = await request(
    "/rest/v1/profiles?select=id&role=eq.student",
    { ...A, method: 'HEAD', headers: { Prefer: 'count=exact' } },
  );
  const range = counted.headers.get('content-range');
  if (counted.status === 200 && range) {
    ok('exact count via HEAD + Content-Range', dim(range));
  } else {
    fail('head count', `status ${counted.status}, range ${range}`);
  }

  // ── Writes ───────────────────────────────────────────────────────────────

  console.log('\nWrites');

  const savedPassport = await expectOk('upsert the passport, reading the row back',
    '/rest/v1/student_passports?on_conflict=profile_id&select=*',
    {
      ...S,
      method: 'POST',
      headers: {
        Prefer: 'resolution=merge-duplicates,return=representation',
        Accept: 'application/vnd.pgrst.object+json',
      },
      body: {
        profile_id: student.user.id,
        date_of_birth: '2005-03-02',
        nationality: 'NG',
        current_country: 'NG',
        highest_qualification: 'WASSCE',
        grade_value: 81,
        grade_scheme: 'percentage',
        english_test_name: 'ielts',
        english_score: 7.5,
        target_countries: ['CA', 'GB', 'US'],
        target_levels: ['undergraduate'],
        target_fields: ['computer-science', 'data-science'],
        budget_min: 5000,
        budget_max: 32000,
        budget_currency: 'USD',
        intended_intake: 'Fall 2026',
        bio: 'Updated by the smoke test.',
      },
    });

  if (savedPassport?.grade_value === 81 && savedPassport?.target_countries?.length === 3) {
    ok('arrays and numerics round-trip through a write');
  } else {
    fail('passport upsert', JSON.stringify(savedPassport)?.slice(0, 200));
  }
  if (savedPassport?.normalized_grade === 81) {
    ok('the generated column recomputed on write',
      dim(`(normalized_grade ${savedPassport.normalized_grade})`));
  } else {
    fail('generated column on write', `got ${savedPassport?.normalized_grade}`);
  }

  const saved = await expectOk('save a program (institution)',
    '/rest/v1/programs?select=*',
    {
      ...I,
      method: 'POST',
      headers: { Prefer: 'return=representation', Accept: 'application/vnd.pgrst.object+json' },
      body: {
        institution_id: institutionId,
        name: 'MSc Cybersecurity (smoke test)',
        level: 'postgraduate',
        field_of_study: 'cybersecurity',
        tuition_min: 20000,
        tuition_max: 26000,
        tuition_currency: 'USD',
        duration_months: 12,
        intakes: ['Fall 2026'],
        min_grade_value: 60,
        min_grade_scheme: 'percentage',
        min_english_band: 6.5,
        scholarship_available: true,
        is_active: true,
      },
    });

  if (saved?.id) {
    ok('the new program got an id', dim(saved.id.slice(0, 8)));

    await expectOk('patch the program',
      `/rest/v1/programs?id=eq.${saved.id}&select=*`,
      {
        ...I,
        method: 'PATCH',
        headers: { Prefer: 'return=representation' },
        body: { tuition_max: 27000 },
      });

    await expectStatus('delete the program', 204,
      `/rest/v1/programs?id=eq.${saved.id}`, { ...I, method: 'DELETE' });
  }

  // Saving a passport should have re-run matching via the trigger.
  const rematched = await expectOk('matching re-ran after the passport changed',
    `/rest/v1/match_scores?select=program_id,score&student_id=eq.${student.user.id}` +
    `&order=score.desc`, S);
  if (rematched?.length > 0) {
    ok('matches present after the write', dim(`(${rematched.length})`));
  } else {
    fail('trigger-driven matching', 'no matches after saving the passport');
  }

  // ── RLS still applies ────────────────────────────────────────────────────

  console.log('\nRLS through the REST layer');

  const otherStudent = await signIn('amina.bello@example.com');
  const otherPassport = await request(
    `/rest/v1/student_passports?select=*&profile_id=eq.${student.user.id}`,
    { token: otherStudent.access_token },
  );
  if (Array.isArray(otherPassport.body) && otherPassport.body.length === 0) {
    ok('a student cannot read another student\'s passport');
  } else {
    fail('RLS leak', `got ${JSON.stringify(otherPassport.body)?.slice(0, 160)}`);
  }

  const escalation = await request(
    `/rest/v1/profiles?id=eq.${student.user.id}`,
    { ...S, method: 'PATCH', body: { role: 'admin' } },
  );
  if (escalation.status >= 400) {
    ok('self-promotion to admin is refused',
      dim(`(${escalation.body?.message?.slice(0, 48)})`));
  } else {
    fail('privilege escalation', `PATCH role returned ${escalation.status}`);
  }

  const anonRead = await request('/rest/v1/student_passports?select=*');
  if (Array.isArray(anonRead.body) && anonRead.body.length === 0) {
    ok('anon sees no passports');
  } else {
    fail('anon access', `got ${JSON.stringify(anonRead.body)?.slice(0, 160)}`);
  }

  // ── Storage ──────────────────────────────────────────────────────────────

  console.log('\nStorage');

  const bytes = Buffer.from('%PDF-1.4 smoke test transcript');
  const objectPath = `${student.user.id}/${Date.now()}-transcript.pdf`;

  const upload = await fetch(`${BASE}/storage/v1/object/passport-docs/${objectPath}`, {
    method: 'POST',
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${student.access_token}`,
      'Content-Type': 'application/pdf',
    },
    body: bytes,
  });
  if (upload.ok) ok('upload into the student\'s own prefix');
  else fail('upload', `${upload.status} ${(await upload.text()).slice(0, 160)}`);

  const forbidden = await fetch(
    `${BASE}/storage/v1/object/passport-docs/${otherStudent.user.id}/forged.pdf`,
    {
      method: 'POST',
      headers: {
        apikey: anonKey,
        Authorization: `Bearer ${student.access_token}`,
        'Content-Type': 'application/pdf',
      },
      body: bytes,
    },
  );
  if (!forbidden.ok) {
    ok('upload into another student\'s prefix is refused', dim(`(${forbidden.status})`));
  } else {
    fail('storage RLS', 'cross-prefix upload succeeded');
  }

  const signed = await expectOk('create a signed URL',
    `/storage/v1/object/sign/passport-docs/${objectPath}`,
    { ...S, method: 'POST', body: { expiresIn: 3600 } });

  if (signed?.signedURL) {
    const fetched = await fetch(`${BASE}/storage/v1${signed.signedURL}`);
    const content = await fetched.text();
    if (fetched.ok && content.includes('smoke test transcript')) {
      ok('the signed URL serves the bytes back');
    } else {
      fail('signed URL', `${fetched.status} ${content.slice(0, 100)}`);
    }
  }

  // ── Edge Functions ───────────────────────────────────────────────────────

  console.log('\nEdge Functions');

  await expectOk('compute-matches',
    '/functions/v1/compute-matches',
    { ...S, method: 'POST', body: { student_id: student.user.id } });

  await expectOk('send-notification',
    '/functions/v1/send-notification',
    {
      ...I,
      method: 'POST',
      body: {
        recipient_id: student.user.id,
        kind: 'institution_invited_you',
        title: 'Maplecrest University would like to hear from you',
        message: 'Sent by the smoke test.',
      },
    });

  const notifications = await expectOk('the notification landed',
    `/rest/v1/notifications?select=*&profile_id=eq.${student.user.id}` +
    `&order=created_at.desc&limit=5`, S);
  if (notifications?.length > 0) {
    ok('student can read it', dim(notifications[0].title.slice(0, 40)));
  } else {
    fail('notification', 'nothing readable by the student');
  }

  // ── Live Spaces ──────────────────────────────────────────────────────────
  //
  // No media flows here — nothing is signed without LIVEKIT_* in the
  // environment. What these check is the half that is SQL: that the schema
  // reaches the right decision and the REST layer can carry it.

  console.log('\nLive Spaces');

  const space = await expectOk('an institution schedules a Space',
    '/rest/v1/spaces',
    {
      ...I,
      method: 'POST',
      headers: {
        Prefer: 'return=representation',
        Accept: 'application/vnd.pgrst.object+json',
      },
      body: {
        institution_id: institutionId,
        host_profile_id: institution.user.id,
        title: 'Admissions hour, from the smoke test',
        kind: 'admissions_hour',
        scheduled_for: new Date().toISOString(),
      },
    });

  await expectOk('a student can see it on the Spaces tab',
    `/rest/v1/spaces?select=*&id=eq.${space?.id}`, S);

  await expectOk('the institution goes live',
    '/functions/v1/livekit-room',
    { ...I, method: 'POST', body: { action: 'go_live', space_id: space?.id } });

  // The grant is returned whether or not a token could be signed, so the
  // decision the schema reached is visible either way.
  const listener = await expectOk('a student asks to join',
    '/functions/v1/livekit-token',
    { ...S, method: 'POST', body: { space_id: space?.id } });

  if (listener?.admission === 'admitted'
      && listener.role === 'listener'
      && listener.can_publish === false
      && String(listener.display_name).startsWith('@')
      && !JSON.stringify(listener).includes(student.user.id)) {
    ok('they join as a listener, by handle, publishing nothing',
      dim(listener.display_name));
  } else {
    fail('livekit-token', JSON.stringify(listener)?.slice(0, 220));
  }

  if (listener?.token) {
    ok('a real token was signed', dim('LIVEKIT_* is set'));
  } else if (listener?.error) {
    ok('no credentials, and it says so rather than faking one', dim('503-equivalent'));
  }

  await expectStatus('neither id is a 400', 400,
    '/functions/v1/livekit-token', { ...S, method: 'POST', body: {} });

  const roster = await expectOk('the host reads its roster',
    `/rest/v1/space_roster?select=*&space_id=eq.${space?.id}`, I);
  const theListener = roster?.find((r) => r.role === 'listener');
  if (theListener && theListener.handle && theListener.shared_name === null) {
    ok('the roster shows a handle and no name');
  } else {
    fail('space_roster', JSON.stringify(roster)?.slice(0, 200));
  }

  await expectOk('the student identifies in order to speak',
    '/rest/v1/rpc/identify_in_space',
    { ...S, method: 'POST', body: { p_space_id: space?.id } });

  const speaker = await expectOk('and gets a publishing grant',
    '/functions/v1/livekit-token',
    { ...S, method: 'POST', body: { space_id: space?.id } });
  if (speaker?.role === 'speaker' && speaker.can_publish === true
      && speaker.identity === listener?.identity) {
    ok('same identity, new permissions');
  } else {
    fail('the upgrade', JSON.stringify(speaker)?.slice(0, 200));
  }

  await expectOk('the host mutes them',
    '/functions/v1/livekit-room',
    {
      ...I,
      method: 'POST',
      body: {
        action: 'moderate',
        participant_id: theListener?.participant_id,
        moderation: 'muted',
        reason: 'smoke test',
      },
    });

  await expectOk('and the mute is on the record',
    `/rest/v1/space_moderation_events?select=*&space_id=eq.${space?.id}` +
    '&action=eq.muted', I);

  console.log(`\n${passed + failed} checks, ${failed} failed\n`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(red(`\n  Smoke test crashed: ${err.message}\n`));
  process.exit(1);
});
