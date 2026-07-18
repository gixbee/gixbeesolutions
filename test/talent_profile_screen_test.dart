// Gixbee 2026 — composed-screen widget test (Pass 121).
//
// Extends the ProviderScope-override pattern (Passes 117–120) to a screen
// whose data does NOT come through a public `FutureProvider` seam. Instead of
// overriding a `FutureProvider`, this suite overrides the plain
// `talentRepositoryProvider` (a `Provider<TalentRepository>`) with a
// hand-rolled fake subclass — still no mock package (none is installed and
// none may be added), no Dio call, no network.
//
// `TalentProfileScreen` reads `ref.read(talentRepositoryProvider).getProfile()`
// in its `initState` and keeps its own `_isLoading` / `_profile` local state.
// We swap in a `_FakeTalentRepo` whose `getProfile()` returns whatever the test
// seeds (a never-completing future → loading; a map → data; a throw → the
// caught error path). The fake still calls `super(Dio())` to satisfy the base
// constructor, but that Dio is never used because `getProfile` is overridden.
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
import 'package:gixbee/features/jobs/talent_profile_screen.dart';
import 'package:gixbee/repositories/talent_repository.dart';
import 'package:gixbee/shared/widgets/gx_skeleton.dart';

/// A hand-rolled fake `TalentRepository`. Only `getProfile()` is exercised by
/// the screen's `initState`; every other method is inherited (and never hit).
/// `super(Dio())` satisfies the base ctor without opening any connection.
class _FakeTalentRepo extends TalentRepository {
  _FakeTalentRepo(this._getProfile) : super(Dio());

  final Future<Map<String, dynamic>> Function() _getProfile;

  @override
  Future<Map<String, dynamic>> getProfile() => _getProfile();
}

/// Hosts the screen under a `ProviderScope` whose `talentRepositoryProvider` is
/// replaced by a [_FakeTalentRepo] built from [getProfile]. The screen is not a
/// `Scaffold`, so it is wrapped in one (its `Navigator.pop` /
/// `ScaffoldMessenger` look-ups need the ancestors). A plain dark [ThemeData]
/// is used (not `GixbeeTheme`) so `Theme.of(context)` resolves without pulling
/// in google_fonts' runtime font fetch.
Widget _host(Future<Map<String, dynamic>> Function() getProfile) => ProviderScope(
      overrides: [
        talentRepositoryProvider.overrideWithValue(_FakeTalentRepo(getProfile)),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(body: TalentProfileScreen()),
      ),
    );

void main() {
  group('TalentProfileScreen', () {
    testWidgets('loading → renders skeleton placeholders, not the sections',
        (tester) async {
      // A future that never completes keeps `_isLoading` true.
      final never = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(_host(() => never.future));
      await tester.pump(); // build (loading branch)
      await tester.pump(const Duration(milliseconds: 300)); // skeleton frame

      expect(find.byType(GxSkeleton), findsWidgets);
      // The data sections must not be present while loading.
      expect(find.text('SKILLS'), findsNothing);
      // The neutral header is always present.
      expect(find.text('Talent Bio'), findsOneWidget);
    });

    testWidgets('data with skills → renders profile, sections and skill chips',
        (tester) async {
      await tester.pumpWidget(_host(() async => {
            'fullName': 'Asha Rao',
            'bio': 'Experienced plumber and electrician',
            'skills': ['Plumbing', 'Wiring'],
            'alertsEnabled': true,
          }));
      await tester.pump(); // loading
      await tester.pump(); // getProfile resolves → data branch
      await tester.pump(const Duration(milliseconds: 400)); // GxFade settles

      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('SKILLS'), findsOneWidget);
      expect(find.text('Plumbing'), findsOneWidget);
      expect(find.text('Wiring'), findsOneWidget);
      // Skills present → 70% strength and NO "complete registration" CTA.
      expect(find.text('PROFILE STRENGTH · 70%'), findsOneWidget);
      expect(find.text('Complete professional registration'), findsNothing);
    });

    testWidgets('data with no skills → shows the complete-registration CTA',
        (tester) async {
      await tester.pumpWidget(_host(() async => {
            'fullName': 'Ravi Kumar',
            'skills': <dynamic>[],
          }));
      await tester.pump(); // loading
      await tester.pump(); // data branch (no skills)
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Complete professional registration'), findsOneWidget);
      expect(
          find.text('Add your skills and rates to appear in searches.'),
          findsOneWidget);
      // No skills → 30% strength.
      expect(find.text('PROFILE STRENGTH · 30%'), findsOneWidget);
    });

    testWidgets('getProfile throws → falls back to the empty profile view',
        (tester) async {
      await tester.pumpWidget(
          _host(() => Future<Map<String, dynamic>>.error(StateError('boom'))));
      await tester.pump(); // loading
      await tester.pump(); // getProfile errors → caught, _profile stays null
      await tester.pump(const Duration(milliseconds: 400));

      // With a null profile the card shows its fallback name and the CTA.
      expect(find.text('Your Name'), findsOneWidget);
      expect(find.text('Complete professional registration'), findsOneWidget);
      // Skeletons must be gone once loading finished.
      expect(find.byType(GxSkeleton), findsNothing);
    });

    testWidgets('header shows the title and subtitle', (tester) async {
      await tester.pumpWidget(_host(() async => {'skills': <dynamic>[]}));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Talent Bio'), findsOneWidget);
      expect(find.text('How customers see you when you apply'), findsOneWidget);
    });
  });
}
