import 'package:flutter_test/flutter_test.dart';
import 'package:lekkside_connect/features/meet/models/call_grant.dart';
import 'package:lekkside_connect/features/meet/models/room_protocol.dart';
import 'package:lekkside_connect/features/meet/models/space.dart';

void main() {
  group('Space model & status checks', () {
    test('isOver correctly identifies ended and cancelled spaces', () {
      final scheduled = Space(
        id: '1',
        institutionId: 'inst-1',
        title: 'Admissions hour',
        kind: 'admissions_hour',
        status: 'scheduled',
        scheduledFor: DateTime.now().add(const Duration(hours: 1)),
        durationMin: 45,
        maxParticipants: 100,
        requiresAdmission: false,
        hostProfileId: 'host-1',
      );
      expect(scheduled.isScheduled, isTrue);
      expect(scheduled.isLive, isFalse);
      expect(scheduled.isOver, isFalse);

      final live = Space(
        id: '2',
        institutionId: 'inst-1',
        title: 'Live Briefing',
        kind: 'open_day',
        status: 'live',
        scheduledFor: DateTime.now(),
        durationMin: 30,
        maxParticipants: 100,
        requiresAdmission: false,
        hostProfileId: 'host-1',
      );
      expect(live.isLive, isTrue);
      expect(live.isScheduled, isFalse);
      expect(live.isOver, isFalse);

      final ended = Space(
        id: '3',
        institutionId: 'inst-1',
        title: 'Past Q&A',
        kind: 'scholarship_qa',
        status: 'ended',
        scheduledFor: DateTime.now().subtract(const Duration(hours: 2)),
        durationMin: 60,
        maxParticipants: 100,
        requiresAdmission: false,
        hostProfileId: 'host-1',
      );
      expect(ended.isLive, isFalse);
      expect(ended.isScheduled, isFalse);
      expect(ended.isOver, isTrue);

      final cancelled = Space(
        id: '4',
        institutionId: 'inst-1',
        title: 'Cancelled Tour',
        kind: 'campus_tour',
        status: 'cancelled',
        scheduledFor: DateTime.now().subtract(const Duration(days: 1)),
        durationMin: 30,
        maxParticipants: 100,
        requiresAdmission: false,
        hostProfileId: 'host-1',
      );
      expect(cancelled.isOver, isTrue);
    });

    test('Spaces list partitioning into active vs history', () {
      final list = [
        Space(
          id: '1',
          institutionId: 'inst-1',
          title: 'Upcoming',
          kind: 'admissions_hour',
          status: 'scheduled',
          scheduledFor: DateTime.now().add(const Duration(hours: 1)),
          durationMin: 45,
          maxParticipants: 100,
          requiresAdmission: false,
          hostProfileId: 'host-1',
        ),
        Space(
          id: '2',
          institutionId: 'inst-1',
          title: 'Live Now',
          kind: 'open_day',
          status: 'live',
          scheduledFor: DateTime.now(),
          durationMin: 30,
          maxParticipants: 100,
          requiresAdmission: false,
          hostProfileId: 'host-1',
        ),
        Space(
          id: '3',
          institutionId: 'inst-1',
          title: 'Ended Space',
          kind: 'scholarship_qa',
          status: 'ended',
          scheduledFor: DateTime.now().subtract(const Duration(hours: 2)),
          durationMin: 60,
          maxParticipants: 100,
          requiresAdmission: false,
          hostProfileId: 'host-1',
        ),
      ];

      final liveList = list.where((s) => s.isLive).toList();
      final upcomingList = list.where((s) => s.isScheduled).toList();
      final historyList = list.where((s) => s.isOver).toList();

      expect(liveList.length, 1);
      expect(liveList.first.id, '2');

      expect(upcomingList.length, 1);
      expect(upcomingList.first.id, '1');

      expect(historyList.length, 1);
      expect(historyList.first.id, '3');
      expect(historyList.first.title, 'Ended Space');
    });
  });

  group('Room roles', () {
    // The whole point of the `moderator` role is that it is NOT staff: it
    // carries the mute buttons and none of the institution's visibility.
    test('a moderator moderates but is not staff', () {
      expect(RoomProtocol.moderatorRoles, contains('moderator'));
      expect(RoomProtocol.staffRoles, isNot(contains('moderator')));

      const moderator = CallGrant(admission: 'admitted', role: 'moderator');
      expect(moderator.canModerate, isTrue);
      expect(moderator.isStaff, isFalse);
    });

    test('staff are both, and a speaker is neither', () {
      for (final role in ['host', 'cohost']) {
        final grant = CallGrant(admission: 'admitted', role: role);
        expect(grant.canModerate, isTrue, reason: role);
        expect(grant.isStaff, isTrue, reason: role);
      }
      for (final role in ['speaker', 'listener']) {
        final grant = CallGrant(admission: 'admitted', role: role);
        expect(grant.canModerate, isFalse, reason: role);
        expect(grant.isStaff, isFalse, reason: role);
      }
    });
  });
}
