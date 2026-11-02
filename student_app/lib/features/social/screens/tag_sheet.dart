import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/verified_badge.dart';

class TaggedAccount {
  final String handle;
  final String name;
  final String? avatarUrl;
  final bool isInstitution;
  final bool isVerified;

  const TaggedAccount({
    required this.handle,
    required this.name,
    this.avatarUrl,
    this.isInstitution = false,
    this.isVerified = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaggedAccount &&
          runtimeType == other.runtimeType &&
          handle.toLowerCase() == other.handle.toLowerCase();

  @override
  int get hashCode => handle.toLowerCase().hashCode;
}

/// A modal sheet that lets a student or institution search and select
/// institutions and fellow students to tag in their post.
class TagSheet extends StatefulWidget {
  final Set<TaggedAccount> initiallySelected;

  const TagSheet({super.key, this.initiallySelected = const {}});

  @override
  State<TagSheet> createState() => _TagSheetState();
}

class _TagSheetState extends State<TagSheet> {
  final _searchController = TextEditingController();
  final _selected = <TaggedAccount>{};
  Timer? _debounce;
  bool _loading = false;
  String _filter = 'all'; // 'all', 'institution', 'student'
  List<TaggedAccount> _results = [];

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initiallySelected);
    _performSearch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _loading = true);

    try {
      final clean = query.replaceAll('@', '').trim();
      var queryBuilder = SupabaseService.instance.client
          .from('public_profiles')
          .select('handle, display_name, avatar_url, kind, institution_id, is_verified');

      if (clean.isNotEmpty) {
        queryBuilder = queryBuilder.or(
          'handle.ilike.%$clean%,display_name.ilike.%$clean%',
        );
      }

      if (_filter == 'institution') {
        queryBuilder = queryBuilder.or('kind.eq.institution,institution_id.not.is.null');
      } else if (_filter == 'student') {
        queryBuilder = queryBuilder.eq('kind', 'student');
      }

      final rows = await queryBuilder.limit(30);

      final accounts = (rows as List).map((r) {
        final row = r as Map<String, dynamic>;
        final kind = row['kind'] as String? ?? 'student';
        final instId = row['institution_id'] as String?;
        final isInst = kind == 'institution' || kind == 'embassy' || (instId != null && instId.isNotEmpty);

        return TaggedAccount(
          handle: row['handle'] as String? ?? '',
          name: row['display_name'] as String? ?? row['handle'] as String? ?? '',
          avatarUrl: row['avatar_url'] as String?,
          isInstitution: isInst,
          isVerified: row['is_verified'] as bool? ?? false,
        );
      }).where((a) => a.handle.isNotEmpty).toList();

      if (mounted) {
        setState(() {
          _results = accounts;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(TaggedAccount account) {
    setState(() {
      if (_selected.contains(account)) {
        _selected.remove(account);
      } else {
        _selected.add(account);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.textLight.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tag in this post',
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'They will receive a notification and be tagged.',
                        style: text.bodySmall?.copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: Text('Done (${_selected.length})'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by university or student name...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _performSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: colors.surfaceVariant,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Filter chips: All, Universities, Students
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _filter == 'all',
                  onSelected: (_) {
                    setState(() => _filter = 'all');
                    _performSearch(_searchController.text);
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.apartment_rounded, size: 14),
                      SizedBox(width: 4),
                      Text('Universities'),
                    ],
                  ),
                  selected: _filter == 'institution',
                  onSelected: (_) {
                    setState(() => _filter = 'institution');
                    _performSearch(_searchController.text);
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_rounded, size: 14),
                      SizedBox(width: 4),
                      Text('Students'),
                    ],
                  ),
                  selected: _filter == 'student',
                  onSelected: (_) {
                    setState(() => _filter = 'student');
                    _performSearch(_searchController.text);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),
          Divider(color: colors.divider, height: 1),

          // Selected pill tray if any
          if (_selected.isNotEmpty) ...[
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: colors.surfaceVariant.withValues(alpha: 0.5),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _selected.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final account = _selected.elementAt(index);
                  return Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      account.isInstitution ? Icons.apartment_rounded : Icons.person_rounded,
                      size: 14,
                      color: colors.accent,
                    ),
                    label: Text('@${account.handle}'),
                    deleteIcon: const Icon(Icons.close_rounded, size: 14),
                    onDeleted: () => _toggle(account),
                  );
                },
              ),
            ),
            Divider(color: colors.divider, height: 1),
          ],

          // Results list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Text(
                          'No matching universities or students found.',
                          style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final account = _results[index];
                          final isSelected = _selected.contains(account);

                          return ListTile(
                            leading: InstitutionAvatar(
                              logoUrl: account.avatarUrl,
                              initials: account.name.isNotEmpty
                                  ? account.name[0].toUpperCase()
                                  : '?',
                              size: 40,
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    account.name,
                                    style: text.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (account.isVerified) ...[
                                  const SizedBox(width: 4),
                                  VerifiedBadge(
                                    subject: account.isInstitution
                                        ? VerifiedSubject.institution
                                        : VerifiedSubject.student,
                                    compact: true,
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Row(
                              children: [
                                Text(
                                  '@${account.handle}',
                                  style: text.bodySmall?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: account.isInstitution
                                        ? colors.accent.withValues(alpha: 0.12)
                                        : colors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    account.isInstitution ? 'University' : 'Student',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: account.isInstitution ? colors.accent : colors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            trailing: Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggle(account),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            onTap: () => _toggle(account),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
