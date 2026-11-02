import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../passport/models/passport.dart';
import '../models/post.dart';

/// The feed, its tabs, and everything a post card can do.
///
/// Each tab keeps its own page of posts so switching between them is instant
/// and does not refetch. Engagement is optimistic — a like that waits for a
/// round trip feels broken — and rolls back if the server refuses.
class FeedProvider extends ChangeNotifier {
  final _service = SupabaseService.instance;

  static const int _pageSize = 30;

  List<FeedTab> _tabs = const [
    FeedTab(label: 'For you', kind: FeedKind.forYou),
    FeedTab(label: 'Following', kind: FeedKind.following),
  ];

  final Map<String, List<Post>> _posts = {};
  final Map<String, bool> _loading = {};
  final Map<String, bool> _exhausted = {};
  String? _error;

  FeedProvider() {
    try {
      _service.authChanges.listen((state) {
        if (state.event == AuthChangeEvent.signedOut) {
          _tabs = const [
            FeedTab(label: 'For you', kind: FeedKind.forYou),
            FeedTab(label: 'Following', kind: FeedKind.following),
          ];
          _posts.clear();
          _loading.clear();
          _exhausted.clear();
          _error = null;
          notifyListeners();
        }
      });
    } catch (_) {
      // Uninitialized Supabase in pure unit tests
    }
  }

  List<FeedTab> get tabs => _tabs;
  String? get error => _error;

  List<Post> postsFor(FeedTab tab) => _posts[_key(tab)] ?? const [];
  bool isLoading(FeedTab tab) => _loading[_key(tab)] ?? false;
  bool isExhausted(FeedTab tab) => _exhausted[_key(tab)] ?? false;

  static String _key(FeedTab tab) =>
      '${tab.kind.name}:${tab.topicKind ?? ''}:${tab.topicValue ?? ''}';

  // ── Tabs ──────────────────────────────────────────────────────────────────

  /// Builds the tab row from the student's own passport.
  ///
  /// This is why `post_topics` reuses `fields_of_study` and ISO country codes
  /// rather than a tag vocabulary of its own — the tabs come straight from
  /// what they already told us they want, with no extra setup.
  void buildTabs(Passport? passport, String Function(String) fieldLabel) {
    final tabs = <FeedTab>[
      const FeedTab(label: 'For you', kind: FeedKind.forYou),
      const FeedTab(label: 'Following', kind: FeedKind.following),
      const FeedTab(
        label: 'Questions',
        kind: FeedKind.kind,
        topicValue: 'question',
      ),
      const FeedTab(
        label: 'Announcements',
        kind: FeedKind.kind,
        topicValue: 'announcement',
      ),
    ];

    for (final field in passport?.targetFields ?? const <String>[]) {
      tabs.add(FeedTab(
        label: fieldLabel(field),
        kind: FeedKind.topic,
        topicKind: 'field',
        topicValue: field,
      ));
    }

    for (final country in passport?.targetCountries ?? const <String>[]) {
      tabs.add(FeedTab(
        label: AppConstants.popularDestinations[country] ?? country,
        kind: FeedKind.topic,
        topicKind: 'country',
        topicValue: country,
      ));
    }

    // Only notify when the set actually changed, or every passport reload
    // rebuilds the TabController and throws away the reader's position.
    final changed = tabs.length != _tabs.length ||
        !List.generate(tabs.length, (i) => tabs[i].label == _tabs[i].label)
            .every((same) => same);

    if (changed) {
      _tabs = tabs;
      notifyListeners();
    }
  }

