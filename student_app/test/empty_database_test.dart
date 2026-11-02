// Drives the real providers against an EMPTY database.
//
// Everything else in this suite runs against the seed: 70 students, 3
// institutions, 8 programs, 11 posts. A real Supabase project on day one has
// none of that, and that is the state the app has never once been exercised in.
//
// Two different things get checked here.
//
//   1. Nothing crashes or errors when there is nothing to show. A provider that
//      does `rows.first` or `(json['x'] as num)` on an absent column is fine
//      against the seed and dead against an empty table.
//   2. Empty really is empty. No placeholder institution, no sample program, no
//      demo post — if a screen has something on it, a person put it there.
//
// Then it builds the real thing end to end, from nothing: an institution signs
// itself up, fills in a listing, posts — and a student who signed up seconds
// earlier sees that post in their feed. That is the whole product in one test,
// with no seeded row involved anywhere.
//
// Needs the dev server started with NO demo data:
//
//   cd devserver   && npm run empty
//   cd student_app && flutter test test/empty_database_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lekkside_connect/features/applications/providers/applications_provider.dart';
import 'package:lekkside_connect/features/auth/providers/auth_provider.dart';
import 'package:lekkside_connect/features/discover/providers/discover_provider.dart';
import 'package:lekkside_connect/features/fairs/providers/fairs_provider.dart';
import 'package:lekkside_connect/features/institution/providers/institution_provider.dart';
import 'package:lekkside_connect/features/matches/providers/matches_provider.dart';
import 'package:lekkside_connect/features/meet/providers/meet_provider.dart';
import 'package:lekkside_connect/features/messages/providers/messages_provider.dart';
import 'package:lekkside_connect/features/notifications/providers/notifications_provider.dart';
import 'package:lekkside_connect/features/passport/models/passport.dart';
import 'package:lekkside_connect/features/passport/providers/passport_provider.dart';
import 'package:lekkside_connect/features/social/providers/feed_provider.dart';

const devServerUrl = 'http://localhost:54321';
const password = 'Lekkside123!';

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

/// Whether the dev server was started with the demo seed.
///
/// Checked by signing in as the seed's own student: the earlier version of this
/// read `institutions` as anon, which RLS correctly hides, so it reported
/// "empty" against every database and guarded nothing.
///
/// Only reported, not enforced — the assertions below are all scoped to the
/// accounts these tests create, so they hold either way.
Future<bool> databaseIsSeeded() async {
  try {
    final res = await Supabase.instance.client.auth
        .signInWithPassword(email: 'chidi.okeke@example.com', password: password);
    await Supabase.instance.client.auth.signOut();
    return res.session != null;
  } catch (_) {
    return false;
  }
}

