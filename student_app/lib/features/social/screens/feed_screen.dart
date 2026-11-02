import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_chrome.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/chrome_button.dart';
import '../../../core/widgets/material_surface.dart';
import '../../../core/widgets/verified_badge.dart';
import '../../../core/utils/motion.dart';
import '../../applications/providers/applications_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../matches/providers/matches_provider.dart';
import '../../passport/providers/passport_provider.dart';
import '../models/post.dart';
import '../providers/feed_provider.dart';
import '../widgets/app_drawer.dart';
import '../widgets/post_card.dart';
import 'post_sheets.dart';

/// The landing page: the feed, with swipeable tabs across the top.
///
/// Laid out like the X reference — avatar left, wordmark centre, tabs below,
/// a stream of cards separated by hairlines, and a floating compose button.
///
/// *For you* is assembled from the passport the student already filled in, so
/// someone who follows nobody still opens a feed that is about them.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;

    final passport = context.read<PassportProvider>();
    final feed = context.read<FeedProvider>();

    // These feed the pinned action cards and the drawer counts.
    await Future.wait([
      passport.load(),
      context.read<MatchesProvider>().load(),
      context.read<ApplicationsProvider>().load(),
    ]);

    if (!mounted) return;
    feed.buildTabs(passport.passport, passport.fieldLabel);
    if (feed.tabs.isNotEmpty) {
      feed.load(feed.tabs.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final feed = context.watch<FeedProvider>();
    final user = context.watch<AuthProvider>().user;
    final tabKey = feed.tabs.map((t) => t.label).join(',');

    return DefaultTabController(
      key: ValueKey(tabKey),
      length: feed.tabs.length,
      child: Scaffold(
      // The bar is glass: the feed passes under it rather than starting below
      // it, which is what tells you the list continues upward.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: const MaterialSurface(
          lightFromTop: false,
          child: SizedBox.expand(),
        ),
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leadingWidth: 60,
        // The avatar stays on the left because it opens the drawer, and a
        // left-hand panel that is summoned from the right-hand side of the bar
        // reads as a mistake. The reference has no drawer to reconcile.
        leading: Builder(
          builder: (context) => Center(
            child: ChromeButton(
              tooltip: 'Your account',
              onTap: () => Scaffold.of(context).openDrawer(),
              child: InstitutionAvatar(
                logoUrl: user?.avatarUrl,
                initials: user?.initials ?? '?',
                size: 30,
              ),
            ),
          ),
        ),
        title: Text(
          AppConstants.appName,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(color: colors.textPrimary),
        ),
        centerTitle: true,
        actions: [
          // One compose entry point in the chrome, where this screen used to
          // carry three — an app-bar pill, an extended FAB and the prompt card.
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ChromeButton.icon(
              icon: Icons.add_rounded,
              tooltip: 'New post',
              onTap: () => context.push(AppConstants.routeCompose),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Align(
            alignment: Alignment.centerLeft,
            // Sizes, weights, colours and the indicator all come from
            // tabBarTheme now.
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorWeight: 2,
              onTap: (i) => feed.load(feed.tabs[i]),
              tabs: feed.tabs.map((t) => Tab(text: t.label)).toList(),
            ),
          ),
        ),
      ),

      drawer: const AppDrawer(),

      body: TabBarView(
        children: feed.tabs
            .map((tab) => _FeedList(key: ValueKey(tab.label), tab: tab))
            .toList(),
      ),
    ),
  );
  }
}

/// One tab's list of posts.
class _FeedList extends StatefulWidget {
  final FeedTab tab;

  const _FeedList({super.key, required this.tab});

