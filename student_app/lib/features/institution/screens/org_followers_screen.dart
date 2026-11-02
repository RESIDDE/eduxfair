import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../messages/providers/messages_provider.dart';
import '../../messages/screens/chat_screen.dart';
import '../models/org_follower.dart';
import '../providers/institution_provider.dart';

/// The list of prospective students following this institution.
///
/// Students who follow receive the institution's updates and announcements
/// in their social Following feed tab.
class OrgFollowersScreen extends StatefulWidget {
  const OrgFollowersScreen({super.key});

  @override
  State<OrgFollowersScreen> createState() => _OrgFollowersScreenState();
}

class _OrgFollowersScreenState extends State<OrgFollowersScreen> {
  final _service = SupabaseService.instance;
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<OrgFollower> _followers = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final institutionId = context.read<InstitutionProvider>().institutionId;
    if (institutionId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _service.client.rpc(
        'my_institution_followers',
        params: {'p_institution_id': institutionId},
      );

      if (!mounted) return;
      setState(() {
        _followers = (res as List)
            .map((r) => OrgFollower.fromMap((r as Map).cast<String, dynamic>()))
            .toList();
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

  List<OrgFollower> get _filteredFollowers {
    if (_search.trim().isEmpty) return _followers;
    final q = _search.toLowerCase().trim();
    return _followers.where((f) {
      return f.fullName.toLowerCase().contains(q) ||
          (f.country != null && f.country!.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _messageStudent(OrgFollower follower) async {
    final institution = context.read<InstitutionProvider>().institution;
    if (institution == null) return;

    final messages = context.read<MessagesProvider>();
    final conversationId = await messages.openConversation(
      institutionId: institution.id,
      studentId: follower.studentId,
      subject: 'Message from ${institution.name}',
    );

    if (!mounted) return;
    if (conversationId != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conversationId,
          title: follower.fullName.isNotEmpty ? follower.fullName : 'Student',
        ),
      ));
    } else if (messages.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(messages.error!),
          backgroundColor: context.colors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final followers = _filteredFollowers;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Student followers'),
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
              : _followers.isEmpty
                  ? const EmptyState(
                      icon: Icons.people_outline_rounded,
                      title: 'No followers yet',
                      message: 'When prospective students tap Follow on your institution profile, they will appear here and automatically receive your updates in their Following feed.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          // Header Banner
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
                                    color: colors.primary.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.people_alt_rounded,
                                      size: 24, color: colors.primary),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        formatThousands(_followers.length),
                                        style: text.headlineSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Students currently following your updates',
                                        style: text.bodySmall
                                            ?.copyWith(color: colors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Search Box
                          if (_followers.length > 5) ...[
                            TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Search followers by name or country...',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _search.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _search = '');
                                        },
                                      )
                                    : null,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: colors.border),
                                ),
                              ),
                              onChanged: (val) => setState(() => _search = val),
                            ),
                            const SizedBox(height: 14),
                          ],

                          Text(
                            'All followers (${followers.length})',
                            style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),

                          ...followers.map((follower) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
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
                                    backgroundImage: follower.avatarUrl != null
                                        ? NetworkImage(follower.avatarUrl!)
                                        : null,
                                    child: follower.avatarUrl == null
                                        ? Text(
                                            follower.initials,
                                            style: text.titleSmall?.copyWith(
                                                fontWeight: FontWeight.bold),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          follower.fullName,
                                          style: text.titleSmall?.copyWith(
                                              fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            if (follower.country != null) ...[
                                              Icon(Icons.public_rounded,
                                                  size: 13, color: colors.textLight),
                                              const SizedBox(width: 4),
                                              Text(
                                                AppConstants.homeCountries[follower.country] ??
                                                    follower.country!,
                                                style: text.labelSmall?.copyWith(
                                                    color: colors.textSecondary),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            Text(
                                              'Followed ${formatRelative(follower.followedAt)}',
                                              style: text.labelSmall
                                                  ?.copyWith(color: colors.textLight),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _messageStudent(follower),
                                    icon: Icon(Icons.forum_outlined,
                                        size: 20, color: colors.accent),
                                    tooltip: 'Message student',
                                  ),
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
