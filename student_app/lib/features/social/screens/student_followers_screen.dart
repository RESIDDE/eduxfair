import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/verified_badge.dart';

/// Screen displaying the student's followers and who they are following.
class StudentFollowersScreen extends StatefulWidget {
  final int initialTabIndex;

  const StudentFollowersScreen({super.key, this.initialTabIndex = 0});

  @override
  State<StudentFollowersScreen> createState() => _StudentFollowersScreenState();
}

class _StudentFollowersScreenState extends State<StudentFollowersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _followers = const [];
  List<Map<String, dynamic>> _following = const [];

  bool _loadingFollowers = true;
  bool _loadingFollowing = true;
  String? _errorFollowers;
  String? _errorFollowing;

  int _followerCount = 0;
  int _followingCount = 0;

  String _followerQuery = '';
  String _followingQuery = '';

  final Set<String> _busyHandles = {};
  final Set<String> _busyInstitutions = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _loadCounts();
    _loadFollowers();
    _loadFollowing();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    try {
      final counts = await SupabaseService.instance.client.rpc('my_social_counts');
      if (counts != null && counts is Map && mounted) {
        setState(() {
          _followerCount = (counts['followers'] as num?)?.toInt() ?? 0;
          _followingCount = (counts['following'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadFollowers() async {
    setState(() {
      _loadingFollowers = true;
      _errorFollowers = null;
    });

    try {
      final rows = await SupabaseService.instance.client
          .rpc('my_student_followers', params: {'p_limit': 100});
      if (!mounted) return;
      final list = (rows as List?) ?? const [];
      setState(() {
        _followers = list
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        _followerCount = _followers.length;
        _loadingFollowers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorFollowers = SupabaseService.describeError(e);
        _loadingFollowers = false;
      });
    }
  }

  Future<void> _loadFollowing() async {
    setState(() {
      _loadingFollowing = true;
      _errorFollowing = null;
    });

    try {
      final rows = await SupabaseService.instance.client
          .rpc('my_student_following', params: {'p_limit': 150});
      if (!mounted) return;
      final list = (rows as List?) ?? const [];
      setState(() {
        _following = list
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        _followingCount = _following.length;
        _loadingFollowing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorFollowing = SupabaseService.describeError(e);
        _loadingFollowing = false;
      });
    }
  }

  Future<void> _toggleFollowHandle(String handle, bool currentFollowing) async {
    if (_busyHandles.contains(handle)) return;
    setState(() => _busyHandles.add(handle));

    final nextState = !currentFollowing;

    try {
      await SupabaseService.instance.client.rpc(
        'follow_handle',
        params: {
          'p_handle': handle,
          'p_follow': nextState,
        },
      );

      if (!mounted) return;
      setState(() {
        _busyHandles.remove(handle);
        // Update local follower back status
        for (final f in _followers) {
          if (f['handle'] == handle) {
            f['is_following'] = nextState;
          }
        }
        // Update following count
        _followingCount = (_followingCount + (nextState ? 1 : -1)).clamp(0, 999999);
      });
      _loadFollowing();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyHandles.remove(handle));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(SupabaseService.describeError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _toggleFollowInstitution(String institutionId, bool currentFollowing) async {
    if (_busyInstitutions.contains(institutionId)) return;
    setState(() => _busyInstitutions.add(institutionId));

    final nextState = !currentFollowing;

    try {
      await SupabaseService.instance.client.rpc(
        'follow_institution',
        params: {
          'p_institution_id': institutionId,
          'p_follow': nextState,
        },
      );

      if (!mounted) return;
      setState(() {
        _busyInstitutions.remove(institutionId);
        if (!nextState) {
          // Removed from following
          _following.removeWhere((item) => item['institution_id'] == institutionId);
          _followingCount = (_followingCount - 1).clamp(0, 999999);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyInstitutions.remove(institutionId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(SupabaseService.describeError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: const AppBackButton(),
        title: Text(
          'Network',
          style: text.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: colors.textPrimary,
          unselectedLabelColor: colors.textSecondary,
          indicatorColor: colors.accent,
          indicatorWeight: 2.5,
          tabs: [
            Tab(text: 'Followers ($_followerCount)'),
            Tab(text: 'Following ($_followingCount)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFollowersTab(context),
          _buildFollowingTab(context),
        ],
      ),
    );
  }

  Widget _buildFollowersTab(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    if (_loadingFollowers) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorFollowers != null) {
      return Center(
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load followers',
          message: _errorFollowers!,
          actionLabel: 'Try again',
          onAction: _loadFollowers,
        ),
      );
    }

    if (_followers.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFollowers,
        child: ListView(
          padding: const EdgeInsets.all(32),
          children: const [
            SizedBox(height: 60),
            EmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No followers yet',
              message:
                  'When students or educators follow your profile, they will appear here.',
            ),
          ],
        ),
      );
    }

    final filtered = _followers.where((f) {
      if (_followerQuery.isEmpty) return true;
      final q = _followerQuery.toLowerCase();
      final name = (f['display_name'] as String? ?? '').toLowerCase();
      final handle = (f['handle'] as String? ?? '').toLowerCase();
      final bio = (f['bio'] as String? ?? '').toLowerCase();
      return name.contains(q) || handle.contains(q) || bio.contains(q);
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadFollowers,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: filtered.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: 'Search followers...',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (val) => setState(() => _followerQuery = val.trim()),
              ),
            );
          }

          final follower = filtered[index - 1];
          final handle = follower['handle']?.toString() ?? '';
          final displayName = follower['display_name']?.toString() ?? 'Student';
          final avatarUrl = follower['avatar_url']?.toString();
          final isVerified = follower['is_verified'] == true;
          final bio = follower['bio']?.toString();
          final isFollowing = follower['is_following'] == true;
          final isBusy = _busyHandles.contains(handle);

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: InstitutionAvatar(
              logoUrl: avatarUrl,
              initials: displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
              size: 44,
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    displayName,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isVerified) ...[
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
                  '@$handle',
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
                if (bio != null && bio.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    bio,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: colors.textLight),
                  ),
                ],
              ],
            ),
            trailing: isBusy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : SizedBox(
                    height: 32,
                    child: isFollowing
                        ? OutlinedButton(
                            onPressed: () => _toggleFollowHandle(handle, true),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 32),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              side: BorderSide(color: colors.border),
                              foregroundColor: colors.textPrimary,
                            ),
                            child: const Text(
                              'Following',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          )
                        : FilledButton(
                            onPressed: () => _toggleFollowHandle(handle, false),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 32),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              backgroundColor: colors.accent,
                              foregroundColor: colors.onAccent,
                            ),
                            child: const Text(
                              'Follow back',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                  ),
            onTap: () => context.push('${AppConstants.routeHandle}/$handle'),
          );
        },
      ),
    );
  }

  Widget _buildFollowingTab(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    if (_loadingFollowing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorFollowing != null) {
      return Center(
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load following',
          message: _errorFollowing!,
          actionLabel: 'Try again',
          onAction: _loadFollowing,
        ),
      );
    }

    if (_following.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFollowing,
        child: ListView(
          padding: const EdgeInsets.all(32),
          children: [
            const SizedBox(height: 60),
            EmptyState(
              icon: Icons.school_outlined,
              title: 'Not following anyone yet',
              message:
                  'Follow universities and students to receive their updates and admission announcements.',
              actionLabel: 'Discover universities',
              onAction: () => context.go(AppConstants.routeDiscover),
            ),
          ],
        ),
      );
    }

    final filtered = _following.where((f) {
      if (_followingQuery.isEmpty) return true;
      final q = _followingQuery.toLowerCase();
      final name = (f['name'] as String? ?? '').toLowerCase();
      final handle = (f['handle'] as String? ?? '').toLowerCase();
      final subtitle = (f['subtitle'] as String? ?? '').toLowerCase();
      return name.contains(q) || handle.contains(q) || subtitle.contains(q);
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadFollowing,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: filtered.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: 'Search following...',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (val) => setState(() => _followingQuery = val.trim()),
              ),
            );
          }

          final item = filtered[index - 1];
          final kind = item['kind']?.toString() ?? 'student';
          final isInstitution = kind == 'institution';
          final institutionId = item['institution_id']?.toString();
          final name = item['name']?.toString() ?? 'Institution';
          final handle = item['handle']?.toString();
          final avatarUrl = item['avatar_url']?.toString();
          final subtitle = item['subtitle']?.toString();
          final isVerified = item['is_verified'] == true;
          final isBusy = isInstitution
              ? _busyInstitutions.contains(institutionId)
              : _busyHandles.contains(handle);

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: InstitutionAvatar(
              logoUrl: avatarUrl,
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
                if (isVerified) ...[
                  const SizedBox(width: 4),
                  VerifiedBadge(
                    subject: isInstitution
                        ? VerifiedSubject.institution
                        : VerifiedSubject.student,
                    compact: true,
                  ),
                ],
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (handle != null && handle.isNotEmpty)
                  Text(
                    '@$handle',
                    style: text.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: colors.textLight),
                  ),
                ],
              ],
            ),
            trailing: isBusy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : SizedBox(
                    height: 32,
                    child: OutlinedButton(
                      onPressed: () {
                        if (isInstitution && institutionId != null) {
                          _toggleFollowInstitution(institutionId, true);
                        } else if (handle != null) {
                          _toggleFollowHandle(handle, true);
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        side: BorderSide(color: colors.border),
                        foregroundColor: colors.textPrimary,
                      ),
                      child: const Text(
                        'Following',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
            onTap: () {
              if (isInstitution && institutionId != null) {
                context.push('${AppConstants.routeInstitution}/$institutionId');
              } else if (handle != null) {
                context.push('${AppConstants.routeHandle}/$handle');
              }
            },
          );
        },
      ),
    );
  }
}
