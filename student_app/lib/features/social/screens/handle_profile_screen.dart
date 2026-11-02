import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/widgets/verified_badge.dart';
import '../models/post.dart';
import '../providers/feed_provider.dart';
import '../widgets/post_card.dart';
import 'post_sheets.dart';

/// Screen displayed when navigating to `/u/:handle`.
///
/// The same profile for everyone: avatar, bio, follower and following counts,
/// and a timeline of what they have posted.
///
/// An institution gets exactly that too, plus a button in the app bar through
/// to its full prospectus. The prospectus answers "what can I study here"; the
/// profile answers "what has this university been saying", and bouncing
/// straight to the former meant nobody could ever ask the latter.
class HandleProfileScreen extends StatefulWidget {
  final String handle;

  const HandleProfileScreen({super.key, required this.handle});

  @override
  State<HandleProfileScreen> createState() => _HandleProfileScreenState();
}

class _HandleProfileScreenState extends State<HandleProfileScreen> {
  Map<String, dynamic>? _profile;
  List<Post> _posts = const [];
  bool _loading = true;
  bool _loadingPosts = false;
  String? _error;

  bool _isFollowing = false;
  bool _followBusy = false;
  int _followerCount = 0;
  int _followingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cleanHandle = widget.handle.replaceAll('@', '').trim();
      final res = await SupabaseService.instance.client
          .from('public_profiles')
          .select()
          .ilike('handle', cleanHandle)
          .maybeSingle();

      if (res == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Account @${widget.handle} was not found.';
        });
        return;
      }

      // An institution handle used to bounce straight to the prospectus here,
      // which meant a university had no profile — no bio, no follower count
      // and, most of the day-to-day, no timeline of what it had actually
      // posted. Everything below already renders one (the avatar branches on
      // `kind`, and the app bar carries a button through to the full
      // university page), so the screen just had to be allowed to draw it.

      final followerCount = (res['follower_count'] as num?)?.toInt() ?? 0;
      final followingCount = (res['following_count'] as num?)?.toInt() ?? 0;

      // Check if current user is following this handle
      bool isFollowing = false;
      try {
        final fRes = await SupabaseService.instance.client.rpc(
          'is_following_handle',
          params: {'p_handle': cleanHandle},
        );
        isFollowing = fRes as bool? ?? false;
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _profile = res;
        _followerCount = followerCount;
        _followingCount = followingCount;
        _isFollowing = isFollowing;
        _loading = false;
      });

      _loadPosts(cleanHandle);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = SupabaseService.describeError(e);
      });
    }
  }

  Future<void> _loadPosts(String cleanHandle) async {
    setState(() => _loadingPosts = true);
    try {
      final posts = await context.read<FeedProvider>().postsByHandle(cleanHandle);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loadingPosts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPosts = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (_followBusy || _profile == null) return;
    setState(() => _followBusy = true);

    final cleanHandle = widget.handle.replaceAll('@', '').trim();
    final nextState = !_isFollowing;

    try {
      await SupabaseService.instance.client.rpc(
        'follow_handle',
        params: {
          'p_handle': cleanHandle,
          'p_follow': nextState,
        },
      );

      if (!mounted) return;
      setState(() {
        _isFollowing = nextState;
        _followerCount = (_followerCount + (nextState ? 1 : -1)).clamp(0, 9999999);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(SupabaseService.describeError(e)),
          backgroundColor: context.colors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('@${widget.handle}')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: EmptyState(
              icon: Icons.person_off_outlined,
              title: 'Account not found',
              message: _error ?? 'This account does not exist or has been removed.',
              actionLabel: 'Back to feed',
              onAction: () => context.go(AppConstants.routeFeed),
            ),
          ),
        ),
      );
    }

    final p = _profile!;
    final displayName = p['display_name'] as String? ?? widget.handle;
    final handle = p['handle'] as String? ?? widget.handle;
    final bio = p['bio'] as String?;
    final avatarUrl = p['avatar_url'] as String?;
    final isVerified = p['is_verified'] as bool? ?? false;
    final kind = p['kind'] as String? ?? 'student';
    final institutionId = p['institution_id'] as String?;
    final institutionName = p['institution_name'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: Text('@$handle'),
        actions: [
          if (institutionId != null)
            IconButton(
              tooltip: 'View University Page',
              icon: const Icon(Icons.school_outlined),
              onPressed: () => context.push('${AppConstants.routeInstitution}/$institutionId'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            // Profile header card
            Container(
              padding: const EdgeInsets.all(20),
              color: colors.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      kind == 'student'
                          ? UserAvatar(
                              avatarUrl: avatarUrl,
                              initials: displayName.isNotEmpty
                                  ? displayName[0].toUpperCase()
                                  : '?',
                              size: 72,
                            )
                          : InstitutionAvatar(
                              logoUrl: avatarUrl,
                              initials: displayName.isNotEmpty
                                  ? displayName[0].toUpperCase()
                                  : '?',
                              size: 72,
                            ),
                      const Spacer(),
                      if (institutionId != null)
                        FilledButton.icon(
                          onPressed: () => context.push('${AppConstants.routeInstitution}/$institutionId'),
                          icon: const Icon(Icons.account_balance_outlined, size: 18),
                          label: const Text('View University'),
                        )
                      else
                        _followBusy
                            ? const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : _isFollowing
                                ? OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 36),
                                    ),
                                    onPressed: _toggleFollow,
                                    icon: const Icon(Icons.check, size: 18),
                                    label: const Text('Following'),
                                  )
                                : FilledButton.icon(
                                    onPressed: _toggleFollow,
                                    icon: const Icon(Icons.person_add_outlined, size: 18),
                                    label: const Text('Follow'),
                                  ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isVerified) ...[
                        const SizedBox(width: 6),
                        VerifiedBadge(
                          subject: kind == 'institution'
                              ? VerifiedSubject.institution
                              : kind == 'educator'
                                  ? VerifiedSubject.educator
                                  : VerifiedSubject.student,
                        ),
                      ],
                    ],
                  ),

                  Text(
                    '@$handle',
                    style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                  ),

                  if (institutionName != null && institutionName.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.location_city_outlined, size: 16, color: colors.textSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            institutionName,
                            style: text.bodySmall?.copyWith(color: colors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (bio != null && bio.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      bio,
                      style: text.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Followers & Following counters
                  Row(
                    children: [
                      _StatItem(
                        count: _followingCount,
                        label: 'Following',
                      ),
                      const SizedBox(width: 20),
                      _StatItem(
                        count: _followerCount,
                        label: 'Followers',
                      ),
                      const SizedBox(width: 20),
                      _StatItem(
                        count: _posts.length,
                        label: 'Posts',
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          kind.toUpperCase(),
                          style: text.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Posts section title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Posts',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),

            if (_loadingPosts)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_posts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: EmptyState(
                  icon: Icons.forum_outlined,
                  title: 'No posts yet',
                  message: '@$handle has not shared any posts yet.',
                ),
              )
            else
              ..._posts.map((post) {
                final feed = context.read<FeedProvider>();
                return PostCard(
                  post: post,
                  onTap: () => context.push('${AppConstants.routePost}/${post.id}'),
                  onLike: (p) => engage(context, p, feed.toggleLike),
                  onBookmark: (p) => engage(context, p, feed.toggleBookmark),
                  onReply: (p) => openReplySheet(context, p),
                  onRepost: (p) => openRepostSheet(context, p),
                  onShare: (p) => sharePost(context, p),
                  onMore: (p) => openPostMenu(context, p),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final int count;
  final String label;

  const _StatItem({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;

    return Row(
      children: [
        Text(
          '$count',
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}
