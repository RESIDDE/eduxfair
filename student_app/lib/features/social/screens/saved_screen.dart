import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/widgets/empty_state.dart';
import '../models/post.dart';
import '../providers/feed_provider.dart';
import '../widgets/post_card.dart';
import 'post_sheets.dart';

/// Posts the student bookmarked.
///
/// Bookmarks are private by design — never counted, never shown to the author —
/// so this reads them directly rather than through a feed function.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  List<Post> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = SupabaseService.instance;
    final feed = context.read<FeedProvider>();

    final rows = await service.client
        .from('post_bookmarks')
        .select('post_id')
        .eq('profile_id', service.userId!)
        .order('created_at', ascending: false);

    final posts = <Post>[];
    for (final row in rows as List) {
      final post = await feed.postById(row['post_id'] as String);
      if (post != null) posts.add(post);
    }

    if (!mounted) return;
    setState(() {
      _posts = posts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final feed = context.read<FeedProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Saved')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _posts.isEmpty
              ? const EmptyState(
                  icon: Icons.bookmark_border_rounded,
                  title: 'Nothing saved yet',
                  message: 'Tap the bookmark on any post and it will be here '
                      'for you. Only you can see this.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _posts.length,
                    itemBuilder: (context, i) => PostCard(
                      post: _posts[i],
                      onTap: () =>
                          context.push('${AppConstants.routePost}/${_posts[i].id}'),
                      onAuthorTap: (h) =>
                          context.push('${AppConstants.routeHandle}/$h'),
                      onLike: feed.toggleLike,
                      onBookmark: (p) async {
                        await feed.toggleBookmark(p);
                        _load();
                      },
                      onReply: (p) => openReplySheet(context, p),
                      onRepost: (p) => openRepostSheet(context, p),
                      onShare: (p) => sharePost(context, p),
                      onMore: (p) => openPostMenu(context, p),
                    ),
                  ),
                ),
    );
  }
}
