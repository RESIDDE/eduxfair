import '../../../core/constants/app_constants.dart';

/// A post as the feed views return it.
///
/// Keyed on the author's `handle`, never an account id — the rule the identity
/// split established, and the reason an institution browsing anonymous match
/// cards cannot cross-reference them against the feed.
class Post {
  final String id;
  final String kind;
  final String? body;
  final String? linkUrl;
  final String replyPolicy;

  final int likeCount;
  final int commentCount;
  final int repostCount;

  final DateTime? pinnedAt;
  final DateTime createdAt;
  final DateTime? editedAt;

  // The author, resolved.
  final String authorHandle;
  final String authorName;
  final String? authorAvatar;
  final String authorKind;
  final bool authorVerified;
  final String? authorCountry;

  /// Set when this post reshares another. Body null means a plain repost;
  /// body present means a quote.
  final Post? reposted;

  final List<PostMedia> media;
  final List<PostTopic> topics;
  final List<PostTag> tags;

  // This reader's own state, so the card renders correctly without a second
  // round trip.
  final bool liked;
  final bool bookmarked;
  final bool repostedByMe;
  final bool isMine;

  const Post({
    required this.id,
    this.kind = 'update',
    this.body,
    this.linkUrl,
    this.replyPolicy = 'everyone',
    this.likeCount = 0,
    this.commentCount = 0,
    this.repostCount = 0,
    this.pinnedAt,
    required this.createdAt,
    this.editedAt,
    required this.authorHandle,
    required this.authorName,
    this.authorAvatar,
    this.authorKind = 'student',
    this.authorVerified = false,
    this.authorCountry,
    this.reposted,
    this.media = const [],
    this.topics = const [],
    this.tags = const [],
    this.liked = false,
    this.bookmarked = false,
    this.repostedByMe = false,
    this.isMine = false,
  });

  bool get isRepost => reposted != null;

  /// A plain reshare renders as the original with a "reshared by" line above;
  /// a quote renders as its own post with the original embedded.
  bool get isQuote => isRepost && (body?.trim().isNotEmpty ?? false);

  /// What the card should actually show the body and media of.
  Post get content => isRepost && !isQuote ? reposted! : this;

  bool get isOrganisation =>
      authorKind == 'institution' || authorKind == 'embassy';

  bool get isPinned => pinnedAt != null;

  String get kindLabel => switch (kind) {
        'question' => 'Question',
        'announcement' => 'Announcement',
        'requirement' => 'Requirements',
        _ => 'Update',
      };

  /// Shown as a chip only where it adds something — an ordinary update does
  /// not need labelling as one.
  bool get showsKindChip => kind != 'update';

  List<String> get fieldTopics =>
      topics.where((t) => t.kind == 'field').map((t) => t.value).toList();

  List<String> get countryTopics =>
      topics.where((t) => t.kind == 'country').map((t) => t.value).toList();

  factory Post.fromMap(Map<String, dynamic> map) {
    final reposted = map['reposted'];

    return Post(
      id: map['id'] as String,
      kind: map['kind'] as String? ?? 'update',
      body: map['body'] as String?,
      linkUrl: map['link_url'] as String?,
      replyPolicy: map['reply_policy'] as String? ?? 'everyone',
      likeCount: (map['like_count'] as num?)?.toInt() ?? 0,
      commentCount: (map['comment_count'] as num?)?.toInt() ?? 0,
      repostCount: (map['repost_count'] as num?)?.toInt() ?? 0,
      pinnedAt: _time(map['pinned_at']),
      createdAt: _time(map['created_at'])!,
      editedAt: _time(map['edited_at']),
      authorHandle: map['author_handle'] as String? ?? '',
      authorName: map['author_name'] as String? ?? '',
      authorAvatar: map['author_avatar'] as String?,
      authorKind: map['author_kind'] as String? ?? 'student',
      authorVerified: map['author_verified'] as bool? ?? false,
      authorCountry: map['author_country'] as String?,
      reposted: reposted == null
          ? null
          : Post.fromMap((reposted as Map).cast<String, dynamic>()),
      media: (map['media'] as List? ?? const [])
          .map((e) => PostMedia.fromMap((e as Map).cast<String, dynamic>()))
          .toList(),
      topics: (map['topics'] as List? ?? const [])
          .map((e) => PostTopic.fromMap((e as Map).cast<String, dynamic>()))
          .toList(),
      tags: (map['tags'] as List? ?? const [])
          .map((e) => PostTag.fromMap((e as Map).cast<String, dynamic>()))
          .toList(),
      liked: map['liked'] as bool? ?? false,
      bookmarked: map['bookmarked'] as bool? ?? false,
      repostedByMe: map['reposted_by_me'] as bool? ?? false,
      isMine: map['is_mine'] as bool? ?? false,
    );
  }

  static DateTime? _time(dynamic v) {
    final raw = v?.toString();
    return raw == null ? null : DateTime.parse(raw).toLocal();
  }