  @override
  State<_FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<_FeedList>
    with AutomaticKeepAliveClientMixin {
  final _controller = ScrollController();
  final _searchController = TextEditingController();
  Timer? _debounceTimer;
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  final Set<String> _busyHandles = {};
  String? _searchError;

  // Keeps each tab's scroll position when swiping between them, which is what
  // makes the tab row feel like the reference rather than a reset every time.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<FeedProvider>().load(widget.tab);
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_controller.position.pixels >=
        _controller.position.maxScrollExtent - 600) {
      context.read<FeedProvider>().loadMore(widget.tab);
    }
  }

  void _onSearchChanged(String text) {
    _debounceTimer?.cancel();
    final query = text.trim();
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
        _searchError = null;
      });
      return;
    }

    setState(() {}); // Immediate rebuild to reflect clear button & typed query

    _debounceTimer = Timer(const Duration(milliseconds: 280), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final res = await SupabaseService.instance.client.rpc(
        'search_students_with_follow',
        params: {'p_query': query, 'p_limit': 15},
      );
      if (!mounted) return;
      final list = (res as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      setState(() {
        _searchResults = list;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = SupabaseService.describeError(e);
        _isSearching = false;
      });
    }
  }

  Future<void> _toggleFollowStudent(String handle, bool currentFollowing) async {
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
        for (final item in _searchResults) {
          if (item['handle'] == handle) {
            item['is_following'] = nextState;
            final count = (item['follower_count'] as num?)?.toInt() ?? 0;
            item['follower_count'] =
                (count + (nextState ? 1 : -1)).clamp(0, 999999);
          }
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextState ? 'Following @$handle' : 'Unfollowed @$handle',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final feed = context.watch<FeedProvider>();
    final posts = feed.postsFor(widget.tab);
    final loading = feed.isLoading(widget.tab);

    if (loading && posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final pinned = _pinnedCards(context);

    if (posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => feed.load(widget.tab, refresh: true),
        child: ListView(
          controller: _controller,
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + 8,
            bottom: AppChrome.navClearance(context),
          ),
          children: [
            ...pinned,
            const SizedBox(height: 16),
            EmptyState(
              icon: widget.tab.kind == FeedKind.following
                  ? Icons.person_add_alt_outlined
                  : Icons.forum_outlined,
              title: widget.tab.kind == FeedKind.following
                  ? 'You are not following anyone yet'
                  : 'No posts yet',
              message: widget.tab.kind == FeedKind.following
                  ? 'Follow institutions or students to see their updates here.'
                  : 'Be the first to share an update, or search student tags to connect!',
              actionLabel: 'Create a Post',
              onAction: () => context.push(AppConstants.routeCompose),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => feed.load(widget.tab, refresh: true),
      child: ListView.builder(
        controller: _controller,
        // Room for the floating bar at the bottom and the glass bar at the
        // top, now that content runs behind both.
        // Scaffold already publishes both insets through MediaQuery:
        // `extendBodyBehindAppBar` puts the full app-bar height into
        // padding.top, and MainShell's `extendBody` puts the nav bar's
        // measured height into padding.bottom. Adding 96 to the former was
        // counting the app bar twice.
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 8,
          bottom: AppChrome.navClearance(context),
        ),
        itemCount: posts.length + pinned.length + 1,
        itemBuilder: (context, index) {
          // Action cards, compose prompt, search bar, and nudges
          if (index < pinned.length) return pinned[index];

          final postIndex = index - pinned.length;
          if (postIndex >= posts.length) {
            return feed.isExhausted(widget.tab)
                ? const SizedBox(height: 24)
                : const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
          }

          // Cards fade and rise a little as they first appear.
          return _Card(post: posts[postIndex], tab: widget.tab).entrance(
            context,
            delay: Duration(milliseconds: 40 * postIndex.clamp(0, 6)),
            duration: const Duration(milliseconds: 280),
          );
        },
      ),
    );
  }

  /// Cards, search bar, compose box, and nudges pinned to the top of the feed.
  List<Widget> _pinnedCards(BuildContext context) {
    if (widget.tab.kind != FeedKind.forYou) return const [];

    final passport = context.watch<PassportProvider>();
    final matches = context.watch<MatchesProvider>();
    final applications = context.watch<ApplicationsProvider>();
    final cards = <Widget>[];

    // 1. Search student tag @xyz to follow directly from For You page
    cards.add(_buildStudentSearchBar(context));

    // 2. Search results (if query is typed)
    if (_searchController.text.trim().isNotEmpty) {
      cards.add(_buildSearchResultsCard(context));
    }

    // 3. Compose box on the "For you" feed
    cards.add(_buildComposePromptCard(context));

    // 4. The Passport nudges
    if (!passport.isMatchable) {
      cards.add(_Nudge(
        icon: Icons.badge_rounded,
        title: 'Finish your Education Passport',
        body: 'Institutions can only find you once it reaches '
            '${AppConstants.minCompletenessToMatch}%. Yours is at '
            '${passport.completeness}%.',
        actionLabel: 'Continue',
        onTap: () => context.push(AppConstants.routePassportEdit),
        tone: _NudgeTone.warning,
      ));
    }

    if (matches.invitationCount > 0) {
      cards.add(_Nudge(
        icon: Icons.handshake_rounded,
        title: matches.invitationCount == 1
            ? 'An institution asked for you'
            : '${matches.invitationCount} institutions asked for you',
        body: 'They matched your profile and want to hear from you.',
        actionLabel: 'See who',
        onTap: () => context.push(AppConstants.routeMatches),
        tone: _NudgeTone.good,
      ));
    }

    if (applications.offerCount > 0) {
      cards.add(_Nudge(
        icon: Icons.celebration_rounded,
        title: applications.offerCount == 1
            ? 'You have an offer'
            : 'You have ${applications.offerCount} offers',
        body: 'Review the terms and respond when you are ready.',
        actionLabel: 'View',
        onTap: () => context.push(AppConstants.routeApplications),
        tone: _NudgeTone.good,
      ));
    }

    if (applications.outstandingRequestCount > 0) {
      cards.add(_Nudge(
        icon: Icons.upload_file_rounded,
        title: 'Documents requested',
        body: '${applications.outstandingRequestCount} outstanding — your '
            'application is waiting on these.',
        actionLabel: 'Upload',
        onTap: () => context.push(AppConstants.routeApplications),
        tone: _NudgeTone.warning,
      ));
    }

    return cards;
  }

  Widget _buildStudentSearchBar(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        style: text.bodyMedium?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Search student tag @xyz or name to follow...',
          hintStyle: text.bodyMedium?.copyWith(
            color: colors.textSecondary.withValues(alpha: 0.75),
            fontSize: 13.5,
          ),
          prefixIcon: Icon(Icons.alternate_email_rounded,
              size: 20, color: colors.accent),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                )
              : (_isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildSearchResultsCard(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final query = _searchController.text.trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.people_alt_rounded, size: 16, color: colors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Students matching "$query"',
                    style: text.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                  child: Text(
                    'Dismiss',
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.divider.withValues(alpha: 0.5)),
          if (_isSearching && _searchResults.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_searchError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _searchError!,
                style: TextStyle(color: colors.error, fontSize: 13),
              ),
            )
          else if (_searchResults.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.person_search_rounded,
                        size: 36,
                        color: colors.textSecondary.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                    Text(
                      'No student found with tag "$query"',
                      style: text.bodyMedium
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _searchResults.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 64,
                color: colors.divider.withValues(alpha: 0.5),
              ),
              itemBuilder: (context, idx) {
                final student = _searchResults[idx];
                final handle = student['handle']?.toString() ?? '';
                final displayName =
                    student['display_name']?.toString() ?? 'Student';
                final avatarUrl = student['avatar_url']?.toString();
                final isVerified = student['is_verified'] == true;
                final isFollowing = student['is_following'] == true;
                final isSelf = student['is_self'] == true;
                final followerCount =
                    (student['follower_count'] as num?)?.toInt() ?? 0;
                final isBusy = _busyHandles.contains(handle);
                final bio = student['bio']?.toString();

                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: InstitutionAvatar(
                    logoUrl: avatarUrl,
                    initials: displayName.isNotEmpty
                        ? displayName[0].toUpperCase()
                        : '?',
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
                      Row(
                        children: [
                          Text(
                            '@$handle',
                            style: text.bodySmall?.copyWith(
                              color: colors.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '• $followerCount ${followerCount == 1 ? 'follower' : 'followers'}',
                            style: text.bodySmall
                                ?.copyWith(color: colors.textLight),
                          ),
                        ],
                      ),
                      if (bio != null && bio.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          bio,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                  trailing: isSelf
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colors.border),
                          ),
                          child: Text(
                            'You',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.textSecondary,
                            ),
                          ),
                        )
                      : (isBusy
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : SizedBox(
                              height: 32,
                              child: isFollowing
                                  ? OutlinedButton(
                                      onPressed: () =>
                                          _toggleFollowStudent(handle, true),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 32),
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        side: BorderSide(color: colors.border),
                                        foregroundColor: colors.textPrimary,
                                      ),
                                      child: const Text(
                                        'Following',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    )
                                  : FilledButton.icon(
                                      onPressed: () =>
                                          _toggleFollowStudent(handle, false),
                                      icon: const Icon(Icons.person_add_rounded,
                                          size: 14),
                                      label: const Text(
                                        'Follow',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(0, 32),
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        backgroundColor: colors.accent,
                                        foregroundColor: colors.onAccent,
                                      ),
                                    ),
                            )),
                  onTap: () =>
                      context.push('${AppConstants.routeHandle}/$handle'),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildComposePromptCard(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final user = context.watch<AuthProvider>().user;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.push(AppConstants.routeCompose),
            child: Row(
              children: [
                InstitutionAvatar(
                  logoUrl: user?.avatarUrl,
                  initials: user?.initials ?? '?',
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: colors.background,
                      borderRadius: BorderRadius.circular(24),
                      border:
                          Border.all(color: colors.border.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      "What's on your mind? Share an update...",
                      style: text.bodyMedium?.copyWith(
                        color: colors.textSecondary.withValues(alpha: 0.8),
                        fontSize: 13.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => context.push(AppConstants.routeCompose),
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('Post',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: colors.divider.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ComposeQuickAction(
                icon: Icons.image_rounded,
                label: 'Photo',
                color: colors.success,
                onTap: () => context.push(AppConstants.routeCompose),
              ),
              _ComposeQuickAction(
                icon: Icons.alternate_email_rounded,
                label: 'Tag Student / Uni',
                color: colors.accent,
                onTap: () => context.push(AppConstants.routeCompose),
              ),
              _ComposeQuickAction(
                icon: Icons.public_rounded,
                label: 'Public Feed',
                color: colors.info,
                onTap: () => context.push(AppConstants.routeCompose),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComposeQuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ComposeQuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A post, wired to the provider.
class _Card extends StatelessWidget {
  final Post post;
  final FeedTab tab;

  const _Card({required this.post, required this.tab});

  @override
  Widget build(BuildContext context) {
    final feed = context.read<FeedProvider>();

    return PostCard(
      post: post,
      onTap: () => context.push('${AppConstants.routePost}/${post.id}'),
      onAuthorTap: (handle) =>
          context.push('${AppConstants.routeHandle}/$handle'),
      onLike: (p) => engage(context, p, feed.toggleLike),
      onBookmark: (p) => engage(context, p, feed.toggleBookmark),
      onReply: (p) => openReplySheet(context, p),
      onRepost: (p) => openRepostSheet(context, p),
      onShare: (p) => sharePost(context, p),
      onMore: (p) => openPostMenu(context, p),
    );
  }
}

// ── Nudges ──────────────────────────────────────────────────────────────────

enum _NudgeTone { good, warning }

class _Nudge extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onTap;
  final _NudgeTone tone;

  const _Nudge({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onTap,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    final (fg, bg) = tone == _NudgeTone.good
        ? (colors.success, colors.successLight)
        : (colors.warning, colors.warningLight);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium?.copyWith(color: fg)),
                const SizedBox(height: 2),
                Text(body, style: text.bodySmall?.copyWith(height: 1.4)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: onTap,
                  child: Text(
                    actionLabel,
                    style: text.labelLarge?.copyWith(color: fg),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
