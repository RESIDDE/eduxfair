import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'features/applications/screens/application_detail_screen.dart';
import 'features/applications/screens/applications_screen.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/forgot_password_screen.dart';
import 'features/auth/screens/account_type_screen.dart';
import 'features/auth/screens/institution_register_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/onboarding_screen.dart';
import 'features/auth/screens/otp_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/institution/screens/institution_setup_screen.dart';
import 'features/institution/screens/institution_shell.dart';
import 'features/institution/screens/org_appointments_screen.dart';
import 'features/institution/screens/org_dashboard_screen.dart';
import 'features/institution/screens/org_fairs_screen.dart';
import 'features/institution/screens/org_followers_screen.dart';
import 'features/institution/screens/org_more_screen.dart';
import 'features/institution/screens/org_inbox_screen.dart';
import 'features/institution/screens/org_pipeline_screen.dart';
import 'features/institution/screens/org_posts_screen.dart';
import 'features/institution/screens/org_profile_screen.dart';
import 'features/institution/screens/org_programs_screen.dart';
import 'features/institution/screens/org_settings_screen.dart';
import 'features/institution/screens/org_spaces_screen.dart';
import 'features/institution/screens/org_students_screen.dart';
import 'features/institution/screens/org_team_screen.dart';
import 'features/meet/call/call_provider.dart';
import 'features/meet/call/call_screen.dart';
import 'features/meet/models/room_protocol.dart';
import 'features/institution/providers/institution_provider.dart';
import 'features/discover/screens/discover_screen.dart';
import 'features/discover/screens/institution_screen.dart';
import 'features/discover/screens/program_screen.dart';
import 'features/fairs/screens/fair_passport_screen.dart';
import 'features/fairs/screens/fair_report_screen.dart';
import 'features/notifications/screens/notifications_screen.dart' as notif;
import 'features/social/screens/composer_screen.dart';
import 'features/social/screens/feed_screen.dart';
import 'features/social/screens/handle_profile_screen.dart';
import 'features/social/screens/post_detail_screen.dart';
import 'features/social/screens/saved_screen.dart';
import 'features/social/screens/spaces_screen.dart';
import 'features/social/screens/student_followers_screen.dart';
import 'features/matches/screens/matches_screen.dart';
import 'features/meet/screens/appointment_request_screen.dart';
import 'features/meet/screens/appointments_screen.dart';
import 'features/messages/screens/chat_screen.dart';
import 'features/messages/screens/conversations_screen.dart';
import 'features/passport/screens/documents_screen.dart';
import 'features/passport/screens/passport_edit_screen.dart';
import 'features/passport/screens/passport_screen.dart';
import 'features/passport/screens/sharing_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'features/shell/main_shell.dart';

/// Keys for the root navigator and each tab branch, so a pushed route can
/// choose whether it covers the bottom bar or sits inside a tab.
final _rootKey = GlobalKey<NavigatorState>();



class EduxfairApp extends StatefulWidget {
  const EduxfairApp({super.key});

  @override
  State<EduxfairApp> createState() => _EduxfairAppState();
}

class _EduxfairAppState extends State<EduxfairApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter(
      context.read<AuthProvider>(),
      context.read<InstitutionProvider>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      // Black by default, which is the look this product is being measured
      // against. The light palette is still X's own and still correct, so
      // this is one word away from following the system again
      // (ThemeMode.system) if form-filling in daylight wins the argument.
      themeMode: ThemeMode.dark,
      routerConfig: _router,
    );
  }
}

/// Backwards compatibility alias
typedef LekksideConnectApp = EduxfairApp;

