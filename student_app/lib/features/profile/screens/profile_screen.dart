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
import '../../../core/theme/theme_mode_sheet.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/settings_section.dart';
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
        content: const Text(
          'Your passport stays safe and will be here when '
          'you come back.',
        ),
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
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        // Rows run edge to edge, as the reference's settings do, so only the
        // header and the footer are inset.
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
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
                      Text(
                        user?.fullName ?? 'Your name',
                        style: text.titleLarge,
                      ),
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
                          user?.avatarUrl == null
                              ? 'Add photo'
                              : 'Change photo',
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
          ),

          const SizedBox(height: 12),
          SettingsSection(
            title: 'My passport',
            rows: [
              SettingsRow(
                icon: Icons.badge_outlined,
                label: 'Education Passport',
                value: '${passport.completeness}%',
                // `push`, not `go`: this is a detail screen reached from
                // settings, and replacing the stack left it with no way back.
                onTap: () => context.push(AppConstants.routePassport),
              ),
              SettingsRow(
                icon: Icons.folder_outlined,
                label: 'Documents',
                value: '${passport.documents.length}',
                onTap: () => context.push(AppConstants.routeDocuments),
              ),
              SettingsRow(
                icon: Icons.visibility_outlined,
                label: 'Who can see me',
                value: '${passport.activeShares.length}',
                onTap: () => context.push(AppConstants.routeSharing),
              ),
            ],
          ),

          SettingsSection(
            title: 'Activity',
            rows: [
              SettingsRow(
                icon: Icons.send_outlined,
                label: 'My applications',
                onTap: () => context.push(AppConstants.routeApplications),
              ),
              SettingsRow(
                icon: Icons.event_available_outlined,
                label: 'My meetings',
                onTap: () => context.push(AppConstants.routeAppointments),
              ),
              SettingsRow(
                icon: Icons.qr_code_2_rounded,
                label: 'Fair Passport',
                onTap: () => context.push(AppConstants.routeFairPassport),
              ),
              SettingsRow(
                icon: Icons.people_outline_rounded,
                label: 'Followers & Following',
                onTap: () => context.push(AppConstants.routeStudentFollowers),
              ),
            ],
          ),

          SettingsSection(
            title: 'Appearance',
            rows: [
              SettingsRow(
                icon: Icons.dark_mode_outlined,
                label: 'Theme',
                value: context.watch<ThemeProvider>().label,
                onTap: () => showThemeModeSheet(context),
              ),
            ],
          ),

          SettingsSection(
            title: 'About',
            rows: [
              SettingsRow(
                icon: Icons.description_outlined,
                label: 'Terms of Service',
                onTap: () => launchUrl(
                  Uri.parse(AppConstants.termsUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              SettingsRow(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy',
                onTap: () => launchUrl(
                  Uri.parse(AppConstants.privacyUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              SettingsRow(
                icon: Icons.mail_outline_rounded,
                label: 'Contact support',
                onTap: () =>
                    launchUrl(Uri.parse('mailto:${AppConstants.supportEmail}')),
              ),
            ],
          ),

          const SizedBox(height: 8),
          SettingsSection(
            rows: [
              SettingsRow(
                icon: Icons.logout_rounded,
                label: 'Sign out',
                tint: colors.error,
                onTap: () => _signOut(context),
              ),
            ],
          ),

          const SizedBox(height: 20),
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
