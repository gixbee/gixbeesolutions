// Gixbee 2026 — composed-screen widget test (Pass 119).
//
// Extends the ProviderScope-override pattern from `notifications_screen_test`
// (Pass 117) and `my_bookings_screen_test` (Pass 118) to a third real screen:
// `WorkerListScreen` (the Instant Help / Plan a Service list). It is driven
// entirely by the public, overridable `nearbyWorkersProvider`
// (a `FutureProvider.autoDispose<List<Worker>>`), which we replace with a
// plain `ProviderScope` override to exercise each async branch
// (loading → skeletons, data → worker cards + result count, empty → empty
// state, error → inline error). No mock package (none is installed and none
// may be added), no Dio, no network.
//
// Each worker bento card hosts a `_CardFavHeart` whose `initState` reads
// `favouritesRepositoryProvider` to fetch saved-state. We override that
// provider with a fake that resolves `isFavourite` to `false` synchronously,
// so the data-branch cards never touch Dio and leave no pending network work.
//
// NOTE ON PUMPING: while the provider is loading, the screen shows
// `GxSkeleton`s, which drive a `..repeat()` controller and therefore never
// settle; the data branch is wrapped in a `GxFade`. `pumpAndSettle` would time
// out on the loading frame, so this suite pumps explicit, bounded frames
// instead — never `pumpAndSettle`.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/search/worker_list_screen.dart';
import 'package:gixbee/repositories/favourites_repository.dart';
import 'package:gixbee/repositories/worker_repository.dart';
import 'package:gixbee/shared/models/worker.dart';
import 'package:gixbee/shared/widgets/gx_empty.dart';
import 'package:gixbee/shared/widgets/gx_skeleton.dart';

/// A [FavouritesRepository] that never touches the network: `isFavourite`
/// resolves to `false` on a microtask (no timer, no Dio call), so the
/// `_CardFavHeart.initState` load on every rendered worker card completes
/// cleanly under the harness. `add`/`remove` are unused by these tests.
class _FakeFavRepo extends FavouritesRepository {
  _FakeFavRepo() : super(Dio());

  @override
  Future<bool> isFavourite(String workerId) async => false;
}

/// Builds a fully-populated [Worker] with overridable fields, shaped like the
/// objects `nearbyWorkersProvider` yields from `Worker.fromMap`.
Worker _worker(
  String id,
  String name, {
  String title = 'Verified Pro',
  double rating = 4.7,
  double hourlyRate = 300,
  List<String> skills = const ['Electrician'],
  String status = 'available',
}) =>
    Worker(
      id: id,
      name: name,
      title: title,
      bio: 'Experienced professional.',
      imageUrl: 'https://example.invalid/$id.jpg',
      rating: rating,
      completedJobs: 42,
      reviewCount: 18,
      isFeatured: false,
      hourlyRate: hourlyRate,
      skills: skills,
      availabilityTags: const ['Weekdays'],
      primaryType: SkillType.manual,
      status: status,
    );

/// Hosts [WorkerListScreen] under a `ProviderScope` whose
/// `nearbyWorkersProvider` is replaced by [create] and whose
/// `favouritesRepositoryProvider` is a no-network fake. A plain dark
/// [ThemeData] is used (not `GixbeeTheme`) so `Theme.of(context)` resolves
/// without pulling in google_fonts' runtime font fetch.
Widget _host(
  FutureOr<List<Worker>> Function() create, {
  bool isInstant = true,
}) =>
    ProviderScope(
      overrides: [
        nearbyWorkersProvider.overrideWith((ref) => create()),
        favouritesRepositoryProvider.overrideWithValue(_FakeFavRepo()),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: WorkerListScreen(isInstant: isInstant),
      ),
    );

void main() {
  group('WorkerListScreen', () {
    testWidgets('loading → renders skeleton placeholders, not the empty state',
        (tester) async {
      // A future that never completes keeps the provider in AsyncLoading.
      final never = Completer<List<Worker>>();
      await tester.pumpWidget(_host(() => never.future));
      await tester.pump(); // build (loading branch)
      await tester.pump(const Duration(milliseconds: 300)); // skeleton frame

      expect(find.byType(GxSkeleton), findsWidgets);
      expect(find.byType(GxEmptyState), findsNothing);
    });

    testWidgets('data → renders a card per worker with a result count',
        (tester) async {
      await tester.pumpWidget(_host(() async => [
            _worker('w_0001', 'Asha Kumar'),
            _worker('w_0002', 'Ravi Patel'),
          ]));
      await tester.pump(); // loading
      await tester.pump(); // provider resolves → data branch
      await tester.pump(const Duration(milliseconds: 400)); // GxFade settles

      expect(find.text('Asha Kumar'), findsOneWidget);
      expect(find.text('Ravi Patel'), findsOneWidget);
      // The instant-mode live-region result count reflects the two workers.
      expect(find.text('2 pros available nearby'), findsOneWidget);
      // No empty state while there is data.
      expect(find.byType(GxEmptyState), findsNothing);
    });

    testWidgets('empty list → shows the empty state', (tester) async {
      await tester.pumpWidget(_host(() async => <Worker>[]));
      await tester.pump(); // loading
      await tester.pump(); // data branch (empty)
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(GxEmptyState), findsOneWidget);
      expect(find.text('No pros match your filters'), findsOneWidget);
      // No worker names should be present.
      expect(find.text('Asha Kumar'), findsNothing);
    });

    testWidgets('error → renders the inline error text', (tester) async {
      await tester.pumpWidget(
          _host(() => Future<List<Worker>>.error(StateError('boom'))));
      await tester.pump(); // loading
      await tester.pump(); // provider resolves → error branch
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Error:'), findsOneWidget);
    });

    testWidgets('instant header shows Instant Help title + Filters action',
        (tester) async {
      await tester.pumpWidget(_host(() async => <Worker>[]));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Instant Help'), findsOneWidget);
      expect(find.byTooltip('Filters'), findsOneWidget);
      expect(find.byTooltip('Go back'), findsOneWidget);
    });

    testWidgets('planned mode header shows the Plan a Service title',
        (tester) async {
      await tester.pumpWidget(
          _host(() async => <Worker>[], isInstant: false));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Plan a Service'), findsOneWidget);
      expect(find.text('Instant Help'), findsNothing);
    });
  });
}
