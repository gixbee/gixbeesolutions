// Gixbee 2026 — composed-screen widget test (Pass 131): PostJobScreen.
//
// PostJobScreen (lib/features/jobs/post_job_screen.dart — the business-quad
// "Post a Job" form reached from the hiring flow, accentBlue) has THREE data
// seams, all plain Riverpod `Provider`s over Dio-backed repositories:
//   • masterEntriesRepositoryProvider.getByType('SKILL')  → skill chips (initState)
//   • businessRepositoryProvider.getMyBusinesses()        → employer lookup (submit)
//   • hiringRepositoryProvider.postJob(JobPost)           → the POST (submit)
// Each is overridden with a hand-rolled fake that `extends` the real repository
// and calls `super(Dio())` (the proven Provider-override seam, Passes 119/121–128
// — no mock package, no real Dio call, no network). The unused Dio is never
// touched because every method the screen calls is overridden.
//
// A plain dark ThemeData is used (not GixbeeTheme) so no google_fonts runtime
// fetch happens; the gx_* widgets read only GixbeeTheme's const colours, which
// resolve offline. The screen has no animation loop, so bounded pumps suffice
// (never pumpAndSettle). Snack tests drain the ScaffoldMessenger auto-dismiss
// Timer (3s info/success, 4s error) before teardown.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/jobs/post_job_screen.dart';
import 'package:gixbee/repositories/master_entries_repository.dart';
import 'package:gixbee/repositories/business_repository.dart';
import 'package:gixbee/repositories/hiring_repository.dart';
import 'package:gixbee/shared/models/business.dart';
import 'package:gixbee/shared/models/job_post.dart';
import 'package:gixbee/shared/widgets/gx_button.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

/// Returns a fixed skill list, or throws to exercise the initState fallback.
class _FakeMasterRepo extends MasterEntriesRepository {
  _FakeMasterRepo({this.labels = const ['Plumbing', 'Welding'], this.fail = false})
      : super(Dio());
  final List<String> labels;
  final bool fail;

  @override
  Future<List<MasterEntry>> getByType(String type) async {
    if (fail) throw 'boom';
    return labels
        .map((l) => MasterEntry(id: l, label: l, type: 'SKILL'))
        .toList();
  }
}

/// Returns a configurable list of businesses (empty → the "list a business
/// first" error branch).
class _FakeBusinessRepo extends BusinessRepository {
  _FakeBusinessRepo({required this.businesses}) : super(Dio());
  final List<Business> businesses;

  @override
  Future<List<Business>> getMyBusinesses() async => businesses;
}

/// Captures the posted JobPost (or throws if [fail]).
class _FakeHiringRepo extends HiringRepository {
  _FakeHiringRepo({this.fail = false}) : super(Dio());
  final bool fail;
  JobPost? posted;

  @override
  Future<void> postJob(JobPost jobData) async {
    if (fail) throw 'server down';
    posted = jobData;
  }
}

Business _biz(String id) => Business(
      id: id,
      name: 'Acme Corp',
      type: 'company',
      ownerId: 'owner-1',
      status: 'active',
    );

// ── Harnesses ────────────────────────────────────────────────────────────────

/// Hosts PostJobScreen directly as `home` (fine for every flow that does NOT
/// call Navigator.pop — i.e. all but the happy path).
Widget _host(List<dynamic> overrides) => ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const PostJobScreen(),
      ),
    );

