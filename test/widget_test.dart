// Gixbee 2026 — widget tests for the shared `gx_*` design-language widgets.
//
// These replace the default Flutter "counter increments" starter test, which
// referenced a counter UI that GixbeeApp never had (so it could never pass).
// The widgets exercised here are pure and dependency-free — no providers, no
// network, no platform channels — so they render deterministically under
// `flutter test`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/shared/widgets/gx_button.dart';
import 'package:gixbee/shared/widgets/gx_pressable.dart';
import 'package:gixbee/shared/widgets/gx_empty.dart';
import 'package:gixbee/theme.dart';

/// Minimal host so `Theme.of(context)` (used by GxEmptyState) resolves.
Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('GxButton', () {
    testWidgets('renders its label', (tester) async {
      await tester.pumpWidget(_wrap(GxButton(label: 'Continue', onTap: () {})));
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('fires onTap when enabled', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(GxButton(label: 'Continue', onTap: () => taps++)),
      );
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('shows a spinner and hides the label while loading', (tester) async {
      await tester.pumpWidget(
        _wrap(GxButton(label: 'Saving', onTap: () {}, loading: true)),
      );
      expect(find.text('Saving'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('does not fire onTap while loading', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(GxButton(label: 'Saving', onTap: () => taps++, loading: true)),
      );
      await tester.tap(find.byType(GxButton), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('disabled (null onTap) renders and does not throw on tap', (tester) async {
      await tester.pumpWidget(
        _wrap(const GxButton(label: 'Disabled', onTap: null)),
      );
      await tester.tap(find.byType(GxButton), warnIfMissed: false);
      await tester.pump();
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('renders a leading icon when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(GxButton(
          label: 'Next',
          icon: Icons.arrow_forward,
          onTap: () {},
        )),
      );
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });

    testWidgets('outline variant with a quad accent still renders its label', (tester) async {
      await tester.pumpWidget(
        _wrap(GxButton(
          label: 'Cancel',
          filled: false,
          accent: GixbeeTheme.accentBlue,
          onTap: () {},
        )),
      );
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('GxPressable', () {
    testWidgets('renders its child and fires onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(GxPressable(onTap: () => taps++, child: const Text('tap me'))),
      );
      expect(find.text('tap me'), findsOneWidget);
      await tester.tap(find.text('tap me'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('null onTap does not throw when tapped', (tester) async {
      await tester.pumpWidget(
        _wrap(const GxPressable(onTap: null, child: Text('static'))),
      );
      await tester.tap(find.text('static'));
      await tester.pump();
      expect(find.text('static'), findsOneWidget);
    });
  });

  group('GxEmptyState', () {
    testWidgets('renders its icon, title and message', (tester) async {
      await tester.pumpWidget(
        _wrap(const GxEmptyState(
          icon: Icons.inbox_outlined,
          title: 'Nothing here',
          message: 'You have no items yet.',
        )),
      );
      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text('You have no items yet.'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    });

    testWidgets('shows and fires the CTA when actionLabel + onAction are given', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(GxEmptyState(
          icon: Icons.search_off,
          title: 'No results',
          actionLabel: 'Refresh',
          onAction: () => taps++,
        )),
      );
      expect(find.text('Refresh'), findsOneWidget);
      await tester.tap(find.text('Refresh'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('omits the CTA pill when no action is provided', (tester) async {
      await tester.pumpWidget(
        _wrap(const GxEmptyState(
          icon: Icons.inbox_outlined,
          title: 'Empty',
        )),
      );
      // The only GxPressable in GxEmptyState is the CTA pill.
      expect(find.byType(GxPressable), findsNothing);
    });
  });
}
