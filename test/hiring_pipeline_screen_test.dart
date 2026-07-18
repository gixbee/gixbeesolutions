// Gixbee 2026 — composed-screen widget test (Pass 122).
//
// Extends the ProviderScope-override + fake-repository pattern (Passes 119–121)
// to `HiringPipelineScreen`, an employer-facing kanban board. Like
// `TalentProfileScreen`, this screen has NO public `FutureProvider` seam: it
// reads `ref.read(hiringRepositoryProvider).getApplicationsForJob(jobId)` in
// `initState` and keeps its own `_isLoading` / `_applications` local state.
//
// We swap in a `_FakeHiringRepo extends HiringRepository` whose
// `getApplicationsForJob` returns whatever the test seeds — no mock package
// (none is installed and none may be added), no Dio call, no network. The fake
// still calls `super(Dio())` to satisfy the base constructor, but that Dio is
// never used because the only method the screen hits is overridden.
//
// NOTE ON PUMPING: while loading, the screen shows `GxSkeleton`s, which drive a
// `..repeat()` controller and therefore never settle. `pumpAndSettle` would
// time out, so this suite pumps explicit, bounded frames instead. The
// loading→data swap crosses a `GxFade` (AnimatedSwitcher, 280 ms); a 400 ms
// pump lets it complete before assertions.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/business/hiring_pipeline_screen.dart';
import 'package:gixbee/repositories/hiring_repository.dart';
import 'package:gixbee/shared/models/job_post.dart';
import 'package:gixbee/shared/widgets/gx_skeleton.dart';

/// A hand-rolled fake `HiringRepository`. Only `getApplicationsForJob` is
/// exercised by the screen's `initState`; every other method is inherited (and
/// never hit). `super(Dio())` satisfies the base ctor without opening any
/// connection.
class _FakeHiringRepo extends HiringRepository {
  _FakeHiringRepo(this._getApplications) : super(Dio());

  final Future<List<JobApplication>> Function() _getApplications;

  @override
  Future<List<JobApplication>> getApplicationsForJob(String jobId) =>
      _getApplications();
}

/// A minimal `JobPost` — `JobApplication` requires one, but the pipeline card
/// never renders any of its fields, so the values are placeholders.
final _job = JobPost(
  id: 'job-1',
  title: 'Plumber',
  description: 'desc',
  requiredSkills: const ['Plumbing'],
  jobType: 'Full Time',
  experience: 'Fresher',
  location: 'Kochi',
  isActive: true,
  employerId: 'emp-1',
);

/// Builds a `JobApplication` in a given stage with a given applicant name.
JobApplication _app(String id, String name, ApplicationStatus status) =>
    JobApplication(
      id: id,
      jobPost: _job,
      applicantId: 'appl-$id',
      applicantName: name,
      status: status,
      createdAt: DateTime(2026, 6, 30),
    );

/// Hosts the screen under a `ProviderScope` whose `hiringRepositoryProvider` is
/// replaced by a [_FakeHiringRepo] built from [getApplications]. The screen is
/// its own `Scaffold`, so it only needs the `MaterialApp` ancestor (for
/// `ScaffoldMessenger` / `Navigator`). A plain dark [ThemeData] is used (not
/// `GixbeeTheme`) so `Theme.of(context)` resolves without pulling in
/// google_fonts' runtime font fetch.
Widget _host(Future<List<JobApplication>> Function() getApplications) =>
    ProviderScope(
      overrides: [
        hiringRepositoryProvider
            .overrideWithValue(_FakeHiringRepo(getApplications)),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const HiringPipelineScreen(
          jobId: 'job-1',
          jobTitle: 'Senior Plumber',
        ),
      ),
    );

void main() {
  group('HiringPipelineScreen', () {
    testWidgets('loading → renders skeletons, not the kanban columns',
        (tester) async {
      // A future that never completes keeps `_isLoading` true.
      final never = Completer<List<JobApplication>>();
      await tester.pumpWidget(_host(() => never.future));
      await tester.pump(); // build (loading branch)
      await tester.pump(const Duration(milliseconds: 300)); // skeleton frame

      expect(find.byType(GxSkeleton), findsWidgets);
      // The stage column headers only exist in the data branch.
      expect(find.text('APPLIED'), findsNothing);
      // The AppBar header is always present (outside the GxFade body).
      expect(find.text('Hiring Pipeline'), findsOneWidget);
      expect(find.text('Senior Plumber'), findsOneWidget);
    });

    testWidgets('data → renders all four stage columns and candidate cards',
        (tester) async {
      await tester.pumpWidget(_host(() async => [
            _app('1', 'Asha Rao', ApplicationStatus.applied),
            _app('2', 'Ravi Kumar', ApplicationStatus.applied),
            _app('3', 'Meera Nair', ApplicationStatus.interview),
            _app('4', 'John Doe', ApplicationStatus.selected),
          ]));
      await tester.pump(); // loading
      await tester.pump(); // getApplicationsForJob resolves → data branch
      await tester.pump(const Duration(milliseconds: 400)); // GxFade settles

      // Every stage column header is present (one column per stage).
      expect(find.text('APPLIED'), findsOneWidget);
      expect(find.text('INTERVIEW'), findsOneWidget);
      expect(find.text('SELECTED'), findsOneWidget);
      expect(find.text('REJECTED'), findsOneWidget);

      // Candidate names render on their cards.
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('Meera Nair'), findsOneWidget);
      expect(find.text('John Doe'), findsOneWidget);

      // Each candidate card exposes a "View Profile" action (4 candidates).
      expect(find.text('View Profile'), findsNWidgets(4));
    });

    testWidgets('empty data → all columns show a zero count and no cards',
        (tester) async {
      await tester.pumpWidget(_host(() async => <JobApplication>[]));
      await tester.pump(); // loading
      await tester.pump(); // data branch (empty)
      await tester.pump(const Duration(milliseconds: 400));

      // All four columns still render, each with a '0' count badge.
      expect(find.text('APPLIED'), findsOneWidget);
      expect(find.text('REJECTED'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(4));
      // No candidate cards → no "View Profile" actions.
      expect(find.text('View Profile'), findsNothing);
    });

    testWidgets('getApplicationsForJob throws → caught, empty board shown',
        (tester) async {
      await tester.pumpWidget(_host(
          () => Future<List<JobApplication>>.error(StateError('boom'))));
      await tester.pump(); // loading
      await tester.pump(); // errors → caught, _isLoading=false, list empty
      await tester.pump(const Duration(milliseconds: 400));

      // The catch block leaves an empty board rather than a crash.
      expect(find.text('APPLIED'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(4));
      // Skeletons must be gone once loading finished.
      expect(find.byType(GxSkeleton), findsNothing);
    });
  });
}
