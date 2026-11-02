// A back arrow that does nothing is worse than no arrow.
//
// Flutter's `BackButton` calls `Navigator.maybePop()`, which silently ignores
// the tap when there is nothing to pop — and with go_router that is routine,
// because `context.go` replaces the stack. Four auth screens shipped with an
// arrow in exactly that state.
//
// No network: this pumps the widget against a two-route go_router.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:lekkside_connect/core/widgets/app_back_button.dart';

GoRouter routerFor({required bool replaceStack}) => GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => replaceStack
                    ? context.go('/detail')
                    : context.push('/detail'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/detail',
          builder: (_, __) => const Scaffold(
            appBar: null,
            body: Row(children: [
              AppBackButton(fallback: '/start'),
              Text('detail'),
            ]),
          ),
        ),
      ],
    );

void main() {
  testWidgets('pops when there is something to pop', (tester) async {
    await tester.pumpWidget(
        MaterialApp.router(routerConfig: routerFor(replaceStack: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);

    await tester.tap(find.byType(AppBackButton));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget, reason: 'it went back');
  });

  testWidgets('and still goes somewhere when the stack was replaced',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp.router(routerConfig: routerFor(replaceStack: true)));
    await tester.pumpAndSettle();

    // `go` replaces the stack, so there is nothing to pop. This is the case
    // where Flutter's own BackButton does nothing at all.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);

    await tester.tap(find.byType(AppBackButton));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget,
        reason: 'with an empty stack it must fall back, not sit there '
            'ignoring taps');
  });

  testWidgets('Flutter\'s BackButton is the thing that fails here',
      (tester) async {
    // Guards the reason this widget exists: if a future Flutter makes
    // BackButton fall back on its own, this test fails and the widget can go.
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.go('/detail'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/detail',
          builder: (_, __) => const Scaffold(
            body: Row(children: [BackButton(), Text('detail')]),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('detail'), findsOneWidget,
        reason: 'the stock BackButton swallows the tap on an empty stack — '
            'which is the bug AppBackButton exists to fix');
  });
}
