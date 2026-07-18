// Gixbee 2026 — widget tests for the remaining pure `gx_*` design-language
// surfaces that `widget_test.dart` did not yet cover: the loading skeletons,
// the content cross-fade, the glass container, and the glass dialog/toast
// helpers. Like the sibling suite, every widget exercised here is
// dependency-free (no providers, no network, no platform channels) so it
// renders deterministically under `flutter test`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/shared/widgets/gx_skeleton.dart';
import 'package:gixbee/shared/widgets/gx_fade.dart';
import 'package:gixbee/shared/widgets/glass_container.dart';
import 'package:gixbee/shared/widgets/gx_dialog.dart';
import 'package:gixbee/shared/widgets/gx_snackbar.dart';

/// Minimal host so `Theme.of(context)` resolves for the widgets that read it.
Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

/// Host that hands back a live `context` under a ScaffoldMessenger, with a
/// button that invokes [onOpen] — used to trigger the dialog/toast helpers.
Widget _trigger(void Function(BuildContext) onOpen) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => onOpen(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  group('GxSkeleton', () {
    // NOTE: GxSkeleton drives a `..repeat(reverse: true)` controller, so it
    // never settles — use `pump`, never `pumpAndSettle`, in this group.
    testWidgets('renders a single sized block', (tester) async {
      await tester.pumpWidget(
        _wrap(const GxSkeleton(width: 120, height: 16)),
      );
      await tester.pump();
      expect(find.byType(GxSkeleton), findsOneWidget);
    });

    testWidgets('pulses via a FadeTransition without throwing', (tester) async {
      await tester.pumpWidget(
        _wrap(const GxSkeleton(width: 80, height: 80, radius: 20)),
      );
      await tester.pump(const Duration(milliseconds: 450));
      // GxSkeleton pulses via a FadeTransition; a page route may add its own,
      // so assert at least one exists rather than exactly one.
      expect(find.byType(FadeTransition), findsWidgets);
    });
  });

  group('GxSkeletonStrip', () {
    testWidgets('builds `count` skeleton cards', (tester) async {
      await tester.pumpWidget(
        _wrap(const SizedBox(
          height: 90,
          child: GxSkeletonStrip(cardWidth: 100, cardHeight: 80, count: 3),
        )),
      );
      await tester.pump();
      expect(find.byType(GxSkeleton), findsNWidgets(3));
    });
  });

  group('GxFade', () {
    testWidgets('renders its child inside an AnimatedSwitcher', (tester) async {
      await tester.pumpWidget(
        _wrap(const GxFade(
          child: Text('content', key: ValueKey('data')),
        )),
      );
      await tester.pump();
      expect(find.byType(AnimatedSwitcher), findsOneWidget);
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('cross-fades to a new keyed child', (tester) async {
      await tester.pumpWidget(
        _wrap(const GxFade(
          child: Text('loading', key: ValueKey('loading')),
        )),
      );
      await tester.pump();
      expect(find.text('loading'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(const GxFade(
          child: Text('done', key: ValueKey('data')),
        )),
      );
      await tester.pumpAndSettle();
      expect(find.text('done'), findsOneWidget);
      expect(find.text('loading'), findsNothing);
    });
  });

  group('GlassContainer', () {
    testWidgets('renders its child behind a BackdropFilter', (tester) async {
      await tester.pumpWidget(
        _wrap(const GlassContainer(child: Text('glass')),
        ),
      );
      await tester.pump();
      expect(find.text('glass'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('showGxDialog', () {
    testWidgets('shows its title, message and fires the action onTap',
        (tester) async {
      var confirmed = 0;
      await tester.pumpWidget(_trigger((context) {
        showGxDialog(
          context,
          title: 'Delete item?',
          message: 'This cannot be undone.',
          actions: [
            GxDialogAction(
              'Confirm',
              isPrimary: true,
              onTap: () {
                confirmed++;
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      }));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Delete item?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(confirmed, 1);
      // Dialog dismissed → its title is gone.
      expect(find.text('Delete item?'), findsNothing);
    });
  });

  group('showGxSnack', () {
    testWidgets('shows a floating glass toast with the message',
        (tester) async {
      await tester.pumpWidget(_trigger((context) {
        showGxSnack(context, 'Saved!', type: GxSnackType.success);
      }));

      await tester.tap(find.text('open'));
      await tester.pump(); // schedule the snackbar
      await tester.pump(const Duration(milliseconds: 400)); // entrance frame
      expect(find.text('Saved!'), findsOneWidget);
    });
  });
}