void main() {
  late bool available;
  var seeded = false;
  var skipReason = 'dev server unavailable';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});

    available = await devServerIsRunning();
    if (!available) {
      skipReason = 'no dev server on $devServerUrl — run `npm run empty` in '
          'devserver/';
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
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      debug: false,
    );

    seeded = await databaseIsSeeded();
  });

  /// Waits until the provider has loaded the profile for [id].
  ///
  /// Every test shares one Supabase client, and each of these tests creates its
  /// own account. Waiting on a role — or merely on `user != null` — matches the
  /// *previous* test's profile whenever the roles agree, and the assertions
  /// that follow then describe the wrong account. The id is the only signal
  /// that is unambiguous.
  Future<void> waitForUserId(AuthProvider auth, String id) async {
    for (var i = 0; i < 40; i++) {
      if (auth.user?.id == id) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// A brand-new account of either role, created the way the app creates one.
  Future<AuthProvider> signUpFresh({
    required String role,
    required String name,
    required String email,
  }) async {
    final auth = AuthProvider();
    final ok = await auth.signUp(
      email: email,
      password: password,
      fullName: name,
      role: role,
    );
    expect(ok, isTrue, reason: auth.error);

    // The session switches before the profile row is read back, so wait for
    // the session first and then for its profile.
    for (var i = 0; i < 40 && auth.email != email; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(auth.email, email, reason: 'the session did not become this account');

    final id = Supabase.instance.client.auth.currentUser!.id;
    await waitForUserId(auth, id);
    expect(auth.user?.id, id);
    expect(auth.user?.role, role);
    return auth;
  }

  group('on an empty database', () {
    setUp(() {
      if (!available) markTestSkipped(skipReason);
    });

    test('a brand-new student sees empty surfaces, not errors', () async {
      if (!available) return;

      final stamp = DateTime.now().microsecondsSinceEpoch;
      await signUpFresh(
        role: 'student',
        name: 'First Student',
        email: 'first.$stamp@example.com',
      );

      // Every provider the student shell touches on a cold start. The point is
      // not that these are empty — of course they are — but that each query is
      // accepted and decodes, with `error` null rather than an exception.
      final passport = PassportProvider();
      await passport.load();
      expect(passport.error, isNull);
      expect(passport.passport, isNull,
          reason: 'a new student has no passport until they fill one in');

      // Discovery shows whatever institutions and programs real organisations
      // have added, so its contents are not this test's business. What is:
      // that the query is accepted, and that nothing arrives half-formed.
      final discover = DiscoverProvider();
      await discover.load();
      expect(discover.error, isNull);
      if (!seeded) {
        expect(discover.programs, isEmpty,
            reason: 'no program exists until an institution adds one');
      }
      for (final institution in discover.institutions) {
        expect(institution.name.trim(), isNotEmpty,
            reason: 'a listing with no name is a placeholder, not content');
      }

      final matches = MatchesProvider();
      await matches.load();
      expect(matches.error, isNull);
      expect(matches.matches, isEmpty);

      final applications = ApplicationsProvider();
      await applications.load();
      expect(applications.error, isNull);
      expect(applications.applications, isEmpty);

      final meet = MeetProvider();
      await meet.load();
      expect(meet.error, isNull);
      expect(meet.appointments, isEmpty);

      final messages = MessagesProvider();
      await messages.loadConversations();
      expect(messages.error, isNull);
      expect(messages.conversations, isEmpty);

      final notifications = NotificationsProvider();
      await notifications.load();
      expect(notifications.error, isNull);
      expect(notifications.notifications, isEmpty);
      expect(notifications.unreadCount, 0);

      final fairs = FairsProvider();
      await fairs.load();
      expect(fairs.error, isNull);

      // And the landing page itself: tabs still build, the feed is simply bare.
      final feed = FeedProvider();
      feed.buildTabs(null, (f) => f);
      expect(feed.tabs, isNotEmpty,
          reason: 'For you and Following exist before any passport does');
      await feed.load(feed.tabs.first);
      expect(feed.error, isNull);
      if (!seeded) {
        expect(feed.postsFor(feed.tabs.first), isEmpty,
            reason: 'a new student with no passport and no follows, on a '
                'database with no posts, has an empty feed');
      }

      // The assertion that matters whatever is in the database, and the one
      // that caught the handle bug: every post on a screen is attributable.
      for (final post in feed.postsFor(feed.tabs.first)) {
        expect(post.authorHandle, isNotEmpty,
            reason: 'a post with no handle renders a bare "@" and links '
                'nowhere');
        expect(post.authorName.trim(), isNotEmpty);
      }
    });

    test('an institution signs up and its page starts genuinely blank', () async {
      if (!available) return;

      final stamp = DateTime.now().microsecondsSinceEpoch;
      await signUpFresh(
        role: 'institution_member',
        name: 'First Registrar',
        email: 'registrar.$stamp@firstcollege.example',
      );

      final institutions = InstitutionProvider();
      await institutions.load();
      expect(institutions.error, isNull);
      expect(institutions.isResolved, isTrue);
      expect(institutions.needsSetup, isTrue,
          reason: 'step two of signup has not happened yet');

      final created = await institutions.createInstitution(
        name: 'First College $stamp',
        country: 'CA',
        kind: 'college',
        city: 'Toronto',
        emailDomain: 'firstcollege.example',
        description: 'Everything on this page was typed by us.',
      );
      expect(created, isTrue, reason: institutions.error);

      final managed = institutions.managed!;
      // Nothing is filled in on their behalf: the prospectus starts empty and
      // completeness reflects only what they actually entered.
      expect(managed.completeness, lessThan(50),
          reason: 'a new listing is mostly blank, and should say so');
      expect(managed.profile.tagline, isNull);
      expect(managed.profile.campusLife, isNull);
      expect(managed.profile.rankings, isEmpty);
      expect(managed.profile.accreditation, isEmpty);
      expect(managed.profile.applicationSteps, isEmpty);
      expect(managed.profile.costOfLivingMin, isNull);
      expect(managed.tier, 'basic');

      // No badge is granted for signing up.
      final row = await Supabase.instance.client
          .from('institutions')
          .select('verification_status')
          .eq('id', managed.institution.id)
          .single();
      expect(row['verification_status'], isNot('verified'));

      // And the dashboard's numbers are real zeros, not sample figures.
      expect(institutions.demand.matchedStudents, 0);
    });

    test('a student is issued a handle and can post with it', () async {
      if (!available) return;

      final stamp = DateTime.now().microsecondsSinceEpoch;
      final auth = await signUpFresh(
        role: 'student',
        name: 'Handle Seeker',
        email: 'seeker.$stamp@example.com',
      );

      final passport = PassportProvider();
      await passport.load();
      expect(passport.handle, isNotNull,
          reason: 'derive_student_handle() issues one at signup');
      expect(passport.handle, startsWith('handle_'),
          reason: 'built from the first name');
      expect(passport.handle, isNot(contains('seeker')),
          reason: 'the surname is not public');

      // Posting works immediately, with nothing claimed first.
      final feed = FeedProvider();
      final posted = await feed.createPost(body: 'My first post.');
      expect(posted, isNotNull, reason: feed.error);

      // And it is attributed, which is why a handle is required at all: a
      // post with a blank author reaches the feed as a bare "@".
      final mine = await feed.postsByHandle(passport.handle!);
      expect(mine, isNotEmpty);
      expect(mine.first.authorHandle, passport.handle);
      expect(mine.first.authorHandle, isNotEmpty);

      // Renaming still works — being handed a name is not being stuck with it.
      final renamed = await passport.claimHandle(
          'seeker${stamp % 100000000}', auth.user!.fullName);
      expect(renamed, isTrue, reason: passport.error);
      expect(passport.handle, isNot(startsWith('handle_')));
    });

    test('a university posts and a student sees it — nothing seeded', () async {
      if (!available) return;

      final stamp = DateTime.now().microsecondsSinceEpoch;
      final studentEmail = 'reader.$stamp@example.com';

      // ── A student, with a passport that says what they want ───────────────
      final student = await signUpFresh(
        role: 'student',
        name: 'Real Student',
        email: studentEmail,
      );
      final studentId = student.user!.id;

      final passport = PassportProvider();
      await passport.load();
      final saved = await passport.save(Passport(
        profileId: student.user!.id,
        nationality: 'NG',
        currentCountry: 'NG',
        highestQualification: 'secondary',
        targetFields: const ['computer_science'],
        targetCountries: const ['CA'],
        targetLevels: const ['undergraduate'],
      ));
      expect(saved, isTrue, reason: passport.error);

      // ── An institution, which fills in its own page and posts ─────────────
      await student.signOut();
      final org = await signUpFresh(
        role: 'institution_member',
        name: 'Admissions Lead',
        email: 'admissions.$stamp@realcollege.example',
      );

      final institutions = InstitutionProvider();
      await institutions.load();
      expect(
        await institutions.createInstitution(
          name: 'Real College $stamp',
          country: 'CA',
          kind: 'university',
          city: 'Vancouver',
          emailDomain: 'realcollege.example',
          description: 'We wrote this ourselves.',
        ),
        isTrue,
        reason: institutions.error,
      );

      final orgFeed = FeedProvider();
      final postedId = await orgFeed.createPost(
        body: 'Our scholarship for West African students closes in 14 days.',
        institutionId: institutions.institutionId,
        fields: const ['computer_science'],
        countries: const ['CA'],
      );
      expect(postedId, isNotNull, reason: orgFeed.error);

      // ── The student, following nobody, finds it under For you ─────────────
      await org.signOut();
      final back = AuthProvider();
      await back.signIn(email: studentEmail, password: password);
      await waitForUserId(back, studentId);
      expect(back.user?.id, studentId);

      final reader = PassportProvider();
      await reader.load();

      final feed = FeedProvider();
      feed.buildTabs(reader.passport, (f) => f);
      await feed.load(feed.tabs.first);
      expect(feed.error, isNull);

      final forYou = feed.postsFor(feed.tabs.first);
      expect(forYou, isNotEmpty,
          reason: 'For you must match on the passport, not on a follow graph');

      final post = forYou.first;
      expect(post.body, contains('scholarship'));
      expect(post.authorName, contains('Real College'));
      // The identity split: a handle reaches the client, never an account id.
      expect(post.authorHandle, isNotEmpty);
      expect(post.likeCount, 0);
      expect(post.commentCount, 0);

      // And the student can act on it, which is the other half of "live".
      await feed.toggleLike(post);
      expect(feed.error, isNull);
      await feed.load(feed.tabs.first, refresh: true);
      final afterLike = feed.postsFor(feed.tabs.first).first;
      expect(afterLike.likeCount, 1,
          reason: 'the like has to survive a reload, not just the optimistic '
              'patch');
    });
  });
}
