// Demo data for the dev server.
//
// Separate from supabase/seed.sql because that one creates passwords with
// `extensions.crypt`, which PGlite does not have — users here go through the
// same hashing the auth module uses for a real signup. The fixture content
// deliberately mirrors it so a demo looks the same either way.
//
// Everything is inserted as the service role, so RLS does not get in the way of
// building the fixture. From the moment a client signs in, RLS applies.

import { randomUUID } from 'node:crypto';
import { asService } from './db.mjs';
import { hashPassword } from './auth.mjs';

export const DEMO_PASSWORD = 'Lekkside123!';

const STUDENTS = [
  ['chidi.okeke@example.com', 'Chidi Okeke', 'NG', 78, 7.0, ['CA', 'GB'], 'computer-science', 30000],
  ['amina.bello@example.com', 'Amina Bello', 'NG', 82, 7.5, ['CA', 'US'], 'computer-science', 35000],
  ['tunde.adebayo@example.com', 'Tunde Adebayo', 'NG', 71, 6.5, ['GB'], 'business', 20000],
  ['ngozi.eze@example.com', 'Ngozi Eze', 'NG', 88, 8.0, ['CA', 'GB'], 'data-science', 40000],
  ['kwame.mensah@example.com', 'Kwame Mensah', 'GH', 75, 6.5, ['CA'], 'engineering', 28000],
  ['akosua.darko@example.com', 'Akosua Darko', 'GH', 69, 6.0, ['GB'], 'business', 18000],
  ['wanjiku.kamau@example.com', 'Wanjiku Kamau', 'KE', 84, 7.0, ['US', 'CA'], 'nursing', 33000],
  ['brian.otieno@example.com', 'Brian Otieno', 'KE', 73, 6.5, ['CA', 'GB'], 'cybersecurity', 30000],
  ['fatima.sow@example.com', 'Fatima Sow', 'NG', 66, 6.0, ['GB'], 'computer-science', 16000],
  ['emeka.nwosu@example.com', 'Emeka Nwosu', 'NG', 79, 7.0, ['CA'], 'computer-science', 26000],
  ['zainab.yusuf@example.com', 'Zainab Yusuf', 'NG', 91, 8.0, ['US', 'GB'], 'medicine', 45000],
  ['samuel.mwangi@example.com', 'Samuel Mwangi', 'KE', 68, 6.0, ['CA', 'GB'], 'business', 19000],
];

const POSTGRADUATE_FIELDS = new Set(['data-science', 'medicine']);

// A larger cohort behind the named students.
//
// `student_demand_stats` suppresses any group smaller than five, so with only a
// dozen students every demand cell is withheld and the dashboard's headline
// feature looks broken when it is in fact working correctly. These push the
// common combinations over the floor, which is also a fair reflection of what
// real fair traffic looks like: heavily concentrated on a few destinations.
const COHORT = [
  // [count, origin, destinations, field, level, grade, ielts, budget]
  [9, 'NG', ['CA'], 'computer-science', 'undergraduate', 76, 6.5, 28000],
  [7, 'NG', ['GB'], 'business', 'undergraduate', 68, 6.0, 18000],
  [6, 'NG', ['CA', 'GB'], 'engineering', 'undergraduate', 74, 6.5, 26000],
  [6, 'NG', ['US'], 'computer-science', 'undergraduate', 81, 7.0, 34000],
  [5, 'GH', ['CA'], 'business', 'undergraduate', 70, 6.0, 20000],
  [5, 'GH', ['GB'], 'computer-science', 'undergraduate', 72, 6.5, 22000],
  [5, 'KE', ['CA'], 'nursing', 'undergraduate', 79, 6.5, 30000],
  [5, 'KE', ['GB'], 'business', 'undergraduate', 69, 6.0, 19000],
  [5, 'NG', ['CA'], 'data-science', 'postgraduate', 84, 7.0, 36000],
  [5, 'NG', ['GB'], 'computer-science', 'postgraduate', 80, 7.0, 24000],
];

