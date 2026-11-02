// The Apple-design work, held in place.
//
// These are widget tests with no network: they pump the primitives directly,
// so they run anywhere and say something specific. Each one guards a rule from
// the apple-design skill that the app previously broke outright.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lekkside_connect/core/theme/app_theme.dart';
import 'package:lekkside_connect/core/utils/dynamic_type.dart';
import 'package:lekkside_connect/core/widgets/custom_button.dart';
import 'package:lekkside_connect/core/widgets/material_surface.dart';
import 'package:lekkside_connect/core/widgets/pressable.dart';

Widget host(
  Widget child, {
  double textScale = 1.0,
  bool reduceMotion = false,
  bool highContrast = false,
}) =>
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
          highContrast: highContrast,
        ),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  group('§1 response — feedback on press, not release', () {
    testWidgets('the control yields the instant it is touched', (tester) async {
      await tester.pumpWidget(host(Pressable(onTap: () {}, child: const Text('Tap'))));

      // The x entry, not `getMaxScaleOnAxis()`. `Transform.scale` scales x and
      // y and leaves z at 1, so the "max scale on axis" of a shrinking control
      // is always 1.0 — the measurement reports no press however hard you
      // press.
      double scaleOf() => tester
          .widget<Transform>(
            find.ancestor(
              of: find.text('Tap'),
              matching: find.byType(Transform),
            ).first,
          )
          .transform
          .entry(0, 0);

      expect(scaleOf(), closeTo(1.0, 0.001), reason: 'at rest');

      // Touch down only — no release.
      final gesture = await tester.startGesture(tester.getCenter(find.text('Tap')));
      // One frame to deliver the pointer, a second to advance the clock: the
      // first pump only dispatches the event, so the press has not yet had a
      // frame to render into.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      expect(scaleOf(), lessThan(1.0),
          reason: 'the press must show before the finger lifts');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(scaleOf(), closeTo(1.0, 0.01), reason: 'and spring back after');
    });

    testWidgets('sliding away cancels it', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
          host(Pressable(onTap: () => taps++, child: const Text('Tap'))));

      final gesture = await tester.startGesture(tester.getCenter(find.text('Tap')));
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.moveBy(const Offset(0, 300)); // drag away
      await gesture.up();
      await tester.pumpAndSettle();

      expect(taps, 0, reason: 'dragging off a control must cancel it');
    });
  });

  group('§13 haptics — on the causal event', () {
    testWidgets('a press plays a tick, and silence is opt-in', (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate' ||
              call.method.startsWith('HapticFeedback')) {
            calls.add(call.arguments?.toString() ?? call.method);
          }
          return null;
        },
      );

      await tester.pumpWidget(host(Pressable(onTap: () {}, child: const Text('A'))));
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(calls, isNotEmpty, reason: 'a tap should be felt');

      calls.clear();
      await tester.pumpWidget(
          host(Pressable(onTap: () {}, haptic: null, child: const Text('B'))));
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty,
          reason: 'haptic: null means silent — over-feedback trains people to '
              'ignore all of it');
    });
  });

  group('§14 reduced motion — gentler, never absent', () {
    testWidgets('the press does not move, but still registers', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(
        Pressable(onTap: () => taps++, child: const Text('Tap')),
        reduceMotion: true,
      ));

      // No Transform is inserted at all when motion is reduced.
      expect(
        find.ancestor(of: find.text('Tap'), matching: find.byType(Transform)),
        findsNothing,
      );

      await tester.tap(find.text('Tap'));
      await tester.pumpAndSettle();
      expect(taps, 1, reason: 'reduced motion must not mean reduced function');
    });
  });

  group('§15 typography — tracking and leading are size-specific', () {
    testWidgets('large text is tracked tighter than small', (tester) async {
      late TextTheme type;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(builder: (context) {
          type = Theme.of(context).textTheme;
          return const SizedBox();
        }),
      ));

      // Display sizes pull in; label sizes push out. A single value for both
      // is wrong at one end or the other.
      expect(type.displayLarge!.letterSpacing, lessThan(0));
      expect(type.displaySmall!.letterSpacing, lessThan(0));
      expect(type.labelSmall!.letterSpacing, greaterThan(0));

      // Monotonic through the scale, rather than two arbitrary ends.
      expect(type.displayLarge!.letterSpacing!,
          lessThan(type.displaySmall!.letterSpacing!));
      expect(type.headlineSmall!.letterSpacing!,
          lessThan(type.titleSmall!.letterSpacing!));

      // Leading runs the other way: tight on headings, open on body.
      expect(type.displayLarge!.height!, lessThan(type.bodyLarge!.height!));
      expect(type.bodyLarge!.height!, greaterThanOrEqualTo(1.4));
    });

    testWidgets('every style in the scale sets both', (tester) async {
      late TextTheme type;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(builder: (context) {
          type = Theme.of(context).textTheme;
          return const SizedBox();
        }),
      ));

      final styles = <String, TextStyle?>{
        'displayLarge': type.displayLarge,
        'displayMedium': type.displayMedium,
        'displaySmall': type.displaySmall,
        'headlineLarge': type.headlineLarge,
        'headlineMedium': type.headlineMedium,
        'headlineSmall': type.headlineSmall,
        'titleLarge': type.titleLarge,
        'titleMedium': type.titleMedium,
        'titleSmall': type.titleSmall,
        'bodyLarge': type.bodyLarge,
        'bodyMedium': type.bodyMedium,
        'bodySmall': type.bodySmall,
        'labelLarge': type.labelLarge,
        'labelMedium': type.labelMedium,
        'labelSmall': type.labelSmall,
      };

      for (final entry in styles.entries) {
        expect(entry.value?.letterSpacing, isNotNull,
            reason: '${entry.key} has no tracking');
        expect(entry.value?.height, isNotNull,
            reason: '${entry.key} has no leading');
      }
    });
  });

  group('Dynamic Type — the layout grows with the text', () {
    testWidgets('a button gets taller as text does', (tester) async {
      await tester.pumpWidget(host(const CustomButton(label: 'Continue')));
      final atDefault = tester.getSize(find.byType(CustomButton)).height;

      await tester.pumpWidget(
          host(const CustomButton(label: 'Continue'), textScale: 1.6));
      await tester.pumpAndSettle();
      final atLarge = tester.getSize(find.byType(CustomButton)).height;

      expect(atLarge, greaterThan(atDefault),
          reason: 'a fixed 54pt box around scaled text clips it');
    });

    testWidgets('but stops growing before it becomes absurd', (tester) async {
      late double scale;
      await tester.pumpWidget(host(
        Builder(builder: (context) {
          scale = context.layoutScale;
          return const SizedBox();
        }),
        textScale: 3.0,
      ));

      expect(scale, 1.6,
          reason: 'spacing is clamped even though the type keeps scaling — a '
              'button three times its height helps nobody');
    });

    testWidgets('and the accessibility threshold is reported', (tester) async {
      late bool large;
      await tester.pumpWidget(host(
        Builder(builder: (context) {
          large = context.isLargeText;
          return const SizedBox();
        }),
        textScale: 1.4,
      ));
      expect(large, isTrue);
    });
  });

  group('§12 materials — translucency, and when to drop it', () {
    testWidgets('chrome is a blurred layer by default', (tester) async {
      await tester.pumpWidget(host(
        const MaterialSurface(child: SizedBox(height: 50, width: 200)),
      ));
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('and goes solid under Increase Contrast', (tester) async {
      await tester.pumpWidget(host(
        const MaterialSurface(child: SizedBox(height: 50, width: 200)),
        highContrast: true,
      ));
      expect(find.byType(BackdropFilter), findsNothing,
          reason: 'a weak blur is the worst of both — drop it entirely');
    });
  });
}
