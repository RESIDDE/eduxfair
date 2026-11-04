import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/verified_badge.dart';

/// Students matching a query, with a Follow button on each.
///
/// This used to live as a card pinned to the top of the feed, where it was the
/// one search box in the app that was not behind the Search tab. Moving it
/// here means there is a single answer to "where do I search?".
class StudentSearchResults extends StatefulWidget {
  /// The query, driven by the Discover screen's one search box.
  final String query;

  /// Padding for the bottom of the list, so the floating nav bar clears it.
  final EdgeInsets padding;

  const StudentSearchResults({
    super.key,
    required this.query,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<StudentSearchResults> createState() => _StudentSearchResultsState();
}

class _StudentSearchResultsState extends State<StudentSearchResults> {
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  final _busy = <String>{};
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.query.trim().isNotEmpty) _schedule();
  }

  @override
  void didUpdateWidget(StudentSearchResults old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _schedule();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    final query = widget.query.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
        _error = null;
      });
      return;
    }
    // Typing is faster than the round trip, and every keystroke would
    // otherwise be its own query.
    _debounce = Timer(const Duration(milliseconds: 280), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final res = await SupabaseService.instance.client.rpc(
        'search_students_with_follow',
        params: {'p_query': query, 'p_limit': 25},
      );
      if (!mounted) return;
      setState(() {
        _results = (res as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = SupabaseService.describeError(e);
        _searching = false;
      });
    }
  }

  Future<void> _toggleFollow(String handle, bool following) async {
    if (_busy.contains(handle)) return;
    setState(() => _busy.add(handle));
    final next = !following;

    try {
      await SupabaseService.instance.client.rpc(
        'follow_handle',
        params: {'p_handle': handle, 'p_follow': next},
      );
      if (!mounted) return;
      setState(() {
        _busy.remove(handle);
        for (final item in _results) {
          if (item['handle'] == handle) {
            item['is_following'] = next;
            final count = (item['follower_count'] as num?)?.toInt() ?? 0;
            item['follower_count'] = (count + (next ? 1 : -1)).clamp(0, 999999);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(handle));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(SupabaseService.describeError(e)),
          backgroundColor: context.colors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final query = widget.query.trim();

    if (query.isEmpty) {
      return const EmptyState(
        icon: Icons.alternate_email_rounded,
        title: 'Find a student',
        message: 'Search a name or an @handle to follow someone.',
      );
    }
    if (_searching && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Could not search',
        message: _error!,
      );
    }
    if (_results.isEmpty) {
      return EmptyState(
        icon: Icons.person_search_rounded,
        title: 'Nobody matched',
        message: 'No student matches “$query”.',
      );
    }

    return ListView.separated(
      padding: widget.padding,
      itemCount: _results.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: 64,
        color: colors.divider.withValues(alpha: 0.5),
      ),
      itemBuilder: (context, i) {
        final student = _results[i];
        final handle = student['handle']?.toString() ?? '';
        final name = student['display_name']?.toString() ?? 'Student';
        final bio = student['bio']?.toString();
        final following = student['is_following'] == true;
        final isSelf = student['is_self'] == true;
        final followers = (student['follower_count'] as num?)?.toInt() ?? 0;
        final busy = _busy.contains(handle);

        return ListTile(
          onTap: () =>
              context.push('${AppConstants.routeHandle}/$handle'),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: InstitutionAvatar(
            logoUrl: student['avatar_url']?.toString(),
            initials: name.isNotEmpty ? name[0].toUpperCase() : '?',
            size: 44,
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (student['is_verified'] == true) ...[
                const SizedBox(width: 4),
                const VerifiedBadge(
                  subject: VerifiedSubject.student,
                  compact: true,
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '@$handle · $followers '
                '${followers == 1 ? 'follower' : 'followers'}',
                style: text.bodySmall?.copyWith(color: colors.textLight),
              ),
              if (bio != null && bio.trim().isNotEmpty)
                Text(
                  bio,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
            ],
          ),
          trailing: isSelf
              ? Text('You',
                  style: text.bodySmall?.copyWith(color: colors.textLight))
              : busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : following
                      ? OutlinedButton(
                          onPressed: () => _toggleFollow(handle, true),
                          child: const Text('Following'),
                        )
                      : FilledButton(
                          onPressed: () => _toggleFollow(handle, false),
                          child: const Text('Follow'),
                        ),
        );
      },
    );
  }
}
