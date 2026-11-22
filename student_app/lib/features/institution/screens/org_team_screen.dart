import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/user_avatar.dart';
import '../widgets/org_ui.dart';
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
            .select(
              'id, member_role, created_at, profile_id, profiles(id, full_name)',
            )
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
        content: Text(
          'Are you sure you want to remove ${member.fullName} from this institution account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
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
      await _service.client
          .from('institution_members')
          .delete()
          .eq('id', member.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Team member removed.')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(SupabaseService.describeError(e)),
          backgroundColor: Colors.red,
        ),
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

    final used = _members.length;
    final seats = _seats < used ? used : _seats;
    final plan = _tier.isEmpty
        ? ''
        : '${_tier[0].toUpperCase()}${_tier.substring(1)}';

    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(), title: const Text('Team')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 40),
                children: [
                  // Seats, as a meter: one segment per seat, filled for
                  // each person using one — read at a glance.
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: colors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$used of $seats seats used',
                                style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (plan.isNotEmpty) OrgTag('$plan plan'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (seats > 12)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: seats == 0 ? 0 : used / seats,
                              minHeight: 6,
                              backgroundColor: colors.surfaceVariant,
                              color: colors.textPrimary,
                            ),
                          )
                        else
                          Row(
                            children: [
                              for (var i = 0; i < seats; i++) ...[
                                if (i > 0) const SizedBox(width: 4),
                                Expanded(
                                  child: Container(
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: i < used
                                          ? colors.textPrimary
                                          : colors.surfaceVariant,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                  const OrgNotice(
                    icon: Icons.info_outline_rounded,
                    margin: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    message:
                        'Colleagues join by signing up for an '
                        'institution account in the app. Your plan sets '
                        'how many seats you have — contact Eduxfair to add '
                        'more.',
                  ),
                  OrgSectionLabel('Members', count: _members.length),
                  OrgGroup(
                    children: [
                      for (final member in _members)
                        Builder(
                          builder: (context) {
                            final isMe = member.profileId == myUserId;
                            final initials = member.fullName
                                .split(RegExp(r'\s+'))
                                .where((w) => w.isNotEmpty)
                                .take(2)
                                .map((w) => w[0].toUpperCase())
                                .join();
                            return OrgRow(
                              leading: UserAvatar(
                                initials: initials.isEmpty ? '?' : initials,
                                size: 44,
                              ),
                              title: isMe
                                  ? '${member.fullName} (you)'
                                  : member.fullName,
                              subtitle:
                                  '${member.roleLabel} · added '
                                  '${formatDate(member.createdAt)}',
                              trailing: isOwner && !member.isOwner && !isMe
                                  ? IconButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _removeMember(member),
                                      icon: Icon(
                                        Icons.person_remove_outlined,
                                        size: 20,
                                        color: colors.error,
                                      ),
                                      tooltip: 'Remove from the team',
                                    )
                                  : (member.isOwner
                                        ? const OrgTag('Owner')
                                        : null),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