/// Hosts PostJobScreen behind a pushed route so its success-path
/// `Navigator.pop` returns to a launcher rather than popping the last route.
Widget _pushHost(List<dynamic> overrides) => ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute(builder: (_) => const PostJobScreen()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

/// Fills the four required text fields (order: title, salary, location,
/// description) so `_formKey.validate()` passes.
Future<void> _fillForm(WidgetTester tester) async {
  final fields = find.byType(EditableText);
  await tester.enterText(fields.at(0), 'Senior Welder');
  await tester.enterText(fields.at(1), '25000');
  await tester.enterText(fields.at(2), 'Pune');
  await tester.enterText(fields.at(3), 'Fabrication work');
  await tester.pump();
}

void main() {
  group('PostJobScreen', () {
    testWidgets('renders header, section labels, dropdowns and fetched skills',
        (tester) async {
      await tester.pumpWidget(_host([
        masterEntriesRepositoryProvider
            .overrideWithValue(_FakeMasterRepo()),
      ]));
      await tester.pump(); // drain the initState skill fetch microtask

      expect(find.text('Post a Job'), findsOneWidget);
      expect(find.text('Job Details'), findsOneWidget);
      expect(find.text('Skills Required'), findsOneWidget);
      expect(find.text('Experience Required'), findsOneWidget);
      expect(find.text('Job Type'), findsOneWidget);
      // Fetched skill chips (from the fake, not the fallback defaults).
      expect(find.widgetWithText(FilterChip, 'Plumbing'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Welding'), findsOneWidget);
      // Default dropdown selections.
      expect(find.text('Fresher'), findsOneWidget);
      expect(find.text('Full Time'), findsOneWidget);
      // The submit CTA.
      expect(find.widgetWithText(GxButton, 'Post Job'), findsOneWidget);
    });

    testWidgets('falls back to default skills when the fetch fails',
        (tester) async {
      await tester.pumpWidget(_host([
        masterEntriesRepositoryProvider
            .overrideWithValue(_FakeMasterRepo(fail: true)),
      ]));
      await tester.pump(); // fetch throws → catch sets the defaults

      for (final s in ['General Labor', 'Technician', 'Engineer', 'Designer']) {
        expect(find.widgetWithText(FilterChip, s), findsOneWidget);
      }
      expect(find.widgetWithText(FilterChip, 'Plumbing'), findsNothing);
    });

    testWidgets('empty submit shows validation errors and no skill snack',
        (tester) async {
      await tester.pumpWidget(_host([
        masterEntriesRepositoryProvider
            .overrideWithValue(_FakeMasterRepo()),
      ]));
      await tester.pump();

      await tester.tap(find.widgetWithText(GxButton, 'Post Job'));
      await tester.pump();

      // Form.validate() fails first → four 'Required' errors, and the code
      // returns before the skill-empty check, so no snack.
      expect(find.text('Required'), findsNWidgets(4));
      expect(find.text('Please select at least one skill'), findsNothing);
    });

    testWidgets('valid form but no skill selected shows the skill snack',
        (tester) async {
      await tester.pumpWidget(_host([
        masterEntriesRepositoryProvider
            .overrideWithValue(_FakeMasterRepo()),
      ]));
      await tester.pump();

      await _fillForm(tester);
      await tester.tap(find.widgetWithText(GxButton, 'Post Job'));
      await tester.pump(); // run _submitJob to the synchronous skill check
      await tester.pump(); // enqueue the toast
      await tester.pump(const Duration(milliseconds: 400)); // animate in

      expect(find.text('Please select at least one skill'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('no business → error snack, no post', (tester) async {
      final hiring = _FakeHiringRepo();
      await tester.pumpWidget(_host([
        masterEntriesRepositoryProvider
            .overrideWithValue(_FakeMasterRepo()),
        businessRepositoryProvider
            .overrideWithValue(_FakeBusinessRepo(businesses: const [])),
        hiringRepositoryProvider.overrideWithValue(hiring),
      ]));
      await tester.pump();

      await _fillForm(tester);
      await tester.tap(find.widgetWithText(FilterChip, 'Plumbing'));
      await tester.pump();
      await tester.tap(find.widgetWithText(GxButton, 'Post Job'));
      await tester.pump(); // isLoading=true
      await tester.pump(); // await getMyBusinesses → throws → catch
      await tester.pump(const Duration(milliseconds: 400)); // error toast in

      expect(find.textContaining('must list a business'), findsOneWidget);
      expect(hiring.posted, isNull);

      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('happy path posts the job and pops back to the launcher',
        (tester) async {
      final hiring = _FakeHiringRepo();
      await tester.pumpWidget(_pushHost([
        masterEntriesRepositoryProvider
            .overrideWithValue(_FakeMasterRepo()),
        businessRepositoryProvider
            .overrideWithValue(_FakeBusinessRepo(businesses: [_biz('emp-9')])),
        hiringRepositoryProvider.overrideWithValue(hiring),
      ]));
      await tester.pump();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle(); // route transition (no data loop yet)
      await tester.pump(); // skill fetch microtask

      await _fillForm(tester);
      await tester.tap(find.widgetWithText(FilterChip, 'Plumbing'));
      await tester.pump();

      await tester.tap(find.widgetWithText(GxButton, 'Post Job'));
      await tester.pump(); // isLoading=true
      await tester.pump(); // await getMyBusinesses
      await tester.pump(); // await postJob → success snack + pop
      await tester.pump(const Duration(milliseconds: 400)); // toast + pop anim

      // postJob got the right payload.
      expect(hiring.posted, isNotNull);
      expect(hiring.posted!.title, 'Senior Welder');
      expect(hiring.posted!.employerId, 'emp-9');
      expect(hiring.posted!.requiredSkills, contains('Plumbing'));
      expect(hiring.posted!.jobType, 'Full Time');
      expect(hiring.posted!.experience, 'Fresher');
      // Popped back: the launcher button is visible again.
      expect(find.text('open'), findsOneWidget);
      expect(find.text('Post a Job'), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
