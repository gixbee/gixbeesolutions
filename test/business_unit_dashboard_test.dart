// Gixbee 2026 — composed-screen widget test (Pass 121).
//
// Continues the ProviderScope-override pattern established by
// `notifications_screen_test.dart` (Pass 117) and extended through
// MyBookings / WorkerList / MessagesList (Passes 118–120): drive a real
// screen purely through its public, overridable provider — no mock package
// (none is installed and none may be added), no Dio, no network.
//
// `BusinessUnitDashboard` (My Businesses, the accentBlue business hub reached
// from Profile) is driven entirely by the public `myBusinessesProvider`
// (a `FutureProvider.autoDispose<List<Business>>`, declared at the top of
// `business_unit_dashboard.dart`), which we replace with a plain
// `ProviderScope` override to exercise every async branch:
//   loading → GxSkeletons, data → per-business bento cards,
//   empty → GxEmptyState 'No businesses yet',
//   error → GxEmptyState "Couldn't load your businesses".
//
// The data-branch card (`_BusinessCard`) renders purely from the `Business`
// model — its `ref` is only used inside onTap callbacks (calendar / operators
// sheets), never on build — so no secondary provider override is needed and no
// network fires during layout. `_BizAction` / `_StatusChip` are plain
// StatelessWidgets.
//
// NOTE ON PUMPING: while the provider is loading, the screen shows
// `GxSkeleton`s, which drive a `..repeat()` controller and therefore never
// settle. `pumpAndSettle` would time out on the loading frame, so this suite
// pumps explicit, bounded frames instead — never `pumpAndSettle`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/business/business_unit_dashboard.dart';
import 'package:gixbee/shared/models/business.dart';
import 'package:gixbee/shared/widgets/gx_empty.dart';
import 'package:gixbee/shared/widgets/gx_skeleton.dart';

/// Hosts the screen under a `ProviderScope` whose `myBusinessesProvider` is
/// replaced by [create]. A plain dark [ThemeData] is used (not `GixbeeTheme`)
/// so `Theme.of(context)` resolves without pulling in google_fonts' runtime
/// font fetch.
Widget _host(FutureOr<List<Business>> Function() create) => ProviderScope(
      overrides: [
        myBusinessesProvider.overrideWith((ref) => create()),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const BusinessUnitDashboard(),
      ),
    );

/// A minimal [Business] shaped like the backend `/businesses/mine` payload the
/// screen reads. Only `id`/`name`/`type`/`ownerId`/`status` are required;
/// `type == 'HIRING'` drives the "Hiring Unit" label + Post Job / Candidates
/// actions, anything else → "Service Unit" + Calendar / Operators.
Business _biz(String id, String name, String type, String status) => Business(
      id: id,
      name: name,
      type: type,
      ownerId: 'owner_1',
      status: status,
    );

void main() {
  group('BusinessUnitDashboard', () {
    testWidgets('loading → renders skeleton placeholders, not an empty state',
        (tester) async {
      // A future that never completes keeps the provider in AsyncLoading.
      final never = Completer<List<Business>>();
      await tester.pumpWidget(_host(() => never.future));
      await tester.pump(); // build (loading branch)
      await tester.pump(const Duration(milliseconds: 300)); // skeleton frame

      expect(find.byType(GxSkeleton), findsWidgets);
      // Neither empty nor error copy should show while loading.
      expect(find.text('No businesses yet'), findsNothing);
      expect(find.byType(GxEmptyState), findsNothing);
    });

    testWidgets('data → renders one card per business with its type label',
        (tester) async {
      await tester.pumpWidget(_host(() async => [
            _biz('bz_0001', 'Sharma Plumbing', 'HIRING', 'VERIFIED'),
            _biz('bz_0002', 'Grand Banquet Hall', 'RENTAL', 'PENDING'),
          ]));
      await tester.pump(); // loading
      await tester.pump(); // provider resolves → data branch
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Sharma Plumbing'), findsOneWidget);
      expect(find.text('Grand Banquet Hall'), findsOneWidget);
      // Type-specific sub-labels.
      expect(find.text('Hiring Unit'), findsOneWidget);
      expect(find.text('Service Unit'), findsOneWidget);
      // Hiring unit shows Post Job / Candidates; service unit Calendar / Operators.
      expect(find.text('Post Job'), findsOneWidget);
      expect(find.text('Candidates'), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Operators'), findsOneWidget);
      // No empty state when there is data.
      expect(find.byType(GxEmptyState), findsNothing);
    });

    testWidgets('data → status chip reflects each business status',
        (tester) async {
      await tester.pumpWidget(_host(() async => [
            _biz('bz_0001', 'Sharma Plumbing', 'HIRING', 'VERIFIED'),
            _biz('bz_0002', 'Grand Banquet Hall', 'RENTAL', 'PENDING'),
          ]));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('VERIFIED'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
    });

    testWidgets('empty list → shows the "No businesses yet" empty state',
        (tester) async {
      await tester.pumpWidget(_host(() async => <Business>[]));
      await tester.pump(); // loading
      await tester.pump(); // data branch (empty)
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(GxEmptyState), findsOneWidget);
      expect(find.text('No businesses yet'), findsOneWidget);
      // No business cards should be present.
      expect(find.text('Sharma Plumbing'), findsNothing);
    });

    testWidgets('error → shows the "Couldn\'t load" empty state',
        (tester) async {
      await tester.pumpWidget(
          _host(() => Future<List<Business>>.error(StateError('boom'))));
      await tester.pump(); // loading
      await tester.pump(); // provider resolves → error branch
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(GxEmptyState), findsOneWidget);
      expect(find.text("Couldn't load your businesses"), findsOneWidget);
    });

    testWidgets('AppBar shows the title and the Add Business FAB',
        (tester) async {
      await tester.pumpWidget(_host(() async => <Business>[]));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('My Businesses'), findsOneWidget);
      expect(find.text('Add Business'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });
}
