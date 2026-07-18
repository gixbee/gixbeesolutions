// Gixbee 2026 — composed-screen widget test (Pass 124).
//
// Extends the ProviderScope-override + fake-repository pattern (Passes 119–122)
// to `ApplicationTrackerScreen`, the talent-side "My Applications" tracker
// (Find-a-Job tab 2, accentGreen quad). Like `HiringPipelineScreen`, this
// screen has NO public `FutureProvider` seam: its `initState` reads
// `ref.read(hiringRepositoryProvider).getMyApplications()` and keeps its own
// `_isLoading` / `_applications` local state.
//
// We swap in a `_FakeHiringRepo extends HiringRepository` whose
// `getMyApplications` returns whatever the test seeds — no mock package (none is
// installed and none may be added), no Dio call, no network. The fake still
// calls `super(Dio())` to satisfy the base constructor, but that Dio is never
// used because the only method the screen hits is overridden.
//
// TWO DIFFERENCES from the pipeline suite worth noting:
//   1. This screen is NOT its own `Scaffold` — it returns a `SafeArea`/`Column`
//      — so the host wraps it in a `Scaffold(body: ...)` (which also supplies
//      the `ScaffoldMessenger` the error path's `showGxSnack` needs).
//   2. There is NO `GxFade`/`AnimatedSwitcher` here: the loading→data swap is a
//      plain conditional, so no fade duration must elapse. But the loading
//      `GxSkeleton`s drive a `..repeat()` controller that never settles, so this
//      suite still pumps explicit, bounded frames instead of `pumpAndSettle`.
//
// The header (title + stats row + segmented pills) renders in EVERY state, so
// its copy is asserted independent of the load branch. Only the current tab
// ("All") of the `TabBarView` builds on frame 1, and every tab merely filters
// the already-loaded in-memory list — no per-tab Dio, hence no pending timers.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/jobs/application_tracker_screen.dart';
import 'package:gixbee/repositories/hiring_repository.dart';
import 'package:gixbee/shared/models/job_post.dart';
import 'package:gixbee/shared/widgets/gx_skeleton.dart';

/// A hand-rolled fake `HiringRepository`. Only `getMyApplications` is exercised
/// by the screen's `initState`; every other method is inherited (and never
/// hit). `super(Dio())` satisfies the base ctor without opening any connection.
class _FakeHiringRepo extends HiringRepository {
  _FakeHiringRepo(this._getMyApplications) : super(Dio());

  final Future<List<JobApplication>> Function() _getMyApplications;

  @override
  Future<List<JobApplication>> getMyApplications() => _getMyApplications();
}

/// Builds a minimal `JobPost` with a distinct [title] so each card is
/// individually findable. `createdAt` is left null on the application (below) so
/// the card never touches `DateFormat`.
JobPost _job(String id, String title) => JobPost(
      id: id,
      title: title,
      description: 'desc',
      requiredSkills: const ['Plumbing'],
      jobType: 'Full Time',
      experience: 'Fresher',
      location: 'Kochi',
      isActive: true,
      employerId: 'emp-$id',
    );

/// Builds a `JobApplication` in a given stage. `createdAt: null` avoids the
/// card's `DateFormat.yMMMd()` branch entirely.
JobApplication _app(String id, String title, ApplicationStatus status) =>
    JobApplication(
      id: id,
      jobPost: _job(id, title),
      applicantId: 'appl-$id',
      status: status,
    );

/// Hosts the screen under a `ProviderScope` whose `hiringRepositoryProvider` is
/// replaced by a [_FakeHiringRepo] built from [getMyApplications]. The screen is
/// NOT its own `Scaffold`, so it is wrapped in one (which also provides the
/// `ScaffoldMessenger` used by the error path). A plain dark [ThemeData] is used
/// (not `GixbeeTheme`) so `Theme.of(context)` resolves without pulling in
/// google_fonts' runtime font fetch.
Widget _host(Future<List<JobApplication>> Function() getMyApplications) =>
    ProviderScope(
      overrides: [
        hiringRepositoryProvider
            .overrideWithValue(_FakeHiringRepo(getMyApplications)),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(body: ApplicationTrackerScreen()),
      ),
    );

