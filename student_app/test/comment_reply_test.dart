import 'package:flutter_test/flutter_test.dart';
import 'package:lekkside_connect/features/social/models/post.dart';

void main() {
  group('PostComment model & threading tests', () {
    test('PostComment instantiates and copyWith works properly', () {
      final comment = PostComment(
        id: 'comment-1',
        parentId: null,
        body: 'First comment on post',
        likeCount: 3,
        createdAt: DateTime(2026, 1, 1),
        authorHandle: 'alice',
        authorName: 'Alice Johnson',
        authorAvatar: null,
        authorVerified: true,
        liked: false,
        isMine: true,
      );

      expect(comment.id, 'comment-1');
      expect(comment.parentId, isNull);
      expect(comment.likeCount, 3);
      expect(comment.liked, isFalse);

      final updated = comment.copyWith(
        liked: true,
        likeCount: 4,
      );

      expect(updated.id, 'comment-1');
      expect(updated.liked, isTrue);
      expect(updated.likeCount, 4);
      expect(updated.authorHandle, 'alice');
    });

    test('Comment hierarchy correctly groups root comments and nested replies', () {
      final now = DateTime.now();
      final comments = [
        PostComment(
          id: 'c1',
          parentId: null,
          body: 'Root comment 1',
          createdAt: now.subtract(const Duration(hours: 3)),
          authorHandle: 'user1',
          authorName: 'User One',
        ),
        PostComment(
          id: 'c2',
          parentId: null,
          body: 'Root comment 2',
          createdAt: now.subtract(const Duration(hours: 2)),
          authorHandle: 'user2',
          authorName: 'User Two',
        ),
        PostComment(
          id: 'r1_1',
          parentId: 'c1',
          body: 'Reply to root comment 1',
          createdAt: now.subtract(const Duration(hours: 1)),
          authorHandle: 'user3',
          authorName: 'User Three',
        ),
        PostComment(
          id: 'r1_2',
          parentId: 'c1',
          body: 'Another reply to root comment 1',
          createdAt: now.subtract(const Duration(minutes: 30)),
          authorHandle: 'user4',
          authorName: 'User Four',
        ),
      ];

      // Separate root comments
      final rootComments = comments
          .where((c) =>
              c.parentId == null ||
              !comments.any((parent) => parent.id == c.parentId))
          .toList();

      expect(rootComments.length, 2);
      expect(rootComments.map((c) => c.id), containsAll(['c1', 'c2']));

      // Group replies by parentId
      final repliesByParent = <String, List<PostComment>>{};
      for (final c in comments) {
        if (c.parentId != null && comments.any((p) => p.id == c.parentId)) {
          repliesByParent.putIfAbsent(c.parentId!, () => []).add(c);
        }
      }

      expect(repliesByParent['c1']?.length, 2);
      expect(repliesByParent['c1']?.map((r) => r.id), ['r1_1', 'r1_2']);
      expect(repliesByParent['c2'], isNull);
    });

    test('Replying to a reply flattens parentId to thread root', () {
      final now = DateTime.now();
      final rootComment = PostComment(
        id: 'root-100',
        parentId: null,
        body: 'Root topic',
        createdAt: now,
        authorHandle: 'root_user',
        authorName: 'Root User',
      );

      final replyComment = PostComment(
        id: 'reply-200',
        parentId: 'root-100',
        body: 'First response',
        createdAt: now.add(const Duration(minutes: 5)),
        authorHandle: 'responder',
        authorName: 'Responder User',
      );

      // When replying to a top-level comment:
      final targetParentForRoot = rootComment.parentId ?? rootComment.id;
      expect(targetParentForRoot, 'root-100');

      // When replying to a reply, parentId flattens to the root thread ID:
      final targetParentForReply = replyComment.parentId ?? replyComment.id;
      expect(targetParentForReply, 'root-100');
    });
  });
}
