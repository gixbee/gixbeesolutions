// Gixbee 2026 — first *composed-screen* widget test (Pass 117).
//
// Every prior suite (`widget_test.dart`, `gx_widgets_extra_test.dart`,
// `gx_widgets_pure_test.dart`) covers the pure, dependency-free `gx_*` design
// widgets in isolation. This suite steps up to a real screen —
// `NotificationsScreen` — proving its three async branches
// (loading → skeletons, data → tiles, empty → GxEmptyState) render correctly.
//
// It is authored without any mock package (none is installed and none may be
// added): the screen is driven entirely by the public
// `notificationsProvider` (a `FutureProvider.autoDispose`), which we replace
// with a plain `ProviderScope` override — no Dio, no network, no repository.
// The screen's `initState` touches `FlutterSecureStorage`, but that call is
// wrapped in a try/catch, so the `MissingPluginException` thrown under the
// test harness is swallowed and never reaches the frame.
//
// NOTE ON PUMPING: while the provider is loading, the screen shows
// `GxSkeleton`s, which drive a `..repeat()` controller and therefore never
// settle. `pumpAndSettle` would time out on the loading frame, so this suite
// pumps explicit, bounded frames instead — never `pumpAndSettle`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/notifications/notifications_screen.dart';
import 'package:gixbee/shared/widgets/gx_empty.dart';
import 'package:gixbee/shared/widgets/gx_skeleton.dart';

/// Hosts the screen under a `ProviderScope` whose `notificationsProvider` is
/// replaced by [create]. A plain dark [ThemeData] is used (not `GixbeeTheme`)
/// so `Theme.of(context).colorScheme` resolves without pulling in google_fonts'
/// runtime font fetch.
Widget _host(FutureOr<List<AppNotification>> Function() create) => ProviderScope(
      overrides: [
        notificationsProvider.overrideWith((ref) => create()),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const NotificationsScreen(),
      ),
    );

AppNotification _notif(String id, String title, String body, String type) =>
    AppNotification(
      id: id,
      title: title,
      body: body,
      type: type,
      timestamp: DateTime(2026, 1, 1),
    );

void main() {
  group('NotificationsScreen', () {
    testWidgets('loading → renders skeleton placeholders, not tiles',
        (tester) async {
      // A future that never completes keeps the provider in AsyncLoading.
      final never = Completer<List<AppNotification>>();
      await tester.pumpWidget(_host(() => never.future));
      await tester.pump(); // build (loading branch)
      await tester.pump(const Duration(milliseconds: 300)); // skeleton frame

      expect(find.byType(GxSkeleton), findsWidgets);
      // Neither the empty state nor any data tile should be showing yet.
      expect(find.byType(GxEmptyState), findsNothing);
      expect(find.text('No notifications yet'), findsNothing);
    });

    testWidgets('data → renders one tile per visible notification',
        (tester) async {
      await tester.pumpWidget(_host(() async => [
            _notif('1_requested', 'New Booking Request', 'x needs help',
                'new_booking'),
            _notif('2_accepted', 'Booking Accepted', 'y accepted', 'booking_accepted'),
          ]));
      await tester.pump(); // loading
      await tester.pump(); // provider resolves → data branch
      await tester.pump(const Duration(milliseconds: 400)); // GxFade settles

      expect(find.text('New Booking Request'), findsOneWidget);
      expect(find.text('Booking Accepted'), findsOneWidget);
      // Each notification is swipe-to-dismiss.
      expect(find.byType(Dismissible), findsNWidgets(2));
      // The empty state must not appear when there is data.
      expect(find.byType(GxEmptyState), findsNothing);
    });

    testWidgets('empty → renders the GxEmptyState placeholder', (tester) async {
      await tester.pumpWidget(_host(() async => <AppNotification>[]));
      await tester.pump(); // loading
      await tester.pump(); // provider resolves → data branch (empty list)
      await tester.pump(const Duration(milliseconds: 400)); // GxFade settles

      expect(find.byType(GxEmptyState), findsOneWidget);
      expect(find.text('No notifications yet'), findsOneWidget);
      expect(find.text('Your booking updates will appear here.'), findsOneWidget);
      expect(find.byType(Dismissible), findsNothing);
    });

    testWidgets('AppBar shows the title and a Refresh action', (tester) async {
      await tester.pumpWidget(_host(() async => <AppNotification>[]));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.byTooltip('Refresh'), findsOneWidget);
    });
  });
}
