import 'package:flutter_test/flutter_test.dart';
import 'package:lekkside_connect/features/notifications/models/app_notification.dart';
import 'package:lekkside_connect/features/social/models/post.dart';
import 'package:lekkside_connect/features/social/screens/tag_sheet.dart';

void main() {
  group('PostTag model tests', () {
    test('PostTag fromMap and toMap work properly', () {
      final tag = PostTag.fromMap({
        'handle': 'oxford_uni',
        'name': 'University of Oxford',
        'is_institution': true,
      });

      expect(tag.handle, 'oxford_uni');
      expect(tag.name, 'University of Oxford');
      expect(tag.isInstitution, isTrue);

      final map = tag.toMap();
      expect(map['handle'], 'oxford_uni');
      expect(map['name'], 'University of Oxford');
      expect(map['is_institution'], isTrue);
    });

    test('Post parses tags from JSON response', () {
      final post = Post.fromMap({
        'id': 'post-1',
        'kind': 'question',
        'body': 'Thinking of studying CS here!',
        'created_at': DateTime.now().toIso8601String(),
        'author_handle': 'john_doe',
        'author_name': 'John Doe',
        'tags': [
          {
            'handle': 'oxford_uni',
            'name': 'University of Oxford',
            'is_institution': true,
          },
          {
            'handle': 'sarah_smith',
            'name': 'Sarah Smith',
            'is_institution': false,
          },
        ],
      });

      expect(post.tags.length, 2);
      expect(post.tags.first.handle, 'oxford_uni');
      expect(post.tags.first.isInstitution, isTrue);
      expect(post.tags.last.handle, 'sarah_smith');
      expect(post.tags.last.isInstitution, isFalse);
    });
  });

  group('TaggedAccount tests', () {
    test('TaggedAccount equality is case-insensitive on handle', () {
      const a = TaggedAccount(handle: 'Oxford_Uni', name: 'Oxford');
      const b = TaggedAccount(handle: 'oxford_uni', name: 'University of Oxford');
      const c = TaggedAccount(handle: 'cambridge_uni', name: 'Cambridge');

      expect(a, equals(b));
      expect(a == c, isFalse);
      expect({a, b}.length, 1);
    });
  });

  group('AppNotification post_tagged deep link', () {
    test('post_tagged notification links to the specific post', () {
      final notif = AppNotification(
        id: 'notif-1',
        kind: 'post_tagged',
        title: 'John tagged you',
        body: 'John tagged you in a post',
        payload: {'post_id': 'post-456', 'author_handle': 'john'},
        createdAt: DateTime.now(),
      );

      expect(notif.deepLinkTarget, '/post/post-456');
    });

    test('post_tagged notification falls back to /feed if no post_id', () {
      final notif = AppNotification(
        id: 'notif-2',
        kind: 'post_tagged',
        title: 'John tagged you',
        createdAt: DateTime.now(),
      );

      expect(notif.deepLinkTarget, '/feed');
    });
  });
}