  /// Builds the tab set for an institution, giving universities a full
  /// community feed (For you), their own posts, mentions, student inquiries,
  /// and academic program field tabs.
  void buildOrgTabs({
    required String? handle,
    List<String> programFields = const [],
    String? country,
    String Function(String)? fieldLabel,
  }) {
    final tabs = <FeedTab>[
      const FeedTab(label: 'For you', kind: FeedKind.forYou),
      FeedTab(
        label: 'Our posts',
        kind: FeedKind.topic,
        topicKind: 'handle',
        topicValue: handle ?? '',
      ),
      if (handle != null && handle.isNotEmpty)
        FeedTab(
          label: 'Mentions',
          kind: FeedKind.tagged,
          topicValue: handle,
        ),
      const FeedTab(
        label: 'Questions',
        kind: FeedKind.kind,
        topicValue: 'question',
      ),
      const FeedTab(
        label: 'Announcements',
        kind: FeedKind.kind,
        topicValue: 'announcement',
      ),
    ];

    if (country != null && country.isNotEmpty) {
      tabs.add(FeedTab(
        label: AppConstants.popularDestinations[country] ?? country,
        kind: FeedKind.topic,
        topicKind: 'country',
        topicValue: country,
      ));
    }

    for (final field in programFields) {
      final label = fieldLabel != null ? fieldLabel(field) : field;
      tabs.add(FeedTab(
        label: label,
        kind: FeedKind.topic,
        topicKind: 'field',
        topicValue: field,
      ));
    }

    final changed = tabs.length != _tabs.length ||
        !List.generate(tabs.length, (i) => tabs[i].label == _tabs[i].label)
            .every((same) => same);

    if (changed) {
      _tabs = tabs;
      notifyListeners();
    }
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Future<void> load(FeedTab tab, {bool refresh = false}) async {
    final key = _key(tab);
    if (_loading[key] == true) return;
    if (!refresh && (_posts[key]?.isNotEmpty ?? false)) return;

    _loading[key] = true;
    _error = null;
    notifyListeners();

    try {
      final rows = await _fetch(tab, before: null);
      _posts[key] = rows;
      _exhausted[key] = rows.length < _pageSize;
    } catch (e) {
      _error = SupabaseService.describeError(e);
    } finally {
      _loading[key] = false;
      notifyListeners();
    }
  }

  Future<void> loadMore(FeedTab tab) async {
    final key = _key(tab);
    if (_loading[key] == true || _exhausted[key] == true) return;

    final existing = _posts[key] ?? const <Post>[];
    if (existing.isEmpty) return load(tab);

    _loading[key] = true;
    notifyListeners();

    try {
      // Keyset paging on created_at rather than an offset: an offset shifts
      // under you as new posts arrive and starts repeating rows.
      final rows = await _fetch(tab, before: existing.last.createdAt);
      _posts[key] = [...existing, ...rows];
      _exhausted[key] = rows.length < _pageSize;
    } catch (e) {
      _error = SupabaseService.describeError(e);
    } finally {
      _loading[key] = false;
      notifyListeners();
    }
  }

  Future<List<Post>> _fetch(FeedTab tab, {DateTime? before}) async {
    final params = <String, dynamic>{
      'p_limit': _pageSize,
      'p_before': before?.toUtc().toIso8601String(),
    };

    final rows = switch (tab.kind) {
      FeedKind.forYou =>
        await _service.client.rpc('feed_for_you', params: params),
      FeedKind.following =>
        await _service.client.rpc('feed_following', params: params),
      FeedKind.topic => tab.topicKind == 'handle'
          ? await _service.client.rpc('feed_by_handle', params: {
              'p_handle': tab.topicValue,
              'p_limit': _pageSize,
              if (before != null) 'p_before': before.toUtc().toIso8601String(),
            })
          : await _service.client.rpc('feed_by_topic', params: {
              ...params,
              'p_kind': tab.topicKind,
              'p_value': tab.topicValue,
            }),
      FeedKind.kind => await _service.client.rpc('feed_by_kind', params: {
          ...params,
          'p_kind': tab.topicValue,
        }),
      FeedKind.tagged => await _service.client.rpc('feed_tagged', params: {
          ...params,
          if (tab.topicValue != null && tab.topicValue!.isNotEmpty)
            'p_handle': tab.topicValue,
        }),
    };

    return (rows as List)
        .map((r) => Post.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  /// One account's posts, for a profile page.
  /// Posts matching a search, for Discover.
  ///
  /// Goes through `search_posts`, which reads the same `feed_posts` view the
  /// feed does — so a blocked account's posts stay invisible here too, rather
  /// than reappearing through a side door.
  Future<List<Post>> searchPosts(String query) async {
    if (query.trim().isEmpty) return const [];
    _error = null;
    try {
      final rows = await _service.client
          .rpc('search_posts', params: {'p_query': query.trim(), 'p_limit': 40});
      return (rows as List)
          .map((r) => Post.fromMap((r as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return const [];
    }
  }

  Future<List<Post>> postsByHandle(String handle) async {
    try {
      final rows = await _service.client
          .rpc('feed_by_handle', params: {'p_handle': handle, 'p_limit': 50});
      return (rows as List)
          .map((r) => Post.fromMap((r as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return [];
    }
  }

  Future<Post?> postById(String id) async {
    try {
      final rows =
          await _service.client.rpc('post_by_id', params: {'p_post_id': id});
      final list = rows as List;
      if (list.isEmpty) return null;
      return Post.fromMap((list.first as Map).cast<String, dynamic>());
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return null;
    }
  }

  Future<List<PostComment>> comments(String postId) async {
    try {
      final rows = await _service.client
          .rpc('post_comments', params: {'p_post_id': postId});
      return (rows as List)
          .map((r) => PostComment.fromMap((r as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return [];
    }
  }

  // ── Engagement ────────────────────────────────────────────────────────────

  /// Applies a change to every copy of a post across every loaded tab.
  ///
  /// The same post appears under For you, Following and a topic tab at once;
  /// liking it in one place has to move all of them or the counts disagree on
  /// screen.
  void _patch(String postId, Post Function(Post) change) {
    for (final key in _posts.keys) {
      _posts[key] = _posts[key]!
          .map((p) => p.id == postId ? change(p) : p)
          .toList();
    }
    notifyListeners();
  }

  Future<void> toggleLike(Post post) async {
    final liked = post.liked;
    _patch(
      post.id,
      (p) => p.copyWith(
        liked: !liked,
        likeCount: (p.likeCount + (liked ? -1 : 1)).clamp(0, 1 << 30),
      ),
    );

    try {
      if (liked) {
        await _service.client
            .from('post_likes')
            .delete()
            .eq('post_id', post.id)
            .eq('profile_id', _service.userId!);
      } else {
        await _service.client.from('post_likes').insert({
          'post_id': post.id,
          'profile_id': _service.userId,
        });
      }
    } catch (e) {
      // Put it back, so the card never claims something that did not happen.
      _patch(
        post.id,
        (p) => p.copyWith(
          liked: liked,
          likeCount: (p.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 30),
        ),
      );
      _error = SupabaseService.describeError(e);
      notifyListeners();
    }
  }

  Future<void> toggleBookmark(Post post) async {
    final saved = post.bookmarked;
    _patch(post.id, (p) => p.copyWith(bookmarked: !saved));

    try {
      if (saved) {
        await _service.client
            .from('post_bookmarks')
            .delete()
            .eq('post_id', post.id)
            .eq('profile_id', _service.userId!);
      } else {
        await _service.client.from('post_bookmarks').insert({
          'post_id': post.id,
          'profile_id': _service.userId,
        });
      }
    } catch (e) {
      _patch(post.id, (p) => p.copyWith(bookmarked: saved));
      _error = SupabaseService.describeError(e);
      notifyListeners();
    }
  }

  /// Reshares, or undoes a reshare. A quote always creates a new post.
  Future<bool> toggleRepost(Post post, {String? quote}) async {
    // The target is the original, since reposts are flattened server-side.
    final target = post.reposted?.id ?? post.id;
    final was = post.repostedByMe;

    if (quote == null) {
      _patch(
        target,
        (p) => p.copyWith(
          repostedByMe: !was,
          repostCount: (p.repostCount + (was ? -1 : 1)).clamp(0, 1 << 30),
        ),
      );
    }

    try {
      await _service.client.rpc('repost', params: {
        'p_post_id': target,
        'p_body': quote,
      });
      return true;
    } catch (e) {
      if (quote == null) {
        _patch(
          target,
          (p) => p.copyWith(
            repostedByMe: was,
            repostCount: (p.repostCount + (was ? 1 : -1)).clamp(0, 1 << 30),
          ),
        );
      }
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  // ── Writing ───────────────────────────────────────────────────────────────

  /// Creates a post, optionally as an institution.
  ///
  /// Through the RPC rather than an insert, so the rate limit, the restriction
  /// check and the topic tags all happen in one transaction — a client that
  /// skipped any of them would create a post that bypasses it.
  Future<String?> createPost({
    required String body,
    String kind = 'update',
    String? institutionId,
    String? linkUrl,
    String replyPolicy = 'everyone',
    List<String> fields = const [],
    List<String> countries = const [],
    List<String> taggedHandles = const [],
    List<({Uint8List bytes, String name, String? mime})> media = const [],
  }) async {
    _error = null;

    try {
      final postId = await _service.client.rpc('create_post', params: {
        'p_body': body,
        'p_kind': kind,
        'p_institution_id': institutionId,
        'p_link_url': linkUrl,
        'p_reply_policy': replyPolicy,
        'p_fields': fields,
        'p_countries': countries,
        'p_tagged_handles': taggedHandles,
      }) as String;

      for (var i = 0; i < media.length; i++) {
        final item = media[i];
        // Prefixed with the uploader's uuid, which is what the storage policy
        // authorizes on.
        final path =
            '${_service.userId}/${DateTime.now().millisecondsSinceEpoch}-$i-'
            '${item.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}';

        await _service.uploadBytes(
          bucket: AppConstants.bucketPostMedia,
          path: path,
          bytes: item.bytes,
          contentType: item.mime,
        );

        // `post_media` has had width and height columns since the social
        // migration and nothing ever wrote them, so every post in the app
        // reported an unknown aspect ratio and the card had to guess. Reading
        // them off the encoded bytes costs one header parse and means the
        // feed lays the picture out correctly on its first frame instead of
        // reflowing once it decodes.
        final size = await _imageSize(item.bytes);

        await _service.client.from('post_media').insert({
          'post_id': postId,
          'storage_path': path,
          'mime': item.mime,
          'ord': i,
          if (size != null) 'width': size.$1,
          if (size != null) 'height': size.$2,
        });
      }

      return postId;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return null;
    }
  }

  Future<bool> reply(String postId, String body, {String? parentId}) async {
    _error = null;
    try {
      await _service.client.rpc('comment_on_post', params: {
        'p_post_id': postId,
        'p_body': body,
        'p_parent_id': parentId,
      });
      _patch(postId, (p) => p.copyWith(commentCount: p.commentCount + 1));
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> toggleCommentLike(PostComment comment) async {
    final liked = comment.liked;
    try {
      if (liked) {
        await _service.client
            .from('comment_likes')
            .delete()
            .eq('comment_id', comment.id)
            .eq('profile_id', _service.userId!);
      } else {
        await _service.client.from('comment_likes').insert({
          'comment_id': comment.id,
          'profile_id': _service.userId,
        });
      }
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeComment(String commentId, String postId) async {
    _error = null;
    try {
      await _service.client.rpc('remove_comment', params: {'p_comment_id': commentId});
      _patch(postId, (p) => p.copyWith(commentCount: (p.commentCount - 1).clamp(0, 1 << 30)));
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  /// Removes a post — and, server-side, every reshare of it.
  Future<bool> removePost(Post post) async {
    _error = null;
    try {
      await _service.client.rpc('remove_post', params: {'p_post_id': post.id});
      for (final key in _posts.keys) {
        _posts[key] = _posts[key]!
            .where((p) => p.id != post.id && p.reposted?.id != post.id)
            .toList();
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  // ── Relationships and moderation ──────────────────────────────────────────

  Future<bool> follow(String handle, {bool follow = true}) =>
      _call('follow_handle', {'p_handle': handle, 'p_follow': follow});

  Future<bool> block(String handle) =>
      _call('moderate_handle', {'p_handle': handle, 'p_action': 'block'});

  Future<bool> mute(String handle) =>
      _call('moderate_handle', {'p_handle': handle, 'p_action': 'mute'});

  Future<bool> report({
    required String subjectType,
    required String subjectId,
    required String reason,
    String? note,
  }) async {
    _error = null;
    try {
      await _service.client.from('reports').insert({
        'reporter_id': _service.userId,
        'subject_type': subjectType,
        'subject_id': subjectId,
        'reason': reason,
        'note': note,
      });
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> _call(String fn, Map<String, dynamic> params) async {
    _error = null;
    try {
      await _service.client.rpc(fn, params: params);
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}

/// The pixel dimensions of an encoded image, without fully decoding it.
///
/// `ImageDescriptor` reads the header only, which is all this needs, and works
/// on web as well as the phones — `dart:io` is not available on all three
/// targets and neither is anything that takes a file path.
Future<(int, int)?> _imageSize(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    return (descriptor.width, descriptor.height);
  } catch (_) {
    // An unreadable header is not a reason to fail the post; the card falls
    // back to resolving the ratio once the image loads.
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}
