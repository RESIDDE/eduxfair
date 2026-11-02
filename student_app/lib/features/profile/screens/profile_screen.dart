import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/profile_photo_sheet.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../passport/providers/passport_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploadingAvatar = false;

  Future<void> _changeAvatar() async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    final res = await showProfilePhotoPickerSheet(
      context: context,
      title: 'Profile photo',
      hasExisting: user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty,
    );

    if (res == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      if (res.isRemoved) {
        final ok = await auth.removeAvatar();
        if (mounted && ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile picture removed.')),
          );
        }
      } else if (res.bytes != null && res.fileName != null) {
        final ok = await auth.uploadAvatar(
          bytes: res.bytes!,
          fileName: res.fileName!,
          mimeType: res.mimeType,
        );
        if (mounted && ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile picture updated.')),
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
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _editName(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final controller = TextEditingController(text: auth.user?.fullName ?? '');

    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your name'),
        content: CustomTextField(
          controller: controller,
          hint: 'As it appears on your documents',
          textCapitalization: TextCapitalization.words,
          validator: AppValidators.validateName,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == null || saved.trim().length < 2) return;
    await auth.updateProfile(fullName: saved);
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Your passport stays safe and will be here when '
            'you come back.'),
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
    final user = context.watch<AuthProvider>().user;
    final passport = context.watch<PassportProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Row(
            children: [
              UserAvatar(
                avatarUrl: user?.avatarUrl,
                initials: user?.initials ?? '?',
                size: 68,
                onEdit: _changeAvatar,
                isBusy: _uploadingAvatar,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.fullName ?? 'Your name', style: text.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      AppConstants.homeCountries[user?.country] ??
                          user?.country ??
                          'Country not set',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: _changeAvatar,
                      child: Text(
                        user?.avatarUrl == null ? 'Add photo' : 'Change photo',
                        style: text.labelSmall?.copyWith(
                          color: colors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _editName(context),
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Edit name',
              ),
            ],
          ),

          const SizedBox(height: 28),
          _Group(
            title: 'My passport',
            tiles: [
              _Tile(
                icon: Icons.badge_outlined,
                label: 'Education Passport',
                trailing: '${passport.completeness}%',
                // `push`, not `go`: this is a detail screen reached from
                // settings, and replacing the stack left it with no way back.
                onTap: () => context.push(AppConstants.routePassport),
              ),
              _Tile(
                icon: Icons.folder_outlined,
                label: 'Documents',
                trailing: '${passport.documents.length}',
                onTap: () => context.push(AppConstants.routeDocuments),
              ),
              _Tile(
                icon: Icons.visibility_outlined,
                label: 'Who can see me',
                trailing: '${passport.activeShares.length}',
                onTap: () => context.push(AppConstants.routeSharing),
              ),
            ],
          ),

          const SizedBox(height: 20),
          _Group(
            title: 'Activity',
            tiles: [
              _Tile(
                icon: Icons.send_outlined,
                label: 'My applications',
                onTap: () => context.push(AppConstants.routeApplications),
              ),
              _Tile(
                icon: Icons.event_available_outlined,
                label: 'My meetings',
                onTap: () => context.push(AppConstants.routeAppointments),
              ),
              _Tile(
                icon: Icons.qr_code_2_rounded,
                label: 'Fair Passport',
                onTap: () => context.push(AppConstants.routeFairPassport),
              ),
              _Tile(
                icon: Icons.people_outline_rounded,
                label: 'Followers & Following',
                onTap: () => context.push(AppConstants.routeStudentFollowers),
              ),
            ],
          ),

          const SizedBox(height: 20),
          _Group(
            title: 'About',
            tiles: [
              _Tile(
                icon: Icons.description_outlined,
                label: 'Terms of Service',
                onTap: () => launchUrl(
                  Uri.parse(AppConstants.termsUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              _Tile(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy',
                onTap: () => launchUrl(
                  Uri.parse(AppConstants.privacyUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              _Tile(
                icon: Icons.mail_outline_rounded,
                label: 'Contact support',
                onTap: () => launchUrl(
                  Uri.parse('mailto:${AppConstants.supportEmail}'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.error,
              side: BorderSide(color: colors.error),
            ),
          ),
          const SizedBox(height: 16),
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

class _Tile {
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
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
          child: Text(
            title,
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
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
                  onTap: tiles[i].onTap,
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
                          child:
                              Text(tiles[i].label, style: text.bodyLarge),
                        ),
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
