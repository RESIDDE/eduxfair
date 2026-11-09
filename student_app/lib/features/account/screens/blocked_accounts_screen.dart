import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../social/providers/feed_provider.dart';

/// Who you have blocked or muted, and how to undo it.
///
/// Guideline 1.2 asks for "the ability to block abusive users". Blocking
/// already worked; this is the half that was missing — without it a block was
/// a one-way door, and a mis-tap was permanent.
class BlockedAccountsScreen extends StatefulWidget {
  const BlockedAccountsScreen({super.key});

  @override
  State<BlockedAccountsScreen> createState() => _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState extends State<BlockedAccountsScreen> {
  List<Map<String, dynamic>>? _rows;
  final _busy = <String>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res =
          await SupabaseService.instance.client.rpc('my_blocked_accounts');
      if (!mounted) return;
      setState(() {
        _rows = (res as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = SupabaseService.describeError(e));
    }
  }

  Future<void> _undo(String handle, String kind) async {
    if (_busy.contains(handle)) return;
    setState(() => _busy.add(handle));

    final feed = context.read<FeedProvider>();
    final ok = await feed.moderateHandle(
      handle,
      kind == 'block' ? 'unblock' : 'unmute',
    );

    if (!mounted) return;
    setState(() => _busy.remove(handle));
    if (ok) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kind == 'block' ? 'Unblocked @$handle.' : 'Unmuted @$handle.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(feed.error ?? 'Could not undo that.'),
          backgroundColor: context.colors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final rows = _rows;

    return Scaffold(
      appBar: AppBar(title: const Text('Blocked accounts')),
      body: _error != null
          ? EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Could not load',
              message: _error!,
            )
          : rows == null
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? const EmptyState(
                      icon: Icons.shield_outlined,
                      title: 'Nobody is blocked',
                      message: 'Accounts you block or mute show up here, and '
                          'you can undo either from this screen.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.only(top: 8, bottom: 32),
                        itemCount: rows.length + 1,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, indent: 72, color: colors.divider),
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 4, 20, 14),
                              child: Text(
                                'Blocking makes the two of you invisible to '
                                'one another. Muting only hides someone from '
                                'your feed. Neither is ever shown to them.',
                                style: text.bodySmall
                                    ?.copyWith(color: colors.textSecondary),
                              ),
                            );
                          }

                          final row = rows[i - 1];
                          final handle = row['handle']?.toString() ?? '';
                          final name =
                              row['display_name']?.toString() ?? handle;
                          final kind = row['kind']?.toString() ?? 'block';
                          final busy = _busy.contains(handle);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 4),
                            leading: InstitutionAvatar(
                              logoUrl: row['avatar_url']?.toString(),
                              initials:
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                              size: 42,
                            ),
                            title: Text(name, style: text.titleSmall),
                            subtitle: Text(
                              kind == 'block'
                                  ? '@$handle · Blocked'
                                  : '@$handle · Muted',
                              style: text.bodySmall
                                  ?.copyWith(color: colors.textLight),
                            ),
                            trailing: busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : OutlinedButton(
                                    onPressed: () => _undo(handle, kind),
                                    child: Text(
                                        kind == 'block' ? 'Unblock' : 'Unmute'),
                                  ),
                          );
                        },
                      ),
                    ),
    );
  }
}
