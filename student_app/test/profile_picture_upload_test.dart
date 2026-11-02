import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lekkside_connect/core/widgets/institution_avatar.dart';
import 'package:lekkside_connect/core/widgets/user_avatar.dart';
import 'package:lekkside_connect/core/utils/profile_photo_sheet.dart';
import 'package:lekkside_connect/features/auth/models/app_user.dart';

void main() {
  group('AppUser avatar tests', () {
    test('copyWith updates and clears avatarUrl', () {
      final user = AppUser(
        id: '123',
        role: 'student',
        fullName: 'Jane Doe',
        avatarUrl: 'https://example.com/avatar.jpg',
        createdAt: DateTime.now(),
      );

      final updated = user.copyWith(avatarUrl: 'https://example.com/new_avatar.jpg');
      expect(updated.avatarUrl, 'https://example.com/new_avatar.jpg');

      final cleared = updated.copyWith(clearAvatar: true);
      expect(cleared.avatarUrl, isNull);
    });
  });

  group('ProfilePhotoResult', () {
    test('picked creates valid payload', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final res = ProfilePhotoResult.picked(
        bytes: bytes,
        fileName: 'avatar.png',
        mimeType: 'image/png',
      );
      expect(res.isRemoved, isFalse);
      expect(res.bytes, bytes);
      expect(res.fileName, 'avatar.png');
      expect(res.mimeType, 'image/png');
    });

    test('removed creates removal payload', () {
      final res = ProfilePhotoResult.removed();
      expect(res.isRemoved, isTrue);
      expect(res.bytes, isNull);
    });
  });

  group('UserAvatar widget', () {
    testWidgets('renders initials when no avatarUrl', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              avatarUrl: null,
              initials: 'JD',
            ),
          ),
        ),
      );

      expect(find.text('JD'), findsOneWidget);
    });

    testWidgets('renders edit button when onEdit is provided', (tester) async {
      bool edited = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              avatarUrl: null,
              initials: 'JD',
              onEdit: () => edited = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.photo_camera_rounded));
      expect(edited, isTrue);
    });

    testWidgets('shows loading spinner when isBusy', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              avatarUrl: null,
              initials: 'JD',
              isBusy: true,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('InstitutionAvatar widget', () {
    testWidgets('renders initials when no logoUrl', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InstitutionAvatar(
              logoUrl: null,
              initials: 'OX',
            ),
          ),
        ),
      );

      expect(find.text('OX'), findsOneWidget);
    });

    testWidgets('renders edit badge when onEdit provided', (tester) async {
      bool edited = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InstitutionAvatar(
              logoUrl: null,
              initials: 'OX',
              onEdit: () => edited = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.photo_camera_rounded));
      expect(edited, isTrue);
    });
  });
}
