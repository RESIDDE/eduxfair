// Drives the real providers against the local dev server.
//
// The domain tests in domain_test.dart cover pure logic. This covers the part
// that only breaks against a real wire: that every query the providers issue is
// accepted, and that what comes back decodes into the models without throwing.
//
// That is not hypothetical — `numeric` columns arrive from Postgres as strings,
// and `(value as num)` on a String is a crash. A test like this is the only
// thing that catches it before a user does.
//
// Needs `npm start` in devserver/. Skips itself, loudly, when nothing is
// listening, so `flutter test` stays green for anyone who has not started it.
//
//   cd devserver && npm start
//   cd student_app && flutter test test/devserver_integration_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lekkside_connect/features/applications/providers/applications_provider.dart';
import 'package:lekkside_connect/features/auth/models/app_user.dart';
import 'package:lekkside_connect/features/auth/providers/auth_provider.dart';
import 'package:lekkside_connect/features/discover/providers/discover_provider.dart';
import 'package:lekkside_connect/features/fairs/providers/fairs_provider.dart';
import 'package:lekkside_connect/features/institution/models/pipeline.dart';
import 'package:lekkside_connect/features/institution/providers/institution_provider.dart';
import 'package:lekkside_connect/features/institution/providers/org_desk_provider.dart';
import 'package:lekkside_connect/features/matches/providers/matches_provider.dart';
import 'package:lekkside_connect/features/meet/providers/meet_provider.dart';
import 'package:lekkside_connect/features/messages/providers/messages_provider.dart';
import 'package:lekkside_connect/features/notifications/providers/notifications_provider.dart';
import 'package:lekkside_connect/features/passport/models/passport.dart';
import 'package:lekkside_connect/features/passport/providers/passport_provider.dart';
import 'package:lekkside_connect/features/social/models/post.dart';
import 'package:lekkside_connect/features/social/providers/feed_provider.dart';

const devServerUrl = 'http://localhost:54321';
const demoPassword = 'Lekkside123!';
const studentEmail = 'chidi.okeke@example.com';

Future<bool> devServerIsRunning() async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final request = await client.getUrl(Uri.parse('$devServerUrl/health'));
    final response = await request.close();
    await response.drain<void>();
    client.close();
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// The dev server's own config, never the app's active one.
///
/// `.env` is whichever environment the app is pointed at, and these suites sign
/// accounts up and write posts — so they read `.env.local` and verify it names
/// localhost before connecting. Reading `.env` would aim them at a hosted
/// project the moment someone switched environments.
Future<({String url, String key})?> localConfig() async {
  final file = File('.env.local');
  if (!file.existsSync()) return null;

  String url = '', key = '';
  for (final line in await file.readAsLines()) {
    if (line.startsWith('SUPABASE_URL=')) {
      url = line.substring('SUPABASE_URL='.length).trim();
    } else if (line.startsWith('SUPABASE_ANON_KEY=')) {
      key = line.substring('SUPABASE_ANON_KEY='.length).trim();
    }
  }
  if (key.isEmpty) return null;

  final host = Uri.tryParse(url)?.host;
  if (host != 'localhost' && host != '127.0.0.1') return null;
  return (url: url, key: key);
}

