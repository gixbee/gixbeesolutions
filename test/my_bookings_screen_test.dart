// Gixbee 2026 — composed-screen widget test (Pass 118).
//
// Follows the ProviderScope-override pattern established by
// `notifications_screen_test.dart` (Pass 117): drive a real screen purely
// through its public, overridable provider — no mock package (none is
// installed and none may be added), no Dio, no network.
//
// `MyBookingsScreen`'s ACTIVE tab is driven entirely by the public
// `myBookingsProvider` (a `FutureProvider.autoDispose<List<dynamic>>`), which
// we replace with a plain `ProviderScope` override to exercise every async
// branch (loading → skeletons, data → cards, error → error list). The active
// booking card's `Consumer` reads `currentUserProvider`; we override it to
// resolve to `null` so no auth-token / profile network call is attempted.
//
// Only the ACTIVE tab (index 0) is built on the first frame: TabBarView lays
// its pages out in a PageView whose default 250px cache extent does not reach
// the full-width adjacent (Completed / Cancelled) pages, so their paginated
// `_loadPage` Dio calls never fire during these tests — no pending timers at
// teardown.
//
// NOTE ON PUMPING: while the provider is loading, the screen shows
// `GxSkeleton`s, which drive a `..repeat()` controller and therefore never
// settle. `pumpAndSettle` would time out on the loading frame, so this suite
// pumps explicit, bounded frames instead — never `pumpAndSettle`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/jobs/my_bookings_screen.dart';
import 'package:gixbee/repositories/auth_repository.dart';
import 'package:gixbee/repositories/booking_repository.dart';
import 'package:gixbee/shared/widgets/gx_skeleton.dart';

/// Hosts the screen under a `ProviderScope` whose `myBookingsProvider` is
/// replaced by [create]. `currentUserProvider` is overridden to `null` so the
/// active-booking card's `Consumer` reads a resolved value without any auth /
/// profile network call. A plain dark [ThemeData] is used (not `GixbeeTheme`)
/// so `Theme.of(context)` resolves without pulling in google_fonts' runtime
/// font fetch.
Widget _host(FutureOr<List<dynamic>> Function() create) => ProviderScope(
      overrides: [
        myBookingsProvider.overrideWith((ref) => create()),
        currentUserProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const MyBookingsScreen(),
      ),
    );

/// A minimal booking map shaped like the backend `/bookings/my` payload the
/// screen reads (`skill`, `status`, `totalAmount`, `scheduledAt`, `customer`).
/// The status values used here are all in the screen's ACTIVE filter set.
Map<String, dynamic> _booking(String id, String skill, String status, num amount) => {
      'id': id,
      'skill': skill,
      'status': status,
      'totalAmount': amount,
      'scheduledAt': '2026-07-01T10:00:00.000',
      'customer': {'name': 'Asha Kumar'},
    };

void main() {
  group('MyBookingsScreen', () {
    testWidgets('loading → renders skeleton placeholders, not the empty state',
        (tester) async {
      // A future that never completes keeps the provider in AsyncLoading.
      final never = Completer<List<dynamic>>();
      await tester.pumpWidget(_host(() => never.future));
      await tester.pump(); // build (loading branch)
      await tester.pump(const Duration(milliseconds: 300)); // skeleton frame

      expect(find.byType(GxSkeleton), findsWidgets);
      // The empty-state copy must not show while loading.
      expect(find.text('No active bookings found'), findsNothing);
    });

    testWidgets('data → renders one active card per booking', (tester) async {
      await tester.pumpWidget(_host(() async => [
            _booking('bk_0001', 'Plumbing', 'ACCEPTED', 1200),
            _booking('bk_0002', 'Cleaning', 'IN_PROGRESS', 850),
          ]));
      await tester.pump(); // loading
      await tester.pump(); // provider resolves → data branch
      await tester.pump(const Duration(milliseconds: 400)); // GxFade settles

      expect(find.text('Plumbing'), findsOneWidget);
      expect(find.text('Cleaning'), findsOneWidget);
      // Amounts render on the cards (formatted with a rupee sign).
      expect(find.textContaining('₹'), findsWidgets);
      // The empty state must not appear when there is active data.
      expect(find.text('No active bookings found'), findsNothing);
    });

    testWidgets('data with no ACTIVE-status bookings → shows the empty state',
        (tester) async {
      // COMPLETED is filtered out of the ACTIVE tab, so the list is empty.
      await tester.pumpWidget(_host(() async => [
            _booking('bk_9001', 'Painting', 'COMPLETED', 500),
          ]));
      await tester.pump(); // loading
      await tester.pump(); // data branch (filtered to empty)
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('No active bookings found'), findsOneWidget);
    });

    testWidgets('empty list → shows the empty state', (tester) async {
      await tester.pumpWidget(_host(() async => <dynamic>[]));
      await tester.pump(); // loading
      await tester.pump(); // data branch (empty)
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('No active bookings found'), findsOneWidget);
      // No booking service labels should be present.
      expect(find.text('Plumbing'), findsNothing);
    });

    testWidgets('error → renders the error list', (tester) async {
      await tester.pumpWidget(
          _host(() => Future<List<dynamic>>.error(StateError('boom'))));
      await tester.pump(); // loading
      await tester.pump(); // provider resolves → error branch
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Could not load bookings'), findsOneWidget);
    });

    testWidgets('AppBar shows the title and a Refresh action', (tester) async {
      await tester.pumpWidget(_host(() async => <dynamic>[]));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('My Bookings'), findsOneWidget);
      expect(find.byTooltip('Refresh'), findsOneWidget);
    });
  });
}