GoRouter _buildRouter(AuthProvider auth, InstitutionProvider institutions) =>
    GoRouter(
      navigatorKey: _rootKey,
      initialLocation: AppConstants.routeSplash,
      // Re-evaluates redirects when either changes: the session decides whether
      // anyone is signed in, and the institution decides whether staff go to
      // setup or to their dashboard.
      refreshListenable: Listenable.merge([auth, institutions]),
      redirect: (context, state) {
        final location = state.matchedLocation;

        const open = {
          AppConstants.routeSplash,
          AppConstants.routeOnboarding,
          AppConstants.routeLogin,
          AppConstants.routeSignup,
          AppConstants.routeRegister,
          AppConstants.routeRegisterInstitution,
          AppConstants.routeOtp,
          AppConstants.routeForgotPassword,
        };

        // Let the splash screen finish deciding; it handles the cold-start
        // branch itself, including whether onboarding has been seen.
        if (auth.status == AuthStatus.unknown) return null;

        final isOpen = open.contains(location);

        if (!auth.isSignedIn && !isOpen) return AppConstants.routeLogin;

        // One app, two shells. Which one a person gets is decided here by
        // their role — institutions and embassies are not sent anywhere else.
        //
        // Gated on `user` rather than on status, because the profile row that
        // carries the role loads a moment after the session does; acting
        // earlier would bounce a student on every cold start.
        final user = auth.user;

        // Custom OTP verification guard: unverified accounts are held at /otp.
        if (auth.isSignedIn && user != null && !user.isEmailVerified) {
          if (location == AppConstants.routeOtp) return null;
          final email = Uri.encodeComponent(auth.email ?? '');
          return '${AppConstants.routeOtp}?email=$email';
        }

        final isStaff = user?.isStaff ?? false;
        final inOrgShell = location.startsWith('/org');

        // Full-screen routes that live outside the org shell but are genuinely
        // shared. Without this, `if (!inOrgShell) return routeOrgHome` bounces
        // staff straight back to the dashboard the moment they tap "write a
        // post" — which is why an institution could not post even once the
        // composer and `create_post(p_institution_id)` both existed.
        //
        // Deliberately a list rather than a prefix test: the student shell
        // must stay closed to staff, and "anything not /org" was exactly the
        // rule that made that true.
        final staffMayLeaveShell = location == AppConstants.routeCompose ||
            location.startsWith('${AppConstants.routePost}/') ||
            location == AppConstants.routeProfile ||
            location.startsWith('${AppConstants.routeInstitution}/') ||
            location.startsWith('${AppConstants.routeHandle}/') ||
            location.startsWith(AppConstants.routeStudentFollowers) ||
            // A call room is the same screen for staff and students, and the
            // role inside it comes from the token rather than the route.
            location.startsWith('${AppConstants.routeCall}/');

        if (auth.isSignedIn && isStaff) {
          // Wait rather than guess about WHICH org screen: before the first
          // load has finished we do not know whether this account has an
          // institution, and guessing wrong sends a legitimate institution to
          // the setup screen.
          //
          // But returning null means "stay where you are", and where they are
          // may be a student route — a deep link, or the splash's old landing.
          // That painted the student shell until the institution resolved,
          // which is the flash this branch used to cause. We already know they
          // are staff, so move them into the org shell now and let the slower
          // question (dashboard or setup?) be answered a moment later.
          if (!institutions.isResolved) {
            return (inOrgShell || staffMayLeaveShell)
                ? null
                : AppConstants.routeOrgHome;
          }

          // Staff with no institution yet have nothing to show a dashboard
          // about, and every screen below needs an institution id.
          if (institutions.needsSetup) {
            return location == AppConstants.routeOrgSetup
                ? null
                : AppConstants.routeOrgSetup;
          }
          if (location == AppConstants.routeOrgSetup) {
            return AppConstants.routeOrgHome;
          }
          if (!inOrgShell && !staffMayLeaveShell) {
            return AppConstants.routeOrgHome;
          }
          return null;
        }

        // A student who somehow reached an institution route goes home.
        if (auth.isSignedIn && inOrgShell) return AppConstants.routeFeed;

        // Signed in but sitting on an auth screen: send them home. The splash
        // route is excluded so its own routing is not fought over.
        if (auth.isSignedIn && isOpen && location != AppConstants.routeSplash) {
          return AppConstants.routeFeed;
        }

        return null;
      },
      routes: [
        GoRoute(
          path: AppConstants.routeSplash,
          builder: (_, __) => const SplashScreen(),
        ),
        GoRoute(
          path: AppConstants.routeOnboarding,
          builder: (_, __) => const OnboardingScreen(),
        ),
        GoRoute(
          path: AppConstants.routeLogin,
          builder: (_, __) => const LoginScreen(),
        ),
        GoRoute(
          path: AppConstants.routeSignup,
          builder: (_, __) => const AccountTypeScreen(),
        ),
        GoRoute(
          path: AppConstants.routeRegister,
          builder: (_, __) => const RegisterScreen(),
        ),
        GoRoute(
          path: AppConstants.routeRegisterInstitution,
          builder: (_, __) => const InstitutionRegisterScreen(),
        ),
        GoRoute(
          path: AppConstants.routeOtp,
          builder: (_, state) => OtpScreen(
            email: state.uri.queryParameters['email'] ?? '',
            kind: state.uri.queryParameters['kind'],
          ),
        ),
        GoRoute(
          path: AppConstants.routeForgotPassword,
          builder: (_, __) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: AppConstants.routeOrgSetup,
          // `kind` is carried from step one of sign-up. Absent when staff
          // arrive here cold, in which case the screen defaults it.
          builder: (_, state) => InstitutionSetupScreen(
            kind: state.uri.queryParameters['kind'],
          ),
        ),

        GoRoute(
          path: AppConstants.routeOrgInbox,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const OrgInboxScreen(),
        ),
        GoRoute(
          path: AppConstants.routeOrgPipeline,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const OrgPipelineScreen(),
        ),

        GoRoute(
          path: AppConstants.routeOrgPrograms,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const OrgProgramsScreen(),
        ),
        GoRoute(
          path: AppConstants.routeOrgSettings,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const OrgSettingsScreen(),
        ),

        GoRoute(
          path: AppConstants.routeOrgStudents,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const OrgStudentsScreen(),
        ),
        GoRoute(
          path: AppConstants.routeOrgAppointments,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const OrgAppointmentsScreen(),
        ),
        GoRoute(
          path: AppConstants.routeOrgFairs,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const OrgFairsScreen(),
        ),
        GoRoute(
          path: AppConstants.routeOrgTeam,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const OrgTeamScreen(),
        ),
        GoRoute(
          path: AppConstants.routeOrgFollowers,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const OrgFollowersScreen(),
        ),

        // ── The institution shell ─────────────────────────────────────────
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => InstitutionShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppConstants.routeOrgHome,
                builder: (_, __) => const OrgDashboardScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppConstants.routeOrgProfile,
                builder: (_, __) => const OrgProfileScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppConstants.routeOrgPosts,
                builder: (_, __) => const OrgPostsScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppConstants.routeOrgSpaces,
                builder: (_, __) => const OrgSpacesScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppConstants.routeOrgMore,
                builder: (_, __) => const OrgMoreScreen(),
              ),
            ]),
          ],
        ),

        // ── Full-screen routes that cover the tab bar ──────────────────────
        GoRoute(
          path: AppConstants.routeProfile,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const ProfileScreen(),
        ),
        GoRoute(
          path: AppConstants.routeStudentFollowers,
          parentNavigatorKey: _rootKey,
          builder: (_, state) {
            final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0;
            return StudentFollowersScreen(initialTabIndex: tab);
          },
        ),
        GoRoute(
          path: '${AppConstants.routePost}/:id',
          parentNavigatorKey: _rootKey,
          builder: (_, state) =>
              PostDetailScreen(postId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: AppConstants.routeCompose,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const ComposerScreen(),
        ),
        GoRoute(
          path: '${AppConstants.routeHandle}/:handle',
          parentNavigatorKey: _rootKey,
          builder: (_, state) =>
              HandleProfileScreen(handle: state.pathParameters['handle']!),
        ),
        // A call room. Full-screen over the tab bar, and shared by students and
        // staff: the role inside the room comes from the token, not the route.
        //
        // CallProvider is created HERE rather than in main.dart's MultiProvider,
        // unlike every other provider in this app. It owns a LiveKit Room and a
        // native media session that must be disposed when the route leaves, and
        // a global one would hold the microphone open for the life of the app.
        GoRoute(
          path: '${AppConstants.routeCall}/:kind/:id',
          parentNavigatorKey: _rootKey,
          builder: (_, state) => ChangeNotifierProvider(
            create: (_) => CallProvider(
              kind: CallKind.parse(state.pathParameters['kind']!),
              id: state.pathParameters['id']!,
            ),
            child: const CallScreen(),
          ),
        ),
        GoRoute(
          path: AppConstants.routeSaved,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const SavedScreen(),
        ),
        // Reached from the drawer now rather than from a tab.
        GoRoute(
          path: AppConstants.routePassport,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const PassportScreen(),
        ),
        GoRoute(
          path: AppConstants.routeMatches,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const MatchesScreen(),
        ),
        GoRoute(
          path: AppConstants.routeHome,
          parentNavigatorKey: _rootKey,
          // The old Home tab is now the Feed; anything still pointing here —
          // a notification deep link, a saved route — follows it across.
          redirect: (_, __) => AppConstants.routeFeed,
        ),
        GoRoute(
          path: AppConstants.routePassportEdit,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const PassportEditScreen(),
        ),
        GoRoute(
          path: AppConstants.routeDocuments,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const DocumentsScreen(),
        ),
        GoRoute(
          path: AppConstants.routeSharing,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const SharingScreen(),
        ),
        GoRoute(
          path: '${AppConstants.routeInstitution}/:id',
          parentNavigatorKey: _rootKey,
          builder: (_, state) =>
              InstitutionScreen(institutionId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '${AppConstants.routeProgram}/:id',
          parentNavigatorKey: _rootKey,
          builder: (_, state) =>
              ProgramScreen(programId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: AppConstants.routeAppointments,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const AppointmentsScreen(),
        ),
        GoRoute(
          path: AppConstants.routeAppointmentRequest,
          parentNavigatorKey: _rootKey,
          builder: (_, state) => AppointmentRequestScreen(
            institutionId: state.uri.queryParameters['institution'] ?? '',
            programId: state.uri.queryParameters['program'],
          ),
        ),
        GoRoute(
          path: AppConstants.routeApplications,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const ApplicationsScreen(),
        ),
        GoRoute(
          path: '${AppConstants.routeApplicationDetail}/:id',
          parentNavigatorKey: _rootKey,
          builder: (_, state) =>
              ApplicationDetailScreen(applicationId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: AppConstants.routeFairPassport,
          parentNavigatorKey: _rootKey,
          builder: (_, __) => const FairPassportScreen(),
        ),
        GoRoute(
          path: '${AppConstants.routeFairReport}/:id',
          parentNavigatorKey: _rootKey,
          builder: (_, state) =>
              FairReportScreen(fairId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '${AppConstants.routeChat}/:id',
          parentNavigatorKey: _rootKey,
          builder: (_, state) =>
              ChatScreen(conversationId: state.pathParameters['id']!),
        ),

        // ── The tab shell ─────────────────────────────────────────────────
        // One branch per tab, so each keeps its own stack and scroll position.
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => MainShell(navigationShell: shell),
          branches: [
            // The feed is the landing page — the first thing a student sees.
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppConstants.routeFeed,
                builder: (_, __) => const FeedScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppConstants.routeDiscover,
                builder: (_, __) => const DiscoverScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppConstants.routeSpaces,
                builder: (_, __) => const SpacesScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppConstants.routeNotifications,
                builder: (_, __) => const notif.NotificationsScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: AppConstants.routeMessages,
                builder: (_, __) => const ConversationsScreen(),
              ),
            ]),
          ],
        ),
      ],
    );
