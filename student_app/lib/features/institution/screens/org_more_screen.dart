import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/theme/theme_mode_sheet.dart';
import '../../../core/widgets/settings_section.dart';
import '../../../core/constants/app_chrome.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/profile_photo_sheet.dart';
import '../../../core/utils/push_once.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/verified_badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/institution_provider.dart';

/// Everything that does not earn a tab.
///
/// The recruitment screens live here until they are ported — matched students,
/// pipeline, inbox and meetings are real work but not what someone opens the
/// app to do, so they sit one tap deeper rather than crowding five tabs.
class OrgMoreScreen extends StatefulWidget {
  const OrgMoreScreen({super.key});

  @override
  State<OrgMoreScreen> createState() => _OrgMoreScreenState();
}

class _OrgMoreScreenState extends State<OrgMoreScreen> {
  bool _uploadingLogo = false;

  Future<void> _pickAndUploadLogo() async {
    final provider = context.read<InstitutionProvider>();
    final managed = provider.managed;
    if (managed == null) return;

    final hasExisting = managed.institution.logoUrl != null &&
        managed.institution.logoUrl!.isNotEmpty;

    final res = await showProfilePhotoPickerSheet(
      context: context,
      title: 'University logo / profile picture',
      hasExisting: hasExisting,
    );

    if (res == null || !mounted) return;

    setState(() => _uploadingLogo = true);
    try {
      if (res.isRemoved) {
        final ok = await provider.removeLogo();
        if (mounted && ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('University logo removed.')),
          );
        }
      } else if (res.bytes != null && res.fileName != null) {
        final ok = await provider.uploadLogo(
          bytes: res.bytes!,
          fileName: res.fileName!,
          mimeType: res.mimeType,
        );
        if (mounted && ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('University logo updated.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(SupabaseService.describeError(e)),
            backgroundColor: context.colors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Your institution page stays exactly as it is.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await context.read<AuthProvider>().signOut();
    if (context.mounted) context.go(AppConstants.routeLogin);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final provider = context.watch<InstitutionProvider>();
    final managed = provider.managed;
    final user = context.watch<AuthProvider>().user;
    final demand = provider.demand;

    String? count(int n) => n > 0 ? formatThousands(n) : null;

    // The same grouped list as the student's Settings screen, row for row in
    // style, so staff and students learn one app rather than two.
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: EdgeInsets.only(bottom: AppChrome.navClearance(context)),
        children: [
          if (managed != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  InstitutionAvatar(
                    logoUrl: managed.institution.logoUrl,
                    initials: managed.institution.initials,
                    size: 64,
                    onEdit: _pickAndUploadLogo,
                    isBusy: _uploadingLogo,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                managed.institution.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (managed.isVerified) ...[
                              const SizedBox(width: 4),
                              const VerifiedBadge(
                                subject: VerifiedSubject.institution,
                                compact: true,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${user?.fullName ?? 'You'} · '
                          '${managed.isOwner ? 'Owner' : 'Admissions officer'}',
                          style: text.bodyMedium
                              ?.copyWith(color: colors.textSecondary),
                        ),
                        Text(
                          '${managed.tierLabel} plan',
                          style: text.bodySmall
                              ?.copyWith(color: colors.textLight),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          SettingsSection(
            title: 'Recruitment',
            rows: [
              SettingsRow(
                icon: Icons.person_search_outlined,
                label: 'Matched students',
                value: count(demand.matchedStudents),
                onTap: () => context.push(AppConstants.routeOrgStudents),
              ),
              SettingsRow(
                icon: Icons.workspaces_outline,
                label: 'Applications',
                value: count(demand.openApplications),
                onTap: () => context.push(AppConstants.routeOrgPipeline),
              ),
              SettingsRow(
                icon: Icons.forum_outlined,
                label: 'Inbox',
                value: count(demand.unreadConversations),
                onTap: () => context.push(AppConstants.routeOrgInbox),
              ),
              SettingsRow(
                icon: Icons.event_available_outlined,
                label: 'Meeting requests',
                value: count(demand.pendingAppointments),
                onTap: () => context.push(AppConstants.routeOrgAppointments),
              ),
              SettingsRow(
                icon: Icons.people_outline_rounded,
                label: 'Student followers',
                value: count(demand.followers),
                onTap: () => context.push(AppConstants.routeOrgFollowers),
              ),
            ],
          ),

          SettingsSection(
            title: 'Our institution',
            rows: [
              if (!(managed?.isEmbassy ?? false))
                SettingsRow(
                  icon: Icons.school_outlined,
                  label: 'Programmes',
                  onTap: () => context.push(AppConstants.routeOrgPrograms),
                ),
              SettingsRow(
                icon: Icons.qr_code_2_rounded,
                label: 'Fairs and booths',
                onTap: () => context.push(AppConstants.routeOrgFairs),
              ),
              SettingsRow(
                icon: Icons.group_outlined,
                label: 'Team',
                onTap: () => context.push(AppConstants.routeOrgTeam),
              ),
              SettingsRow(
                icon: Icons.verified_outlined,
                label: 'Listing and verification',
                value: managed == null
                    ? null
                    : managed.isVerified
                        ? 'Verified'
                        : managed.institution.verificationStatus == 'pending'
                            ? 'In review'
                            : 'Not verified',
                onTap: () => context.push(AppConstants.routeOrgSettings),
              ),
            ],
          ),

          // The same safety, legal and account controls a student has, for
          // the same reasons: guideline 1.2 (block and report, published
          // contact), 5.1.1(i) (privacy policy reachable in the app) and
          // 5.1.1(v) (an account made in the app can be deleted in the app).
          SettingsSection(
            title: 'Appearance',
            rows: [
              SettingsRow(
                icon: Icons.dark_mode_outlined,
                label: 'Theme',
                value: switch (context.watch<ThemeProvider>().mode) {
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                  ThemeMode.system => 'System',
                },
                onTap: () => showThemeModeSheet(context),
              ),
            ],
          ),

          SettingsSection(
            title: 'Safety',
            rows: [
              SettingsRow(
                icon: Icons.block_outlined,
                label: 'Blocked accounts',
                onTap: () => context.pushOnce(AppConstants.routeBlocked),
              ),
              SettingsRow(
                icon: Icons.shield_outlined,
                label: 'Community Guidelines',
                onTap: () => context.pushOnce(AppConstants.routeGuidelines),
              ),
            ],
          ),

          SettingsSection(
            title: 'About',
            rows: [
              SettingsRow(
                icon: Icons.description_outlined,
                label: 'Terms of Service',
                onTap: () => context.pushOnce(AppConstants.routeTerms),
              ),
              SettingsRow(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy',
                onTap: () => context.pushOnce(AppConstants.routePrivacy),
              ),
              SettingsRow(
                icon: Icons.mail_outline_rounded,
                label: 'Contact support',
                onTap: () => launchUrl(
                    Uri.parse('mailto:${AppConstants.supportEmail}')),
              ),
            ],
          ),

          SettingsSection(
            title: 'Account',
            rows: [
              SettingsRow(
                icon: Icons.logout_rounded,
                label: 'Sign out',
                onTap: () => _signOut(context),
              ),
              SettingsRow(
                icon: Icons.delete_outline_rounded,
                label: 'Delete account',
                tint: colors.error,
                onTap: () => context.pushOnce(AppConstants.routeDeleteAccount),
              ),
            ],
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              '${AppConstants.appName} ${AppConstants.appVersion}',
              style: text.labelSmall?.copyWith(color: colors.textLight),
            ),
          ),
        ],
      ),
    );
  }
}