const FIRST_NAMES = [
  'Ada', 'Bola', 'Chuka', 'Dami', 'Efe', 'Femi', 'Gozie', 'Hauwa', 'Ifeoma',
  'Jide', 'Kemi', 'Lanre', 'Maryam', 'Nneka', 'Obi', 'Patience', 'Rotimi',
  'Sade', 'Tari', 'Uche', 'Vera', 'Wale', 'Yemi', 'Zara',
];
const LAST_NAMES = [
  'Abiola', 'Balogun', 'Chukwu', 'Danjuma', 'Eze', 'Fashola', 'Gyamfi',
  'Hassan', 'Ibrahim', 'Jalloh', 'Kamau', 'Lawal', 'Mensah', 'Njoku',
  'Okafor', 'Peters', 'Quarshie', 'Sule', 'Tetteh', 'Uduak',
];

// Relative to today rather than hardcoded. An intake that closed last March
// makes a seeded demo look broken — the student page filters to open intakes —
// and a label that disagrees between a program and a passport silently costs
// every student the intake bonus in matching.
const monthsOut = (n) => {
  const d = new Date();
  d.setMonth(d.getMonth() + n);
  return d;
};
const asDate = (d) => d.toISOString().slice(0, 10);
const termLabel = (d) => {
  const month = d.getMonth();
  const season = month <= 3 ? 'Winter' : month <= 7 ? 'Summer' : 'Fall';
  return `${season} ${d.getFullYear()}`;
};

/** The intake currently being recruited for, and the one after it. */
const CURRENT_INTAKE = termLabel(monthsOut(6));
const NEXT_INTAKE = termLabel(monthsOut(12));

