// Gixbee 2026 — composed-screen widget test (Pass 122).
//
// Extends the ProviderScope-override pattern (Passes 117–121) to a sixth real
// screen: `JobAlertsScreen` (the Find-a-Job / open-gigs list, accentGreen
// quad). It is fed only by a repository `Provider` — `hiringRepositoryProvider`
// (a `Provider<HiringRepository>`) — with no `FutureProvider` seam in front of
// it: the screen reads `ref.read(hiringRepositoryProvider).getMatchingJobs()`
// in `initState` and keeps its own `_isLoading` / `_jobs` local state.
//
// This reuses the exact fake-repo convention shipped in Pass 119
// (`_FakeFavRepo extends FavouritesRepository`) and Pass 121
// (`_FakeTalentRepo extends TalentRepository`): a hand-rolled
// `_FakeHiringRepo extends HiringRepository` whose `getMatchingJobs()` returns
// the test-seeded value, built with `super(Dio())` to satisfy the base ctor
// (that Dio is never used — only `getMatchingJobs` is exercised). No mock
// package (none is installed and none may be added), no Dio call, no network.
//
// NOTE ON PUMPING: while loading, the screen shows a `ListView` of `GxSkeleton`
// placeholders, which drive a `..repeat()` controller and therefore never
// settle; `pumpAndSettle` would time out. This suite pumps explicit, bounded
// frames instead. The data/empty branch is a plain `setState` ternary (no
// AnimatedSwitcher), so a couple of frames after the future resolves is enough.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/jobs/job_alerts_screen.dart';
import 'package:gixbee/repositories/hiring_repository.dart';
import 'package:gixbee/shared/models/job_post.dart';
import 'package:gixbee/shared/widgets/gx_empty.dart';
import 'package:gixbee/shared/widgets/gx_skeleton.dart';

/// A hand-rolled fake `HiringRepository`. Only `getMatchingJobs()` is exercised
/// by the screen's `initState`; every other method is inherited (and never
/// hit). `super(Dio())` satisfies the base ctor without opening any connection.
class _FakeHiringRepo extends HiringRepository {
  _FakeHiringRepo(this._getMatchingJobs) : super(Dio());

  final Future<List<JobPost>> Function() _getMatchingJobs;

  @override
  Future<List<JobPost>> getMatchingJobs() => _getMatchingJobs();
}

/// Builds a `JobPost` shaped like the objects `getMatchingJobs` yields from
/// `JobPost.fromJson`, with overridable fields.
JobPost _job(
  String id,
  String title, {
  String jobType = 'Electrician',
  String description = 'A short job description for the listing.',
  double? salaryMin = 200,
  double? salaryMax = 500,
  String experience = 'Fresher',
  String location = 'Kochi',
  String? employerName = 'Acme Services',
}) =>
    JobPost(
      id: id,
      title: title,
      description: description,
      requiredSkills: const [],
      salaryMin: salaryMin,
      salaryMax: salaryMax,
      jobType: jobType,
      experience: experience,
      location: location,
      isActive: true,
      employerId: 'emp-$id',
      employerName: employerName,
    );

/// Hosts the screen under a `ProviderScope` whose `hiringRepositoryProvider` is
/// replaced by a [_FakeHiringRepo] built from [getMatchingJobs]. The screen is a
/// `SafeArea`/`Column` (not a `Scaffold`), so it is wrapped in one — its error
/// path calls `showGxSnack`, which needs a `ScaffoldMessenger` ancestor, and
/// its back button needs a `Navigator`. A plain dark [ThemeData] is used (not
/// `GixbeeTheme`) so `Theme.of(context)` resolves without google_fonts' runtime
/// font fetch.
Widget _host(Future<List<JobPost>> Function() getMatchingJobs) => ProviderScope(
      overrides: [
        hiringRepositoryProvider
            .overrideWithValue(_FakeHiringRepo(getMatchingJobs)),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(body: JobAlertsScreen()),
      ),
    );

void main() {
  group('JobAlertsScreen', () {
    testWidgets('loading → renders skeleton placeholders, not cards or empty',
        (tester) async {
      // A future that never completes keeps `_isLoading` true.
      final never = Completer<List<JobPost>>();
      await tester.pumpWidget(_host(() => never.future));
      await tester.pump(); // build (loading branch)
      await tester.pump(const Duration(milliseconds: 300)); // skeleton frame

      expect(find.byType(GxSkeleton), findsWidgets);
      // No results yet → no empty state and no job-card content.
      expect(find.byType(GxEmptyState), findsNothing);
      expect(find.text('No jobs available right now'), findsNothing);
      // The neutral header is always present.
      expect(find.text('Find a Job'), findsOneWidget);
    });

    testWidgets('data → renders a bento card per job with title + type badge',
        (tester) async {
      await tester.pumpWidget(_host(() async => [
            _job('1', 'Senior Electrician Needed', jobType: 'Electrician'),
            _job('2', 'House Painter Wanted',
                jobType: 'Painting', salaryMin: 300, salaryMax: 700),
          ]));
      await tester.pump(); // loading
      await tester.pump(); // getMatchingJobs resolves → data branch
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Senior Electrician Needed'), findsOneWidget);
      expect(find.text('House Painter Wanted'), findsOneWidget);
      // The per-card type badge is uppercased (distinct from the filter chips).
      expect(find.text('ELECTRICIAN'), findsOneWidget);
      expect(find.text('PAINTING'), findsOneWidget);
      // Pay pill renders the ₹min–₹max range.
      expect(find.text('₹200–₹500'), findsOneWidget);
      // Header count reflects the loaded jobs; no empty state.
      expect(find.text('2 open gigs near you'), findsOneWidget);
      expect(find.byType(GxEmptyState), findsNothing);
      expect(find.byType(GxSkeleton), findsNothing);
    });

    testWidgets('empty → shows the "no jobs" empty state', (tester) async {
      await tester.pumpWidget(_host(() async => <JobPost>[]));
      await tester.pump(); // loading
      await tester.pump(); // resolves → empty branch
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(GxEmptyState), findsOneWidget);
      expect(find.text('No jobs available right now'), findsOneWidget);
      expect(find.text('0 open gigs near you'), findsOneWidget);
      // Skeletons are gone once loading finished.
      expect(find.byType(GxSkeleton), findsNothing);
    });

    testWidgets('getMatchingJobs throws → falls back to the empty state',
        (tester) async {
      await tester.pumpWidget(
          _host(() => Future<List<JobPost>>.error(StateError('boom'))));
      await tester.pump(); // loading
      await tester.pump(); // errors → caught, _isLoading=false, _jobs stays []
      await tester.pump(const Duration(milliseconds: 100));

      // The catch sets _isLoading=false with an empty _jobs list, so the
      // screen shows its empty state (plus a snackbar the ScaffoldMessenger
      // hosts). No skeletons remain.
      expect(find.byType(GxEmptyState), findsOneWidget);
      expect(find.text('No jobs available right now'), findsOneWidget);
      expect(find.byType(GxSkeleton), findsNothing);
    });

    testWidgets('header shows title and the open-gigs subtitle', (tester) async {
      await tester.pumpWidget(_host(() async => [
            _job('1', 'Plumber for Apartments', jobType: 'Plumbing'),
          ]));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Find a Job'), findsOneWidget);
      expect(find.text('1 open gigs near you'), findsOneWidget);
    });
  });
}
