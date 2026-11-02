import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/profile_photo_sheet.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          if (managed != null) ...[
            Row(
              children: [
                InstitutionAvatar(
                  logoUrl: managed.institution.logoUrl,
                  initials: managed.institution.initials,
                  size: 56,
                  onEdit: _pickAndUploadLogo,
                  isBusy: _uploadingLogo,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(managed.institution.name, style: text.titleLarge),
                      Text(
                        '${managed.tierLabel} plan · '
                        '${managed.isOwner ? 'Owner' : 'Admissions officer'}',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            VerificationStatusChip(
              status: managed.institution.verificationStatus,
              subject: VerifiedSubject.institution,
            ),
            const SizedBox(height: 24),
          ],

          _Group(
            title: 'Recruitment',
            tiles: [
              _Tile(
                icon: Icons.auto_awesome_outlined,
                label: 'Matched students',
                trailing: '${demand.matchedStudents}',
                route: AppConstants.routeOrgStudents,
              ),
              _Tile(
                icon: Icons.workspaces_outline,
                label: 'Pipeline',
                trailing: '${demand.openApplications}',
                route: AppConstants.routeOrgPipeline,
              ),
              _Tile(
                icon: Icons.forum_outlined,
                label: 'Inbox',
                trailing: demand.unreadConversations > 0
                    ? '${demand.unreadConversations}'
                    : null,
                route: AppConstants.routeOrgInbox,
              ),
              _Tile(
                icon: Icons.event_available_outlined,
                label: 'Meeting requests',
                trailing: demand.pendingAppointments > 0
                    ? '${demand.pendingAppointments}'
                    : null,
                route: AppConstants.routeOrgAppointments,
              ),
              _Tile(
                icon: Icons.people_outline_rounded,
                label: 'Student followers',
                trailing: '${demand.followers}',
                route: AppConstants.routeOrgFollowers,
              ),
            ],
          ),

          const SizedBox(height: 18),
          _Group(
            title: 'Our institution',
            tiles: [
              if (!(managed?.isEmbassy ?? false))
                _Tile(
                  icon: Icons.school_outlined,
                  label: 'Programs',
                  route: AppConstants.routeOrgPrograms,
                ),
              _Tile(
                icon: Icons.qr_code_2_rounded,
                label: 'Fairs and booths',
                route: AppConstants.routeOrgFairs,
              ),
              _Tile(
                icon: Icons.group_outlined,
                label: 'Team',
                route: AppConstants.routeOrgTeam,
              ),
              _Tile(
                icon: Icons.settings_outlined,
                label: 'Settings and verification',
                route: AppConstants.routeOrgSettings,
              ),
            ],
          ),

          const SizedBox(height: 26),
          OutlinedButton.icon(
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.error,
              side: BorderSide(color: colors.error),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              '${user?.fullName ?? ''} · ${AppConstants.appName} '
              '${AppConstants.appVersion}',
              style: text.labelSmall?.copyWith(color: colors.textLight),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile {
  final IconData icon;
  final String label;
  final String? trailing;
  final String route;

  const _Tile({
    required this.icon,
    required this.label,
    this.trailing,
    required this.route,
  });
}

class _Group extends StatelessWidget {
  final String title;
  final List<_Tile> tiles;

  const _Group({required this.title, required this.tiles});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title,
              style: text.labelMedium?.copyWith(color: colors.textSecondary)),
        ),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                InkWell(
                  onTap: () => context.push(tiles[i].route),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(i == 0 ? 16 : 0),
                    bottom: Radius.circular(i == tiles.length - 1 ? 16 : 0),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(tiles[i].icon, size: 20, color: colors.accent),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Text(tiles[i].label, style: text.bodyLarge)),
                        if (tiles[i].trailing != null)
                          Text(
                            tiles[i].trailing!,
                            style: text.bodySmall
                                ?.copyWith(color: colors.textSecondary),
                          ),
                        const SizedBox(width: 6),
                        Icon(Icons.chevron_right_rounded,
                            size: 20, color: colors.textLight),
                      ],
                    ),
                  ),
                ),
                if (i < tiles.length - 1)
                  Divider(
                      height: 1,
                      color: colors.divider,
                      indent: 50,
                      endIndent: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
