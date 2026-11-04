import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_chrome.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/chrome_button.dart';
import '../../../core/widgets/material_surface.dart';
import '../../../core/utils/motion.dart';
import '../../applications/providers/applications_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../matches/providers/matches_provider.dart';
import '../../passport/providers/passport_provider.dart';
import '../models/post.dart';
import '../providers/feed_provider.dart';
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
        // Straight to the account screen rather than opening a drawer over
        // the feed. The drawer was a second, near-identical copy of that
        // screen's list — its rows all led to the same places — so the tap now
        // goes where the student was heading anyway.
        leading: Center(
          child: ChromeButton(
            tooltip: 'Your account',
            onTap: () => context.push(AppConstants.routeProfile),
            child: InstitutionAvatar(
              logoUrl: user?.avatarUrl,
              initials: user?.initials ?? '?',
              size: 30,
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

  /// Anything pinned above the stream of posts.
  ///
  /// Empty, and kept as a seam rather than deleted: the feed previously
  /// opened with a student search box and up to four standing to-do
  /// cards, which put a form and a chore list between the student and
  /// the thing they came to read. Search moved to the Search tab and the
  /// to-dos to Notifications, where the nav badge already counts them.
  List<Widget> _pinnedCards(BuildContext context) => const [];

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
