import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../models/passport_share.dart';
import '../providers/passport_provider.dart';

/// "Who can see my passport" — the student's complete, revocable record of
/// every institution with access.
///
/// This screen is correct by construction: every path that grants access
/// (applying, requesting a meeting, connecting at a booth) writes a
/// `passport_shares` row rather than being a hidden exception in the access
/// rules, so there is nowhere else access can come from.
class SharingScreen extends StatefulWidget {
  const SharingScreen({super.key});

  @override
  State<SharingScreen> createState() => _SharingScreenState();
}

class _SharingScreenState extends State<SharingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PassportProvider>().load();
    });
  }

  Future<void> _confirmRevoke(PassportShare share) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Revoke ${share.institutionName}?'),
        content: const Text(
          'They will no longer see your name, contact details or documents.\n\n'
          'If you have an open application or meeting with them, revoking may '
          'stop them progressing it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep sharing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final provider = context.read<PassportProvider>();
    final ok = await provider.revokeShare(share);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? '${share.institutionName} can no longer see your passport.'
            : provider.error ?? 'Could not revoke access.'),
        backgroundColor: ok ? null : context.colors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final provider = context.watch<PassportProvider>();

    final active = provider.activeShares;
    final revoked = provider.allShares.where((s) => !s.isActive).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Who can see me')),
      body: provider.loading && provider.allShares.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: provider.load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.infoLight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined,
                            size: 20, color: colors.accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('You are in control',
                                  style: text.titleSmall?.copyWith(
                                      color: colors.accent,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(
                                'Institutions can only see your name, contact '
                                'details and documents while they appear '
                                'below. Everyone else sees an anonymous '
                                'profile — your country, level, field and '
                                'grade band.',
                                style: text.bodySmall?.copyWith(height: 1.45),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (active.isEmpty && revoked.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: EmptyState(
                        icon: Icons.visibility_off_outlined,
                        title: 'Nobody can see your details',
                        message: 'When you apply, request a meeting, or '
                            'connect at a fair booth, that institution gets '
                            'access — and it will appear here for you to '
                            'revoke at any time.',
                      ),
                    )
                  else ...[
                    if (active.isNotEmpty) ...[
                      Text(
                        'Can see your passport (${active.length})',
                        style: text.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      ...active.map(
                        (share) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ShareTile(
                            share: share,
                            onRevoke: () => _confirmRevoke(share),
                          ),
                        ),
                      ),
                    ],
                    if (revoked.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('Previously shared', style: text.titleLarge),
                      const SizedBox(height: 6),
                      Text(
                        // Explains why revoked entries persist: the record is
                        // the student's own evidence of who once had access.
                        'Kept as a record. These institutions no longer have '
                        'access.',
                        style: text.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      ...revoked.map(
                        (share) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ShareTile(share: share),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}

class _ShareTile extends StatelessWidget {
  final PassportShare share;
  final VoidCallback? onRevoke;

  const _ShareTile({required this.share, this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final isActive = share.isActive;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActive ? colors.surface : colors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: isActive ? 1 : 0.5,
            child: InstitutionAvatar(
              logoUrl: share.institutionLogoUrl,
              initials: share.institutionName.isEmpty
                  ? '?'
                  : share.institutionName[0].toUpperCase(),
              size: 42,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  share.institutionName,
                  style: text.titleMedium?.copyWith(
                    color: isActive ? colors.textPrimary : colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (share.reason != null)
                  Text(
                    share.reason!,
                    style: text.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  isActive
                      ? 'Shared ${_relative(share.grantedAt)}'
                      : 'Revoked ${_relative(share.revokedAt!)}',
                  style: text.labelSmall?.copyWith(color: colors.textLight),
                ),
              ],
            ),
          ),
          if (onRevoke != null)
            TextButton(
              onPressed: onRevoke,
              style: TextButton.styleFrom(foregroundColor: colors.error),
              child: const Text('Revoke'),
            ),
        ],
      ),
    );
  }

  static String _relative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 30) return '${diff.inDays} days ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} months ago';
    return '${(diff.inDays / 365).floor()} years ago';
  }
}
