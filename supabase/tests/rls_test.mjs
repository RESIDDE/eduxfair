// Cross-tenant RLS assertions for Lekkside Connect.
//
// Supabase-first means Postgres RLS *is* the authorization layer — there is no
// server in front of it to catch a mistake. So these assertions are the gate
// the plan puts before any feature work, and they are written to fail loudly
// rather than to pass easily.
//
// Impersonation works the way the hosted stack does: `set role authenticated`
// plus the `request.jwt.claims` GUC that auth.uid() reads. A test that forgot
// `set role` would run as superuser and silently bypass every policy, so
// asUser() always sets both and the first assertion below proves the harness
// really is being constrained.

export async function runAssertions(db, { red, green, dim }) {
  let failures = 0;
  let checked = 0;

  const ids = {};
  const uuid = async () => (await db.query('select gen_random_uuid() as id')).rows[0].id;

  // ---------------------------------------------------------------- helpers

  async function asUser(userId, fn) {
    // A null id means anon: no sub claim, and the anon role.
    await db.exec(
      userId === null
        ? `set role anon; set request.jwt.claims = '{"role":"anon"}';`
        : `set role authenticated;
           set request.jwt.claims = '{"sub":"${userId}","role":"authenticated"}';`,
    );
    try {
      return await fn();
    } finally {
      await db.exec('reset role; reset request.jwt.claims;');
    }
  }

  async function count(sql, params = []) {
    const r = await db.query(sql, params);
    return Number(r.rows[0].n);
  }

  function ok(label) {
    checked += 1;
    console.log(`  ${green('ok')}  ${label}`);
  }

  function fail(label, detail) {
    checked += 1;
    failures += 1;
    console.log(`  ${red('FAIL')}  ${label}`);
    if (detail) console.log(red(`        ${detail}`));
  }

  // Asserts a visibility count under a given user.
  async function expectRows(label, userId, sql, expected, params = []) {
    try {
      const n = await asUser(userId, () => count(sql, params));
      if (n === expected) ok(`${label} ${dim(`(${n} rows)`)}`);
      else fail(label, `expected ${expected} row(s), got ${n}`);
    } catch (err) {
      fail(label, `query errored: ${err.message}`);
    }
  }

  // Asserts that a write is rejected, whether by a policy or by a guard trigger.
  async function expectDenied(label, userId, sql, params = []) {
    try {
      await asUser(userId, async () => {
        const r = await db.query(sql, params);
        // An UPDATE/DELETE filtered out by RLS affects 0 rows rather than
        // raising, which is still a denial — but an INSERT that succeeds is not.
        if (/^\s*insert/i.test(sql)) throw new Error('__inserted__');
        if (r.affectedRows && r.affectedRows > 0) throw new Error('__affected__');
      });
      ok(`${label} ${dim('(no rows affected)')}`);
    } catch (err) {
      if (err.message === '__inserted__' || err.message === '__affected__') {
        fail(label, 'the write SUCCEEDED but should have been denied');
      } else {
        ok(`${label} ${dim(`(rejected: ${err.message.split('\n')[0].slice(0, 60)})`)}`);
      }
    }
  }

  async function expectAllowed(label, userId, sql, params = []) {
    try {
      await asUser(userId, () => db.query(sql, params));
      ok(label);
    } catch (err) {
      fail(label, `should have been allowed but failed: ${err.message}`);
    }
  }

  // ------------------------------------------------------------------- seed
  // Seeded as the superuser so RLS does not interfere with building the
  // fixture. Everything afterwards runs as a constrained role.

  console.log('\nSeeding fixture');

  const mk = async (key, email, role, name) => {
    ids[key] = await uuid();
    await db.query(
      `insert into auth.users (id, email, raw_user_meta_data)
       values ($1, $2, jsonb_build_object('role', $3::text, 'full_name', $4::text))`,
      [ids[key], email, role, name]
    );
  };

  await mk('ownerA',   'owner@univ-a.ca',   'institution_member', 'Owner A');
  await mk('officerA', 'officer@univ-a.ca', 'institution_member', 'Officer A');
  await mk('ownerB',   'owner@univ-b.ac.uk','institution_member', 'Owner B');
  await mk('s1',       's1@example.com',    'student',            'Student One');
  await mk('s2',       's2@example.com',    'student',            'Student Two');
  await mk('s3',       's3@example.com',    'student',            'Student Three');
  await mk('s4',       's4@example.com',    'student',            'Student Four');
  await mk('admin',    'admin@lekkside.com','student',            'Platform Admin');

  // Admin cannot be self-assigned at signup (by design), so grant it directly.
  await db.query(`update profiles set role = 'admin' where id = $1`, [ids.admin]);

  const profileCount = await count('select count(*) as n from profiles');
  if (profileCount === 8) ok(`on_auth_user_created mirrored 8 auth users into profiles`);
  else fail('on_auth_user_created trigger', `expected 8 profiles, got ${profileCount}`);

  // Signup metadata must not be able to request the admin role.
  const sneak = await uuid();
  await db.query(
    `insert into auth.users (id, email, raw_user_meta_data)
     values ($1, 'sneak@example.com', '{"role":"admin","full_name":"Sneaky"}'::jsonb)`,
    [sneak]
  );
  const sneakRole = (await db.query('select role from profiles where id = $1', [sneak]))
    .rows[0].role;
  if (sneakRole === 'student') ok(`signup metadata claiming role=admin was clamped to student`);
  else fail('signup role clamp', `got role '${sneakRole}' from signup metadata`);

  // Institutions, created through the real bootstrap function as their owners.
  ids.instA = await asUser(ids.ownerA, async () =>
    (await db.query(
      `select create_institution('University A', 'CA', 'https://univ-a.ca', 'univ-a.ca',
                                 'Toronto', 'Test institution A') as id`
    )).rows[0].id);
  ids.instB = await asUser(ids.ownerB, async () =>
    (await db.query(
      `select create_institution('University B', 'GB', 'https://univ-b.ac.uk', 'univ-b.ac.uk',
                                 'London', 'Test institution B') as id`
    )).rows[0].id);
  ok(`create_institution() bootstrapped two institutions with owner memberships`);

  // A second seat at A.
  await asUser(ids.ownerA, () => db.query(
    `insert into institution_members (institution_id, profile_id, member_role)
     values ($1, $2, 'admissions_officer')`, [ids.instA, ids.officerA]));
  ok('owner added a second admissions-officer seat');

  // Mark both verified via the admin queue, so badge state is realistic.
  await db.query(
    `update verifications set status = 'verified', reviewer_id = $1
      where subject_type = 'institution'`, [ids.admin]);

  // Programs.
  const prog = async (key, inst, name, level, field, active = true, extra = {}) => {
    ids[key] = (await db.query(
      `insert into programs (institution_id, name, level, field_of_study, is_active,
                             tuition_min, tuition_max, tuition_currency, intakes,
                             min_grade_value, min_grade_scheme, min_english_band,
                             scholarship_available)
       values ($1,$2,$3::study_level,$4,$5,$6,$7,'USD',$8,$9,$10::grading_scheme,$11,$12)
       returning id`,
      [inst, name, level, field, active,
       extra.tmin ?? 15000, extra.tmax ?? 25000,
       extra.intakes ?? ['Fall 2026'],
       extra.grade ?? 65, extra.gradeScheme ?? 'percentage',
       extra.english ?? 6.0, extra.scholarship ?? false]
    )).rows[0].id;
  };

  await prog('pA1', ids.instA, 'BSc Computer Science', 'undergraduate', 'computer-science');
  await prog('pA2', ids.instA, 'MSc Data Science', 'postgraduate', 'data-science');
  await prog('pA3', ids.instA, 'Unpublished Draft', 'undergraduate', 'business', false);
  await prog('pB1', ids.instB, 'BSc Computing', 'undergraduate', 'computer-science');
  ok('seeded 4 programs (one of them an inactive draft at A)');

  // Passports. s1 and s2 are both strong matches for pA1; s2 never shares.
  const passport = async (student, country) => {
    await db.query(
      `insert into student_passports (
         profile_id, date_of_birth, nationality, current_country,
         highest_qualification, grade_value, grade_scheme,
         english_test_name, english_score,
         target_countries, target_levels, target_fields,
         budget_max, budget_currency, intended_intake)
       values ($1, '2005-03-02', 'NG', $2, 'WASSCE', 78, 'percentage',
               'ielts', 7.0, array['CA','GB'],
               array['undergraduate']::study_level[], array['computer-science'],
               30000, 'USD', 'Fall 2026')`,
      [student, country]);
  };
  await passport(ids.s1, 'NG');
  await passport(ids.s2, 'NG');
  await passport(ids.s3, 'GH');

  const comp = (await db.query(
    'select completeness from student_passports where profile_id = $1', [ids.s1]))
    .rows[0].completeness;
  if (comp >= 50) ok(`completeness trigger scored a filled passport at ${comp}`);
  else fail('completeness trigger', `expected >= 50, got ${comp}`);

  // Matching.
  const matched = (await db.query('select refresh_matches_for_program($1) as n', [ids.pA1]))
    .rows[0].n;
  if (Number(matched) >= 2) ok(`refresh_matches_for_program matched ${matched} students to pA1`);
  else fail('matching', `expected >= 2 matches for pA1, got ${matched}`);

  const topScore = (await db.query(
    'select score, reasons from match_scores where program_id = $1 and student_id = $2',
    [ids.pA1, ids.s1])).rows[0];
  if (topScore && topScore.score >= 80 && topScore.reasons.length >= 4) {
    ok(`match carries an explainable score (${topScore.score}, ` +
       `${topScore.reasons.length} reasons)`);
  } else {
    fail('match reasons', `score/reasons looked wrong: ${JSON.stringify(topScore)}`);
  }

  // A fair with both institutions exhibiting.
  ids.fair = (await db.query(
    `insert into fairs (name, slug, city, country, venue, starts_at, ends_at)
     values ('Lekkside Lagos 2026', 'lagos-2026', 'Lagos', 'NG', 'Eko Centre',
             now() + interval '30 days', now() + interval '31 days')
     returning id`)).rows[0].id;

  for (const [k, inst, code] of [['exA', ids.instA, 'A01'], ['exB', ids.instB, 'B01']]) {
    ids[k] = (await db.query(
      `insert into fair_exhibitors (fair_id, institution_id, booth_code, booth_label, package)
       values ($1, $2, $3, 'Booth ' || $3, 'booth_plus_platform') returning id`,
      [ids.fair, inst, code])).rows[0].id;
  }
  ok('seeded a fair with both institutions exhibiting');

  // ------------------------------------------------- the consent gate

  console.log('\nConsent gate — a student\'s identity requires a live share');

  await expectRows(
    'institution A cannot see an unshared student\'s passport',
    ids.ownerA,
    'select count(*) as n from student_passports where profile_id = $1', 0, [ids.s2]);

  await expectRows(
    'institution A cannot see an unshared student\'s profile row',
    ids.ownerA,
    'select count(*) as n from profiles where id = $1', 0, [ids.s2]);

  await expectRows(
    'a student cannot see another student\'s passport',
    ids.s1,
    'select count(*) as n from student_passports where profile_id = $1', 0, [ids.s2]);

  await expectRows(
    'a student CAN see their own passport',
    ids.s1,
    'select count(*) as n from student_passports where profile_id = $1', 1, [ids.s1]);

  // s1 grants a share, which is the only way identity crosses.
  await expectAllowed(
    'a student may grant a passport share',
    ids.s1,
    `insert into passport_shares (profile_id, institution_id, reason)
     values ($1, $2, 'test grant')`, [ids.s1, ids.instA]);

  await expectRows(
    'after the share, institution A CAN see that passport',
    ids.ownerA,
    'select count(*) as n from student_passports where profile_id = $1', 1, [ids.s1]);

  await expectRows(
    'the share does not leak to institution B',
    ids.ownerB,
    'select count(*) as n from student_passports where profile_id = $1', 0, [ids.s1]);

  await expectRows(
    'the second officer at A inherits the share',
    ids.officerA,
    'select count(*) as n from student_passports where profile_id = $1', 1, [ids.s1]);

  await expectDenied(
    'an institution cannot grant itself a share',
    ids.ownerA,
    `insert into passport_shares (profile_id, institution_id, reason)
     values ($1, $2, 'self-granted')`, [ids.s2, ids.instA]);

  // Revocation.
  await asUser(ids.s1, () => db.query(
    'update passport_shares set revoked_at = now() where profile_id = $1 and institution_id = $2',
    [ids.s1, ids.instA]));

  await expectRows(
    'after revocation, institution A can no longer see the passport',
    ids.ownerA,
    'select count(*) as n from student_passports where profile_id = $1', 0, [ids.s1]);

  await expectRows(
    'revocation is a timestamp, so the grant history survives for the student',
    ids.s1,
    'select count(*) as n from passport_shares where profile_id = $1', 1, [ids.s1]);

  // ------------------------------------------------- pseudonymous discovery

  console.log('\nReverse admission — discovery without identity');

  // All three seeded passports target CA/GB + computer-science + undergraduate,
  // so all three match pA1. The point of the assertion is that A sees its own
  // program's cards at all; the isolation check is the next one.
  await expectRows(
    'institution A sees pseudonymous match cards for its own program',
    ids.ownerA,
    'select count(*) as n from matched_student_cards where program_id = $1', 3, [ids.pA1]);

  await expectRows(
    'institution B sees no cards for institution A\'s program',
    ids.ownerB,
    'select count(*) as n from matched_student_cards where program_id = $1', 0, [ids.pA1]);

  // The card must carry no identifying columns at all.
  const cardCols = (await db.query(
    `select column_name from information_schema.columns
      where table_name = 'matched_student_cards'`)).rows.map((r) => r.column_name);
  const leaked = cardCols.filter((c) =>
    ['full_name', 'email', 'phone', 'bio', 'date_of_birth', 'avatar_url',
     'grade_value', 'normalized_grade', 'budget_max'].includes(c));
  if (leaked.length === 0) {
    ok(`match card exposes no identifying column ${dim(`(${cardCols.length} cols)`)}`);
  } else {
    fail('match card columns', `identifying columns present: ${leaked.join(', ')}`);
  }

  // The refresh triggers score every active program, so s1 matches all three
  // (pA1 and pB1 strongly, pA2 on country and affordability alone). A student
  // reads these from match_scores — matched_student_cards is the institution's
  // pseudonymous view and is not theirs to read.
  await expectRows(
    'a student sees their own matches',
    ids.s1,
    'select count(*) as n from match_scores where student_id = $1', 3, [ids.s1]);

  await expectRows(
    'and no other student\'s matches',
    ids.s1,
    'select count(*) as n from match_scores where student_id <> $1', 0, [ids.s1]);

  await expectRows(
    'a student cannot read the institution-facing card view',
    ids.s1, 'select count(*) as n from matched_student_cards', 0);

  // Internal institution notes must never reach the student.
  // Through the token RPCs: institutions have no direct write on this table
  // any more, because every row carries the profile_id the token withholds.
  const s1Token = await asUser(ids.ownerA, async () => (await db.query(
    'select match_token_for($1, $2) as t', [ids.s1, ids.instA])).rows[0].t);

  await asUser(ids.ownerA, () => db.query(
    `select institution_record_interest($1, $2, 'passed', 'internal note')`,
    [s1Token, ids.pA1]));
  await asUser(ids.ownerA, () => db.query(
    `select institution_record_interest($1, $2, 'invited', null)`,
    [s1Token, ids.pA1]));

  await expectRows(
    'a student sees that they were INVITED',
    ids.s1,
    `select count(*) as n from institution_interests
      where profile_id = $1 and kind = 'invited'`, 1, [ids.s1]);

  await expectRows(
    'a student never learns they were shortlisted or passed over',
    ids.s1,
    `select count(*) as n from institution_interests
      where profile_id = $1 and kind <> 'invited'`, 0, [ids.s1]);

  await expectRows(
    'demand stats are not visible to students',
    ids.s1, 'select count(*) as n from student_demand_stats', 0);

  await expectRows(
    'an institution still cannot see who it shortlisted, only the token',
    ids.ownerA,
    `select count(*) as n from institution_interest_cards
      where institution_id = $1 and token is not null`, 2, [ids.instA]);

  // ------------------------------------------------------ tenant isolation

  console.log('\nTenant isolation');

  await expectRows(
    'institution B cannot see institution A\'s unpublished draft program',
    ids.ownerB,
    'select count(*) as n from programs where id = $1', 0, [ids.pA3]);

  await expectRows(
    'institution A CAN see its own draft program',
    ids.ownerA,
    'select count(*) as n from programs where id = $1', 1, [ids.pA3]);

  await expectRows(
    'a student sees only active programs',
    ids.s1, 'select count(*) as n from programs where id = $1', 0, [ids.pA3]);

  await expectDenied(
    'institution B cannot edit institution A\'s program',
    ids.ownerB,
    `update programs set name = 'hijacked' where id = $1`, [ids.pA1]);

  await expectDenied(
    'a non-owner officer cannot add a seat',
    ids.officerA,
    `insert into institution_members (institution_id, profile_id, member_role)
     values ($1, $2, 'admissions_officer')`, [ids.instA, ids.s4]);

  // Applications.
  ids.app1 = await asUser(ids.s1, async () => (await db.query(
    `insert into applications (profile_id, institution_id, program_id, intake, stage)
     values ($1, $2, $3, 'Fall 2026', 'draft') returning id`,
    [ids.s1, ids.instA, ids.pA1])).rows[0].id);
  ok('student created a draft application');

  await expectRows(
    'institution B cannot see an application made to institution A',
    ids.ownerB,
    'select count(*) as n from applications where id = $1', 0, [ids.app1]);

  await expectRows(
    'institution A CAN see an application made to it',
    ids.ownerA,
    'select count(*) as n from applications where id = $1', 1, [ids.app1]);

  // Conversations and messages.
  ids.conv = await asUser(ids.s1, async () => (await db.query(
    `insert into conversations (student_id, institution_id, subject)
     values ($1, $2, 'Question about CS') returning id`,
    [ids.s1, ids.instA])).rows[0].id);
  await asUser(ids.s1, () => db.query(
    `insert into messages (conversation_id, sender_id, body)
     values ($1, $2, 'Hello')`, [ids.conv, ids.s1]));

  await expectRows(
    'institution B cannot read institution A\'s conversation',
    ids.ownerB,
    'select count(*) as n from conversations where id = $1', 0, [ids.conv]);

  await expectRows(
    'institution B cannot read messages on it',
    ids.ownerB,
    'select count(*) as n from messages where conversation_id = $1', 0, [ids.conv]);

  await expectRows(
    'institution A CAN read the thread addressed to it',
    ids.ownerA,
    'select count(*) as n from messages where conversation_id = $1', 1, [ids.conv]);

  await expectDenied(
    'an uninvolved student cannot post into someone else\'s thread',
    ids.s2,
    `insert into messages (conversation_id, sender_id, body)
     values ($1, $2, 'intruding')`, [ids.conv, ids.s2]);

  await expectDenied(
    'a party cannot forge a message from the other side',
    ids.s1,
    `insert into messages (conversation_id, sender_id, body)
     values ($1, $2, 'forged')`, [ids.conv, ids.ownerA]);

  await expectDenied(
    'messages cannot be edited after the fact',
    ids.ownerA,
    `update messages set body = 'rewritten' where conversation_id = $1`, [ids.conv]);

  // ------------------------- voice notes, pictures, pinning, archiving, search

  await expectAllowed('a voice note records its own duration', ids.s1,
    `insert into messages (conversation_id, sender_id, kind, attachment_path,
                           attachment_name, attachment_mime, duration_ms)
     values ($1, $2, 'voice', $3, 'voice.m4a', 'audio/mp4', 4200)`,
    [ids.conv, ids.s1, `${ids.conv}/1-voice.m4a`]);

  await expectAllowed('and a picture keeps the name it was sent under', ids.s1,
    `insert into messages (conversation_id, sender_id, kind, attachment_path,
                           attachment_name, attachment_mime)
     values ($1, $2, 'image', $3, 'transcript-page-1.png', 'image/png')`,
    [ids.conv, ids.s1, `${ids.conv}/2-page.png`]);

  // The kind is what a client renders from, so a kind with nothing behind it
  // would be a player with no audio or an image with no picture.
  await expectDenied('a non-text message with no attachment is refused', ids.s1,
    `insert into messages (conversation_id, sender_id, kind, body)
     values ($1, $2, 'image', 'no file')`, [ids.conv, ids.s1]);
  await expectDenied('and a voice note with no duration is refused', ids.s1,
    `insert into messages (conversation_id, sender_id, kind, attachment_path)
     values ($1, $2, 'voice', $3)`, [ids.conv, ids.s1, `${ids.conv}/3.m4a`]);

  // Pinning and archiving live on conversation_participants, so one officer
  // archiving a thread cannot take it off a colleague's list.
  await asUser(ids.s1, () => db.query(
    'select set_conversation_state($1, true, null)', [ids.conv]));
  await asUser(ids.ownerA, () => db.query(
    'select set_conversation_state($1, null, true)', [ids.conv]));

  const convState = async (who) => (await db.query(
    `select pinned_at is not null as pinned, archived_at is not null as archived
       from conversation_participants
      where conversation_id = $1 and profile_id = $2`, [ids.conv, who])).rows[0];

  const studentState = await convState(ids.s1);
  const staffState = await convState(ids.ownerA);
  if (studentState?.pinned && !studentState.archived
      && !staffState?.pinned && staffState?.archived) {
    ok('pinning and archiving are per person, on the same thread');
  } else {
    fail('set_conversation_state',
      `student=${JSON.stringify(studentState)} staff=${JSON.stringify(staffState)}`);
  }

  // The two states are a contradiction; resolving it in SQL means no client
  // has to remember the rule.
  await asUser(ids.ownerA, () => db.query(
    'select set_conversation_state($1, true, null)', [ids.conv]));
  const unarchived = await convState(ids.ownerA);
  if (unarchived?.pinned && !unarchived.archived) ok('pinning un-archives');
  else fail('set_conversation_state', JSON.stringify(unarchived));

  await expectDenied('somebody not on a thread cannot pin it', ids.s2,
    'select set_conversation_state($1, true, null)', [ids.conv]);

  // search_conversations is invoker-rights on purpose: messages_select_party
  // decides what is searchable, so it cannot become a way to read a thread the
  // caller is not on.
  const convHits = async (who, q) => await asUser(who, async () => (await db.query(
    'select * from search_conversations($1)', [q])).rows);

  const studentHits = await convHits(ids.s1, 'Hello');
  if (studentHits.length === 1 && studentHits[0].conversation_id === ids.conv) {
    ok(`a party searches their own threads ${dim(`(${studentHits[0].snippet})`)}`);
  } else {
    fail('search_conversations', JSON.stringify(studentHits).slice(0, 160));
  }

  if ((await convHits(ids.ownerA, 'Hello')).length === 1) {
    ok('and so does the institution on the far side');
  } else {
    fail('search_conversations', 'the institution found nothing on its own thread');
  }

  if ((await convHits(ids.s2, 'Hello')).length === 0) {
    ok('while an uninvolved student finds nothing');
  } else {
    fail('search_conversations', 'it LEAKED a thread to a non-party');
  }

  const nameHits = await convHits(ids.s1, 'transcript');
  if (nameHits.length === 1 && nameHits[0].snippet === 'transcript-page-1.png') {
    ok('attachments are found by the name they were sent under');
  } else {
    fail('search_conversations', JSON.stringify(nameHits).slice(0, 160));
  }

  if ((await convHits(ids.s1, '   ')).length === 0) ok('and an empty query matches nothing');
  else fail('search_conversations', 'a blank query returned rows');

  // Leave the thread unpinned, so later sections see what they expect.
  await asUser(ids.s1, () => db.query(
    'select set_conversation_state($1, false, false)', [ids.conv]));
  await asUser(ids.ownerA, () => db.query(
    'select set_conversation_state($1, false, false)', [ids.conv]));

  // ---------------------------------------------- deleting a message, two ways

  const delible = await asUser(ids.s1, async () => (await db.query(
    `insert into messages (conversation_id, sender_id, body)
     values ($1, $2, 'my bank details are 123456') returning id`,
    [ids.conv, ids.s1])).rows[0].id);

  // Delete for me touches nobody else's view, and nothing on the row.
  await asUser(ids.ownerA, () => db.query(
    `select delete_message($1, 'me')`, [delible]));
  const afterHide = (await db.query(
    'select body, deleted_at from messages where id = $1', [delible])).rows[0];
  const hides = await count(
    'select count(*) as n from message_hides where message_id = $1', [delible]);
  if (afterHide.body && !afterHide.deleted_at && hides === 1) {
    ok('delete-for-me hides a message without touching it');
  } else {
    fail('delete_message me', JSON.stringify(afterHide));
  }

  await expectRows('and only the person who hid it has a row', ids.s1,
    'select count(*) as n from message_hides where message_id = $1', 0, [delible]);

  // Only the sender, and only their own.
  await expectDenied('the other party cannot delete it for everyone', ids.ownerA,
    `select delete_message($1, 'everyone')`, [delible]);
  await expectDenied('nor can somebody off the thread do anything to it', ids.s2,
    `select delete_message($1, 'me')`, [delible]);

  await asUser(ids.s1, () => db.query(
    `select delete_message($1, 'everyone')`, [delible]));
  const tombstone = (await db.query(
    `select body, attachment_path, kind::text, deleted_at, deleted_by
       from messages where id = $1`, [delible])).rows[0];
  if (!tombstone.body && !tombstone.attachment_path && tombstone.deleted_at
      && tombstone.deleted_by === ids.s1 && tombstone.kind === 'text') {
    ok('delete-for-everyone clears the message and leaves a tombstone');
  } else {
    fail('delete_message everyone', JSON.stringify(tombstone));
  }

  // The record survives where a dispute can still reach it, and nowhere else.
  await expectRows('the parties cannot read what it said', ids.s1,
    'select count(*) as n from message_redactions where message_id = $1', 0,
    [delible]);
  await expectRows('nor can the institution', ids.ownerA,
    'select count(*) as n from message_redactions where message_id = $1', 0,
    [delible]);
  await expectRows('an admin resolving a dispute can', ids.admin,
    'select count(*) as n from message_redactions where message_id = $1', 1,
    [delible]);

  const kept = (await db.query(
    'select body from message_redactions where message_id = $1', [delible]))
    .rows[0];
  if (kept?.body === 'my bank details are 123456') ok('and it is what was said');
  else fail('message_redactions', JSON.stringify(kept));

  // Still no way round the function.
  await expectDenied('a sender cannot edit their way to the same result', ids.s1,
    `update messages set body = null where id = $1`, [delible]);
  await expectDenied('nor delete the row outright', ids.s1,
    'delete from messages where id = $1', [delible]);
  await expectDenied('and the redaction log cannot be rewritten', ids.admin,
    `update message_redactions set body = 'nothing' where message_id = $1`,
    [delible]);

  // A deleted message stops matching the words it no longer contains.
  const stale = await asUser(ids.s1, async () => (await db.query(
    'select * from search_conversations($1)', ['bank details'])).rows);
  if (stale.length === 0) ok('and search no longer finds it');
  else fail('search_conversations', JSON.stringify(stale).slice(0, 140));

  // A message hidden for me is not one search should hand back either.
  const hidden = await asUser(ids.s1, async () => (await db.query(
    `insert into messages (conversation_id, sender_id, body)
     values ($1, $2, 'zebra crossing') returning id`, [ids.conv, ids.s1]))
    .rows[0].id);
  await asUser(ids.ownerA, () => db.query(`select delete_message($1, 'me')`, [hidden]));
  const forStaff = await asUser(ids.ownerA, async () => (await db.query(
    'select * from search_conversations($1)', ['zebra'])).rows);
  const forStudent = await asUser(ids.s1, async () => (await db.query(
    'select * from search_conversations($1)', ['zebra'])).rows);
  if (forStaff.length === 0 && forStudent.length === 1) {
    ok('a message hidden for one person still searches for the other');
  } else {
    fail('search_conversations', `staff=${forStaff.length} student=${forStudent.length}`);
  }

  // ------------------------------------- the institution's own pins and tabs

  await asUser(ids.ownerA, () => db.query(
    'select set_conversation_state($1, true, null)', [ids.conv]));
  const orgRow = await asUser(ids.ownerA, async () => (await db.query(
    'select pinned_at, archived_at, last_message_body from institution_inbox where conversation_id = $1',
    [ids.conv])).rows[0]);
  if (orgRow?.pinned_at && !orgRow.archived_at) {
    ok('the institution inbox carries the caller\'s own pin');
  } else {
    fail('institution_inbox', JSON.stringify(orgRow));
  }

  await expectRows('and a colleague sees their own state, not that one', ids.officerA,
    `select count(*) as n from institution_inbox
      where conversation_id = $1 and pinned_at is not null`, 0, [ids.conv]);

  // An avatar is as identifying as a name here: the same image is on the
  // student's public handle profile, so showing one on an anonymous row would
  // be a way to match the thread to a handle.
  await db.query(
    `update profiles set avatar_url = 'https://example.test/s3.png' where id = $1`,
    [ids.s3]);

  const avatarConv = await asUser(ids.s3, async () => (await db.query(
    `insert into conversations (student_id, institution_id, subject)
     values ($1, $2, 'avatar gate') returning id`, [ids.s3, ids.instA]))
    .rows[0].id);

  const inboxRow = async () => await asUser(ids.ownerA, async () => (await db.query(
    `select is_shared, shared_name, shared_avatar_url
       from institution_inbox where conversation_id = $1`, [avatarConv])).rows[0]);

  const inboxBefore = await inboxRow();
  if (!inboxBefore.is_shared && !inboxBefore.shared_name
      && !inboxBefore.shared_avatar_url) {
    ok('an unshared student has no name and no face in the inbox');
  } else {
    fail('institution_inbox', JSON.stringify(inboxBefore));
  }

  await asUser(ids.s3, () => db.query(
    `select grant_passport_share($1, $2, 'avatar gate test')`,
    [ids.s3, ids.instA]));

  const inboxAfter = await inboxRow();
  if (inboxAfter.is_shared && inboxAfter.shared_name
      && inboxAfter.shared_avatar_url === 'https://example.test/s3.png') {
    ok('and both arrive together once they share');
  } else {
    fail('institution_inbox', JSON.stringify(inboxAfter));
  }

  await expectRows('while another institution still sees neither', ids.ownerB,
    `select count(*) as n from institution_inbox where conversation_id = $1`, 0,
    [avatarConv]);

  // Revoked again, so the share this created does not collide with the one a
  // later section writes for the same pair — `passport_shares_one_live`
  // allows only one live row per (student, institution).
  await db.query(
    `update passport_shares set revoked_at = now()
      where profile_id = $1 and institution_id = $2 and revoked_at is null`,
    [ids.s3, ids.instA]);

  await asUser(ids.ownerA, () => db.query(
    'select set_conversation_state($1, false, false)', [ids.conv]));

  // ------------------------------------- reactions, replies and forwarding

  const reactable = await asUser(ids.s1, async () => (await db.query(
    `insert into messages (conversation_id, sender_id, body)
     values ($1, $2, 'thanks for the quick answer') returning id`,
    [ids.conv, ids.s1])).rows[0].id);

  await expectAllowed('the institution reacts to a student message', ids.ownerA,
    `insert into message_reactions (message_id, profile_id, emoji)
     values ($1, $2, '🙏')`, [reactable, ids.ownerA]);

  // One per person: changing your mind is an update, not a second row, so a
  // bubble can never show the same person twice.
  await expectDenied('and cannot stack a second reaction of their own', ids.ownerA,
    `insert into message_reactions (message_id, profile_id, emoji)
     values ($1, $2, '😂')`, [reactable, ids.ownerA]);
  await expectAllowed('but can change it', ids.ownerA,
    `update message_reactions set emoji = '😂'
      where message_id = $1 and profile_id = $2`, [reactable, ids.ownerA]);

  // An open emoji field is an open text field, and these threads can have
  // minors in them.
  await expectDenied('an emoji outside the set is refused', ids.s1,
    `insert into message_reactions (message_id, profile_id, emoji)
     values ($1, $2, '🖕')`, [reactable, ids.s1]);

  await expectDenied('nobody can react as somebody else', ids.s1,
    `insert into message_reactions (message_id, profile_id, emoji)
     values ($1, $2, '👍')`, [reactable, ids.s2]);
  await expectDenied('and an outsider cannot react at all', ids.s2,
    `insert into message_reactions (message_id, profile_id, emoji)
     values ($1, $2, '👍')`, [reactable, ids.s2]);

  await expectRows('both parties see the reaction', ids.s1,
    'select count(*) as n from message_reactions where message_id = $1', 1,
    [reactable]);
  await expectRows('an outsider sees none of them', ids.s2,
    'select count(*) as n from message_reactions where message_id = $1', 0,
    [reactable]);

  // Replies, and the fence around them.
  await expectAllowed('a reply quotes a message on the same thread', ids.ownerA,
    `insert into messages (conversation_id, sender_id, body, reply_to_id)
     values ($1, $2, 'any time', $3)`, [ids.conv, ids.ownerA, reactable]);

  // reply_to_id renders a quoted snippet from the row it points at, so
  // pointing it off-thread would be a way to display a message the reader
  // may not see.
  const otherThread = await asUser(ids.s2, async () => (await db.query(
    `insert into conversations (student_id, institution_id, subject)
     values ($1, $2, 'separate') returning id`, [ids.s2, ids.instA])).rows[0].id);
  const otherMsg = await asUser(ids.s2, async () => (await db.query(
    `insert into messages (conversation_id, sender_id, body)
     values ($1, $2, 'private to this thread') returning id`,
    [otherThread, ids.s2])).rows[0].id);

  await expectDenied('a reply cannot quote another conversation', ids.ownerA,
    `insert into messages (conversation_id, sender_id, body, reply_to_id)
     values ($1, $2, 'quoting out of thread', $3)`,
    [ids.conv, ids.ownerA, otherMsg]);

  // Forwarding is a label on a new message, carrying no pointer home.
  await expectAllowed('a forwarded message is just a message with a label', ids.s1,
    `insert into messages (conversation_id, sender_id, body, is_forwarded)
     values ($1, $2, 'passing this on', true)`, [ids.conv, ids.s1]);

  // Deleting clears every label that described content which is now gone.
  // Reactions are deliberately left: both clients refuse to render them on a
  // tombstone, and they go for real when the row does, by cascade.
  await asUser(ids.s1, () => db.query(
    `select delete_message($1, 'everyone')`, [reactable]));
  const cleaned = (await db.query(
    `select reply_to_id, is_forwarded, deleted_at from messages where id = $1`,
    [reactable])).rows[0];
  if (cleaned.deleted_at && !cleaned.reply_to_id && !cleaned.is_forwarded) {
    ok('deleting a message drops its quote and its forwarded label');
  } else {
    fail('delete_message', JSON.stringify(cleaned));
  }

  // The reply survives and goes on pointing at it. Deliberately: the row is
  // tombstoned, not deleted, so the quote renders as "This message was
  // deleted" rather than silently losing the thing it was answering.
  await expectRows('and a reply to it still quotes the tombstone', ids.s1,
    `select count(*) as n from messages
      where conversation_id = $1 and body = 'any time' and reply_to_id = $2`,
    1, [ids.conv, reactable]);

  // ------------------------------------------------ privilege escalation

  console.log('\nPrivilege escalation');

  await expectDenied(
    'a student cannot promote themselves to admin',
    ids.s1, `update profiles set role = 'admin' where id = $1`, [ids.s1]);

  await expectDenied(
    'a student cannot mark their own passport verified',
    ids.s1,
    `update student_passports set verification_status = 'verified' where profile_id = $1`,
    [ids.s1]);

  // Put it back to unverified first, or the UPDATE changes nothing and the
  // guard (which fires only on an actual change) never gets exercised.
  await db.query(
    `update institutions set verification_status = 'unverified' where id = $1`, [ids.instA]);
  await expectDenied(
    'an institution cannot mark itself verified',
    ids.ownerA,
    `update institutions set verification_status = 'verified' where id = $1`, [ids.instA]);

  const stillUnverified = (await db.query(
    'select verification_status from institutions where id = $1', [ids.instA]
  )).rows[0].verification_status;
  if (stillUnverified === 'unverified') {
    ok('and the stored badge state really is unchanged');
  } else {
    fail('verification guard', `status is now '${stillUnverified}'`);
  }

  // The paid feature gate. Institution staff can update their own institution
  // row, so without a guard this is a free upgrade to Enterprise.
  await expectDenied(
    'an institution cannot upgrade its own subscription tier',
    ids.ownerA,
    `update institutions set tier = 'enterprise' where id = $1`, [ids.instA]);

  const tier = (await db.query('select tier from institutions where id = $1', [ids.instA]))
    .rows[0].tier;
  if (tier === 'basic') ok('tier is still basic');
  else fail('tier guard', `tier is now '${tier}'`);

  await expectDenied(
    'nor write the subscription record directly',
    ids.ownerA,
    `update institution_subscriptions set tier = 'enterprise' where institution_id = $1`,
    [ids.instA]);

  // Admin raising the subscription DOES propagate, which is the intended path.
  await db.query(
    `update institution_subscriptions set tier = 'professional' where institution_id = $1`,
    [ids.instA]);
  const syncedTier = (await db.query(
    'select tier from institutions where id = $1', [ids.instA])).rows[0].tier;
  if (syncedTier === 'professional') {
    ok('an admin-set subscription propagates to the institution tier');
  } else {
    fail('tier sync', `expected 'professional', got '${syncedTier}'`);
  }

  await expectDenied(
    'a student cannot award themselves an offer',
    ids.s1, `update applications set stage = 'offer' where id = $1`, [ids.app1]);

  await expectAllowed(
    'a student CAN submit their own application',
    ids.s1, `update applications set stage = 'submitted' where id = $1`, [ids.app1]);

  await expectDenied(
    'an institution cannot accept an offer on the student\'s behalf',
    ids.ownerA, `update applications set stage = 'accepted' where id = $1`, [ids.app1]);

  await expectAllowed(
    'an institution CAN move its own pipeline forward',
    ids.ownerA, `update applications set stage = 'under_review' where id = $1`, [ids.app1]);

  await expectDenied(
    'a student cannot accept before an offer exists',
    ids.s1, `update applications set stage = 'accepted' where id = $1`, [ids.app1]);

  await expectDenied(
    'the decision history cannot be rewritten, even by admin',
    ids.admin,
    `update application_events set to_stage = 'enrolled' where application_id = $1`,
    [ids.app1]);

  await expectDenied(
    'the decision history cannot be deleted, even by admin',
    ids.admin,
    'delete from application_events where application_id = $1', [ids.app1]);

  const trail = await count(
    'select count(*) as n from application_events where application_id = $1', [ids.app1]);
  if (trail >= 3) ok(`every stage change was recorded ${dim(`(${trail} events)`)}`);
  else fail('audit trail', `expected >= 3 events, got ${trail}`);

  // Submitting should have auto-granted a share (consent by action).
  await expectRows(
    'applying grants a visible, revocable share rather than a hidden exception',
    ids.s1,
    `select count(*) as n from passport_shares
      where profile_id = $1 and institution_id = $2 and revoked_at is null`,
    1, [ids.s1, ids.instA]);

  // ------------------------------------------------------------ fair passport

  console.log('\nFair Passport');

  await expectAllowed(
    'a student registers themselves for a fair',
    ids.s2,
    'insert into fair_registrations (fair_id, profile_id) values ($1, $2)',
    [ids.fair, ids.s2]);

  const pass = (await db.query(
    'select pass_code from fair_registrations where profile_id = $1', [ids.s2]))
    .rows[0].pass_code;
  if (/^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$/.test(pass)) {
    ok(`pass code generated without ambiguous characters ${dim(`(${pass})`)}`);
  } else {
    fail('pass code', `unexpected format: ${pass}`);
  }

  await expectRows(
    'an exhibitor cannot browse the fair attendee list',
    ids.ownerA,
    'select count(*) as n from fair_registrations where fair_id = $1', 0, [ids.fair]);

  await expectDenied(
    'booth visits cannot be inserted directly, bypassing the scan check',
    ids.ownerA,
    `insert into booth_visits (fair_id, exhibitor_id, profile_id)
     values ($1, $2, $3)`, [ids.fair, ids.exA, ids.s2]);

  await expectDenied(
    'staff at booth B cannot scan a pass onto booth A',
    ids.ownerB,
    `select record_booth_visit($1, 'A01', null, 'CS', 'high', true, false, null)`, [pass]);

  await expectAllowed(
    'staff at booth A CAN record a scan at their own booth',
    ids.ownerA,
    `select record_booth_visit($1, 'A01', null, 'Computer Science', 'high', true, false, null)`,
    [pass]);

  await expectRows(
    'the scan granted institution A access to that student',
    ids.ownerA,
    'select count(*) as n from student_passports where profile_id = $1', 1, [ids.s2]);

  await expectRows(
    'and the student can see exactly who that grant went to',
    ids.s2,
    `select count(*) as n from passport_shares
      where profile_id = $1 and revoked_at is null`, 1, [ids.s2]);

  await expectDenied(
    'an unknown pass code is rejected',
    ids.ownerA,
    `select record_booth_visit('ZZZZZZZZ', 'A01', null, null, 'low', false, false, null)`);

  const report = await asUser(ids.s2, async () => (await db.query(
    'select fair_report($1) as r', [ids.fair])).rows[0].r);
  if (Number(report.institutions_met) === 1 && Number(report.follow_ups_requested) === 1) {
    ok('fair_report assembled the student\'s event summary');
  } else {
    fail('fair_report', `unexpected report: ${JSON.stringify(report)}`);
  }

  await expectDenied(
    'a student cannot pull another student\'s fair report',
    ids.s1, 'select fair_report($1, $2)', [ids.fair, ids.s2]);

  // ------------------------------------------------- the identity split
  //
  // The reason Phase 2 began with a migration instead of a feed. A public
  // social profile keyed on profiles.id would let any institution member turn
  // an anonymous match card into a named minor with two REST calls. These
  // assertions are the proof that it cannot.

  console.log('\nIdentity split — a match card cannot be resolved to a person');

  // s2 has shared with A (via the booth scan), so use s3, who has shared with
  // nobody, as the student who must stay anonymous.
  await asUser(ids.s3, () => db.query(
    `select claim_handle('ngozi_e', 'Ngozi Eze', 'Looking for a CS place.')`));
  ok('a student claims a public handle');

  await asUser(ids.ownerA, () => db.query(
    `select claim_handle('maplecrest', 'Maplecrest University', null, $1)`,
    [ids.instA]));
  ok('an institution claims a handle for its organisation');

  // The card now carries a token, and no account id anywhere.
  const card = await asUser(ids.ownerA, async () => (await db.query(
    `select * from matched_student_cards
      where program_id = $1 and age_band is not null limit 1`, [ids.pA1])).rows[0]);

  if (card && typeof card.token === 'string' && card.token.length === 32) {
    ok(`match cards are keyed by an opaque token ${dim(`(${card.token.slice(0, 12)}…)`)}`);
  } else {
    fail('match token', `got ${JSON.stringify(card?.token)}`);
  }

  const cardColumns = (await db.query(
    `select column_name from information_schema.columns
      where table_name = 'matched_student_cards'`)).rows.map((r) => r.column_name);

  if (!cardColumns.includes('student_id')) {
    ok('matched_student_cards no longer exposes student_id at all');
  } else {
    fail('match card leak', 'student_id is still a column on the view');
  }

  // THE ATTACK. An institution holds a token and tries every route back to a
  // person: the mapping table, the social profile, and the public directory.
  await expectRows(
    'an institution cannot read the token mapping',
    ids.ownerA, 'select count(*) as n from match_tokens', 0);

  await expectRows(
    'an institution cannot read social_profiles directly',
    ids.ownerA, 'select count(*) as n from social_profiles where profile_id = $1',
    0, [ids.s3]);

  const publicColumns = (await db.query(
    `select column_name from information_schema.columns
      where table_name = 'public_profiles'`)).rows.map((r) => r.column_name);

  if (!publicColumns.includes('profile_id')) {
    ok(`public_profiles has no profile_id column ${dim(`(${publicColumns.length} cols)`)}`);
  } else {
    fail('public directory leak', 'profile_id is selectable from public_profiles');
  }

  await expectDenied(
    'and cannot resolve a token through the helper either',
    ids.ownerB, 'select student_for_match_token($1)', [card?.token ?? 'x']);

  // Two institutions looking at THE SAME student get unrelated tokens, so they
  // cannot compare lists to correlate. s3 is the student who claimed a handle
  // and has shared with nobody, which is exactly the pairing the attack targets.
  const tokenA = await asUser(ids.ownerA, async () => (await db.query(
    'select match_token_for($1, $2) as t', [ids.s3, ids.instA])).rows[0].t);
  const tokenB = await asUser(ids.ownerB, async () => (await db.query(
    'select match_token_for($1, $2) as t', [ids.s3, ids.instB])).rows[0].t);

  if (tokenA && tokenB && tokenA !== tokenB) {
    ok('two institutions see different tokens for the same student');
  } else {
    fail('token correlation', `A=${tokenA} B=${tokenB}`);
  }

  // The directory still works — it is pseudonymity, not invisibility.
  await expectRows(
    'the public directory is readable by any signed-in user',
    ids.ownerA, `select count(*) as n from public_profiles where handle = 'ngozi_e'`, 1);

  await expectRows(
    'but anon sees no directory at all',
    null, `select count(*) as n from public_profiles`, 0);

  // Institutions still act on students — through the token.
  await expectAllowed(
    'an institution invites a student it cannot identify',
    ids.ownerA,
    `select institution_invite_student($1, $2, 'Strong fit for our co-op stream.')`,
    [tokenA, ids.pA1]);

  const invited = await asUser(ids.s3, () => count(
    `select count(*) as n from notifications
      where profile_id = $1 and kind = 'institution_invited_you'`, [ids.s3]));
  if (invited === 1) {
    ok('the invite reaches the right student by token alone');
  } else {
    fail('invite by token', `s3 has ${invited} invite notifications`);
  }

  await expectDenied(
    'an institution cannot act with another institution\'s token',
    ids.ownerB,
    `select institution_record_interest($1, $2, 'shortlisted', null)`,
    [tokenA, ids.pA1]);

  // And the escape hatch still works exactly as before.
  const nameVisible = () => asUser(ids.ownerA, () => count(
    `select count(*) as n from matched_student_cards
      where token = $1 and shared_name is not null`, [tokenA]));

  const beforeShare = await nameVisible();
  await asUser(ids.s3, () => db.query(
    `insert into passport_shares (profile_id, institution_id, reason)
     values ($1, $2, 'identity split test')`, [ids.s3, ids.instA]));
  const afterShare = await nameVisible();

  if (beforeShare === 0 && afterShare > 0) {
    ok('granting a share is still the one way a name appears');
  } else {
    fail('consent gate', `before=${beforeShare} after=${afterShare}`);
  }

  // ---------------------------------------------------- the prospectus
  //
  // Public-facing by design — it is the page an institution wants students to
  // read — so the thing worth asserting is that only its own staff can write it.

  console.log('\nInstitution prospectus');

  const profileRow = await asUser(ids.ownerA, async () => (await db.query(
    'select * from institution_profiles where institution_id = $1', [ids.instA])).rows[0]);

  if (profileRow) {
    ok(`every institution gets a profile row on creation ` +
       dim(`(completeness ${profileRow.completeness})`));
  } else {
    fail('profile bootstrap', 'no institution_profiles row for a created institution');
  }

  await expectAllowed(
    'staff fill in the prospectus',
    ids.ownerA,
    `update institution_profiles
        set tagline = 'Where ambition meets opportunity',
            about = 'A research university in Toronto.',
            campus_life = 'Three campuses on the subway line.',
            accommodation = 'Guaranteed first-year residence.',
            founded_year = 1964,
            student_count = 41000,
            cost_of_living_max = 18000,
            application_fee = 120,
            accreditation = array['Universities Canada'],
            rankings = '[{"body":"QS World","rank":301,"year":2026}]'::jsonb,
            application_steps = '[{"title":"Submit transcript"}]'::jsonb
      where institution_id = $1`, [ids.instA]);

  const scored = await asUser(ids.ownerA, () => count(
    'select completeness as n from institution_profiles where institution_id = $1',
    [ids.instA]));
  if (scored >= 50) {
    ok(`completeness recomputed from the filled fields ${dim(`(${scored}%)`)}`);
  } else {
    fail('completeness trigger', `expected >= 50, got ${scored}`);
  }

  // The write rule, across every prospectus table.
  for (const [table, insert] of [
    ['institution_media',
     `insert into institution_media (institution_id, kind, storage_path, caption)
      values ($1, 'photo', $2, 'The quad')`],
    ['institution_intakes',
     `insert into institution_intakes (institution_id, label, term_starts)
      values ($1, 'Fall 2026', '2026-09-07')`],
    ['institution_scholarships',
     `insert into institution_scholarships (institution_id, name, coverage)
      values ($1, 'International Merit Award', '50% of tuition')`],
    ['institution_contacts',
     `insert into institution_contacts (institution_id, role, email)
      values ($1, 'International admissions', 'intl@univ-a.ca')`],
    ['institution_faqs',
     `insert into institution_faqs (institution_id, question, answer)
      values ($1, 'Do you accept WAEC?', 'Yes, with five credits including English.')`],
  ]) {
    // The media path has to be prefixed with the institution's own uuid, so it
    // takes a second parameter rather than concatenating onto the first.
    const args = table === 'institution_media'
      ? [ids.instA, `${ids.instA}/quad.jpg`]
      : [ids.instA];

    await expectAllowed(`staff add ${table}`, ids.ownerA, insert, args);
    await expectDenied(
      `another institution cannot write ${table}`, ids.ownerB, insert, args);
    await expectDenied(
      `a student cannot write ${table}`, ids.s1, insert, args);
  }

  // Country-specific requirements, which is the whole point of the table.
  await asUser(ids.ownerA, () => db.query(
    `insert into institution_entry_requirements
       (institution_id, from_country, level, qualification, min_grade_value,
        min_grade_scheme, min_english_band)
     values ($1, 'NG', 'undergraduate', 'WASSCE with five credits', 6,
             'waec', 6.5)`, [ids.instA]));
  await asUser(ids.ownerA, () => db.query(
    `insert into institution_entry_requirements
       (institution_id, from_country, level, qualification, min_english_band)
     values ($1, null, null, 'Recognised secondary qualification', 6.0)`,
    [ids.instA]));
  ok('a country-specific rule and a general fallback coexist');

  // A Nigerian student sees their own rule first; a Ghanaian sees the general one.
  const ngView = await asUser(ids.s1, async () => (await db.query(
    'select institution_prospectus($1) as p', [ids.instA])).rows[0].p);

  if (ngView?.resolved_for_country === 'NG'
      && ngView.requirements?.[0]?.from_country === 'NG') {
    ok('the prospectus resolves requirements to the student\'s own country');
  } else {
    fail('requirement resolution',
      `country=${ngView?.resolved_for_country} ` +
      `first=${JSON.stringify(ngView?.requirements?.[0]?.from_country)}`);
  }

  const ghView = await asUser(ids.s3, async () => (await db.query(
    'select institution_prospectus($1) as p', [ids.instA])).rows[0].p);
  if (ghView?.requirements?.length === 1
      && ghView.requirements[0].from_country === null) {
    ok('a student from elsewhere falls back to the general rule');
  } else {
    fail('requirement fallback',
      `got ${JSON.stringify(ghView?.requirements?.map((r) => r.from_country))}`);
  }

  // One call, everything the page renders.
  const sections = ['institution', 'profile', 'media', 'intakes', 'scholarships',
                    'contacts', 'faqs', 'requirements', 'programs'];
  const missingSections = sections.filter((k) => !(k in (ngView ?? {})));
  if (missingSections.length === 0) {
    ok(`the whole page arrives in one call ${dim(`(${sections.length} sections)`)}`);
  } else {
    fail('prospectus shape', `missing: ${missingSections.join(', ')}`);
  }

  // The domain is the basis of the verified badge, not public information.
  if (ngView?.institution && !('email_domain' in ngView.institution)) {
    ok('the prospectus withholds the verification domain');
  } else {
    fail('domain leak', 'email_domain is in the prospectus payload');
  }

  await expectDenied(
    'anon cannot read a prospectus',
    null, 'select institution_prospectus($1)', [ids.instA]);

  // ------------------------------------------------- posts and the feed

  console.log('\nPosts, the feed, and moderation');

  // Handles for everyone involved. s3 claimed one earlier; these are the rest.
  await asUser(ids.s1, () => db.query(
    `select claim_handle('chidi_o', 'Chidi Okeke')`));
  await asUser(ids.s2, () => db.query(
    `select claim_handle('amina_b', 'Amina Bello')`));
  await asUser(ids.ownerB, () => db.query(
    `select claim_handle('northgate', 'Northgate College', null, $1)`,
    [ids.instB]));
  ok('handles claimed for the social fixture');

  // An institution posts, tagged with a field and a destination.
  const orgPost = await asUser(ids.ownerA, async () => (await db.query(
    `select create_post(
       'Global Futures Scholarship closes in 14 days. Full tuition, ten awards.',
       'announcement', $1, null, 'everyone',
       array['computer-science'], array['CA']) as id`,
    [ids.instA])).rows[0].id);
  ok('an institution posts as itself');

  const postCard = await asUser(ids.s1, async () => (await db.query(
    'select * from post_by_id($1)', [orgPost])).rows[0]);

  if (postCard?.author_handle === 'maplecrest'
      && postCard.author_kind === 'institution') {
    ok('the post is attributed to the institution, not the staff member',
      dim(`(@${postCard.author_handle})`));
  } else {
    fail('post attribution',
      `handle=${postCard?.author_handle} kind=${postCard?.author_kind}`);
  }

  // The badge tracks the institution's real status rather than being baked in.
  // An earlier assertion left this one unverified, so it should read false now
  // and flip when admin verifies it.
  if (postCard?.author_verified === false) {
    ok('an unverified institution\'s post carries no badge');
  } else {
    fail('badge', `author_verified was ${postCard?.author_verified}`);
  }

  await db.query(
    `update institutions set verification_status = 'verified' where id = $1`,
    [ids.instA]);
  const verifiedCard = await asUser(ids.s1, async () => (await db.query(
    'select author_verified from post_by_id($1)', [orgPost])).rows[0]);
  if (verifiedCard?.author_verified === true) {
    ok('and the badge appears once it is verified');
  } else {
    fail('badge flip', `got ${verifiedCard?.author_verified}`);
  }

  const feedColumns = (await db.query(
    `select column_name from information_schema.columns
      where table_name = 'feed_posts'`)).rows.map((r) => r.column_name);
  const publicLeak = feedColumns.filter(
    (c) => c === 'author_id' || c === 'profile_id' || c === 'institution_id');
  if (publicLeak.length === 0) {
    ok('feed_posts exposes no unprefixed account id');
  } else {
    fail('feed leak', `exposed: ${publicLeak.join(', ')}`);
  }

  // For you, with nobody followed. This is the assertion the topic vocabulary
  // exists for: s1 targets computer-science and CA, which is what was tagged.
  const forYou = await asUser(ids.s1, async () => (await db.query(
    'select id from feed_for_you(30)')).rows);
  if (forYou.some((r) => r.id === orgPost)) {
    ok(`For you reaches a student following nobody ${dim(`(${forYou.length} posts)`)}`);
  } else {
    fail('for-you', `the tagged post is absent from ${forYou.length} rows`);
  }

  // Following is empty until they follow someone.
  const beforeFollow = await asUser(ids.s1, () =>
    count('select count(*) as n from feed_following(30)'));
  await asUser(ids.s1, () => db.query(`select follow_handle('maplecrest')`));
  const afterFollow = await asUser(ids.s1, () =>
    count('select count(*) as n from feed_following(30)'));

  if (beforeFollow === 0 && afterFollow > 0) {
    ok(`following a handle fills the Following tab ${dim(`(${afterFollow})`)}`);
  } else {
    fail('follow', `before=${beforeFollow} after=${afterFollow}`);
  }

  await expectRows(
    'the follow is counted on the public profile',
    ids.s1,
    `select count(*) as n from public_profiles
      where handle = 'maplecrest' and follower_count = 1`, 1);

  await expectDenied(
    'nobody can follow themselves',
    ids.s1, `select follow_handle('chidi_o')`);

  // ── Reposts ────────────────────────────────────────────────────────────

  const repostId = await asUser(ids.s1, async () => (await db.query(
    'select repost($1) as id', [orgPost])).rows[0].id);
  ok('a student reshares it');

  const reshared = await asUser(ids.s2, async () => (await db.query(
    `select * from feed_by_handle('chidi_o')`)).rows[0]);

  if (reshared?.reposted?.author_handle === 'maplecrest') {
    ok('the reshare carries the original, attributed');
  } else {
    fail('repost shape', JSON.stringify(reshared?.reposted)?.slice(0, 160));
  }

  const counted = await asUser(ids.s1, () => count(
    'select repost_count as n from posts where id = $1', [orgPost]));
  if (counted === 1) ok('the original counts the reshare');
  else fail('repost count', `got ${counted}`);

  // Resharing a reshare reshares the original, rather than chaining.
  const chained = await asUser(ids.s2, async () => (await db.query(
    'select repost($1) as id', [repostId])).rows[0].id);
  const chainedRoot = await asUser(ids.s2, async () => (await db.query(
    'select repost_of from posts where id = $1', [chained])).rows[0].repost_of);
  if (chainedRoot === orgPost) {
    ok('resharing a reshare flattens to the original');
  } else {
    fail('repost chaining', `root was ${chainedRoot}`);
  }

  // ── THE ASSERTION REPOSTS EXIST FOR ───────────────────────────────────
  // Amplification means a removal that misses the copies leaves the content
  // standing exactly where it spread.

  const removed = await asUser(ids.ownerA, async () => (await db.query(
    'select remove_post($1) as n', [orgPost])).rows[0].n);
  if (Number(removed) >= 3) {
    ok(`removing a post removes its reshares too ${dim(`(${removed} rows)`)}`);
  } else {
    fail('cascade removal', `only ${removed} rows were removed`);
  }

  await expectRows(
    'and the reshare is gone from its author\'s own profile feed',
    ids.s2, `select count(*) as n from feed_by_handle('chidi_o')`, 0);

  await expectRows(
    'and from For you',
    ids.s1,
    'select count(*) as n from feed_for_you(30) where id = $1', 0, [orgPost]);

  // ── Replies, policies and rate limits ─────────────────────────────────

  const openPost = await asUser(ids.ownerA, async () => (await db.query(
    `select create_post('Ask us anything about September entry.', 'question',
                        $1, null, 'everyone', array['computer-science'],
                        array['CA']) as id`, [ids.instA])).rows[0].id);

  await expectAllowed(
    'a student replies to an open post',
    ids.s1, `select comment_on_post($1, 'Do you accept WAEC?')`, [openPost]);

  const limitedPost = await asUser(ids.ownerA, async () => (await db.query(
    `select create_post('Limited replies.', 'update', $1, null, 'following',
                        '{}', '{}') as id`, [ids.instA])).rows[0].id);

  await expectDenied(
    'reply policy "following" turns away someone they do not follow',
    ids.s2, `select comment_on_post($1, 'Hello')`, [limitedPost]);

  // ── Blocks and mutes ──────────────────────────────────────────────────

  const s2Post = await asUser(ids.s2, async () => (await db.query(
    `select create_post('Anyone applying to Maplecrest?', 'question', null,
                        null, 'everyone', array['computer-science'],
                        array['CA']) as id`)).rows[0].id);

  await asUser(ids.s1, () => db.query(`select moderate_handle('amina_b', 'mute')`));
  await expectRows(
    'a muted account disappears from the feed',
    ids.s1,
    'select count(*) as n from feed_for_you(30) where id = $1', 0, [s2Post]);
  await expectRows(
    'but is still readable on their own profile',
    ids.s1,
    `select count(*) as n from feed_by_handle('amina_b') where id = $1`,
    1, [s2Post]);
  await asUser(ids.s1, () => db.query(`select moderate_handle('amina_b', 'unmute')`));

  await asUser(ids.s1, () => db.query(`select moderate_handle('amina_b', 'block')`));
  await expectRows(
    'a blocked account is invisible even on their profile',
    ids.s1,
    `select count(*) as n from feed_by_handle('amina_b')`, 0);
  await expectRows(
    'and the block works in the other direction too',
    ids.s2, `select count(*) as n from feed_by_handle('chidi_o')`, 0);

  const followAfterBlock = await asUser(ids.s1, () => count(
    `select count(*) as n from follows
      where follower_id = $1 and followee_id = $2`, [ids.s1, ids.s2]));
  if (followAfterBlock === 0) ok('blocking severs any follow between them');
  else fail('block', 'a follow survived the block');

  await asUser(ids.s1, () => db.query(`select moderate_handle('amina_b', 'unblock')`));

  // ── Restrictions ──────────────────────────────────────────────────────

  await db.query(
    `insert into account_restrictions (profile_id, kind, reason)
     values ($1, 'read_only', 'Testing')`, [ids.s2]);

  await expectDenied(
    'a restricted account cannot post',
    ids.s2, `select create_post('Should not work')`);
  await expectDenied(
    'nor reply',
    ids.s2, `select comment_on_post($1, 'Nor this')`, [openPost]);
  await expectRows(
    'but can still read',
    ids.s2, 'select count(*) as n from feed_for_you(30) where id = $1',
    1, [openPost]);
  await expectRows(
    'and can see that they are restricted, and why',
    ids.s2,
    `select count(*) as n from account_restrictions where reason = 'Testing'`, 1);

  await db.query(`update account_restrictions set lifted_at = now()
                   where profile_id = $1`, [ids.s2]);

  // ── Minors ────────────────────────────────────────────────────────────

  await db.query(
    `update student_passports set date_of_birth = (now() - interval '15 years')::date
      where profile_id = $1`, [ids.s2]);

  const minorFlag = await db.query(
    'select is_minor from social_profiles where profile_id = $1', [ids.s2]);
  if (minorFlag.rows[0]?.is_minor === true) {
    ok('is_minor is derived from the passport, not self-declared');
  } else {
    fail('minor flag', `got ${JSON.stringify(minorFlag.rows[0])}`);
  }

  await expectDenied(
    'an institution cannot cold-message a minor',
    ids.ownerB,
    `insert into conversations (student_id, institution_id, subject)
     values ($1, $2, 'Hello')`, [ids.s2, ids.instB]);

  await asUser(ids.s2, () => db.query(`select follow_handle('northgate')`));
  await expectAllowed(
    'but may once that student follows them',
    ids.ownerB,
    `insert into conversations (student_id, institution_id, subject)
     values ($1, $2, 'Hello')`, [ids.s2, ids.instB]);

  // ── Reporting ─────────────────────────────────────────────────────────

  await expectAllowed(
    'a student reports a post',
    ids.s1,
    `insert into reports (reporter_id, subject_type, subject_id, reason, note)
     values ($1, 'post', $2, 'misinformation', 'Not true.')`,
    [ids.s1, openPost]);

  await expectRows(
    'admin sees it in the one queue',
    ids.admin,
    `select count(*) as n from reports where status = 'pending'`, 1);

  await expectRows(
    'the reported author cannot see who reported them',
    ids.ownerA, 'select count(*) as n from reports', 0);

  await expectAllowed(
    'admin removes the post and resolves the report together',
    ids.admin, `select remove_post($1, 'Removed on review')`, [openPost]);

  await expectRows(
    'and the queue is clear',
    ids.admin,
    `select count(*) as n from reports where status = 'pending'`, 0);

  // ── The identity split still holds with social data present ───────────

  await expectRows(
    'an institution still cannot read social_profiles',
    ids.ownerA,
    'select count(*) as n from social_profiles where profile_id = $1', 0, [ids.s1]);

  const stillNoLeak = (await db.query(
    `select column_name from information_schema.columns
      where table_name = 'public_profiles' and column_name = 'profile_id'`)).rows;
  if (stillNoLeak.length === 0) {
    ok('and the public directory still has no profile_id');
  } else {
    fail('identity split', 'profile_id reappeared on public_profiles');
  }

  // ------------------------------------------- the web console's contracts
  //
  // The React console reads these views and RPCs directly, so their shape is a
  // contract. A renamed column here is a blank dashboard there.

  console.log('\nConsole views and RPCs');

  const demand = await asUser(ids.ownerA, async () => (await db.query(
    'select my_institution_demand($1) as d', [ids.instA])).rows[0].d);

  const demandKeys = [
    'matched_students', 'shared_passports', 'open_applications',
    'pending_appointments', 'unread_conversations', 'top_fields',
  ];
  const missingKeys = demandKeys.filter((k) => !(k in demand));
  if (missingKeys.length === 0) {
    ok(`my_institution_demand returns every key the dashboard reads ` +
       dim(`(matched_students=${demand.matched_students})`));
  } else {
    fail('my_institution_demand shape', `missing: ${missingKeys.join(', ')}`);
  }

  await expectDenied(
    'my_institution_demand refuses an institution you do not staff',
    ids.ownerB, 'select my_institution_demand($1)', [ids.instA]);

  // The card columns the console renders, by name.
  const requiredCardColumns = [
    'token', 'program_id', 'institution_id', 'program_name', 'score',
    'reasons', 'current_country', 'nationality', 'target_levels',
    'target_fields', 'intended_intake', 'grade_band', 'age_band',
    'english_band', 'budget_band', 'completeness', 'passport_verification',
    'is_shared', 'shared_name', 'already_actioned',
  ];
  const absent = requiredCardColumns.filter((c) => !cardCols.includes(c));
  if (absent.length === 0) {
    ok('matched_student_cards exposes every column the console renders');
  } else {
    fail('matched_student_cards shape', `missing: ${absent.join(', ')}`);
  }

  // k-anonymity: the fixture has three students, below the floor of five, so
  // every demand cell must be suppressed rather than shown.
  const cells = await asUser(ids.ownerA, () =>
    count('select count(*) as n from student_demand_stats'));
  if (cells === 0) {
    ok(`demand cells below the floor are suppressed ${dim('(3 students < floor of 5)')}`);
  } else {
    fail('k-anonymity floor', `${cells} cell(s) exposed with only 3 students seeded`);
  }

  // Add enough students to clear the floor, then confirm cells appear.
  for (let i = 0; i < 4; i++) {
    const extra = await uuid();
    await db.query(
      `insert into auth.users (id, email, raw_user_meta_data)
       values ($1, $2, '{"role":"student","full_name":"Bulk Student"}'::jsonb)`,
      [extra, `bulk${i}@example.com`]);
    await db.query(
      `insert into student_passports (
         profile_id, date_of_birth, nationality, current_country,
         highest_qualification, grade_value, grade_scheme,
         english_test_name, english_score,
         target_countries, target_levels, target_fields,
         budget_max, budget_currency, intended_intake)
       values ($1, '2005-03-02', 'NG', 'NG', 'WASSCE', 78, 'percentage',
               'ielts', 7.0, array['CA','GB'],
               array['undergraduate']::study_level[], array['computer-science'],
               30000, 'USD', 'Fall 2026')`,
      [extra]);
  }

  const cellsAfter = await asUser(ids.ownerA, () =>
    count('select count(*) as n from student_demand_stats'));
  if (cellsAfter > 0) {
    ok(`demand cells appear once the floor is met ${dim(`(${cellsAfter} cells, 7 students)`)}`);
  } else {
    fail('demand stats', 'no cells even with 7 matching students');
  }

  await expectRows(
    'and demand stats stay invisible to students regardless',
    ids.s1, 'select count(*) as n from student_demand_stats', 0);

  // ── Student handles are issued, not asked for ──────────────────────────

  await mk('autoA', 'auto.a@example.com', 'student', 'Samuel Ebhomien');
  await mk('autoB', 'auto.b@example.com', 'student', 'Samuel Okonkwo');
  await mk('autoC', 'auto.c@example.com', 'student', '');

  const autoA = (await db.query(
    'select handle, display_name, kind from social_profiles where profile_id = $1',
    [ids.autoA])).rows[0];

  if (autoA && /^[a-z][a-z0-9_]{2,19}$/.test(autoA.handle))
    ok(`a student is given a handle at signup ${dim(`(@${autoA.handle})`)}`);
  else fail('student handle', `got ${JSON.stringify(autoA)}`);

  // The surname must not be in it. The whole consent gate exists so an
  // institution cannot put a name to a student, and a handle is public.
  if (autoA && !autoA.handle.includes('ebhomien'))
    ok('and it does not carry their surname');
  else fail('student handle privacy', `@${autoA?.handle} leaks the surname`);

  // Two people with the same first name must not collide.
  const autoB = (await db.query(
    'select handle from social_profiles where profile_id = $1', [ids.autoB])).rows[0];
  if (autoB && autoB.handle !== autoA.handle)
    ok(`a second Samuel gets a different one ${dim(`(@${autoB.handle})`)}`);
  else fail('handle collision', `both got @${autoA?.handle}`);

  // A missing name still has to produce a valid handle.
  const autoC = (await db.query(
    'select handle from social_profiles where profile_id = $1', [ids.autoC])).rows[0];
  if (autoC && /^[a-z][a-z0-9_]{2,19}$/.test(autoC.handle))
    ok(`an empty name still yields a usable handle ${dim(`(@${autoC.handle})`)}`);
  else fail('handle fallback', `got ${JSON.stringify(autoC)}`);

  // Which means the thing that used to stop a new student now works.
  // A post of its own: `orgPost` is soft-deleted by the moderation
  // assertions above, and "no such post" would pass for the wrong reason.
  const standingPost = await asUser(ids.ownerA, async () => (await db.query(
    `select create_post('Open day on the 14th.', 'announcement', $1) as id`,
    [ids.instA])).rows[0].id);

  await expectAllowed(
    'and they can reply straight away, without claiming anything',
    ids.autoA,
    `select comment_on_post($1, 'Is this open to Nigerians?')`, [standingPost]);

  // Minors stay protected: the handle row is created before any passport, so
  // is_minor starts false and must be corrected when a date of birth arrives.
  await asUser(ids.autoA, () => db.query(
    `insert into student_passports (profile_id, date_of_birth)
     values ($1, (current_date - interval '15 years')::date)`, [ids.autoA]));
  const minorNow = (await db.query(
    'select is_minor from social_profiles where profile_id = $1', [ids.autoA]
  )).rows[0].is_minor;
  if (minorNow === true)
    ok('is_minor is corrected once the passport gives a date of birth');
  else fail('minor protection', 'a 15-year-old is not flagged as a minor');

  // ── A new student's first run ──────────────────────────────────────────
  //
  // Found live: a student signed up, an institution posted, and For you was
  // empty. `from student_passports where profile_id = auth.uid()` yields no
  // rows for someone with no passport, so every branch of the feed's WHERE
  // cross-joined against an empty relation and came out false.

  await mk('fresh', 'fresh@example.com', 'student', 'Fresh Student');
  await asUser(ids.fresh, () => db.query(
    `select claim_handle('fresh_one', 'Fresh Student')`));

  const freshFeed = await asUser(ids.fresh, async () => (await db.query(
    'select count(*)::int as n from feed_for_you(30, null)')).rows[0].n);
  if (freshFeed > 0)
    ok(`a student with no passport still has a feed ${dim(`(${freshFeed} posts)`)}`);
  else
    fail('first-run feed', 'For you was empty for a student with no passport');

  // Only institution posts, though — a stranger's personal posts are not a
  // sensible default for someone who has told us nothing.
  const freshOnlyOrgs = await asUser(ids.fresh, async () => (await db.query(
    `select count(*)::int as n from feed_for_you(30, null) f
      where not exists (select 1 from posts p
                         where p.id = f.id and p.institution_id is not null)`
  )).rows[0].n);
  if (freshOnlyOrgs === 0) ok('and it is institution posts only');
  else fail('first-run feed', `${freshOnlyOrgs} personal post(s) leaked in`);

  // And the fallback stops the moment they say what they want: a passport
  // that matches nothing means a feed that shows nothing, not everything.
  await asUser(ids.fresh, () => db.query(
    `insert into student_passports (profile_id, target_fields, target_countries)
     values ($1, array['nursing'], array['NZ'])`, [ids.fresh]));
  const afterPassport = await asUser(ids.fresh, async () => (await db.query(
    'select count(*)::int as n from feed_for_you(30, null)')).rows[0].n);
  if (afterPassport === 0)
    ok('once the passport says something, the feed obeys it');
  else
    fail('first-run fallback', `${afterPassport} post(s) ignored the passport`);

  // ── Searching posts from Discover ──────────────────────────────────────
  //
  // Discover could search programs and nothing else: the institutions it
  // fetched were never rendered, and posts were unreachable — so "scholarship"
  // found course listings and none of the announcements actually about
  // scholarships.

  const searchable = await asUser(ids.ownerA, async () => (await db.query(
    `select create_post(
       'Chevening scholarship applications open next month.',
       'announcement', $1, null, 'everyone',
       array['computer-science'], array['CA']) as id`,
    [ids.instA])).rows[0].id);

  const hits = await asUser(ids.s1, async () => (await db.query(
    `select count(*)::int as n from search_posts('chevening')`)).rows[0].n);
  if (hits === 1) ok('search_posts finds a post by its body');
  else fail('post search', `expected 1 hit for 'chevening', got ${hits}`);

  // The author is worth matching too: "maplecrest" should find what
  // Maplecrest has said, not only posts containing the word.
  const byAuthor = await asUser(ids.s1, async () => (await db.query(
    `select count(*)::int as n from search_posts('maplecrest')`)).rows[0].n);
  if (byAuthor > 0) ok(`and by author ${dim(`(${byAuthor} posts)`)}`);
  else fail('post search by author', 'searching the institution name found nothing');

  // A topic, so "computer science" reaches posts tagged with it whether or
  // not the phrase is in the text.
  const byTopic = await asUser(ids.s1, async () => (await db.query(
    `select count(*)::int as n from search_posts('computer science')`)).rows[0].n);
  if (byTopic > 0) ok(`and by topic ${dim(`(${byTopic} posts)`)}`);
  else fail('post search by topic', 'a tagged post was not found by its topic');

  // An empty query returns nothing rather than the whole table.
  const blank = await asUser(ids.s1, async () => (await db.query(
    `select count(*)::int as n from search_posts('   ')`)).rows[0].n);
  if (blank === 0) ok('a blank query returns nothing, not everything');
  else fail('post search', `a blank query returned ${blank} rows`);

  // And it inherits the feed's visibility rules rather than going round them:
  // s2 blocked chidi_o earlier, so a search must not surface them.
  await asUser(ids.s2, () => db.query(`select moderate_handle('ngozi_e', 'block')`));
  const afterBlock = await asUser(ids.s2, async () => (await db.query(
    `select count(*)::int as n from search_posts('chevening') f
      where f.author_handle = 'ngozi_e'`)).rows[0].n);
  if (afterBlock === 0) ok('a blocked account stays invisible in search');
  else fail('post search visibility', `${afterBlock} post(s) from a blocked account`);
  await asUser(ids.s2, () => db.query(`select moderate_handle('ngozi_e', 'unblock')`));
  void searchable;

  // ── Reads must survive a read-only transaction ─────────────────────────
  //
  // PostgREST runs every GET inside `BEGIN READ ONLY`. The dev server does
  // not, which is why `match_token_for()` — which minted a token by INSERTing
  // — passed every test here and then failed on the live project with
  // `25006: cannot execute INSERT in a read-only transaction`, taking the
  // inbox, the pipeline and the match cards down with it.
  //
  // Every view an institution reads is checked under the same constraint the
  // real API imposes.

  console.log('\nViews under a read-only transaction');

  for (const view of [
    'matched_student_cards',
    'institution_inbox',
    'institution_pipeline',
    'institution_interest_cards',
    'public_profiles',
  ]) {
    await db.exec(`set role authenticated;
                   set request.jwt.claims = '{"sub":"${ids.ownerA}","role":"authenticated"}';`);
    let failure = null;
    try {
      await db.exec('begin read only');
      await db.query(`select * from ${view} limit 5`);
      await db.exec('rollback');
    } catch (err) {
      failure = err.message.split('\n')[0];
      try { await db.exec('rollback'); } catch { /* already aborted */ }
    }
    await db.exec('reset role; reset request.jwt.claims;');

    if (failure === null) ok(`${view} reads without writing`);
    else fail(`${view} under read-only`, failure.slice(0, 90));
  }

  // And the token is still there to read — minted when the relationship was
  // created rather than when it was first looked at.
  const tokenCount = await count('select count(*) as n from match_tokens');
  if (tokenCount > 0) ok(`tokens are minted up front ${dim(`(${tokenCount})`)}`);
  else fail('match tokens', 'no tokens exist, so every card reads back null');

  // ── The institution inbox and pipeline ─────────────────────────────────
  //
  // Both ported from the console, which read
  // `student:profiles!student_id(full_name)` directly — and
  // `profiles_select_shared_student` only permits that after a share, so every
  // conversation with an unshared student rendered nameless. These views carry
  // the match token instead, exactly as the match cards do.

  console.log('\nInstitution inbox and pipeline');

  const inboxRows = await asUser(ids.ownerA, async () => (await db.query(
    `select * from institution_inbox order by last_message_at desc nulls last`)).rows);
  if (inboxRows.length > 0) ok(`the inbox lists conversations ${dim(`(${inboxRows.length})`)}`);
  else fail('institution inbox', 'no conversations visible to the institution');

  const anonRow = inboxRows.find((r) => r.is_shared === false);
  if (anonRow) {
    if (anonRow.shared_name === null && (anonRow.token ?? '').length >= 16)
      ok('an unshared student is a token, not a name');
    else
      fail('inbox identity', `shared_name=${anonRow.shared_name} token=${anonRow.token}`);
  }

  // No account id anywhere in the row — that is the whole point of the token.
  const inboxCols = Object.keys(inboxRows[0] ?? {});
  if (!inboxCols.includes('student_id') && !inboxCols.includes('profile_id'))
    ok('and the inbox exposes no account id');
  else fail('inbox leak', `columns: ${inboxCols.join(', ')}`);

  // Another institution sees only its own. B has one of its own from the
  // minor-protection assertions above, so "zero rows" would be the wrong
  // test — what matters is that none of them are A's.
  await expectRows('institution B sees none of A\'s conversations',
    ids.ownerB,
    'select count(*) as n from institution_inbox where institution_id = $1',
    0, [ids.instA]);

  // ── pipeline ──
  const pipeline = await asUser(ids.ownerA, async () => (await db.query(
    'select * from institution_pipeline')).rows);
  if (pipeline.length > 0) ok(`the pipeline lists applications ${dim(`(${pipeline.length})`)}`);
  else fail('institution pipeline', 'no applications visible');

  const pipeCols = Object.keys(pipeline[0] ?? {});
  if (!pipeCols.includes('profile_id') && pipeCols.includes('token'))
    ok('keyed by token, with no account id');
  else fail('pipeline leak', `columns: ${pipeCols.join(', ')}`);

  // Grades arrive as bands, never as figures.
  if (!pipeCols.includes('normalized_grade') && !pipeCols.includes('grade_value'))
    ok('and grades are bands, not figures');
  else fail('pipeline leak', 'an exact grade is exposed');

  await expectRows('institution B sees none of A\'s applications',
    ids.ownerB, 'select count(*) as n from institution_pipeline', 0);

  // ── moving an application ──
  const app = pipeline[0].application_id;
  const stageWas = pipeline[0].stage;

  // Deliberately a stage it is not already at. The first version of this moved
  // it to `under_review`, which is where the fixture already had it — so the
  // function correctly did nothing, and the assertion was testing a no-op.
  const target = stageWas === 'conditional_offer' ? 'offer' : 'conditional_offer';

  await expectAllowed(
    'staff move an application on, with a reason',
    ids.ownerA,
    `select set_application_stage($1, $2::application_stage, 'Strong transcript.')`,
    [app, target]);

  const moved = (await db.query(
    `select to_stage, note from application_events
      where application_id = $1 and to_stage = $2::application_stage`,
    [app, target])).rows[0];
  if (moved?.note === 'Strong transcript.')
    ok('and the reason is attached to the event, not lost');
  else fail('stage note', JSON.stringify(moved));

  // A decision stamps the application, so "when did you decide" has an answer.
  const decided = (await db.query(
    'select decision_at is not null as d from applications where id = $1',
    [app])).rows[0].d;
  if (decided) ok('an offer or rejection records when it was decided');
  else fail('decision_at', 'a decision left no timestamp');

  // Setting the stage it is already at writes nothing: a history full of
  // "moved from offer to offer" is noise that hides the real moves.
  const before = await count(
    'select count(*) as n from application_events where application_id = $1', [app]);
  await asUser(ids.ownerA, () => db.query(
    `select set_application_stage($1, $2::application_stage)`, [app, target]));
  const after = await count(
    'select count(*) as n from application_events where application_id = $1', [app]);
  if (before === after) ok('and re-setting the same stage logs nothing');
  else fail('stage no-op', `event count went ${before} -> ${after}`);

  // `draft` is the student's own state; an institution pulling one back there
  // would be rewriting what the student meant to send.
  await expectDenied(
    'but cannot return it to draft',
    ids.ownerA, `select set_application_stage($1, 'draft')`, [app]);

  await expectDenied(
    'nor touch another institution\'s application',
    ids.ownerB, `select set_application_stage($1, 'rejected')`, [app]);

  // ── asking for a document ──
  await expectAllowed(
    'staff request a document',
    ids.ownerA,
    `select request_application_document($1, 'transcript', 'Final year, please.')`,
    [app]);

  const outstanding = await asUser(ids.ownerA, async () => (await db.query(
    'select outstanding_requests from institution_pipeline where application_id = $1',
    [app])).rows[0].outstanding_requests);
  if (outstanding === 1) ok('and it shows as outstanding on the row');
  else fail('document request', `outstanding_requests=${outstanding}`);

  // The student sees it as something to act on.
  await expectRows('the student sees the request on their side',
    ids.s1,
    `select count(*) as n from application_document_requests
      where application_id = $1 and fulfilled_at is null`, 1, [app]);

  // ------------------------------------------------------- institution signup

  console.log('\nInstitution self-signup');

  // Sign-up now forks in the app: student, or organisation. The organisation
  // path self-assigns `institution_member`, which is deliberate — it is how an
  // institution onboards itself — so what it can and cannot do matters.

  await mk('newOrg',  'admissions@newcollege.edu', 'institution_member', 'New Org');
  await mk('newOrg2', 'visa@embassy.example',      'institution_member', 'Embassy Staff');
  await mk('s5',      's5@example.com',            'student',            'Student Five');

  // The kind is what decides whether a listing is about programs or visa
  // routes, and it is chosen at signup. Before this it was defaulted, so every
  // self-signed-up embassy would have been stored as a university.
  const embassyId = await asUser(ids.newOrg2, async () =>
    (await db.query(
      `select create_institution('High Commission of Canada', 'CA', null, null,
                                 'Lagos', 'Visa guidance', 'embassy') as id`
    )).rows[0].id);
  const embassyKind = (await db.query(
    'select kind from institutions where id = $1', [embassyId])).rows[0].kind;
  if (embassyKind === 'embassy') ok('create_institution() stores the kind it was given');
  else fail('institution kind at signup', `expected 'embassy', got '${embassyKind}'`);

  // The default still holds for the console, which calls with six arguments.
  const defaultedId = await asUser(ids.newOrg, async () =>
    (await db.query(
      `select create_institution('New College', 'GB', null, null, 'Leeds', null) as id`
    )).rows[0].id);
  const defaultedKind = (await db.query(
    'select kind from institutions where id = $1', [defaultedId])).rows[0].kind;
  if (defaultedKind === 'university') ok('a six-argument call still defaults the kind');
  else fail('institution kind default', `expected 'university', got '${defaultedKind}'`);

  // InstitutionProvider.load() takes the first membership row with no ORDER BY,
  // so a second listing would make the shell load an arbitrary one of the two.
  await expectDenied(
    'a member cannot create a second institution',
    ids.newOrg,
    `select create_institution('New College Annexe', 'GB', null, null, null, null)`);

  await expectDenied(
    'a student cannot create an institution at all',
    ids.s5,
    `select create_institution('Fake University', 'NG', null, null, null, null)`);

  // Every author has a handle. Found by running the app against an empty
  // database: only the seed ever created social_profiles rows, so an
  // institution that signed itself up could post and reach the feed with a
  // blank author handle — the card showing a bare "@".
  const orgHandle = (await db.query(
    'select handle, kind, institution_id from social_profiles where profile_id = $1',
    [ids.newOrg])).rows[0];
  if (orgHandle && /^[a-z][a-z0-9_]{2,19}$/.test(orgHandle.handle))
    ok(`create_institution() claimed a handle (@${orgHandle.handle})`);
  else fail('institution handle', `got ${JSON.stringify(orgHandle)}`);

  // An embassy's handle is an embassy handle, so its posts are attributed as
  // one rather than as a university.
  const embHandle = (await db.query(
    'select handle, kind from social_profiles where profile_id = $1',
    [ids.newOrg2])).rows[0];
  if (embHandle?.kind === 'embassy') ok('an embassy gets the embassy kind');
  else fail('embassy handle kind', `got '${embHandle?.kind}'`);

  // Two organisations with the same name must not collide on one handle.
  await mk('twinOrg', 'twin@newcollege.edu', 'institution_member', 'Twin Org');
  await asUser(ids.twinOrg, () => db.query(
    `select create_institution('New College', 'IE', null, null, 'Cork', null)`));
  const twin = (await db.query(
    'select handle from social_profiles where profile_id = $1', [ids.twinOrg]
  )).rows[0];
  if (twin && twin.handle !== orgHandle.handle)
    ok(`a same-named institution got a distinct handle (@${twin.handle})`);
  else fail('handle collision', `both got '${twin?.handle}'`);

  // And nothing can post without one, at the single place every write path
  // goes through — so this cannot be reintroduced by a new code path.
  await mk('noHandle', 'nohandle@example.com', 'student', 'No Handle');
  await expectDenied(
    'an account with no handle cannot post',
    ids.noHandle,
    `select create_post('Hello from nobody.')`);
  await expectDenied(
    'nor comment',
    ids.noHandle,
    `select comment_on_post($1, 'Me too.')`, [orgPost]);

  // Self-assigning institution_member grants the ability to make a listing, not
  // a claim that the institution is real — the badge still has to be earned.
  const newOrgVerified = (await db.query(
    'select verification_status from institutions where id = $1', [defaultedId]
  )).rows[0].verification_status;
  if (newOrgVerified !== 'verified')
    ok(`a self-signed-up institution is not verified (${newOrgVerified})`);
  else fail('signup verification', 'a self-signed-up institution came out verified');

  // And the signup role clamp still holds for the role the fork does not offer.
  const sneak2 = await uuid();
  await db.query(
    `insert into auth.users (id, email, raw_user_meta_data)
     values ($1, 'sneak2@example.com', '{"role":"institution_member","full_name":"S"}'::jsonb)`,
    [sneak2]);
  const sneak2Role = (await db.query('select role from profiles where id = $1', [sneak2]))
    .rows[0].role;
  if (sneak2Role === 'institution_member')
    ok('institution_member is self-assignable at signup, by design');
  else fail('signup role', `expected institution_member, got '${sneak2Role}'`);

  // ---------------------------------------------------------------- storage

  // ======================================================== Live Spaces
  //
  // The feature most likely to break the identity split, so these assertions
  // are weighted towards it: what an institution can see of a listener, and
  // what a listener can make true about themselves.

  console.log('\nLive Spaces');

  // Scheduled to start now, so space_is_open() lets people in.
  ids.spaceA = await asUser(ids.ownerA, async () => (await db.query(
    `insert into spaces (institution_id, host_profile_id, title, kind, scheduled_for)
     values ($1, $2, 'Admissions hour: Computer Science', 'admissions_hour', now())
     returning id`, [ids.instA, ids.ownerA])).rows[0].id);
  ok('an institution schedules a Space');

  await expectDenied('a student cannot schedule a Space', ids.s4,
    `insert into spaces (institution_id, host_profile_id, title, scheduled_for)
     values ($1, $2, 'Fake session', now())`, [ids.instA, ids.s4]);

  await expectDenied('institution B cannot schedule one at A', ids.ownerB,
    `insert into spaces (institution_id, host_profile_id, title, scheduled_for)
     values ($1, $2, 'Poaching hour', now())`, [ids.instA, ids.ownerB]);

  await expectRows('a signed-in student can see A\'s session', ids.s4,
    'select count(*) as n from spaces where id = $1', 1, [ids.spaceA]);
  await expectRows('anon sees nothing in spaces', null,
    'select count(*) as n from spaces where id = $1', 0, [ids.spaceA]);

  // A verified institution may run an open door; an unverified one may not.
  const verifiedAdmission = (await db.query(
    'select requires_admission from spaces where id = $1', [ids.spaceA])).rows[0].requires_admission;
  if (verifiedAdmission === false) ok('a verified institution can run an open-door Space');
  else fail('guard_space_admission', 'a verified institution was forced into a waiting room');

  await mk('ownerC', 'owner@univ-c.edu', 'institution_member', 'Owner C');
  ids.instC = await asUser(ids.ownerC, async () => (await db.query(
    `select create_institution('University C', 'US', 'https://univ-c.edu', 'univ-c.edu',
                               'Boston', 'Not yet verified') as id`)).rows[0].id);
  ids.spaceC = await asUser(ids.ownerC, async () => (await db.query(
    `insert into spaces (institution_id, host_profile_id, title, scheduled_for,
                         requires_admission)
     values ($1, $2, 'Unverified open day', now(), false) returning id`,
    [ids.instC, ids.ownerC])).rows[0].id);
  const unverifiedAdmission = (await db.query(
    'select requires_admission from spaces where id = $1', [ids.spaceC])).rows[0].requires_admission;
  if (unverifiedAdmission === true) {
    ok('an unverified institution is forced into a waiting room, whatever it asked for');
  } else {
    fail('guard_space_admission', 'an unverified institution got an open door');
  }

  // ------------------------------------------------- joining as a listener

  const partS4 = await asUser(ids.s4, async () => (await db.query(
    'select join_space($1) as id', [ids.spaceA])).rows[0].id);
  ok('a student joins a Space');

  const grantListener = await asUser(ids.s4, async () => (await db.query(
    'select space_room_grant($1) as g', [ids.spaceA])).rows[0].g);

  if (grantListener.admission === 'admitted'
      && grantListener.role === 'listener'
      && grantListener.can_publish === false
      && grantListener.can_publish_data === false
      && grantListener.can_subscribe === true
      && grantListener.identity === `sp_${partS4}`
      && String(grantListener.display_name).startsWith('@')) {
    ok(`a listener publishes nothing and is named by handle ${dim(`(${grantListener.display_name})`)}`);
  } else {
    fail('listener grant', JSON.stringify(grantListener).slice(0, 220));
  }

  // The whole identity split, in one assertion: nothing the client is handed,
  // and therefore nothing that reaches LiveKit, is an account id.
  if (!JSON.stringify(grantListener).includes(ids.s4)) {
    ok('a room grant carries no account id');
  } else {
    fail('identity split', 'space_room_grant leaked a profiles.id into the token payload');
  }

  await expectRows('institution A sees 0 rows in space_participants', ids.ownerA,
    'select count(*) as n from space_participants where space_id = $1', 0, [ids.spaceA]);

  const rosterCols = (await db.query(
    `select column_name from information_schema.columns
      where table_schema = 'public' and table_name = 'space_roster'`)).rows
    .map((r) => r.column_name);
  if (!rosterCols.includes('profile_id')) {
    ok(`space_roster has no profile_id column ${dim(`(${rosterCols.length} columns)`)}`);
  } else {
    fail('space_roster', 'the roster exposes a profile_id');
  }

  const rosterBefore = await asUser(ids.ownerA, async () => (await db.query(
    'select * from space_roster where space_id = $1 and role = $2',
    [ids.spaceA, 'listener'])).rows);
  if (rosterBefore.length === 1
      && rosterBefore[0].handle
      && rosterBefore[0].shared_name === null
      && rosterBefore[0].is_identified === false) {
    ok('the host sees a handle, and no name');
  } else {
    fail('space_roster', JSON.stringify(rosterBefore).slice(0, 200));
  }

  await expectRows('institution B sees nothing of A\'s roster', ids.ownerB,
    'select count(*) as n from space_roster where space_id = $1', 0, [ids.spaceA]);

  // ---------------------------------- what a listener cannot make true
  //
  // These two are the whole waiting room and the whole consent gate. A student
  // who could write either column would walk past both.

  await expectDenied('a student cannot promote themselves to speaker', ids.s4,
    `update space_participants set role = 'speaker' where id = $1`, [partS4]);
  await expectDenied('a student cannot admit themselves', ids.s4,
    `update space_participants set admission = 'admitted' where id = $1`, [partS4]);
  await expectDenied('a listener cannot post in the chat', ids.s4,
    `insert into space_messages (space_id, participant_id, body)
     values ($1, $2, 'can I ask a question?')`, [ids.spaceA, partS4]);

  // ------------------------------------------------- listening becomes speaking

  const sharesQ = `select count(*) as n from passport_shares
                    where profile_id = $1 and institution_id = $2 and revoked_at is null`;
  const sharesBefore = await count(sharesQ, [ids.s4, ids.instA]);
  await asUser(ids.s4, () => db.query('select identify_in_space($1)', [ids.spaceA]));
  const sharesAfter = await count(sharesQ, [ids.s4, ids.instA]);

  if (sharesBefore === 0 && sharesAfter === 1) {
    ok('speaking writes exactly one live passport share — the same gate as everything else');
  } else {
    fail('identify_in_space', `shares before=${sharesBefore} after=${sharesAfter}`);
  }

  await expectAllowed('once identified, they can post in the chat', ids.s4,
    `insert into space_messages (space_id, participant_id, body)
     values ($1, $2, 'What are the entry requirements?')`, [ids.spaceA, partS4]);

  const grantSpeaker = await asUser(ids.s4, async () => (await db.query(
    'select space_room_grant($1) as g', [ids.spaceA])).rows[0].g);

  if (grantSpeaker.role === 'speaker'
      && grantSpeaker.can_publish === true
      && grantSpeaker.publish_sources.includes('microphone')
      && grantSpeaker.publish_sources.includes('camera')
      && !grantSpeaker.publish_sources.includes('screen_share')) {
    ok('a speaker gets a mic and a camera, and not screen share');
  } else {
    fail('speaker grant', JSON.stringify(grantSpeaker.publish_sources));
  }

  // The identity must survive the upgrade, or every moderation event written
  // against the listener would point at somebody who no longer exists.
  if (grantSpeaker.identity === grantListener.identity) {
    ok('the upgrade does not change their identity');
  } else {
    fail('identity stability',
      `${grantListener.identity} became ${grantSpeaker.identity}`);
  }

  const rosterAfter = await asUser(ids.ownerA, async () => (await db.query(
    'select * from space_roster where participant_id = $1', [partS4])).rows[0]);
  if (rosterAfter.shared_name && rosterAfter.is_identified === true) {
    ok(`the host now sees a name ${dim(`(${rosterAfter.shared_name})`)}`);
  } else {
    fail('space_roster', 'the name did not appear after the share');
  }

  // ------------------------------------------ asking for review vs awarding it

  // The path an institution uses when it has no working mail on its own domain:
  // insert a request, and let an admin resolve it.
  await expectAllowed('an institution can ask to be verified', ids.ownerA,
    `insert into verifications (subject_type, subject_id, evidence)
     values ('institution', $1, '{"method":"review_request"}'::jsonb)`, [ids.instA]);

  // ...but not write its own answer. Without the status check in
  // verifications_insert_subject this succeeded: inert, because the decision
  // trigger is UPDATE-only, yet it showed in the admin queue under "Verified"
  // as though somebody had approved it.
  await expectDenied('an institution cannot insert its own verdict', ids.ownerB,
    `insert into verifications (subject_type, subject_id, status)
     values ('institution', $1, 'verified')`, [ids.instB]);

  await expectDenied('nor set the badge on its own row', ids.ownerB,
    `update institutions set verification_status = 'verified' where id = $1`,
    [ids.instB]);

  // The admin resolves it, and the decision propagates to the institution.
  await asUser(ids.admin, () => db.query(
    `update verifications set status = 'verified', reviewer_id = $1
      where subject_type = 'institution' and subject_id = $2
        and status = 'pending'`, [ids.admin, ids.instA]));
  const badge = (await db.query(
    'select verification_status, verified_at from institutions where id = $1',
    [ids.instA])).rows[0];
  if (badge.verification_status === 'verified' && badge.verified_at) {
    ok('an admin decision moves the badge, and stamps when');
  } else {
    fail('apply_verification_decision', `status=${badge.verification_status}`);
  }

  // ------------------------------------------------------- going live

  await expectDenied('institution B cannot start A\'s session', ids.ownerB,
    `select space_set_status($1, 'live')`, [ids.spaceA]);
  await expectDenied('a student cannot start it either', ids.s4,
    `select space_set_status($1, 'live')`, [ids.spaceA]);
  await expectDenied('a session cannot be un-started', ids.ownerA,
    `select space_set_status($1, 'scheduled')`, [ids.spaceA]);

  await asUser(ids.ownerA, () => db.query(
    `select space_set_status($1, 'live')`, [ids.spaceA]));
  const live = (await db.query(
    'select status, started_at from spaces where id = $1', [ids.spaceA])).rows[0];
  const startEvents = await count(
    `select count(*) as n from space_moderation_events
      where space_id = $1 and action = 'started'`, [ids.spaceA]);
  if (live.status === 'live' && live.started_at && startEvents === 1) {
    ok('going live stamps the start and records who did it');
  } else {
    fail('space_set_status', `status=${live.status} events=${startEvents}`);
  }

  // ------------------------------------------- live means open, for everyone

  // A session scheduled for next week, taken live today. The window says no;
  // `live` says yes, and `live` is the one a host just pressed.
  ids.spaceFuture = await asUser(ids.ownerA, async () => (await db.query(
    `insert into spaces (institution_id, host_profile_id, title, scheduled_for)
     values ($1, $2, 'Scheduled for next week', now() + interval '7 days')
     returning id`, [ids.instA, ids.ownerA])).rows[0].id);

  await expectRows('a student cannot join a session a week out', ids.s4,
    'select space_is_open($1)::int as n', 0, [ids.spaceFuture]);

  // The host, however, is never locked out of their own room.
  await expectRows('but its host can open it whenever', ids.ownerA,
    'select space_is_open($1)::int as n', 1, [ids.spaceFuture]);

  await asUser(ids.ownerA, () => db.query(
    `select space_set_status($1, 'live')`, [ids.spaceFuture]));

  await expectRows('and once live, so can everyone else', ids.s4,
    'select space_is_open($1)::int as n', 1, [ids.spaceFuture]);

  // ------------------------------------- going live tells the right students

  // s2 follows the institution; s4 does not. ownerA already holds instA's
  // handle from the identity-split section, so only the follow is new here.
  await db.query(
    `insert into follows (follower_id, followee_id) values ($1, $2)
     on conflict do nothing`, [ids.s2, ids.ownerA]);

  ids.spaceNotify = await asUser(ids.ownerA, async () => (await db.query(
    `insert into spaces (institution_id, host_profile_id, title, scheduled_for)
     values ($1, $2, 'Announced session', now()) returning id`,
    [ids.instA, ids.ownerA])).rows[0].id);

  const liveNotes = () => count(
    `select count(*) as n from notifications
      where kind = 'space_live' and payload->>'space_id' = $1`,
    [ids.spaceNotify]);

  const notesBefore = await liveNotes();
  await asUser(ids.ownerA, () => db.query(
    `select space_set_status($1, 'live')`, [ids.spaceNotify]));
  const notesAfter = await liveNotes();

  if (notesAfter > notesBefore) {
    ok(`going live notifies the institution's followers ${dim(`(${notesAfter})`)}`);
  } else {
    fail('notify_followers_space_live', 'nobody was told');
  }

  await expectRows('and it reached the follower', ids.s2,
    `select count(*) as n from notifications
      where kind = 'space_live' and payload->>'space_id' = $1`, 1,
    [ids.spaceNotify]);
  await expectRows('a student who does not follow hears nothing', ids.s4,
    `select count(*) as n from notifications
      where kind = 'space_live' and payload->>'space_id' = $1`, 0,
    [ids.spaceNotify]);

  // Editing a session that is already live must not announce it twice.
  await asUser(ids.ownerA, () => db.query(
    `update spaces set title = 'Announced session (edited)' where id = $1`,
    [ids.spaceNotify]));
  const afterEdit = await liveNotes();
  if (afterEdit === notesAfter) ok('editing a live session does not notify again');
  else fail('notify_followers_space_live', 'notified twice for one session');

  // ---------------------------------------------------------- moderation

  await expectDenied('institution B cannot moderate A\'s participant', ids.ownerB,
    `select space_moderate($1, 'muted')`, [partS4]);

  await asUser(ids.ownerA, () => db.query(
    `select space_moderate($1, 'muted', $2)`, [partS4, 'background noise']));
  const muteEvents = await count(
    `select count(*) as n from space_moderation_events
      where subject_participant_id = $1 and action = 'muted'`, [partS4]);
  if (muteEvents === 1) ok('a mute leaves a record of who did it and why');
  else fail('space_moderate', `expected 1 mute event, got ${muteEvents}`);

  await expectRows('the person who was muted can read the record', ids.s4,
    `select count(*) as n from space_moderation_events
      where subject_participant_id = $1`, 1, [partS4]);

  // s2 holds a share with A from the booth scan, but has never identified in
  // THIS room — so the floor is still not the host's to give.
  const partS2 = await asUser(ids.s2, async () => (await db.query(
    'select join_space($1) as id', [ids.spaceA])).rows[0].id);
  await expectDenied('a host cannot give the floor to someone who has not identified',
    ids.ownerA, `select space_moderate($1, 'promoted')`, [partS2]);

  await asUser(ids.ownerA, () => db.query(
    `select space_moderate($1, 'removed', 'off topic')`, [partS2]));
  await expectDenied('a removed participant cannot rejoin', ids.s2,
    'select join_space($1)', [ids.spaceA]);

  const partOwnerA = await asUser(ids.ownerA, async () => (await db.query(
    'select join_space($1) as id', [ids.spaceA])).rows[0].id);
  await expectDenied('the host cannot be removed from their own session', ids.ownerA,
    `select space_moderate($1, 'removed')`, [partOwnerA]);

  await expectDenied('not even an admin can rewrite the moderation log', ids.admin,
    `update space_moderation_events set reason = 'rewritten' where space_id = $1`,
    [ids.spaceA]);
  await expectDenied('nor delete from it', ids.admin,
    'delete from space_moderation_events where space_id = $1', [ids.spaceA]);
  await expectDenied('a host cannot edit a chat message', ids.ownerA,
    `update space_messages set body = 'something else' where space_id = $1`,
    [ids.spaceA]);

  // --------------------------------------------- moderators a host appoints
  //
  // The point of the role is that it is NOT staff: it carries a mute button
  // and carries no new ability to see who anyone is. s4 is already an
  // identified speaker in spaceA, which is the shape an appointment starts
  // from.

  await expectDenied('a student cannot appoint themselves a moderator', ids.s4,
    `select space_moderate($1, 'moderator_granted')`, [partS4]);

  await asUser(ids.ownerA, () => db.query(
    `select space_moderate($1, 'moderator_granted')`, [partS4]));
  const modRole = (await db.query(
    'select role from space_participants where id = $1', [partS4])).rows[0].role;
  if (modRole === 'moderator') ok('the host appoints a moderator');
  else fail('moderator_granted', `role is '${modRole}'`);

  // s3 joins as a plain listener, to be moderated by someone who is not staff.
  const partS3 = await asUser(ids.s3, async () => (await db.query(
    'select join_space($1) as id', [ids.spaceA])).rows[0].id);

  await expectAllowed('the moderator can mute a listener', ids.s4,
    `select space_moderate($1, 'muted')`, [partS3]);
  await expectAllowed('and turn their camera off', ids.s4,
    `select space_moderate($1, 'camera_muted')`, [partS3]);
  await expectDenied('but cannot act on the host', ids.s4,
    `select space_moderate($1, 'removed')`, [partOwnerA]);
  await expectDenied('nor appoint a second moderator', ids.s4,
    `select space_moderate($1, 'moderator_granted')`, [partS3]);
  await expectDenied('a plain attendee moderates nothing at all', ids.s3,
    `select space_moderate($1, 'muted')`, [partS4]);

  // The roster is the whole privacy question. A moderator needs the waiting
  // room and the hand queue; they do not need, and must not get, the names
  // students shared with the INSTITUTION.
  const rosterAsMod = await asUser(ids.s4, async () => (await db.query(
    'select participant_id, handle, shared_name from space_roster where space_id = $1',
    [ids.spaceA])).rows);
  if (rosterAsMod.length > 0 && rosterAsMod.every((r) => r.shared_name === null)) {
    ok(`a moderator reads the roster and not one name ${dim(`(${rosterAsMod.length} rows)`)}`);
  } else if (rosterAsMod.length === 0) {
    fail('space_roster', 'a moderator sees nothing and cannot do the job');
  } else {
    fail('space_roster', `leaked ${JSON.stringify(rosterAsMod.filter((r) => r.shared_name))}`);
  }

  await expectRows('while a plain attendee still sees no roster', ids.s3,
    'select count(*) as n from space_roster where space_id = $1', 0, [ids.spaceA]);

  // The appointment is scoped to the one room. Nothing about moderating
  // spaceA may open a roster belonging to a different institution.
  await expectRows('and a moderator of one space reads no other', ids.s4,
    'select count(*) as n from space_roster where space_id = $1', 0, [ids.spaceC]);

  const staffStillSees = await asUser(ids.ownerA, async () => (await db.query(
    'select shared_name from space_roster where space_id = $1', [ids.spaceA])).rows);
  if (staffStillSees.some((r) => r.shared_name)) {
    ok('and staff still see the names that were shared with them');
  } else {
    fail('space_roster', 'staff lost the names too');
  }

  // Appointing somebody must not unmask them. `cohost` would have: the grant
  // puts a full name on a cohost's video tile.
  const modGrant = await asUser(ids.s4, async () => (await db.query(
    'select space_room_grant($1) as g', [ids.spaceA])).rows[0].g);
  if (modGrant.can_publish && modGrant.display_name.startsWith('@')
      && !modGrant.publish_sources.includes('screen_share')) {
    ok(`a moderator speaks, as a handle, without screen share ${dim(`(${modGrant.display_name})`)}`);
  } else {
    fail('space_room_grant', JSON.stringify(modGrant).slice(0, 200));
  }

  // ------------------------------------------- taking the floor back, for good
  //
  // Demoting set the role and revoked publishing, both correctly — and then
  // the student tapped unmute, the app offered the consent sheet any listener
  // gets, and identify_in_space() promoted them straight back. Two taps, no
  // host involved. s3 is a listener who has never identified, so this walks
  // the whole path.

  await db.query(
    `insert into follows (follower_id, followee_id) values ($1, $2)
     on conflict do nothing`, [ids.s3, ids.ownerA]);

  await expectAllowed('a listener who consents gets the floor', ids.s3,
    'select identify_in_space($1)', [ids.spaceA]);

  await asUser(ids.ownerA, () => db.query(
    `select space_moderate($1, 'demoted')`, [partS3]));

  const sharesHeld = await count(
    `select count(*) as n from passport_shares
      where profile_id = $1 and institution_id = $2`, [ids.s3, ids.instA]);

  await expectDenied('consenting again cannot undo a demotion', ids.s3,
    'select identify_in_space($1)', [ids.spaceA]);

  const demotedRole = (await db.query(
    'select role from space_participants where id = $1', [partS3])).rows[0].role;
  if (demotedRole === 'listener') ok('and they are still a listener');
  else fail('space_floor_withheld', `role is '${demotedRole}'`);

  // A refused promotion must not leave a new share behind for something that
  // did not happen, which is why the check runs before grant_passport_share().
  await expectRows('with no new passport share written', ids.s3,
    `select count(*) as n from passport_shares
      where profile_id = $1 and institution_id = $2`, sharesHeld,
    [ids.s3, ids.instA]);

  // The only way back is the host's own "Give them the floor".
  await asUser(ids.ownerA, () => db.query(
    `select space_moderate($1, 'promoted')`, [partS3]));
  const regranted = (await db.query(
    'select role from space_participants where id = $1', [partS3])).rows[0].role;
  if (regranted === 'speaker') ok('a host can give it back');
  else fail('promoted', `role is '${regranted}'`);

  await expectAllowed('and consenting works again afterwards', ids.s3,
    'select identify_in_space($1)', [ids.spaceA]);

  // Comparing the newest demotion against the newest regrant, rather than
  // merely looking for a demotion, is what makes this repeatable.
  await asUser(ids.ownerA, () => db.query(
    `select space_moderate($1, 'demoted')`, [partS3]));
  await expectDenied('and a second demotion holds just as well', ids.s3,
    'select identify_in_space($1)', [ids.spaceA]);

  // Put s3 back, so later sections see the listener they expect.
  await asUser(ids.ownerA, () => db.query(
    `select space_moderate($1, 'promoted')`, [partS3]));

  // ---------------------------------------------------- muting a whole room

  const silenced = await asUser(ids.s4, async () => (await db.query(
    'select space_mute_all($1, true) as r', [ids.spaceA])).rows[0].r);
  const muteList = silenced.identities ?? [];
  if (muteList.includes(`sp_${partS3}`)
      && !muteList.includes(`sp_${partOwnerA}`)
      && !muteList.includes(`sp_${partS4}`)
      && silenced.include_video === true) {
    ok(`mute-everyone skips the host and the caller ${dim(`(${muteList.length} to mute)`)}`);
  } else {
    fail('space_mute_all', JSON.stringify(silenced).slice(0, 200));
  }

  await expectDenied('a plain attendee cannot silence the room', ids.s3,
    'select space_mute_all($1, false)', [ids.spaceA]);
  await expectAllowed('an admin can', ids.admin,
    'select space_mute_all($1, false)', [ids.spaceA]);
  // Re-appointing the same person: idempotent on the row, and the point here
  // is the authority, not the state change.
  await expectAllowed('and an admin can appoint a moderator too', ids.admin,
    `select space_moderate($1, 'moderator_granted')`, [partS4]);

  const muteAllEvents = await count(
    `select count(*) as n from space_moderation_events
      where space_id = $1 and action = 'muted_everyone'`, [ids.spaceA]);
  if (muteAllEvents === 2) ok('and every room-wide mute left a record');
  else fail('space_mute_all', `expected 2 events, got ${muteAllEvents}`);

  // Taking it back drops them to speaker, not to the back of the room: they
  // were identified before they were appointed, and that has not changed.
  await asUser(ids.ownerA, () => db.query(
    `select space_moderate($1, 'moderator_revoked')`, [partS4]));
  const revokedRole = (await db.query(
    'select role from space_participants where id = $1', [partS4])).rows[0].role;
  if (revokedRole === 'speaker') ok('a revoked moderator keeps the floor they earned');
  else fail('moderator_revoked', `role is '${revokedRole}'`);

  await expectDenied('and moderates nothing afterwards', ids.s4,
    `select space_moderate($1, 'muted')`, [partS3]);

  // ------------------------------------------------------- the waiting room

  const partS4C = await asUser(ids.s4, async () => (await db.query(
    'select join_space($1) as id', [ids.spaceC])).rows[0].id);
  const grantPending = await asUser(ids.s4, async () => (await db.query(
    'select space_room_grant($1) as g', [ids.spaceC])).rows[0].g);
  if (grantPending.admission === 'pending' && grantPending.token === undefined) {
    ok('a waiting student is told to wait, and handed nothing to connect with');
  } else {
    fail('waiting room', JSON.stringify(grantPending).slice(0, 200));
  }

  await expectDenied('a waiting student cannot identify their way in', ids.s4,
    'select identify_in_space($1)', [ids.spaceC]);

  await asUser(ids.ownerC, () => db.query(
    `select space_moderate($1, 'admitted')`, [partS4C]));
  const grantAdmitted = await asUser(ids.s4, async () => (await db.query(
    'select space_room_grant($1) as g', [ids.spaceC])).rows[0].g);
  if (grantAdmitted.admission === 'admitted') ok('once admitted, they are let in');
  else fail('waiting room', `still ${grantAdmitted.admission} after being admitted`);

  // ------------------------------------------- the appointment room and its venue

  ids.apptA = await asUser(ids.s1, async () => (await db.query(
    `insert into appointments (student_id, institution_id, scheduled_for, status, channel)
     values ($1, $2, now(), 'confirmed', 'video') returning id`,
    [ids.s1, ids.instA])).rows[0].id);
  ok('a confirmed video appointment defaults to a Lekkside room');

  const apptGrant = await asUser(ids.s1, async () => (await db.query(
    'select appointment_room_grant($1) as g', [ids.apptA])).rows[0].g);
  if (apptGrant.admission === 'admitted'
      && apptGrant.identity === `ap_${ids.apptA}_s`
      && apptGrant.can_publish === true
      && !JSON.stringify(apptGrant).includes(ids.s1)) {
    ok('both sides of an appointment publish, and neither identity is an account id');
  } else {
    fail('appointment grant', JSON.stringify(apptGrant).slice(0, 220));
  }

  await expectDenied('a third party cannot get a token for someone else\'s meeting',
    ids.ownerB, 'select appointment_room_grant($1)', [ids.apptA]);

  // The hole the new column exposed: appointments_update_student is a whole-row
  // policy, so without the guard a student could point the institution's console
  // at any link they liked.
  await expectDenied('a student cannot change where their meeting is held', ids.s1,
    `update appointments set meeting_mode = 'external_link',
            meeting_url = 'https://not-really-maplecrest.example/join'
      where id = $1`, [ids.apptA]);
  await expectAllowed('the institution can', ids.ownerA,
    `update appointments set meeting_mode = 'external_link',
            meeting_url = 'https://meet.google.com/abc-defg-hij' where id = $1`,
    [ids.apptA]);
  await expectDenied('and an external meeting has no Lekkside room to join', ids.s1,
    'select appointment_room_grant($1)', [ids.apptA]);

  console.log('\nStorage paths');

  await expectDenied(
    'a student cannot upload into another student\'s document folder',
    ids.s1,
    `insert into storage.objects (bucket_id, name)
     values ('passport-docs', $1 || '/forged.pdf')`, [ids.s2]);

  await expectAllowed(
    'a student CAN upload into their own folder',
    ids.s1,
    `insert into storage.objects (bucket_id, name)
     values ('passport-docs', $1 || '/transcript.pdf')`, [ids.s1]);

  await expectRows(
    'institution B cannot read that object',
    ids.ownerB,
    `select count(*) as n from storage.objects
      where bucket_id = 'passport-docs' and name like $1 || '%'`, 0, [ids.s1]);

  // s1's share to A was revoked earlier, then re-granted by submitting, so A
  // can read; this is the storage policy following the same single gate.
  await expectRows(
    'institution A reads it only through the same consent gate',
    ids.ownerA,
    `select count(*) as n from storage.objects
      where bucket_id = 'passport-docs' and name like $1 || '%'`, 1, [ids.s1]);

  // ------------------------------------------------------------- anon access

  console.log('\nUnauthenticated access');

  const anonChecks = [
    ['profiles', 'select count(*) as n from profiles'],
    ['student_passports', 'select count(*) as n from student_passports'],
    ['passport_documents', 'select count(*) as n from passport_documents'],
    ['programs', 'select count(*) as n from programs'],
    ['institutions', 'select count(*) as n from institutions'],
    ['messages', 'select count(*) as n from messages'],
    ['applications', 'select count(*) as n from applications'],
    ['spaces', 'select count(*) as n from spaces'],
    ['space_participants', 'select count(*) as n from space_participants'],
    ['space_messages', 'select count(*) as n from space_messages'],
    ['space_moderation_events', 'select count(*) as n from space_moderation_events'],
    ['space_roster', 'select count(*) as n from space_roster'],
  ];
  for (const [table, sql] of anonChecks) {
    await db.exec(`set role anon; set request.jwt.claims = '{"role":"anon"}';`);
    let n = -1;
    let refusal = null;
    try {
      n = await count(sql);
    } catch (err) {
      refusal = err.message.split('\n')[0];
    }
    await db.exec('reset role; reset request.jwt.claims;');

    // A refusal and a clean empty read used to look identical here — the catch
    // swallowed the error and called it zero rows. They are not the same thing,
    // and the difference is the convention 20251010000025 measured rather than
    // assumed: "with execute revoked from anon, every anon read still returns
    // cleanly (0 rows)". A table that raises instead means a policy helper has
    // lost its PUBLIC execute, which reaches a signed-out client as "You do not
    // have access to that" where it should see an empty list.
    //
    // This exact bug shipped to the hosted project on the Live Spaces tables
    // and was invisible locally, because the old catch blessed it.
    if (refusal !== null) {
      fail(`anon reads ${table} cleanly`,
        `refused instead of returning no rows: ${refusal.slice(0, 90)}`);
    } else if (n === 0) {
      ok(`anon sees nothing in ${table}`);
    } else {
      fail(`anon access to ${table}`, `${n} rows visible without authentication`);
    }
  }


  // The anon key is shipped inside the app, so "anon cannot read" is only half
  // the question. `remove_post()` used to let an anonymous caller delete any
  // post on the platform, and every repost of it: its guard was
  // `v_author <> auth.uid() and not is_admin()`, which is *null* rather than
  // true when there is no session, so the `if` never fired and execution fell
  // through to the delete.
  //
  // Each of these asserts the refusal names authentication, not a type error —
  // a call that fails because an argument was the wrong shape proves nothing.
  // A post that is still standing: `orgPost` was legitimately removed earlier,
  // by the admin-moderation assertions, so it cannot show whether an anonymous
  // delete took effect.
  const livePost = await asUser(ids.s1, async () => (await db.query(
    `select create_post('A post for the anonymous-access checks.') as id`
  )).rows[0].id);

  const anonWrites = [
    ['remove a post',      `select remove_post($1)`,                      [livePost]],
    ['post',               `select create_post('anon was here')`,         []],
    ['comment',            `select comment_on_post($1, 'anon')`,          [livePost]],
    ['repost',             `select repost($1)`,                           [livePost]],
    ['follow someone',     `select follow_handle('chidi_o', true)`,        []],
    ['block someone',      `select moderate_handle('chidi_o', 'block')`,  []],
    ['claim a handle',     `select claim_handle('anonsquatter', 'Anon')`,  []],
    ['create an institution', `select create_institution('Anon U', 'NG')`, []],
    // Live Spaces. identify_in_space() writes a consent row, which makes an
    // anonymous caller reaching it the same bug class as remove_post was.
    ['join a space',        `select join_space($1)`,            [ids.spaceA]],
    ['identify in a space', `select identify_in_space($1)`,     [ids.spaceA]],
    ['raise a hand',        `select raise_hand($1)`,            [ids.spaceA]],
    ['leave a space',       `select leave_space($1)`,           [ids.spaceA]],
    ['moderate a space',    `select space_moderate($1, 'removed')`, [partS4]],
    ['end a space',         `select space_set_status($1, 'ended')`, [ids.spaceA]],
    ['mint a space token',  `select space_room_grant($1)`,      [ids.spaceA]],
    ['mint an appointment token', `select appointment_room_grant($1)`, [ids.apptA]],
    ['remove a chat message', `select remove_space_message(
        (select id from space_messages where space_id = $1 limit 1))`, [ids.spaceA]],
  ];

  for (const [label, sql, params] of anonWrites) {
    await db.exec(`set role anon; set request.jwt.claims = '{"role":"anon"}';`);
    let outcome;
    try {
      await db.query(sql, params);
      outcome = { allowed: true };
    } catch (err) {
      outcome = { allowed: false, message: err.message.split('\n')[0] };
    }
    await db.exec('reset role; reset request.jwt.claims;');

    // Two layers may refuse, and either is a correct refusal — the point is
    // that it must be one of them and not, say, a type error, which would
    // prove nothing about whether anon is actually kept out.
    //
    //   privilege  — …025_api_grants revokes execute from anon
    //   guard      — the function's own `auth.uid() is null` check
    //
    // Both are asserted because they protect against different mistakes: a
    // future migration that re-grants execute still meets the guard, and a
    // future function that forgets the guard is still unreachable.
    const layer = /permission denied for function/i.test(outcome.message)
      ? 'privilege'
      : /authentication required/i.test(outcome.message)
        ? 'guard'
        : null;

    if (outcome.allowed) {
      fail(`anon cannot ${label}`, 'the call SUCCEEDED without authentication');
    } else if (layer) {
      ok(`anon cannot ${label} ${dim(`(${layer})`)}`);
    } else {
      fail(`anon cannot ${label}`,
        `refused, but for the wrong reason: ${outcome.message.slice(0, 90)}`);
    }
  }

  // And the post it tried to remove is still standing.
  const stillThere = await count(
    'select count(*) as n from posts where id = $1 and deleted_at is null', [livePost]);
  if (stillThere === 1) ok('the post anon tried to delete is still there');
  else fail('anon deletion', 'the post was removed by an unauthenticated caller');

  console.log(`\n${checked} assertions, ${failures} failed`);
  return failures;
}
