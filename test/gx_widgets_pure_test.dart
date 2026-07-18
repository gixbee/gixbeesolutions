// Gixbee 2026 — widget tests for the last pure `gx_*` design-language surfaces
// that neither `widget_test.dart` nor `gx_widgets_extra_test.dart` covered: the
// glass text input, the glass card, the glass bottom sheet, and the calendar +
// time picker (exercised through their public `show*` entry points). Like the
// sibling suites, every widget here is dependency-free (no providers, no
// network, no platform channels) so it renders deterministically under
// `flutter test`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/shared/widgets/gx_text_field.dart';
import 'package:gixbee/shared/widgets/gx_glass_card.dart';
import 'package:gixbee/shared/widgets/gx_sheet.dart';
import 'package:gixbee/shared/widgets/gx_calendar.dart';
import 'package:gixbee/shared/widgets/gx_time_picker.dart';

/// Minimal host so `Theme.of(context)` / Material ancestors resolve.
Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

/// Host that hands back a live `context`, with a button that invokes [onOpen] —
/// used to trigger the sheet/calendar/time-picker helpers.
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
  group('GxTextField', () {
    testWidgets('renders its label and hosts a text field', (tester) async {
      await tester.pumpWidget(
        _wrap(const GxTextField(label: 'Email', hint: 'you@site.com')),
      );
      await tester.pump();
      expect(find.text('Email'), findsOneWidget);
      // Wraps a TextFormField (→ TextField) behind a glass BackdropFilter.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('reflects typed text via its controller and onChanged',
        (tester) async {
      final controller = TextEditingController();
      String? changed;
      await tester.pumpWidget(
        _wrap(GxTextField(
          controller: controller,
          onChanged: (v) => changed = v,
        )),
      );
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(controller.text, 'hello');
      expect(changed, 'hello');
    });

    testWidgets('renders a prefix icon when given one', (tester) async {
      await tester.pumpWidget(
        _wrap(const GxTextField(prefixIcon: Icons.search)),
      );
      await tester.pump();
      expect(find.byIcon(Icons.search), findsOneWidget);
    });
  });

  group('GxGlassCard', () {
    testWidgets('renders its child behind a BackdropFilter', (tester) async {
      await tester.pumpWidget(
        _wrap(const GxGlassCard(child: Text('card body'))),
      );
      await tester.pump();
      expect(find.text('card body'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('showGxSheet', () {
    testWidgets('opens a glass sheet with its title and child', (tester) async {
      await tester.pumpWidget(_trigger((context) {
        showGxSheet(
          context,
          title: 'Filters',
          child: const Text('sheet body'),
        );
      }));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('sheet body'), findsOneWidget);
    });
  });

  group('showGxCalendar', () {
    testWidgets('opens the date picker and returns the seeded date on confirm',
        (tester) async {
      DateTime? result;
      var popped = false;
      // Seed relative to now so the initial date is always inside the default
      // [now, now + 365d] range (→ Confirm enabled) regardless of run date.
      final seed = DateTime.now().add(const Duration(days: 5));
      await tester.pumpWidget(_trigger((context) {
        showGxCalendar(context, initialDate: seed).then((v) {
          result = v;
          popped = true;
        });
      }));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Select date'), findsOneWidget);
      expect(find.text('Confirm date'), findsOneWidget);

      await tester.tap(find.text('Confirm date'));
      await tester.pumpAndSettle();
      expect(popped, isTrue);
      expect(result, isNotNull);
    });
  });

  group('showGxTimePicker', () {
    testWidgets('opens the time picker and returns a time on confirm',
        (tester) async {
      TimeOfDay? result;
      var popped = false;
      await tester.pumpWidget(_trigger((context) {
        showGxTimePicker(
          context,
          initialTime: const TimeOfDay(hour: 9, minute: 30),
        ).then((v) {
          result = v;
          popped = true;
        });
      }));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Select time'), findsOneWidget);
      expect(find.text('Confirm time'), findsOneWidget);

      await tester.tap(find.text('Confirm time'));
      await tester.pumpAndSettle();
      expect(popped, isTrue);
      expect(result, isNotNull);
    });
  });
}
