import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../models/org_team_member.dart';
import '../providers/institution_provider.dart';

/// Admissions team members and seat management.
///
/// Owners can view colleagues and manage seats based on subscription limits.
class OrgTeamScreen extends StatefulWidget {
  const OrgTeamScreen({super.key});

  @override
  State<OrgTeamScreen> createState() => _OrgTeamScreenState();
}

class _OrgTeamScreenState extends State<OrgTeamScreen> {
  final _service = SupabaseService.instance;

  bool _loading = true;
  String? _error;
  List<OrgTeamMember> _members = [];
  int _seats = 1;
  String _tier = 'basic';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final institutionId = context.read<InstitutionProvider>().institutionId;
    if (institutionId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _service.client
            .from('institution_members')
            .select('id, member_role, created_at, profile_id, profiles(id, full_name)')
            .eq('institution_id', institutionId)
            .order('created_at'),
        _service.client
            .from('institution_subscriptions')
            .select('tier, seats')
            .eq('institution_id', institutionId)
            .maybeSingle(),
      ]);

      if (!mounted) return;
      final members = (results[0] as List)
          .map((r) => OrgTeamMember.fromMap((r as Map).cast<String, dynamic>()))
          .toList();

      final sub = results[1] as Map<String, dynamic>?;

      setState(() {
        _members = members;
        _seats = (sub?['seats'] as num?)?.toInt() ?? 1;
        _tier = sub?['tier'] as String? ?? 'basic';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = SupabaseService.describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _removeMember(OrgTeamMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove seat?'),
        content: Text('Are you sure you want to remove ${member.fullName} from this institution account?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: ctx.colors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await _service.client.from('institution_members').delete().eq('id', member.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Team member removed.')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SupabaseService.describeError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final provider = context.watch<InstitutionProvider>();
    final isOwner = provider.managed?.isOwner ?? false;
    final myUserId = _service.userId;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Team & seats'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      // Subscription / Seats Banner
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colors.accent.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.group_outlined, size: 24, color: colors.accent),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_members.length} of $_seats seats used',
                                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_tier[0].toUpperCase()}${_tier.substring(1)} plan',
                                    style: text.bodySmall?.copyWith(color: colors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: colors.surfaceVariant,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _tier.toUpperCase(),
                                style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Explanatory note
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colors.surfaceVariant.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, size: 18, color: colors.textSecondary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Colleagues join by signing up for an institution account in the app. Seat limits are determined by your plan — reach out to Eduxfair to upgrade.',
                                style: text.bodySmall?.copyWith(height: 1.45, color: colors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      Text('Team members (${_members.length})', style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),

                      ..._members.map((member) {
                        final isMe = member.profileId == myUserId;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: colors.border),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: colors.surfaceVariant,
                                child: Text(
                                  member.fullName.isNotEmpty ? member.fullName[0].toUpperCase() : '?',
                                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                ),
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
                                            member.fullName,
                                            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isMe) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: colors.accent.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'you',
                                              style: text.labelSmall?.copyWith(
                                                color: colors.accent,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Added ${formatDate(member.createdAt)}',
                                      style: text.labelSmall?.copyWith(color: colors.textLight),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: member.isOwner ? colors.successLight : colors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  member.roleLabel,
                                  style: text.labelSmall?.copyWith(
                                    color: member.isOwner ? colors.success : colors.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (isOwner && !member.isOwner && !isMe) ...[
                                const SizedBox(width: 6),
                                IconButton(
                                  onPressed: _busy ? null : () => _removeMember(member),
                                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: colors.error),
                                  tooltip: 'Remove seat',
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}
