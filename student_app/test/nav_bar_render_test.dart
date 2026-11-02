// How the floating capsule degrades.
//
// Three settings can break it in ways that are invisible until someone with
// them turned on opens the app: Increase Contrast (which must drop both the
// blur and the gradient), the largest text size (which must not overflow five
// tabs out of a narrowed capsule), and the collapsed state (same, with less
// room).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lekkside_connect/core/theme/app_theme.dart';
import 'package:lekkside_connect/features/shell/widgets/floating_nav_bar.dart';

Future<void> pumpBar(
  WidgetTester tester, {
  double collapse = 0,
  double textScale = 1.0,
  bool highContrast = false,
  ThemeData? theme,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AppTheme.darkTheme,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          highContrast: highContrast,
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: FloatingNavBar(
              currentIndex: 0,
              onTap: (_) {},
              badges: const {3: 4, 4: 128},
              collapse: collapse,
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the capsule is glass by default', (tester) async {
    await pumpBar(tester);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(ShaderMask), findsOneWidget,
        reason: 'the active glyph carries the brand gradient');
  });

  testWidgets('Increase Contrast drops both the blur and the gradient — a '
      'washed-out ramp is the worst of both', (tester) async {
    await pumpBar(tester, highContrast: true);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('it never overflows', () {
    for (final collapse in [0.0, 1.0]) {
      for (final scale in [1.0, 1.6, 3.0]) {
        testWidgets(
            'collapse=$collapse at text scale $scale',
            (tester) async {
          await pumpBar(tester, collapse: collapse, textScale: scale);
          expect(tester.takeException(), isNull,
              reason: 'five tabs must fit the capsule at its narrowest');
        });
      }
    }

    testWidgets('and not on a narrow phone either', (tester) async {
      await pumpBar(tester,
          collapse: 1, textScale: 1.6, size: const Size(320, 568));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('collapsing narrows the capsule rather than hiding it, so all '
      'five tabs stay reachable while you read', (tester) async {
    await pumpBar(tester, collapse: 0);
    // The ClipRRect is the capsule's own box — MaterialSurface clips the blur
    // to it, so its size is the capsule's size.
    final expanded = tester.getSize(find.byType(ClipRRect).first);
    await pumpBar(tester, collapse: 1);
    final compact = tester.getSize(find.byType(ClipRRect).first);

    expect(compact.width, lessThan(expanded.width));
    expect(compact.height, lessThan(expanded.height));
    expect(compact.width, greaterThan(0));

    // Still five, still tappable.
    expect(find.byType(Semantics, skipOffstage: false), findsWidgets);
    for (final label in ['Feed', 'Search', 'Spaces']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
  });

  testWidgets('badges stay on the tabs that own them', (tester) async {
    await pumpBar(tester);
    expect(find.bySemanticsLabel('Notifications, 4 unread'), findsOneWidget);
    expect(find.bySemanticsLabel('Messages, 128 unread'), findsOneWidget);
  });
}