export async function seed() {
  return asService(async ({ query }) => {
    const makeUser = async (email, role, fullName) => {
      const id = randomUUID();
      await query(
        `insert into auth.users
           (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
         values ($1, $2, $3, now(), $4::jsonb)`,
        [
          id,
          email,
          hashPassword(DEMO_PASSWORD),
          JSON.stringify({ role, full_name: fullName }),
        ],
      );
      await query(
        `insert into auth.identities (user_id, provider, provider_id, identity_data)
         values ($1, 'email', $2, $3::jsonb)`,
        [id, id, JSON.stringify({ sub: id, email, email_verified: true })],
      );
      return id;
    };

    // ── People ──────────────────────────────────────────────────────────────
    const admin = await makeUser('admin@lekkside.com', 'student', 'Lekkside Admin');
    // 'admin' is deliberately not self-assignable at signup, so grant it here.
    await query(`update profiles set role = 'admin' where id = $1`, [admin]);

    const ownerCA = await makeUser(
      'admissions@maplecrest.ca', 'institution_member', 'Amara Okonkwo');
    const officerCA = await makeUser(
      'officer@maplecrest.ca', 'institution_member', 'Daniel Chen');
    const ownerUK = await makeUser(
      'admissions@northgate.ac.uk', 'institution_member', 'Priya Raman');
    const ownerUS = await makeUser(
      'admissions@lakeshore.edu', 'institution_member', 'Jordan Ellis');

    // ── Institutions ────────────────────────────────────────────────────────
    const institution = async (row) => {
      const result = await query(
        `insert into institutions
           (name, slug, country, city, website, email_domain, description,
            verification_status, verified_at)
         values ($1,$2,$3,$4,$5,$6,$7,$8::verification_status,$9)
         returning id`,
        row,
      );
      return result.rows[0].id;
    };

    const instCA = await institution([
      'Maplecrest University', 'maplecrest-university', 'CA', 'Toronto',
      'https://maplecrest.ca', 'maplecrest.ca',
      'Research university with strong co-op placement in technology and engineering.',
      'verified', new Date().toISOString(),
    ]);
    const instUK = await institution([
      'Northgate College London', 'northgate-college-london', 'GB', 'London',
      'https://northgate.ac.uk', 'northgate.ac.uk',
      'Business and computing college in central London with January and September intakes.',
      'verified', new Date().toISOString(),
    ]);
    const instUS = await institution([
      'Lakeshore State University', 'lakeshore-state-university', 'US', 'Chicago',
      'https://lakeshore.edu', 'lakeshore.edu',
      'Public university with merit scholarships for international undergraduates.',
      'pending', null,
    ]);

    for (const [inst, profile, role] of [
      [instCA, ownerCA, 'owner'],
      [instCA, officerCA, 'admissions_officer'],
      [instUK, ownerUK, 'owner'],
      [instUS, ownerUS, 'owner'],
    ]) {
      await query(
        `insert into institution_members (institution_id, profile_id, member_role)
         values ($1, $2, $3::institution_member_role)`,
        [inst, profile, role],
      );
    }

    for (const [inst, tier, seats] of [
      [instCA, 'enterprise', 5],
      [instUK, 'professional', 2],
      [instUS, 'basic', 1],
    ]) {
      await query(
        `insert into institution_subscriptions (institution_id, tier, seats)
         values ($1, $2::institution_tier, $3)`,
        [inst, tier, seats],
      );
    }

    // ── Programs ────────────────────────────────────────────────────────────
    const PROGRAMS = [
      [instCA, 'BSc Computer Science', 'undergraduate', 'computer-science', 18000, 24000, 48, [CURRENT_INTAKE, NEXT_INTAKE], 65, 6.5, true],
      [instCA, 'MSc Data Science', 'postgraduate', 'data-science', 22000, 28000, 16, [CURRENT_INTAKE], 70, 6.5, true],
      [instCA, 'BEng Mechanical Engineering', 'undergraduate', 'engineering', 19000, 25000, 48, [CURRENT_INTAKE], 65, 6.0, false],
      [instUK, 'BSc Business Management', 'undergraduate', 'business', 13000, 16000, 36, [CURRENT_INTAKE, NEXT_INTAKE], 60, 6.0, false],
      [instUK, 'MSc Computing', 'postgraduate', 'computer-science', 15000, 19000, 12, [CURRENT_INTAKE], 65, 6.5, true],
      [instUK, 'Foundation in Business', 'foundation', 'business', 9000, 11000, 12, [NEXT_INTAKE], 50, 5.5, false],
      [instUS, 'BS Nursing', 'undergraduate', 'nursing', 26000, 32000, 48, [CURRENT_INTAKE], 70, 6.5, true],
      [instUS, 'BS Cybersecurity', 'undergraduate', 'cybersecurity', 24000, 30000, 48, [CURRENT_INTAKE, NEXT_INTAKE], 65, 6.0, true],
    ];

    const programIds = new Map();
    for (const row of PROGRAMS) {
      const result = await query(
        `insert into programs
           (institution_id, name, level, field_of_study, tuition_min, tuition_max,
            tuition_currency, duration_months, intakes, min_grade_value,
            min_grade_scheme, min_english_band, scholarship_available, is_active)
         values ($1,$2,$3::study_level,$4,$5,$6,'USD',$7,
                 array(select jsonb_array_elements_text($8::jsonb)),$9,
                 'percentage'::grading_scheme,$10,$11,true)
         returning id, name`,
        [row[0], row[1], row[2], row[3], row[4], row[5], row[6],
         JSON.stringify(row[7]), row[8], row[9], row[10]],
      );
      programIds.set(result.rows[0].name, result.rows[0].id);
    }

    // ── A filled prospectus for Maplecrest ──────────────────────────────────
    // One institution completed and two left thin on purpose: a demo should
    // show both what a finished page looks like and what a student sees when
    // an institution has not bothered.

    await query(
      `update institution_profiles set
         tagline = 'Where ambition meets opportunity',
         about = $2,
         campus_life = $3,
         accommodation = $4,
         founded_year = 1964,
         student_count = 41000,
         international_student_count = 8700,
         cost_of_living_min = 12000, cost_of_living_max = 18000,
         cost_currency = 'USD',
         application_fee = 120, deposit = 2500, fee_currency = 'USD',
         accreditation = array['Universities Canada', 'AACSB'],
         rankings = $5::jsonb,
         socials = $6::jsonb,
         application_steps = $7::jsonb
       where institution_id = $1`,
      [
        instCA,
        'Maplecrest is a research university in downtown Toronto, with three '
          + 'campuses on the subway line and a co-op programme that places over '
          + '4,000 students into paid work terms each year.',
        'Over 200 student clubs, varsity sport in eight disciplines, and a '
          + 'students\' union that runs an airport pickup every September for '
          + 'new international arrivals.',
        'First-year residence is guaranteed for international students who '
          + 'apply by 1 June. Rooms are single or shared, and the meal plan is '
          + 'included in the quoted cost.',
        JSON.stringify([
          { body: 'QS World University Rankings', rank: 301, year: 2026 },
          { body: "Maclean's (Canada)", rank: 12, year: 2025 },
        ]),
        JSON.stringify({
          instagram: 'https://instagram.com/maplecrest',
          youtube: 'https://youtube.com/@maplecrest',
          linkedin: 'https://linkedin.com/school/maplecrest',
        }),
        JSON.stringify([
          { title: 'Create your Education Passport',
            detail: 'Upload your transcript and English test result.' },
          { title: 'Choose a program and apply',
            detail: 'You can apply to up to three programs per intake.' },
          { title: 'Pay the application fee', detail: 'USD 120, non-refundable.' },
          { title: 'Attend a short interview',
            detail: 'Fifteen minutes, by video, with an admissions officer.' },
          { title: 'Accept your offer and pay the deposit',
            detail: 'USD 2,500, credited against your first term.' },
        ]),
      ],
    );

    for (const [openIn, closeIn, startsIn] of [
      [-2, 3, 6],    // the intake being recruited for right now
      [3, 9, 12],    // and the one after it
    ]) {
      const starts = monthsOut(startsIn);
      await query(
        `insert into institution_intakes
           (institution_id, label, applications_open, applications_close, term_starts)
         values ($1, $2, $3, $4, $5)`,
        [
          instCA,
          termLabel(starts),
          asDate(monthsOut(openIn)),
          asDate(monthsOut(closeIn)),
          asDate(starts),
        ],
      );
    }

    // A Nigerian-specific rule plus a general fallback, so the student page can
    // demonstrate resolving to the reader's own country.
    await query(
      `insert into institution_entry_requirements
         (institution_id, from_country, level, qualification, min_grade_value,
          min_grade_scheme, min_english_band, additional, note)
       values ($1, 'NG', 'undergraduate', 'WASSCE with five credits including English and Mathematics',
               6, 'waec', 6.5,
               array(select jsonb_array_elements_text($2::jsonb)), $3)`,
      [
        instCA,
        JSON.stringify([
          'Certified translation if your transcript is not in English',
          'Proof of funds covering one year of tuition and living costs',
        ]),
        'We accept WAEC and NECO. A C6 or better counts as a credit.',
      ],
    );
    await query(
      `insert into institution_entry_requirements
         (institution_id, from_country, level, qualification, min_english_band)
       values ($1, null, null, 'A recognised secondary school qualification', 6.0)`,
      [instCA],
    );

    for (const [name, coverage, amount, criteria, deadlineIn] of [
      ['International Merit Award', '50% of tuition', 12000,
       'Automatic for applicants with a normalised grade of 80% or above.', 3],
      ['Global Futures Scholarship', 'Full tuition', null,
       'Ten awards a year, by application, for students from Sub-Saharan Africa.', 2],
      ['Residence Bursary', 'One year of accommodation', 9000,
       'Needs-assessed, for first-year international students.', 5],
    ]) {
      await query(
        `insert into institution_scholarships
           (institution_id, name, coverage, amount, currency, criteria, deadline)
         values ($1, $2, $3, $4, 'USD', $5, $6)`,
        [instCA, name, coverage, amount, criteria, asDate(monthsOut(deadlineIn))],
      );
    }

    for (const [role, name, email] of [
      ['International admissions', 'Amara Okonkwo', 'intl@maplecrest.ca'],
      ['Scholarships and funding', null, 'funding@maplecrest.ca'],
      ['Accommodation', null, 'residence@maplecrest.ca'],
    ]) {
      await query(
        `insert into institution_contacts (institution_id, role, name, email)
         values ($1, $2, $3, $4)`,
        [instCA, role, name, email],
      );
    }

    for (const [question, answer] of [
      ['Do you accept WAEC or NECO results?',
       'Yes. We need five credits including English and Mathematics, where a C6 '
         + 'or better counts as a credit.'],
      ['Can I work while I study?',
       'Yes — a Canadian study permit allows up to 24 hours a week off campus '
         + 'during term, and full time during scheduled breaks.'],
      ['Is the deposit refundable if my visa is refused?',
       'Yes. Send us the refusal letter within 30 days and we refund the '
         + 'deposit in full.'],
      ['How long does an admission decision take?',
       'Usually four to six weeks from a complete application, and longer near '
         + 'the Fall closing date.'],
    ]) {
      await query(
        `insert into institution_faqs (institution_id, question, answer)
         values ($1, $2, $3)`,
        [instCA, question, answer],
      );
    }

    // ── Students and their passports ────────────────────────────────────────
    const studentIds = [];
    for (const [email, name, country, grade, ielts, targets, field, budget] of STUDENTS) {
      const id = await makeUser(email, 'student', name);
      studentIds.push(id);

      const levels = POSTGRADUATE_FIELDS.has(field)
        ? ['postgraduate']
        : ['undergraduate'];

      await query(
        `insert into student_passports
           (profile_id, date_of_birth, nationality, current_country,
            highest_qualification, grade_value, grade_scheme,
            english_test_name, english_score,
            target_countries, target_levels, target_fields,
            budget_min, budget_max, budget_currency, intended_intake, bio)
         values ($1, $2, $3, $3, $4, $5, 'percentage'::grading_scheme,
                 'ielts'::english_test, $6,
                 array(select jsonb_array_elements_text($7::jsonb)),
                 array(select jsonb_array_elements_text($8::jsonb))::study_level[],
                 array(select jsonb_array_elements_text($9::jsonb)),
                 5000, $10, 'USD', $12, $11)`,
        [
          id,
          `200${4 + (studentIds.length % 2)}-0${1 + (studentIds.length % 9)}-15`,
          country,
          country === 'NG' ? 'WASSCE' : 'Senior Secondary Certificate',
          grade,
          ielts,
          JSON.stringify(targets),
          JSON.stringify(levels),
          JSON.stringify([field]),
          budget,
          `Seeking a place for ${CURRENT_INTAKE}. Happy to discuss scholarships.`,
          CURRENT_INTAKE,
        ],
      );
    }

    // ── The wider cohort ────────────────────────────────────────────────────
    let cohortIndex = 0;
    for (const [count, origin, destinations, field, level, grade, ielts, budget] of COHORT) {
      for (let i = 0; i < count; i += 1) {
        const first = FIRST_NAMES[cohortIndex % FIRST_NAMES.length];
        const last = LAST_NAMES[(cohortIndex * 7) % LAST_NAMES.length];
        cohortIndex += 1;

        const email = `${first}.${last}.${cohortIndex}@example.com`.toLowerCase();
        const id = await makeUser(email, 'student', `${first} ${last}`);
        studentIds.push(id);

        await query(
          `insert into student_passports
             (profile_id, date_of_birth, nationality, current_country,
              highest_qualification, grade_value, grade_scheme,
              english_test_name, english_score,
              target_countries, target_levels, target_fields,
              budget_min, budget_max, budget_currency, intended_intake)
           values ($1, $2, $3, $3, $4, $5, 'percentage'::grading_scheme,
                   'ielts'::english_test, $6,
                   array(select jsonb_array_elements_text($7::jsonb)),
                   array(select jsonb_array_elements_text($8::jsonb))::study_level[],
                   array(select jsonb_array_elements_text($9::jsonb)),
                   4000, $10, 'USD', $11)`,
          [
            id,
            `2005-0${1 + (cohortIndex % 9)}-1${cohortIndex % 9}`,
            origin,
            origin === 'NG' ? 'WASSCE' : 'Senior Secondary Certificate',
            // Spread a few points either side so grade bands are not uniform.
            grade + ((cohortIndex % 5) - 2),
            ielts,
            JSON.stringify(destinations),
            JSON.stringify([level]),
            JSON.stringify([field]),
            budget,
            CURRENT_INTAKE,
          ],
        );
      }
    }

    // ── The fair ────────────────────────────────────────────────────────────
    const fair = await query(
      `insert into fairs (name, slug, city, country, venue, starts_at, ends_at)
       values ('Lekkside International Education Fair — Lagos 2026', 'lagos-2026',
               'Lagos', 'NG', 'Eko Convention Centre, Victoria Island',
               now() + interval '45 days', now() + interval '46 days')
       returning id`,
    );
    const fairId = fair.rows[0].id;

    for (const [inst, code, label] of [
      [instCA, 'A01', 'Maplecrest University'],
      [instUK, 'A02', 'Northgate College London'],
      [instUS, 'B01', 'Lakeshore State University'],
    ]) {
      await query(
        `insert into fair_exhibitors
           (fair_id, institution_id, booth_code, booth_label, package)
         values ($1, $2, $3, $4, 'booth_plus_platform'::exhibitor_package)`,
        [fairId, inst, code, label],
      );
    }

    // Every student gets a scannable Fair Passport.
    await query(
      `insert into fair_registrations (fair_id, profile_id)
       select $1, id from profiles where role = 'student'`,
      [fairId],
    );

    // ── Handles and a feed worth opening ────────────────────────────────────
    // Without posts the landing page is an empty state, which tells you
    // nothing about whether the thing works.

    const handleFor = async (profileId, handle, name, institutionId = null) => {
      await query(
        `insert into social_profiles
           (profile_id, handle, display_name, kind, institution_id)
         values ($1, $2, $3, $4::social_profile_kind, $5)
         on conflict (profile_id) do update set handle = excluded.handle`,
        [
          profileId,
          handle,
          name,
          institutionId ? 'institution' : 'student',
          institutionId,
        ],
      );
    };

    await handleFor(ownerCA, 'maplecrest', 'Maplecrest University', instCA);
    await handleFor(ownerUK, 'northgate', 'Northgate College London', instUK);
    await handleFor(ownerUS, 'lakeshore', 'Lakeshore State University', instUS);

    // The named students get handles so replies have faces.
    const namedHandles = [
      ['chidi_okeke', 'Chidi Okeke'],
      ['amina_bello', 'Amina Bello'],
      ['tunde_a', 'Tunde Adebayo'],
      ['ngozi_eze', 'Ngozi Eze'],
      ['kwame_m', 'Kwame Mensah'],
      ['akosua_d', 'Akosua Darko'],
      ['wanjiku_k', 'Wanjiku Kamau'],
      ['brian_o', 'Brian Otieno'],
    ];
    for (let i = 0; i < namedHandles.length && i < studentIds.length; i++) {
      await handleFor(studentIds[i], namedHandles[i][0], namedHandles[i][1]);
    }

    // Posts, oldest first so `created_at` spreads backwards realistically.
    const POSTS = [
      [ownerCA, instCA, 'announcement', 72,
       `Global Futures Scholarship is open for ${CURRENT_INTAKE}. Full tuition, ten awards, for students across West Africa. Applications close in eight weeks.`,
       ['computer-science', 'engineering'], ['CA']],
      [ownerCA, instCA, 'update', 54,
       'Our co-op programme placed 4,100 students into paid work terms last year. Average placement: 16 weeks, paid at CAD 22/hour.',
       ['computer-science', 'business'], ['CA']],
      [ownerCA, instCA, 'requirement', 40,
       'For students applying from Nigeria: we accept WAEC and NECO. Five credits including English and Mathematics, where C6 or better counts as a credit. IELTS 6.5 overall.',
       ['computer-science'], ['CA']],
      [ownerUK, instUK, 'announcement', 36,
       `January intake applications are open. Business Management and Computing, both with placement years.`,
       ['business', 'computer-science'], ['GB']],
      [ownerUK, instUK, 'update', 28,
       'We have moved our International Office to the Holborn campus. Walk-ins welcome Tuesday and Thursday, 10am to 4pm.',
       ['business'], ['GB']],
      [ownerUS, instUS, 'announcement', 22,
       'Merit scholarships for international undergraduates are now assessed automatically — no separate application. If your transcript qualifies, the award appears with your offer.',
       ['nursing', 'cybersecurity'], ['US']],
      [ownerCA, instCA, 'question', 18,
       'Admissions officers here. What is the one thing you wish universities explained better about applying from abroad? We will turn the answers into a guide.',
       ['computer-science', 'business', 'engineering'], ['CA']],
      [ownerUK, instUK, 'requirement', 12,
       'Reminder: a UK student visa needs proof of funds held for 28 consecutive days. Start the bank statement clock early — it catches people out every year.',
       ['business', 'computer-science'], ['GB']],
      [ownerCA, instCA, 'update', 6,
       'Residence applications for first-year international students close on the 1st. Guaranteed room if you apply before then.',
       ['computer-science', 'engineering'], ['CA']],
      [ownerUS, instUS, 'update', 3,
       'Our nursing programme is now accredited by CCNE through 2031.',
       ['nursing', 'health-sciences'], ['US']],
    ];

    const postIds = [];
    for (const [author, inst, kind, hoursAgo, body, fields, countries] of POSTS) {
      const result = await query(
        `insert into posts (author_id, institution_id, kind, body, created_at)
         values ($1, $2, $3::post_kind, $4, now() - make_interval(hours => $5))
         returning id`,
        [author, inst, kind, body, hoursAgo],
      );
      const postId = result.rows[0].id;
      postIds.push(postId);

      for (const field of fields) {
        await query(
          `insert into post_topics (post_id, kind, value)
           values ($1, 'field', $2) on conflict do nothing`, [postId, field]);
      }
      for (const country of countries) {
        await query(
          `insert into post_topics (post_id, kind, value)
           values ($1, 'country', $2) on conflict do nothing`, [postId, country]);
      }
    }

    // Replies on the question, so a thread exists to open.
    const questionPost = postIds[6];
    for (const [studentIndex, reply] of [
      [0, 'Whether you accept WAEC, plainly. Every website says "equivalent qualifications" and nobody explains what that means.'],
      [3, 'Total cost. Tuition is always listed, living costs almost never, and that is the number that decides it.'],
      [4, 'How long a decision actually takes. I have been waiting nine weeks somewhere else with no update.'],
    ]) {
      await query(
        `insert into comments (post_id, author_id, body, created_at)
         values ($1, $2, $3, now() - make_interval(hours => $4))`,
        [questionPost, studentIds[studentIndex], reply, 16 - studentIndex],
      );
    }

    // Likes and reshares, spread so the counts are not all identical.
    for (let i = 0; i < postIds.length; i++) {
      const likers = studentIds.slice(0, 3 + ((i * 7) % 20));
      for (const liker of likers) {
        await query(
          `insert into post_likes (post_id, profile_id) values ($1, $2)
           on conflict do nothing`, [postIds[i], liker]);
      }
    }

    // A student reshares the scholarship post, which is the behaviour the
    // whole repost mechanism exists for.
    await query(
      `insert into posts (author_id, repost_of, created_at)
       values ($1, $2, now() - make_interval(hours => 60))`,
      [studentIds[0], postIds[0]],
    );

    // A few follows, so the Following tab is not empty on first open.
    for (const [follower, followee] of [
      [studentIds[0], ownerCA],
      [studentIds[0], ownerUK],
      [studentIds[1], ownerCA],
      [studentIds[2], ownerUK],
    ]) {
      await query(
        `insert into follows (follower_id, followee_id) values ($1, $2)
         on conflict do nothing`, [follower, followee]);
    }

    // ── One worked-through case ─────────────────────────────────────────────
    // So the institution dashboard is not empty on first load and the student
    // app has a timeline to render.
    const chidi = studentIds[0];
    const csProgram = programIds.get('BSc Computer Science');

    // A conversation, so both inboxes have something in them.
    //
    // Without this the student's Messages tab and the institution's Inbox both
    // demo as empty, which makes a working feature look unbuilt — and it is
    // the reason the inbox shipped unported for as long as it did: nobody
    // running the seed ever saw a thread.
    const conversation = (
      await query(
        `insert into conversations (student_id, institution_id, subject, last_message_at)
         values ($1, $2, 'Entry requirements for Computer Science', now())
         returning id`,
        [studentIds[0], instCA],
      )
    ).rows[0].id;

    await query(
      `insert into conversation_participants (conversation_id, profile_id, last_read_at)
       values ($1, $2, now()), ($1, $3, null)`,
      [conversation, studentIds[0], ownerCA],
    );

    for (const [sender, body, minutesAgo] of [
      [studentIds[0],
        'Hello — I have WASSCE at 78% and IELTS 7.0. Would that meet the ' +
        'entry requirements for the September intake?', 180],
      [ownerCA,
        'Hi Chidi, thank you for writing. That looks comfortably within ' +
        'range for Computer Science. Could you send your final transcript?', 90],
      [studentIds[0],
        'Yes, I will upload it today. Does the scholarship close at the ' +
        'same time as the application?', 20],
    ]) {
      await query(
        `insert into messages (conversation_id, sender_id, body, created_at)
         values ($1, $2, $3, now() - ($4 || ' minutes')::interval)`,
        [conversation, sender, body, minutesAgo],
      );
    }

    await query(
      `insert into applications
         (profile_id, institution_id, program_id, intake, stage, student_note)
       values ($1, $2, $3, $5, 'under_review'::application_stage, $4)`,
      [
        chidi,
        instCA,
        csProgram,
        'I have completed WASSCE with 78% average and IELTS 7.0.',
        CURRENT_INTAKE,
      ],
    );

    await query(
      `insert into institution_interests
         (institution_id, program_id, profile_id, kind, note, created_by)
       values ($1, $2, $3, 'invited'::institution_interest_kind, $4, $5)`,
      [instCA, csProgram, chidi, 'Strong match for our co-op stream.', ownerCA],
    );

    // Bookable slots over the next fortnight.
    await query(
      `insert into availability_slots (institution_id, host_profile_id, starts_at, ends_at)
       select $1, $2,
              date_trunc('hour', now()) + (n || ' days')::interval + interval '10 hours',
              date_trunc('hour', now()) + (n || ' days')::interval + interval '10 hours 30 minutes'
         from generate_series(2, 12) as n`,
      [instCA, ownerCA],
    );

    const counts = await query(`
      select
        (select count(*) from profiles where role = 'student')  as students,
        (select count(*) from institutions)                     as institutions,
        (select count(*) from programs)                         as programs,
        (select count(*) from match_scores)                     as matches,
        -- Not student_demand_stats itself: that view is gated on the caller
        -- being an institution member or admin, and the seed is neither, so it
        -- would always report zero here and read like a bug.
        (select count(*) from student_passports
          where completeness >= min_completeness_to_match())    as matchable,
        (select max(completeness) from institution_profiles)    as best_profile,
        (select count(*) from posts where deleted_at is null)   as posts
    `);

    return counts.rows[0];
  });
}
