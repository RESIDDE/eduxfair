import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../applications/providers/applications_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../matches/providers/matches_provider.dart';
import '../../passport/providers/passport_provider.dart';
import '../screens/handle_sheet.dart';

import '../../../core/supabase/supabase_service.dart';

/// Everything personal, behind the avatar — the way X reaches a profile.
///
/// Moving the Passport off the tab bar freed a slot for Notifications, but the
/// Passport is the asset the whole product rests on, so it leads here with its
/// completeness ring rather than sitting in a list of links.
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  int _followers = 0;
  int _following = 0;

  @override
  void initState() {
    super.initState();
    _loadSocialStats();
  }

  Future<void> _loadSocialStats() async {
    try {
      final counts = await SupabaseService.instance.client.rpc('my_social_counts');
      if (counts != null && counts is Map && mounted) {
        setState(() {
          _followers = (counts['followers'] as num?)?.toInt() ?? 0;
          _following = (counts['following'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    final user = context.watch<AuthProvider>().user;
    final passport = context.watch<PassportProvider>();
    final matches = context.watch<MatchesProvider>();
    final applications = context.watch<ApplicationsProvider>();

    void go(String route) {
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.push(route);
    }

    return Drawer(
      backgroundColor: colors.background,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── Who you are ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(AppConstants.routeProfile);
                    },
                    child: UserAvatar(
                      avatarUrl: user?.avatarUrl,
                      initials: user?.initials ?? '?',
                      size: 52,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(user?.fullName ?? 'Your name', style: text.titleLarge),
                  // Tappable either way: issued handles can be changed, and
                  // an account old enough to have none still needs to claim
                  // one. A blank line used to sit here saying nothing.
                  if (passport.handle != null)
                    InkWell(
                      onTap: () => openClaimHandleSheet(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('@${passport.handle}',
                            style: text.bodySmall),
                      ),
                    )
                  else
                    InkWell(
                      onTap: () => openClaimHandleSheet(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          'Choose a handle',
                          style: text.bodySmall?.copyWith(
                            color: context.colors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                  // Without this a student never learns they can have a bio:
                  // it renders on their profile and on every follower list,
                  // and nothing else in the app mentions it.
                  if (passport.handle != null)
                    InkWell(
                      onTap: () => openClaimHandleSheet(context),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          passport.bio?.trim().isNotEmpty == true
                              ? passport.bio!.trim()
                              : 'Add a bio',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            height: 1.35,
                            color: passport.bio?.trim().isNotEmpty == true
                                ? null
                                : context.colors.accent,
                            fontWeight: passport.bio?.trim().isNotEmpty == true
                                ? null
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      InkWell(
                        onTap: () => go('${AppConstants.routeStudentFollowers}?tab=1'),
                        child: _Count(
                          value: _following,
                          label: 'following',
                        ),
                      ),
                      const SizedBox(width: 18),
                      InkWell(
                        onTap: () => go('${AppConstants.routeStudentFollowers}?tab=0'),
                        child: _Count(
                          value: _followers,
                          label: 'followers',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: colors.divider),

            // ── The Passport, given its own weight ────────────────────────
            InkWell(
              onTap: () => go(AppConstants.routePassport),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Row(
                  children: [
                    CircularPercentIndicator(
                      radius: 24,
                      lineWidth: 4,
                      percent: passport.completenessFraction,
                      circularStrokeCap: CircularStrokeCap.round,
                      backgroundColor: colors.surfaceVariant,
                      progressColor: passport.isMatchable
                          ? colors.success
                          : colors.warning,
                      center: Text(
                        '${passport.completeness}',
                        style: text.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Education Passport', style: text.titleMedium),
                          Text(
                            passport.isMatchable
                                ? 'Institutions can find you'
                                : 'Not discoverable yet',
                            style: text.bodySmall?.copyWith(
                              color: passport.isMatchable
                                  ? colors.success
                                  : colors.warning,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: colors.textLight),
                  ],
                ),
              ),
            ),

            Divider(height: 1, color: colors.divider),
            const SizedBox(height: 8),

            _Item(
              icon: Icons.auto_awesome_outlined,
              label: 'My matches',
              trailing: matches.matchCount > 0 ? '${matches.matchCount}' : null,
              onTap: () => go(AppConstants.routeMatches),
            ),
            _Item(
              icon: Icons.send_outlined,
              label: 'My applications',
              trailing: applications.applications.isEmpty
                  ? null
                  : '${applications.applications.length}',
              onTap: () => go(AppConstants.routeApplications),
            ),
            _Item(
              icon: Icons.event_available_outlined,
              label: 'My meetings',
              onTap: () => go(AppConstants.routeAppointments),
            ),
            _Item(
              icon: Icons.bookmark_border_rounded,
              label: 'Saved',
              onTap: () => go(AppConstants.routeSaved),
            ),
            _Item(
              icon: Icons.people_outline_rounded,
              label: 'Followers & Following',
              trailing: _followers > 0 ? '$_followers' : null,
              onTap: () => go(AppConstants.routeStudentFollowers),
            ),
            _Item(
              icon: Icons.qr_code_2_rounded,
              label: 'Fair Passport',
              onTap: () => go(AppConstants.routeFairPassport),
            ),

            const SizedBox(height: 8),
            Divider(height: 1, color: colors.divider),
            const SizedBox(height: 8),

            _Item(
              icon: Icons.folder_outlined,
              label: 'Documents',
              trailing: passport.documents.isEmpty
                  ? null
                  : '${passport.documents.length}',
              onTap: () => go(AppConstants.routeDocuments),
            ),
            _Item(
              icon: Icons.visibility_outlined,
              label: 'Who can see me',
              trailing: passport.activeShares.isEmpty
                  ? null
                  : '${passport.activeShares.length}',
              onTap: () => go(AppConstants.routeSharing),
            ),
            _Item(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () => go(AppConstants.routeProfile),
            ),

            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '${AppConstants.appName} ${AppConstants.appVersion}',
                style: text.labelSmall?.copyWith(color: colors.textLight),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  final int value;
  final String label;

  const _Count({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(formatThousands(value),
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        Text(label, style: text.bodySmall),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;

  const _Item({
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 22, color: colors.textPrimary),
            const SizedBox(width: 18),
            Expanded(
              child: Text(label,
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (trailing != null)
              Text(trailing!,
                  style: text.bodySmall?.copyWith(color: colors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
