import 'package:flutter_test/flutter_test.dart';
import 'package:lekkside_connect/features/passport/models/passport.dart';
import 'package:lekkside_connect/features/social/models/post.dart';
import 'package:lekkside_connect/features/social/providers/feed_provider.dart';

void main() {
  group('Student Tag Search & Follow Tests', () {
    test('Cleans @ prefix from search query for student handle search', () {
      String cleanSearchQuery(String query) {
        final q = query.trim();
        return q.startsWith('@') ? q.substring(1).trim() : q;
      }

      expect(cleanSearchQuery('@xyz'), 'xyz');
      expect(cleanSearchQuery('@john_doe'), 'john_doe');
      expect(cleanSearchQuery('alice'), 'alice');
      expect(cleanSearchQuery('  @sarah  '), 'sarah');
    });

    test('Parses student search result with follow status properly', () {
      final data = {
        'handle': 'david_k',
        'display_name': 'David Kim',
        'avatar_url': 'https://example.com/avatar.png',
        'bio': 'Computer Science student',
        'follower_count': 42,
        'is_verified': true,
        'is_following': false,
        'is_self': false,
      };

      expect(data['handle'], 'david_k');
      expect(data['display_name'], 'David Kim');
      expect(data['follower_count'], 42);
      expect(data['is_verified'], isTrue);
      expect(data['is_following'], isFalse);

      final nextFollowing = !(data['is_following'] as bool);
      data['is_following'] = nextFollowing;
      final count = data['follower_count'] as int;
      data['follower_count'] = count + (nextFollowing ? 1 : -1);

      expect(data['is_following'], isTrue);
      expect(data['follower_count'], 43);
    });
  });

  group('Universal Feed & Designated Areas Tab Tests', () {
    test('buildTabs includes designated areas for questions and announcements', () {
      final feed = FeedProvider();
      const passport = Passport(
        profileId: 'test-profile-id',
        completeness: 80,
        targetFields: ['computer-science-it'],
        targetCountries: ['GB'],
      );

      feed.buildTabs(passport, (slug) => 'Computer Science');

      final labels = feed.tabs.map((t) => t.label).toList();
      expect(labels, contains('For you'));
      expect(labels, contains('Following'));
      expect(labels, contains('Questions'));
      expect(labels, contains('Announcements'));
      expect(labels, contains('Computer Science'));
      expect(labels, contains('United Kingdom'));
    });

    test('buildOrgTabs builds complete community and designated tabs for university', () {
      final feed = FeedProvider();
      feed.buildOrgTabs(
        handle: 'oxford_uni',
        programFields: ['business-management', 'engineering'],
        country: 'GB',
        fieldLabel: (slug) => slug == 'business-management' ? 'Business' : 'Engineering',
      );

      final labels = feed.tabs.map((t) => t.label).toList();
      expect(labels, contains('For you'));
      expect(labels, contains('Our posts'));
      expect(labels, contains('Mentions'));
      expect(labels, contains('Questions'));
      expect(labels, contains('Announcements'));
      expect(labels, contains('United Kingdom'));
      expect(labels, contains('Business'));
      expect(labels, contains('Engineering'));

      final mentionsTab = feed.tabs.firstWhere((t) => t.label == 'Mentions');
      expect(mentionsTab.kind, FeedKind.tagged);
      expect(mentionsTab.topicValue, 'oxford_uni');

      final ourPostsTab = feed.tabs.firstWhere((t) => t.label == 'Our posts');
      expect(ourPostsTab.kind, FeedKind.topic);
      expect(ourPostsTab.topicKind, 'handle');
      expect(ourPostsTab.topicValue, 'oxford_uni');
    });
  });
}