void main() {
  late bool available;
  var skipReason = 'dev server unavailable';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // The test binding installs a mock HttpClient so widget tests cannot make
    // real network calls by accident. This suite is deliberately the exception,
    // so the override has to go — without it every request, including
    // Supabase's own, fails with a fabricated 400.
    HttpOverrides.global = null;

    SharedPreferences.setMockInitialValues({});

    available = await devServerIsRunning();
    if (!available) {
      skipReason = 'no dev server on $devServerUrl — run `npm start` in devserver/';
      return;
    }

    final config = await localConfig();
    if (config == null) {
      available = false;
      skipReason =
          'student_app/.env.local must hold the dev server URL and anon key, '
          'and must point at localhost — these tests create accounts and '
          'write posts, so they never run against a hosted project';
      return;
    }

    await Supabase.initialize(
      url: config.url,
      publishableKey: config.key,
      // Nothing here should try to deep-link or persist across the suite.
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      debug: false,
    );
  });

  /// Waits until the provider has loaded a profile that [matches].
  ///
  /// Every test shares one Supabase client, so a freshly constructed
  /// AuthProvider can resolve the *previous* test's session before the new
  /// sign-in lands. Waiting on `user != null` therefore returns a stale
  /// profile and the assertion that follows tests the wrong account — which is
  /// exactly how a passing suite hid a broken signup endpoint.
  Future<void> waitForUser(
    AuthProvider auth,
    bool Function(AppUser) matches,
  ) async {
    for (var i = 0; i < 40; i++) {
      final u = auth.user;
      if (u != null && matches(u)) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Puts the shared session back to the seeded student.
  ///
  /// Registered with `addTearDown` by every test that signs in as someone
  /// else, because `addTearDown` runs even when the test fails partway. Doing
  /// this at the end of the test body instead leaves the *next* test running
  /// as the wrong account — which turns one failure into a cascade of them and
  /// makes the real cause hard to see.
  Future<void> restoreStudentSession() async {
    final back = AuthProvider();
    await back.signIn(email: studentEmail, password: demoPassword);
    await waitForUser(back, (u) => u.isStudent);
  }

  /// A brand-new student who can post: fresh account, claimed handle, and a
  /// passport that matches the seeded institution's post so *For you* has
  /// something in it.
  ///
  /// The posting tests used to run as the seeded student. `post_rate_limit()`
  /// is 20 posts an hour per author and the dev server keeps its database
  /// across runs, so those posts accumulated until the limit legitimately
  /// fired — making the suite fail roughly every eighth run with
  /// "That is a lot of posting in an hour", which looks like a bug in the
  /// feed and is actually the rate limiter doing its job. A fresh author
  /// starts at zero every time.
  Future<AuthProvider> freshPoster() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final email = 'poster.$stamp@example.com';

    final auth = AuthProvider();
    final created = await auth.signUp(
      email: email,
      password: demoPassword,
      fullName: 'Test Poster',
      role: 'student',
    );
    expect(created, isTrue, reason: auth.error);

    for (var i = 0; i < 40 && auth.email != email; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final id = Supabase.instance.client.auth.currentUser!.id;
    await waitForUser(auth, (u) => u.id == id);

    final passport = PassportProvider();
    await passport.load();
    // Matching the seeded institution's topics, so For you is not empty.
    expect(
      await passport.save(Passport(
        profileId: id,
        nationality: 'NG',
        currentCountry: 'NG',
        highestQualification: 'secondary',
        targetFields: const ['computer-science'],
        targetCountries: const ['CA'],
        targetLevels: const ['undergraduate'],
      )),
      isTrue,
      reason: passport.error,
    );
    // assert_can_write() requires a handle before anything may be posted.
    expect(
      await passport.claimHandle('poster${stamp % 100000000}', 'Test Poster'),
      isTrue,
      reason: passport.error,
    );

    return auth;
  }

  group('against the dev server', () {
    setUp(() {
      if (!available) markTestSkipped(skipReason);
    });

    test('a student can sign in and their profile loads', () async {
      if (!available) return;

      final auth = AuthProvider();
      final signedIn = await auth.signIn(
        email: studentEmail,
        password: demoPassword,
      );

      expect(signedIn, isTrue, reason: auth.error);

      // The profile arrives from a trigger-created row, so give the provider a
      // moment to pick it up.
      await waitForUser(auth, (u) => u.isStudent);

      expect(auth.user, isNotNull);
      expect(auth.user!.isStudent, isTrue);
      expect(auth.user!.fullName, isNotEmpty);
      expect(auth.user!.firstName, 'Chidi');
    });

    test('the passport decodes, including its computed columns', () async {
      if (!available) return;

      final passport = PassportProvider();
      await passport.load();

      expect(passport.error, isNull);
      expect(passport.passport, isNotNull);

      final p = passport.passport!;

      // These three are the reason this test exists: all numeric, and all would
      // throw in `Passport.fromMap` if the server sent them as strings.
      expect(p.completeness, greaterThanOrEqualTo(50));
      expect(p.normalizedGrade, isNotNull);
      expect(p.englishBand, isNotNull);
      expect(p.gradeValue, isNotNull);

      expect(p.isMatchable, isTrue);
      expect(p.targetCountries, isNotEmpty);
      expect(p.targetFields, isNotEmpty);
      expect(p.gradeDisplay, isNot('Not added'));

      // The controlled vocabulary has to load, or the pickers offer nothing.
      expect(passport.fields, isNotEmpty);
      expect(passport.fieldLabel('computer-science'), 'Computer Science & IT');
    });

    test('matches load with their reasons and nested program', () async {
      if (!available) return;

      final matches = MatchesProvider();
      await matches.load();

      expect(matches.error, isNull);
      expect(matches.matches, isNotEmpty);

      final top = matches.matches.first;
      expect(top.score, inInclusiveRange(40, 100));
      expect(top.reasons, isNotEmpty);
      expect(top.reasons.first.detail, isNotEmpty);

      // Two levels of embed: match → program → institution.
      expect(top.program, isNotNull);
      expect(top.program!.name, isNotEmpty);
      expect(top.program!.institution, isNotNull);
      expect(top.program!.institution!.name, isNotEmpty);

      // Numeric fields on the nested program.
      expect(top.program!.tuitionDisplay, isNot('Tuition not published'));

      // The seed invites this student, so reverse admission has something to
      // show rather than an empty tab.
      expect(matches.invitations, isNotEmpty);
      expect(matches.invitations.first.institutionName, isNotEmpty);
    });

    test('discovery pages, filters and saves', () async {
      if (!available) return;

      final discover = DiscoverProvider();
      await discover.load();

      expect(discover.error, isNull);
      expect(discover.programs, isNotEmpty);
      expect(discover.institutions, isNotEmpty);

      final program = discover.programs.first;
      expect(program.institution, isNotNull);
      expect(program.levelLabel, isNotEmpty);

      // A boolean filter, which is the shape that broke the dev server first.
      await discover.setFilters(scholarshipOnly: true);
      expect(discover.error, isNull);
      for (final p in discover.programs) {
        expect(p.scholarshipAvailable, isTrue);
      }

      // A filter that reaches through the embedded institution.
      await discover.clearFilters();
      await discover.setFilters(country: 'CA');
      expect(discover.error, isNull);
      for (final p in discover.programs) {
        expect(p.institution?.country, 'CA');
      }

      await discover.clearFilters();
      final target = discover.programs.first.id;
      final wasSaved = discover.isSaved(target);
      await discover.toggleSaved(target);
      expect(discover.isSaved(target), !wasSaved);
      expect(discover.error, isNull);

      // Put it back, so a re-run starts from the same place.
      await discover.toggleSaved(target);
    });

    test('the institution prospectus loads and resolves to my country', () async {
      if (!available) return;

      final discover = DiscoverProvider();
      await discover.load();

      final maplecrest = discover.institutions.firstWhere(
        (i) => i.name.startsWith('Maplecrest'),
        orElse: () => discover.institutions.first,
      );

      final prospectus = await discover.fetchProspectus(maplecrest.id);
      expect(prospectus, isNotNull, reason: discover.error);

      final p = prospectus!;
      expect(p.institution.name, isNotEmpty);
      expect(p.profile.about, isNotNull);
      expect(p.profile.completeness, greaterThanOrEqualTo(70));

      // Numerics would throw in the model if the server sent them as strings.
      expect(p.profile.costOfLivingMax, isNotNull);
      expect(p.profile.costOfLivingDisplay, isNotNull);

      expect(p.intakes, isNotEmpty);
      expect(p.scholarships, isNotEmpty);
      expect(p.faqs, isNotEmpty);
      expect(p.programs, isNotEmpty);
      expect(p.profile.rankings, isNotEmpty);
      expect(p.profile.applicationSteps, isNotEmpty);
      expect(p.profile.socials, isNotEmpty);

      // The point of the whole table: this student is Nigerian, so the
      // Nigerian rule wins over the general fallback.
      expect(p.resolvedForCountry, 'NG');
      final requirement = p.requirementForMe;
      expect(requirement, isNotNull);
      expect(requirement!.isCountrySpecific, isTrue);
      expect(requirement.fromCountry, 'NG');
      expect(requirement.qualification, contains('WASSCE'));
      expect(requirement.additional, isNotEmpty);
      expect(requirement.englishDisplay, contains('IELTS'));

      // Intakes are ordered soonest first and know their own deadline.
      expect(p.openIntakes, isNotEmpty);
      expect(p.openIntakes.first.daysToClose, isNotNull);
    });

    test('a student cannot edit an institution page', () async {
      if (!available) return;

      final discover = DiscoverProvider();
      await discover.load();
      final target = discover.institutions.first;

      final client = Supabase.instance.client;
      await client
          .from('institution_profiles')
          .update({'about': 'tampered by the integration test'})
          .eq('institution_id', target.id);

      // RLS filters the row out rather than raising, so the check is that the
      // value did not change.
      final after = await client
          .from('institution_profiles')
          .select('about')
          .eq('institution_id', target.id)
          .maybeSingle();

      expect(after?['about'], isNot(contains('tampered')));
    });

    test('the application pipeline loads with its history', () async {
      if (!available) return;

      final applications = ApplicationsProvider();
      await applications.load();

      expect(applications.error, isNull);
      expect(applications.applications, isNotEmpty);

      final application = applications.applications.first;
      expect(application.institution, isNotNull);
      expect(application.program, isNotNull);
      expect(application.stageLabel, isNotEmpty);
      // The append-only trail: at least the creation event.
      expect(application.events, isNotEmpty);
      expect(application.progress, greaterThan(0));
    });

    test('appointments and open slots load', () async {
      if (!available) return;

      final meet = MeetProvider();
      await meet.load();
      expect(meet.error, isNull);

      // The seed publishes slots for the Canadian institution.
      final discover = DiscoverProvider();
      await discover.load();
      final canadian = discover.institutions.firstWhere(
        (i) => i.country == 'CA',
        orElse: () => discover.institutions.first,
      );

      final slots = await meet.fetchSlots(canadian.id);
      expect(meet.error, isNull);
      expect(slots, isNotEmpty);
      expect(slots.first.startsAt.isAfter(DateTime.now()), isTrue);
      expect(slots.first.duration.inMinutes, greaterThan(0));
    });

    test('a conversation can be opened and a message sent', () async {
      if (!available) return;

      final discover = DiscoverProvider();
      await discover.load();
      final institution = discover.institutions.first;

      final messages = MessagesProvider();
      final conversationId = await messages.openConversation(
        institutionId: institution.id,
        subject: 'Integration test enquiry',
      );

      expect(conversationId, isNotNull, reason: messages.error);

      final sent = await messages.send(
        conversationId: conversationId!,
        body: 'Sent by the integration test.',
      );
      expect(sent, isTrue, reason: messages.error);

      await messages.loadMessages(conversationId);
      expect(messages.messagesFor(conversationId), isNotEmpty);
      expect(
        messages.messagesFor(conversationId).last.body,
        'Sent by the integration test.',
      );

      await messages.loadConversations();
      expect(messages.conversations, isNotEmpty);

      messages.dispose();
    });

    test('the Fair Passport and its report load', () async {
      if (!available) return;

      final fairs = FairsProvider();
      await fairs.load();

      expect(fairs.error, isNull);
      expect(fairs.fairs, isNotEmpty);
      expect(fairs.registrations, isNotEmpty);

      final registration = fairs.currentRegistration;
      expect(registration, isNotNull);
      // The code a booth types in: 8 characters, no ambiguous glyphs.
      expect(registration!.passCode, matches(r'^[A-HJ-NP-Z2-9]{8}$'));
      expect(registration.displayCode, contains(' '));

      final report = await fairs.fetchReport(registration.fairId);
      expect(report, isNotNull, reason: fairs.error);
      expect(report!.fairName, isNotEmpty);
    });

    test('notifications load', () async {
      if (!available) return;

      final notifications = NotificationsProvider();
      await notifications.load();
      expect(notifications.error, isNull);
      notifications.dispose();
    });

    test('saving the passport recomputes completeness server-side', () async {
      if (!available) return;

      final passport = PassportProvider();
      await passport.load();
      final before = passport.passport!;

      // Widen the destinations; the trigger should re-run matching, and
      // completeness should come back from the server rather than from here.
      final updated = before.copyWith(
        targetCountries: const ['CA', 'GB', 'US'],
        bio: 'Updated by the integration test.',
      );

      final saved = await passport.save(updated);
      expect(saved, isTrue, reason: passport.error);
      expect(passport.passport!.targetCountries, hasLength(3));
      expect(passport.passport!.completeness, greaterThanOrEqualTo(50));
      expect(passport.passport!.normalizedGrade, isNotNull);

      final matches = MatchesProvider();
      await matches.load();
      expect(matches.matches, isNotEmpty);
    });

    test('an institution account gets the institution experience', () async {
      if (!available) return;

      // Supabase auth does not care about roles, so this signs in fine. What
      // must hold is that the app resolves them to an institution rather than
      // dropping them on a student home screen asking for a passport.
      addTearDown(restoreStudentSession);

      final auth = AuthProvider();
      final signedIn = await auth.signIn(
        email: 'admissions@maplecrest.ca',
        password: demoPassword,
      );
      expect(signedIn, isTrue, reason: auth.error);

      await waitForUser(auth, (u) => u.isInstitutionMember);

      expect(auth.user, isNotNull);
      expect(auth.user!.isStudent, isFalse);
      expect(auth.user!.isInstitutionMember, isTrue);

      // The institution they staff, its profile and its subscription.
      final institutions = InstitutionProvider();
      await institutions.load();

      expect(institutions.error, isNull);
      expect(institutions.isResolved, isTrue);
      // The router keys on this; true here would send them to setup.
      expect(institutions.needsSetup, isFalse);

      final managed = institutions.managed!;
      expect(managed.institution.name, startsWith('Maplecrest'));
      expect(managed.isOwner, isTrue);
      expect(managed.tier, 'enterprise');
      expect(managed.completeness, greaterThanOrEqualTo(70));
      expect(managed.profile.about, isNotNull);

      // The dashboard's headline number.
      expect(institutions.demand.matchedStudents, greaterThan(0));
      expect(institutions.demand.topFields, isNotEmpty);

      // The prospectus sections the editor reads and writes.
      for (final table in [
        'institution_intakes',
        'institution_scholarships',
        'institution_faqs',
        'institution_contacts',
        'institution_entry_requirements',
      ]) {
        final rows = await institutions.listSection(table);
        expect(rows, isNotEmpty, reason: '$table should be seeded');
      }

      // Editing their own page works, and completeness comes back recomputed.
      final saved = await institutions.saveProfile({
        'tagline': 'Edited by the integration test',
      });
      expect(saved, isTrue, reason: institutions.error);
      expect(institutions.profile!.tagline, 'Edited by the integration test');
      expect(institutions.managed!.completeness, greaterThanOrEqualTo(70));

      // A section row round-trips.
      final added = await institutions.saveSectionRow('institution_faqs', {
        'question': 'Added by the integration test?',
        'answer': 'Yes.',
      });
      expect(added, isTrue, reason: institutions.error);

      final faqs = await institutions.listSection('institution_faqs');
      final mine = faqs.firstWhere(
        (f) => f['question'] == 'Added by the integration test?',
      );
      await institutions.deleteSectionRow(
          'institution_faqs', mine['id'] as String);

      // The student surfaces stay empty for them — every query filters on
      // their own id, so nothing leaks in either direction.
      final passport = PassportProvider();
      await passport.load();
      expect(passport.passport, isNull);

      final matches = MatchesProvider();
      await matches.load();
      expect(matches.matches, isEmpty);

      // A student resolves to no institution, so the router keeps them in the
      // student shell. (The session itself is restored by the tear-down.)
      await restoreStudentSession();
      final asStudent = InstitutionProvider();
      await asStudent.load();
      expect(asStudent.managed, isNull);
    });

    test('an organisation signs itself up, both steps', () async {
      if (!available) return;

      // The whole point of the signup fork: before this, the only way to get
      // an institution_member account was the console or the seed script, so
      // no institution could onboard itself from the app at all.
      //
      // The dev server keeps its database across runs, so the address has to
      // be unique per run or the second run fails on "already registered".
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final email = 'visa.$stamp@embassy.example';

      addTearDown(restoreStudentSession);

      final auth = AuthProvider();
      final created = await auth.signUp(
        email: email,
        password: 'Lekkside123!',
        fullName: 'Consular Officer',
        role: 'institution_member',
      );
      expect(created, isTrue, reason: auth.error);

      await waitForUser(auth, (u) => u.isInstitutionMember);

      // handle_new_user() honoured the requested role, so the router will put
      // them in the org shell rather than the student one.
      expect(auth.user, isNotNull);
      expect(auth.user!.isInstitutionMember, isTrue);
      expect(auth.email, email);

      // Step two has not happened yet, which is exactly what sends them there.
      final institutions = InstitutionProvider();
      await institutions.load();
      expect(institutions.isResolved, isTrue);
      expect(institutions.needsSetup, isTrue);

      // Step two. The kind is the part that was previously unsettable: an
      // embassy has visa routes and no programs, so being stored as a
      // university would have been wrong in a way nothing later corrects.
      final listed = await institutions.createInstitution(
        name: 'Consulate of Testland $stamp',
        country: 'CA',
        kind: 'embassy',
        city: 'Lagos',
        emailDomain: 'embassy.example',
        description: 'Visa guidance for students heading to Testland.',
      );
      expect(listed, isTrue, reason: institutions.error);
      expect(institutions.needsSetup, isFalse);

      final managed = institutions.managed!;
      expect(managed.isOwner, isTrue);
      // Every new listing starts on the free tier, unverified.
      expect(managed.tier, 'basic');

      final row = await Supabase.instance.client
          .from('institutions')
          .select('kind, verification_status')
          .eq('id', managed.institution.id)
          .single();
      expect(row['kind'], 'embassy');
      // Self-assigning the role creates a listing; it does not grant a badge.
      expect(row['verification_status'], isNot('verified'));

      // A second listing would make InstitutionProvider.load() pick one of two
      // membership rows arbitrarily — it takes the first with no ORDER BY.
      final again = await institutions.createInstitution(
        name: 'Consulate Annexe $stamp',
        country: 'CA',
        kind: 'embassy',
      );
      expect(again, isFalse);
      expect(institutions.error, isNotNull);
    });

    test('an institution posts from its own shell, and it is attributed',
        () async {
      if (!available) return;

      addTearDown(restoreStudentSession);

      final auth = AuthProvider();
      final signedIn = await auth.signIn(
        email: 'admissions@maplecrest.ca',
        password: demoPassword,
      );
      expect(signedIn, isTrue, reason: auth.error);
      await waitForUser(auth, (u) => u.isInstitutionMember);

      final institutions = InstitutionProvider();
      await institutions.load();
      expect(institutions.error, isNull);

      // What OrgPostsScreen needs and did not used to have: posts are
      // addressed by handle everywhere, so the shell cannot list its own
      // without one.
      final handle = institutions.handle;
      expect(handle, isNotNull,
          reason: 'the org shell lists its posts by handle');

      final feed = FeedProvider();
      final before = await feed.postsByHandle(handle!);

      // Exactly what the composer sends when staff leave the "posting as"
      // switch on the organisation, which is its default for staff.
      final postId = await feed.createPost(
        body: 'Our September intake closes in three weeks.',
        kind: 'announcement',
        institutionId: institutions.institutionId,
        fields: const ['computer-science'],
        countries: const ['CA'],
      );
      expect(postId, isNotNull, reason: feed.error);

      final after = await feed.postsByHandle(handle);
      expect(after.length, before.length + 1,
          reason: 'the new post belongs on the org shell list');

      final mine = after.firstWhere((p) => p.id == postId);
      // Attributed to the institution, not to the staff member who typed it.
      expect(mine.authorHandle, handle);
      expect(mine.authorName, contains('Maplecrest'));
      expect(mine.authorKind, 'institution');
      expect(mine.kind, 'announcement');

      // And a student who follows nobody still receives it, off the passport.
      await restoreStudentSession();
      final studentFeed = FeedProvider();
      final passport = PassportProvider();
      await passport.load();
      studentFeed.buildTabs(passport.passport, (f) => f);
      await studentFeed.load(studentFeed.tabs.first, refresh: true);
      expect(
        studentFeed.postsFor(studentFeed.tabs.first).any((p) => p.id == postId),
        isTrue,
        reason: 'For you must carry it without a follow',
      );
    });

    test('an institution works its inbox and pipeline', () async {
      if (!available) return;

      addTearDown(restoreStudentSession);

      final auth = AuthProvider();
      expect(
        await auth.signIn(
            email: 'admissions@maplecrest.ca', password: demoPassword),
        isTrue,
        reason: auth.error,
      );
      await waitForUser(auth, (u) => u.isInstitutionMember);

      final desk = OrgDeskProvider();
      await desk.load();
      expect(desk.error, isNull);

      // ── Inbox ───────────────────────────────────────────────────────────
      expect(desk.threads, isNotEmpty,
          reason: 'the seeded student has written to Maplecrest');

      final thread = desk.threads.first;
      expect(thread.conversationId, isNotEmpty);
      expect(thread.token, isNotEmpty,
          reason: 'threads are keyed by match token, never an account id');
      // A name only once the student has shared; otherwise the token stands
      // in. This is what the console got wrong — it read profiles.full_name,
      // which RLS refuses before a share, and rendered nothing.
      expect(thread.displayName.trim(), isNotEmpty);
      if (!thread.isShared) {
        expect(thread.sharedName, isNull);
        expect(thread.displayName, startsWith('Student '));
      }

      // Replying back to the student from the inbox:
      final messages = MessagesProvider();
      await messages.loadMessages(thread.conversationId);
      final sent = await messages.send(
        conversationId: thread.conversationId,
        body: 'Hello from admissions!',
      );
      expect(sent, isTrue, reason: messages.error);
      messages.dispose();

      // ── Pipeline ────────────────────────────────────────────────────────
      expect(desk.applications, isNotEmpty);
      final entry = desk.applications.first;
      expect(entry.token, isNotEmpty);
      expect(entry.programName.trim(), isNotEmpty);
      expect(pipelineStages, contains(entry.stage));
      expect(entry.displayName.trim(), isNotEmpty);

      // Grouped the way the board renders it.
      final grouped = desk.byStage;
      expect(grouped.keys.every(pipelineStages.contains), isTrue);
      expect(grouped.values.expand((e) => e).length, desk.applications.length);

      // ── Moving one on, with the reason that becomes its history ─────────
      final target =
          entry.stage == 'conditional_offer' ? 'offer' : 'conditional_offer';
      expect(
        await desk.setStage(entry.applicationId, target,
            note: 'Strong transcript, pending English.'),
        isTrue,
        reason: desk.error,
      );

      final moved = desk.applications
          .firstWhere((a) => a.applicationId == entry.applicationId);
      expect(moved.stage, target);

      final history = await desk.history(entry.applicationId);
      expect(history, isNotEmpty);
      final latest = history.lastWhere((e) => e['to_stage'] == target);
      expect(latest['note'], 'Strong transcript, pending English.',
          reason: 'the reason has to reach the event the trigger writes — a '
              'history of bare timestamps is not a history');

      // ── Asking for a document ───────────────────────────────────────────
      final before = moved.outstandingRequests;
      expect(
        await desk.requestDocument(entry.applicationId, 'transcript',
            note: 'Final year, please.'),
        isTrue,
        reason: desk.error,
      );
      final after = desk.applications
          .firstWhere((a) => a.applicationId == entry.applicationId);
      expect(after.outstandingRequests, before + 1);
      expect(after.needsAttention, isTrue);

      // ── And an institution cannot reach another's desk ──────────────────
      await auth.signOut();
      final other = AuthProvider();
      await other.signIn(
          email: 'admissions@northgate.ac.uk', password: demoPassword);
      await waitForUser(other, (u) => u.isInstitutionMember);

      final otherDesk = OrgDeskProvider();
      await otherDesk.load();
      expect(
        otherDesk.applications
            .any((a) => a.applicationId == entry.applicationId),
        isFalse,
        reason: "another institution must not see Maplecrest's pipeline",
      );
    });

    test('the feed loads, personalised off the passport', () async {
      if (!available) return;

      final passport = PassportProvider();
      await passport.load();
      expect(passport.handle, isNotNull,
          reason: 'the seeded student should have a handle');

      final feed = FeedProvider();
      feed.buildTabs(passport.passport, passport.fieldLabel);

      // For you, Following, then one per field and destination on the passport.
      expect(feed.tabs.length, greaterThan(2));
      expect(feed.tabs[0].kind, FeedKind.forYou);
      expect(feed.tabs[1].kind, FeedKind.following);
      expect(feed.tabs.any((t) => t.topicKind == 'field'), isTrue);
      expect(feed.tabs.any((t) => t.topicKind == 'country'), isTrue);

      await feed.load(feed.tabs[0]);
      expect(feed.error, isNull);

      final forYou = feed.postsFor(feed.tabs[0]);
      expect(forYou, isNotEmpty,
          reason: 'For you must work off the passport, not the follow graph');

      final post = forYou.first;
      expect(post.authorHandle, isNotEmpty);
      expect(post.authorName, isNotEmpty);
      // The whole point of the identity split: no account id reaches a client.
      expect(post.authorKind, anyOf('institution', 'embassy', 'student'));

      // Counts are numbers, not strings — the Dart model casts them.
      expect(post.likeCount, isA<int>());
      expect(post.commentCount, isA<int>());

      // Following is a different set.
      await feed.load(feed.tabs[1]);
      expect(feed.error, isNull);
      expect(feed.postsFor(feed.tabs[1]), isNotEmpty,
          reason: 'the seed follows two institutions');

      // A topic tab resolves.
      final topicTab = feed.tabs.firstWhere((t) => t.topicKind == 'country');
      await feed.load(topicTab);
      expect(feed.error, isNull);
    });

    test('liking, saving and resharing a post', () async {
      if (!available) return;

      // Its own author, so the 20-posts-an-hour limit is never reached by
      // repeated runs: a reshare inserts a posts row and counts towards it.
      addTearDown(restoreStudentSession);
      await freshPoster();

      final passport = PassportProvider();
      await passport.load();

      final feed = FeedProvider();
      feed.buildTabs(passport.passport, passport.fieldLabel);
      await feed.load(feed.tabs[0]);

      final tab = feed.tabs[0];
      final original = feed.postsFor(tab).firstWhere((p) => !p.isRepost);

      // Optimistic, then confirmed by the server.
      final likedBefore = original.liked;
      await feed.toggleLike(original);
      final afterLike = feed.postsFor(tab).firstWhere((p) => p.id == original.id);
      expect(afterLike.liked, !likedBefore);

      await feed.load(tab, refresh: true);
      final persisted = feed.postsFor(tab).firstWhere((p) => p.id == original.id);
      expect(persisted.liked, !likedBefore,
          reason: 'the like should have survived a reload');

      await feed.toggleLike(persisted);

      await feed.toggleBookmark(original);
      final bookmarked =
          feed.postsFor(tab).firstWhere((p) => p.id == original.id);
      expect(bookmarked.bookmarked, isTrue);
      await feed.toggleBookmark(bookmarked);

      // A reshare, then undo — the plain repost toggles.
      final reshared = await feed.toggleRepost(original);
      expect(reshared, isTrue, reason: feed.error);
      await feed.load(tab, refresh: true);
      final afterRepost =
          feed.postsFor(tab).firstWhere((p) => p.id == original.id);
      expect(afterRepost.repostedByMe, isTrue);

      await feed.toggleRepost(afterRepost);
    });

    test('a new student can like, reply and reshare straight away', () async {
      if (!available) return;

      // A student used to have to claim a handle before replying or
      // resharing, and the app only asked at the moment they first tried — so
      // the first thing anyone attempted was the thing that stopped. Handles
      // are issued at signup now, which is what this guards.
      addTearDown(restoreStudentSession);

      final stamp = DateTime.now().microsecondsSinceEpoch;
      final auth = AuthProvider();
      expect(
        await auth.signUp(
          email: 'newcomer.$stamp@example.com',
          password: demoPassword,
          fullName: 'Ada Lovelace',
          role: 'student',
        ),
        isTrue,
        reason: auth.error,
      );
      final id = Supabase.instance.client.auth.currentUser!.id;
      await waitForUser(auth, (u) => u.id == id);

      final passport = PassportProvider();
      await passport.load();
      expect(passport.handle, isNotNull,
          reason: 'a handle is issued at signup, never asked for');
      expect(passport.handle, startsWith('ada_'));
      // The surname is not public. The consent gate exists so an institution
      // cannot put a name to a student; a handle is readable by everyone.
      expect(passport.handle, isNot(contains('lovelace')));

      // An institution post, found with no passport and no follows.
      final feed = FeedProvider();
      feed.buildTabs(null, (f) => f);
      await feed.load(feed.tabs.first, refresh: true);
      final posts = feed.postsFor(feed.tabs.first);
      expect(posts, isNotEmpty);
      final target = posts.firstWhere((p) => !p.isRepost);

      // ── Liking, and the count surviving a reload ────────────────────────
      final before = target.likeCount;
      await feed.toggleLike(target);
      expect(feed.error, isNull);

      await feed.load(feed.tabs.first, refresh: true);
      final reloaded =
          feed.postsFor(feed.tabs.first).firstWhere((p) => p.id == target.id);
      expect(reloaded.likeCount, before + 1,
          reason: 'a count that exists only on the client is the bug that '
              'looked like "likes are not displaying"');
      expect(reloaded.liked, isTrue);

      // ── Replying and resharing, with nothing claimed first ──────────────
      expect(await feed.reply(target.id, 'Is this open to Nigerians?'), isTrue,
          reason: feed.error);
      expect(await feed.toggleRepost(target), isTrue, reason: feed.error);

      // And the reply is attributed to the handle they were given.
      final comments = await feed.comments(target.id);
      expect(comments.any((c) => c.authorHandle == passport.handle), isTrue);
    });

    test('discovery reaches institutions and posts, not just programs',
        () async {
      if (!available) return;

      // Discover fetched institutions on every load and rendered none of
      // them, so a student could only reach a university by finding one of
      // its programmes first. These are the three things the tab now shows.
      final discover = DiscoverProvider();
      await discover.load();
      expect(discover.error, isNull);

      expect(discover.programs, isNotEmpty);
      expect(discover.institutions, isNotEmpty,
          reason: 'the Institutions tab renders exactly this list');

      // Enough to render a tile without a second round trip.
      final first = discover.institutions.first;
      expect(first.name.trim(), isNotEmpty);
      expect(first.location.trim(), isNotEmpty);
      expect(first.initials.trim(), isNotEmpty);
      expect(first.kind, isNotEmpty);

      // Searching narrows institutions, not only programmes.
      await discover.search('maplecrest');
      expect(discover.institutions.any((i) => i.name.contains('Maplecrest')),
          isTrue);
      expect(discover.institutions.length,
          lessThanOrEqualTo(discover.institutions.length));
      await discover.search('');

      // And the Posts tab.
      final feed = FeedProvider();
      final found = await feed.searchPosts('scholarship');
      expect(feed.error, isNull);
      expect(found, isNotEmpty,
          reason: 'a student searching "scholarship" should reach the '
              'announcements actually about scholarships');
      expect(found.first.authorHandle, isNotEmpty);

      // A blank search returns nothing rather than the whole table.
      expect(await feed.searchPosts('   '), isEmpty);
    });

    test('a post carries its replies', () async {
      if (!available) return;

      final passport = PassportProvider();
      await passport.load();
      final feed = FeedProvider();
      feed.buildTabs(passport.passport, passport.fieldLabel);
      await feed.load(feed.tabs[0]);

      // The seeded question has replies on it.
      final question = feed
          .postsFor(feed.tabs[0])
          .firstWhere((p) => p.kind == 'question', orElse: () => feed.postsFor(feed.tabs[0]).first);

      final fetched = await feed.postById(question.id);
      expect(fetched, isNotNull);
      expect(fetched!.id, question.id);

      if (question.commentCount > 0) {
        final comments = await feed.comments(question.id);
        expect(comments, isNotEmpty);
        expect(comments.first.authorHandle, isNotEmpty);
        expect(comments.first.body, isNotEmpty);
      }
    });

    test('a student posts, replies, and removes it', () async {
      if (!available) return;

      addTearDown(restoreStudentSession);
      await freshPoster();

      final feed = FeedProvider();

      final postId = await feed.createPost(
        body: 'Posted by the integration test.',
        kind: 'question',
        fields: const ['computer-science'],
        countries: const ['CA'],
      );
      expect(postId, isNotNull, reason: feed.error);

      final mine = await feed.postById(postId!);
      expect(mine, isNotNull);
      expect(mine!.isMine, isTrue);
      expect(mine.body, contains('integration test'));
      expect(mine.kind, 'question');

      final replied = await feed.reply(postId, 'A reply from the same test.');
      expect(replied, isTrue, reason: feed.error);

      final comments = await feed.comments(postId);
      expect(comments.any((c) => c.body.contains('same test')), isTrue);

      // Removing takes any reshare with it — asserted in SQL, exercised here.
      final removed = await feed.removePost(mine);
      expect(removed, isTrue, reason: feed.error);
      expect(await feed.postById(postId), isNull);
    });

    test('RLS still applies through the wire', () async {
      if (!available) return;

      // Another student's passport must come back empty, not forbidden-looking
      // — RLS filters rows rather than raising.
      final client = Supabase.instance.client;
      final others = await client
          .from('student_passports')
          .select('profile_id')
          .neq('profile_id', client.auth.currentUser!.id);

      expect(others, isEmpty);
    });
  });

  tearDownAll(() async {
    if (available) {
      await Supabase.instance.client.auth.signOut();
    }
  });
}