  /// For optimistic updates: the card changes immediately and the row is
  /// replaced when the server answers.
  Post copyWith({
    int? likeCount,
    int? commentCount,
    int? repostCount,
    bool? liked,
    bool? bookmarked,
    bool? repostedByMe,
  }) =>
      Post(
        id: id,
        kind: kind,
        body: body,
        linkUrl: linkUrl,
        replyPolicy: replyPolicy,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
        repostCount: repostCount ?? this.repostCount,
        pinnedAt: pinnedAt,
        createdAt: createdAt,
        editedAt: editedAt,
        authorHandle: authorHandle,
        authorName: authorName,
        authorAvatar: authorAvatar,
        authorKind: authorKind,
        authorVerified: authorVerified,
        authorCountry: authorCountry,
        reposted: reposted,
        media: media,
        topics: topics,
        tags: tags,
        liked: liked ?? this.liked,
        bookmarked: bookmarked ?? this.bookmarked,
        repostedByMe: repostedByMe ?? this.repostedByMe,
        isMine: isMine,
      );
}

class PostMedia {
  final String storagePath;
  final String? altText;
  final int? width;
  final int? height;

  const PostMedia({
    required this.storagePath,
    this.altText,
    this.width,
    this.height,
  });

  /// The picture's own shape, or null when it was uploaded before the
  /// uploader started recording dimensions.
  ///
  /// Null is deliberately not papered over with a default: the card uses it to
  /// decide whether to ask the decoded image for its size instead, and a
  /// made-up ratio would silently crop.
  double? get ratio {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  factory PostMedia.fromMap(Map<String, dynamic> map) => PostMedia(
        storagePath: map['storage_path'] as String,
        altText: map['alt_text'] as String?,
        width: (map['width'] as num?)?.toInt(),
        height: (map['height'] as num?)?.toInt(),
      );
}

class PostTopic {
  final String kind; // 'field' | 'country'
  final String value;

  const PostTopic({required this.kind, required this.value});

  bool get isCountry => kind == 'country';

  /// Countries resolve from the app's own list; fields need the vocabulary
  /// loaded from `fields_of_study`, so the caller supplies the label.
  String get countryLabel =>
      AppConstants.popularDestinations[value] ??
      AppConstants.homeCountries[value] ??
      value;

  factory PostTopic.fromMap(Map<String, dynamic> map) => PostTopic(
        kind: map['kind'] as String,
        value: map['value'] as String,
      );
}

/// A reply. Threaded one level, which is as deep as is readable on a phone.
class PostComment {
  final String id;
  final String? parentId;
  final String body;
  final int likeCount;
  final DateTime createdAt;
  final String authorHandle;
  final String authorName;
  final String? authorAvatar;
  final bool authorVerified;
  final bool liked;
  final bool isMine;

  const PostComment({
    required this.id,
    this.parentId,
    required this.body,
    this.likeCount = 0,
    required this.createdAt,
    required this.authorHandle,
    required this.authorName,
    this.authorAvatar,
    this.authorVerified = false,
    this.liked = false,
    this.isMine = false,
  });

  factory PostComment.fromMap(Map<String, dynamic> map) => PostComment(
        id: map['id'] as String,
        parentId: map['parent_id'] as String?,
        body: map['body'] as String,
        likeCount: (map['like_count'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        authorHandle: map['author_handle'] as String? ?? '',
        authorName: map['author_name'] as String? ?? '',
        authorAvatar: map['author_avatar'] as String?,
        authorVerified: map['author_verified'] as bool? ?? false,
        liked: map['liked'] as bool? ?? false,
        isMine: map['is_mine'] as bool? ?? false,
      );

  PostComment copyWith({
    String? id,
    String? parentId,
    String? body,
    int? likeCount,
    DateTime? createdAt,
    String? authorHandle,
    String? authorName,
    String? authorAvatar,
    bool? authorVerified,
    bool? liked,
    bool? isMine,
  }) =>
      PostComment(
        id: id ?? this.id,
        parentId: parentId ?? this.parentId,
        body: body ?? this.body,
        likeCount: likeCount ?? this.likeCount,
        createdAt: createdAt ?? this.createdAt,
        authorHandle: authorHandle ?? this.authorHandle,
        authorName: authorName ?? this.authorName,
        authorAvatar: authorAvatar ?? this.authorAvatar,
        authorVerified: authorVerified ?? this.authorVerified,
        liked: liked ?? this.liked,
        isMine: isMine ?? this.isMine,
      );
}

/// One tab across the top of the feed.
class FeedTab {
  final String label;
  final FeedKind kind;

  /// For a topic tab: 'field' or 'country', and the value.
  final String? topicKind;
  final String? topicValue;

  const FeedTab({
    required this.label,
    required this.kind,
    this.topicKind,
    this.topicValue,
  });
}

enum FeedKind { forYou, following, topic, kind, tagged }

/// A tagged institution or fellow student in a post.
class PostTag {
  final String handle;
  final String name;
  final bool isInstitution;

  const PostTag({
    required this.handle,
    required this.name,
    this.isInstitution = false,
  });

  factory PostTag.fromMap(Map<String, dynamic> map) => PostTag(
        handle: map['handle'] as String? ?? '',
        name: map['name'] as String? ?? '',
        isInstitution: map['is_institution'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'handle': handle,
        'name': name,
        'is_institution': isInstitution,
      };
}
