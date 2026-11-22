import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_chrome.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/chrome_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/material_surface.dart';
import '../../passport/providers/passport_provider.dart';
import '../../social/models/post.dart';
import '../../social/providers/feed_provider.dart';
import '../../social/screens/post_sheets.dart';
import '../../social/widgets/post_card.dart';
import '../providers/institution_provider.dart';

/// The university's community feed and post manager.
///
/// Features designated area tabs:
/// - "For you": The universal feed with student posts for everyone, posts matching
///   the institution's fields and destination, and student inquiries.
/// - "Our posts": Posts published by this institution.
/// - "Mentions": Posts where students tagged this institution.
/// - "Questions": Student questions and admission inquiries.
/// - "Announcements": Public institution and fair announcements.
/// - Academic field tabs: Matching the institution's active programs.
class OrgPostsScreen extends StatefulWidget {
  const OrgPostsScreen({super.key});

  @override
  State<OrgPostsScreen> createState() => _OrgPostsScreenState();
}

class _OrgPostsScreenState extends State<OrgPostsScreen>
    with TickerProviderStateMixin {
  TabController? _tabs;
  int _tabCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;

    final institution = context.read<InstitutionProvider>();
    final passport = context.read<PassportProvider>();
    final feed = context.read<FeedProvider>();

    await Future.wait([
      if (!institution.isResolved) institution.load(),
      institution.loadPrograms(),
      passport.load(),
    ]);

    if (!mounted) return;

    final fields = institution.programs
        .map((p) => p.fieldOfStudy)
        .where((f) => f.isNotEmpty)
        .toSet()
        .toList();

    feed.buildOrgTabs(
      handle: institution.handle,
      programFields: fields,
      country: institution.institution?.country,
      fieldLabel: passport.fieldLabel,
    );

    _syncController(feed.tabs.length);
    if (feed.tabs.isNotEmpty) {
      feed.load(feed.tabs.first);
    }
  }

  void _syncController(int count) {
    if (count == _tabCount && _tabs != null) return;
    final index = (_tabs?.index ?? 0).clamp(0, (count - 1).clamp(0, 999));
    _tabs?.dispose();
    _tabs = TabController(length: count, vsync: this, initialIndex: index);
    _tabCount = count;
    setState(() {});
  }

  Future<void> _compose() async {
    await context.push(AppConstants.routeCompose);
    if (mounted) {
      final feed = context.read<FeedProvider>();
      if (_tabs != null && _tabs!.index < feed.tabs.length) {
        feed.load(feed.tabs[_tabs!.index], refresh: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final feed = context.watch<FeedProvider>();
    final institution = context.watch<InstitutionProvider>();

    final controller = _tabs;
    if (controller == null || controller.length != feed.tabs.length) {
      final count = feed.tabs.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncController(count);
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final managed = institution.managed;

    // The same header as the student feed: glass, with the list passing under
    // it; the institution's mark where the student's avatar sits; one way to
    // write a post, in the top-right corner. It used to carry two — a pill in
    // the bar and a floating button — and the floating one would now sit on
    // the tab bar.
    return Scaffold(
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
        leading: Center(
          child: ChromeButton(
            tooltip: 'Our page',
            onTap: () => context.go(AppConstants.routeOrgProfile),
            child: InstitutionAvatar(
              logoUrl: managed?.institution.logoUrl,
              initials: managed?.institution.initials ?? '?',
              size: 30,
            ),
          ),
        ),
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Posts',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (institution.handle != null)
              Text(
                '@${institution.handle}',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ChromeButton.icon(
              icon: Icons.add_rounded,
              tooltip: 'New post',
              onTap: _compose,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Align(
            alignment: Alignment.centerLeft,
            // Styled by tabBarTheme, exactly like the student feed.
            child: TabBar(
              controller: controller,
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
        controller: controller,
        children: feed.tabs.map((tab) => _OrgFeedList(tab: tab)).toList(),
      ),
    );
  }
}

class _OrgFeedList extends StatefulWidget {
  final FeedTab tab;

  const _OrgFeedList({required this.tab});

  @override
  State<_OrgFeedList> createState() => _OrgFeedListState();
}

class _OrgFeedListState extends State<_OrgFeedList>
    with AutomaticKeepAliveClientMixin {
  final _controller = ScrollController();

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

    if (posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => feed.load(widget.tab, refresh: true),
        child: ListView(
          controller: _controller,
          padding: EdgeInsets.fromLTRB(32, MediaQuery.paddingOf(context).top + 32,
              32, AppChrome.navClearance(context)),
          children: [
            EmptyState(
              icon: _emptyIcon(widget.tab),
              title: _emptyTitle(widget.tab),
              message: _emptyMessage(widget.tab),
              actionLabel: 'Write a Post',
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
        // Under the glass header and above the floating tab bar.
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 8,
          bottom: AppChrome.navClearance(context),
        ),
        itemCount: posts.length + 1,
        itemBuilder: (context, index) {
          if (index >= posts.length) {
            return feed.isExhausted(widget.tab)
                ? const SizedBox(height: 24)
                : const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
          }

          final post = posts[index];
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
        },
      ),
    );
  }

  IconData _emptyIcon(FeedTab tab) => switch (tab.kind) {
        FeedKind.forYou => Icons.forum_outlined,
        FeedKind.topic when tab.topicKind == 'handle' => Icons.campaign_outlined,
        FeedKind.tagged => Icons.alternate_email_rounded,
        FeedKind.kind when tab.topicValue == 'question' =>
          Icons.help_outline_rounded,
        FeedKind.kind when tab.topicValue == 'announcement' =>
          Icons.campaign_rounded,
        _ => Icons.school_outlined,
      };

  String _emptyTitle(FeedTab tab) => switch (tab.kind) {
        FeedKind.forYou => 'No community posts yet',
        FeedKind.topic when tab.topicKind == 'handle' =>
          'You have not posted yet',
        FeedKind.tagged => 'No mentions yet',
        FeedKind.kind when tab.topicValue == 'question' =>
          'No student questions yet',
        FeedKind.kind when tab.topicValue == 'announcement' =>
          'No announcements yet',
        _ => 'No posts in ${tab.label} yet',
      };

  String _emptyMessage(FeedTab tab) => switch (tab.kind) {
        FeedKind.forYou =>
          'Posts from students and universities for everyone, or in your fields of study, will appear here.',
        FeedKind.topic when tab.topicKind == 'handle' =>
          'Introduce a new program, announce scholarship deadlines, or answer student inquiries.',
        FeedKind.tagged =>
          'When students or fellow institutions tag your handle in a post, they will land here.',
        FeedKind.kind when tab.topicValue == 'question' =>
          'When students ask questions about study options or admissions, they will show up here.',
        FeedKind.kind when tab.topicValue == 'announcement' =>
          'Important admissions announcements and fair updates will appear here.',
        _ =>
          'Posts tagged with ${tab.label} will be displayed in this designated area.',
      };
}