void main() {
  group('ApplicationTrackerScreen', () {
    testWidgets('loading → renders skeletons, header present, no cards',
        (tester) async {
      // A future that never completes keeps `_isLoading` true.
      final never = Completer<List<JobApplication>>();
      await tester.pumpWidget(_host(() => never.future));
      await tester.pump(); // build (loading branch)
      await tester.pump(const Duration(milliseconds: 300)); // skeleton frame

      expect(find.byType(GxSkeleton), findsWidgets);
      // The header renders in every state.
      expect(find.text('My Applications'), findsOneWidget);
      // No application card has been built yet.
      expect(find.text('Plumber'), findsNothing);
    });

    testWidgets('data → renders a card per application on the "All" tab',
        (tester) async {
      await tester.pumpWidget(_host(() async => [
            _app('1', 'Plumber', ApplicationStatus.applied),
            _app('2', 'Electrician', ApplicationStatus.interview),
            _app('3', 'Cleaner', ApplicationStatus.selected),
          ]));
      await tester.pump(); // loading
      await tester.pump(); // getMyApplications resolves → data branch
      await tester.pump(const Duration(milliseconds: 400)); // press-scale settles

      // Each seeded job title renders on its own card (tab 0 = "All").
      expect(find.text('Plumber'), findsOneWidget);
      expect(find.text('Electrician'), findsOneWidget);
      expect(find.text('Cleaner'), findsOneWidget);

      // Header sub-label reflects the loaded count.
      expect(find.text('3 total · track every stage'), findsOneWidget);

      // Skeletons are gone once loading finished.
      expect(find.byType(GxSkeleton), findsNothing);
    });

    testWidgets('empty data → "All" tab shows the empty state, header 0-count',
        (tester) async {
      await tester.pumpWidget(_host(() async => <JobApplication>[]));
      await tester.pump(); // loading
      await tester.pump(); // data branch (empty)
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('No applications here'), findsOneWidget);
      expect(find.text('0 total · track every stage'), findsOneWidget);
      // All four stat bubbles show a '0' count.
      expect(find.text('0'), findsNWidgets(4));
      // Skeletons must be gone once loading finished.
      expect(find.byType(GxSkeleton), findsNothing);
    });

    testWidgets('getMyApplications throws → caught, empty state shown',
        (tester) async {
      await tester.pumpWidget(_host(
          () => Future<List<JobApplication>>.error(StateError('boom'))));
      await tester.pump(); // loading
      await tester.pump(); // errors → caught, _isLoading=false, list empty
      await tester.pump(const Duration(milliseconds: 400));

      // The catch block leaves an empty tracker rather than a crash.
      expect(find.text('No applications here'), findsOneWidget);
      // Skeletons must be gone once loading finished.
      expect(find.byType(GxSkeleton), findsNothing);

      // The catch also fires `showGxSnack`, which queues a SnackBar with a 4 s
      // auto-dismiss Timer. Drain it (fire the timer + let the exit transition
      // run) so the test doesn't fail teardown with "a Timer is still pending".
      // Safe to pump fixed durations: the empty state (`GxEmptyState`) is a pure
      // StatelessWidget with no repeating animation.
      await tester.pump(const Duration(seconds: 4)); // fire auto-dismiss timer
      await tester.pump(const Duration(milliseconds: 500)); // exit transition
    });

    testWidgets('closed filter → withdrawn/rejected land on the "Closed" tab',
        (tester) async {
      await tester.pumpWidget(_host(() async => [
            _app('1', 'Plumber', ApplicationStatus.applied),
            _app('2', 'Painter', ApplicationStatus.rejected),
          ]));
      await tester.pump(); // loading
      await tester.pump(); // data branch
      await tester.pump(const Duration(milliseconds: 400));

      // Tab 0 ("All") shows both applications.
      expect(find.text('Plumber'), findsOneWidget);
      expect(find.text('Painter'), findsOneWidget);

      // Switch to the "Closed" segment (tab 3): filters to rejected/withdrawn.
      await tester.tap(find.text('Closed'));
      await tester.pump(); // start tab animation
      await tester.pump(const Duration(milliseconds: 400)); // finish swap

      // The rejected application remains; the active one is filtered out.
      expect(find.text('Painter'), findsOneWidget);
      expect(find.text('Plumber'), findsNothing);
    });

    testWidgets('header → title, subtitle and the four segmented pills render',
        (tester) async {
      await tester.pumpWidget(_host(() async => <JobApplication>[]));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('My Applications'), findsOneWidget);
      // Segmented pill labels (distinct from the uppercased stat labels).
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
      // Uppercased stat-bubble labels.
      expect(find.text('INTERVIEW'), findsOneWidget);
      expect(find.text('TOTAL'), findsOneWidget);
    });
  });
}
