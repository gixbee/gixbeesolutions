// Gixbee 2026 — composed-screen widget test (Pass 132).
//
// Extends the ProviderScope-override seam proven across Passes 117–131 to the
// last clean composed screen the Pass 131 report flagged: `ProfileScreen`
// (`lib/features/profile/profile_screen.dart` — the Gojek-style account page,
// accentViolet quad). It is a `ConsumerWidget` that owns its own `Scaffold`
// and composes FOUR Riverpod seams — no `_isLoading` field, no `Repository`
// read in `initState`; every seam is a real provider we replace directly:
//
//   1. `currentUserProvider`  (FutureProvider<User?>)          → the glass
//      profile card (avatar/name/phone) + the "Available for Work" toggle row.
//      Overridden with a closure so we can drive data / loading / error.
//   2. `userStatsProvider`    (FutureProvider<Map<String,int>>) → the stats row
//      (BOOKINGS / SAVED / REVIEWS). Overridden directly (its real body would
//      read `currentUserProvider.future` then hit the network — never runs).
//   3. `talentProfileProvider`(FutureProvider<Map<String,dynamic>>) → toggles
//      the WORK & BUSINESS row between "Register as Pro" (no skills) and
//      "Professional Bio" (has skills).
//   4. `authRepositoryProvider` / `profileRepositoryProvider` (plain Providers)
//      → the Log-Out `signOut()` and the availability-toggle `updateProfile()`.
//      Replaced with hand-rolled fakes that `extend` the real repo and call
//      `super(...)` with a never-touched `Dio()` (the proven seam — no mock
//      package, no Dio call, no network).
//
// NETWORK IMAGE: the profile card avatar is a `CircleAvatar(backgroundImage:
// NetworkImage(...))`. To keep the image layer from throwing under the harness
// we install the same `HttpOverrides` shim used by the Pass-128 worker_detail
// suite (returns 200 + a valid 1x1 transparent PNG for any request), so the
// avatar fetch — and the google_fonts runtime fetch on the WelcomeScreen the
// log-out test lands on — resolve to a well-formed response instead of a 400.
//
// A plain dark `ThemeData` (not `GixbeeTheme`) is used so `Theme.of(context)`
// resolves without pulling google_fonts into the ProfileScreen itself; the
// `gx_*` widgets read only const brand colours. Bounded pumps throughout (the
// GxSkeleton shimmer repeats, so no `pumpAndSettle` on the loading path).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/onboarding/welcome_screen.dart';
import 'package:gixbee/features/profile/profile_screen.dart';
import 'package:gixbee/repositories/auth_repository.dart';
import 'package:gixbee/repositories/profile_repository.dart';
import 'package:gixbee/repositories/talent_repository.dart';
import 'package:gixbee/services/auth_token_service.dart';
import 'package:gixbee/shared/models/user.dart';
import 'package:gixbee/shared/widgets/gx_skeleton.dart';

// ---------------------------------------------------------------------------
// Network-image mock (self-contained; no external package).
// ---------------------------------------------------------------------------

/// A valid 1x1 fully-transparent PNG. Decodes cleanly if the engine ever runs;
/// we only need the HTTP layer to answer 200 with well-formed bytes so
/// `NetworkImage` (and the google_fonts fetch) do not throw a 400.
final Uint8List _kTransparentPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

class _MockImageHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _MockHttpClientRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => _kTransparentPng.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[_kTransparentPng]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// ---------------------------------------------------------------------------
// Fakes + fixtures.
// ---------------------------------------------------------------------------

/// An [AuthRepository] whose `signOut` records that it was called and never
/// touches the network. `super(Dio(), AuthTokenService())` — both unused: the
/// `Dio` is never called and `AuthTokenService()` constructs a const
/// `FlutterSecureStorage` (no platform channel until a method is invoked, which
/// the overridden `signOut` never does).
class _FakeAuthRepo extends AuthRepository {
  bool signedOut = false;
  _FakeAuthRepo() : super(Dio(), AuthTokenService());

  @override
  Future<void> signOut() async {
    signedOut = true;
  }
}

/// A [ProfileRepository] that captures the availability-toggle write instead of
/// hitting `PATCH /admin-user-list/:id`. `super(Dio())` unused.
class _FakeProfileRepo extends ProfileRepository {
  String? updatedUserId;
  Map<String, dynamic>? updatedData;
  _FakeProfileRepo() : super(Dio());

  @override
  Future<void> updateProfile({
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    updatedUserId = userId;
    updatedData = data;
  }
}

/// A [ProfileRepository] whose `updateProfile` always throws, to exercise the
/// availability-toggle `catch` branch → the `Failed to update availability`
/// error snack. `super(Dio())` unused (the override never touches the network).
class _ThrowingProfileRepo extends ProfileRepository {
  _ThrowingProfileRepo() : super(Dio());

  @override
  Future<void> updateProfile({
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    throw Exception('update failed');
  }
}

/// Builds a [User] with the fields ProfileScreen renders; the rest default.
User _user({
  String id = 'u1',
  String name = 'Ada Lovelace',
  String phone = '+919999999999',
  bool available = true,
}) =>
    User(
      id: id,
      phone: phone,
      name: name,
      isAvailableForWork: available,
    );

// ---------------------------------------------------------------------------
// Host.
// ---------------------------------------------------------------------------

/// Hosts [ProfileScreen] under a `ProviderScope` with every seam overridden.
/// [user] drives `currentUserProvider`; [stats]/[talent] default to a resolved
/// value; [auth]/[profile] default to fresh fakes. When [launcher] is true the
/// screen is reached via a pushed route so the log-out `pushAndRemoveUntil`
/// has a navigator stack to clear.
Widget _host({
  required FutureOr<User?> Function(Ref ref) user,
  FutureOr<Map<String, int>> Function(Ref ref)? stats,
  FutureOr<Map<String, dynamic>> Function(Ref ref)? talent,
  _FakeAuthRepo? auth,
  // Widened to the base type so the error-branch test can pass a
  // `_ThrowingProfileRepo` (a sibling of `_FakeProfileRepo`); both extend
  // `ProfileRepository`. The default still constructs a capturing fake.
  ProfileRepository? profile,
}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(user),
      userStatsProvider.overrideWith(
          stats ?? (ref) async => {'bookings': 3, 'saved': 2, 'reviews': 5}),
      talentProfileProvider.overrideWith(
          talent ?? (ref) async => <String, dynamic>{}),
      authRepositoryProvider.overrideWithValue(auth ?? _FakeAuthRepo()),
      profileRepositoryProvider.overrideWithValue(profile ?? _FakeProfileRepo()),
    ],
    child: MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: const ProfileScreen(),
    ),
  );
}

void _phoneView(WidgetTester tester) {
  // Tall viewport so the long scrolling column lays out without a RenderFlex
  // overflow and the bottom rows (toggle, Log Out) are reachable.
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  HttpOverrides? previous;

  setUpAll(() {
    previous = HttpOverrides.current;
    HttpOverrides.global = _MockImageHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = previous;
  });

  group('ProfileScreen', () {
    // Bounded frames: build + the overridden futures resolving on a microtask.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    testWidgets('chrome — title, section labels, menu rows, name + stats',
        (tester) async {
      _phoneView(tester);
      await tester.pumpWidget(_host(user: (ref) async => _user()));
      await settle(tester);

      // Header + section labels.
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('WORK & BUSINESS'), findsOneWidget);
      expect(find.text('PREFERENCES'), findsOneWidget);
      expect(find.text('SUPPORT'), findsOneWidget);

      // Menu rows.
      expect(find.text('My Wallet'), findsOneWidget);
      expect(find.text('Payment History'), findsOneWidget);
      expect(find.text('Saved Vendors'), findsOneWidget);
      expect(find.text('My Businesses'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Help & FAQ'), findsOneWidget);
      expect(find.text('About Gixbee'), findsOneWidget);
      expect(find.text('System Logs'), findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);

      // Identity + stats.
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('BOOKINGS'), findsOneWidget);
      expect(find.text('SAVED'), findsOneWidget);
      expect(find.text('REVIEWS'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // bookings
      expect(find.text('2'), findsOneWidget); // saved
      expect(find.text('5'), findsOneWidget); // reviews
    });

    testWidgets('no talent skills → "Register as Pro" row', (tester) async {
      _phoneView(tester);
      await tester.pumpWidget(_host(
        user: (ref) async => _user(),
        talent: (ref) async => <String, dynamic>{'professionalSkills': <String>[]},
      ));
      await settle(tester);

      expect(find.text('Register as Pro'), findsOneWidget);
      expect(find.text('Professional Bio'), findsNothing);
    });

    testWidgets('talent has skills → "Professional Bio" row', (tester) async {
      _phoneView(tester);
      await tester.pumpWidget(_host(
        user: (ref) async => _user(),
        talent: (ref) async => <String, dynamic>{
          'professionalSkills': <String>['Electrician'],
        },
      ));
      await settle(tester);

      expect(find.text('Professional Bio'), findsOneWidget);
      expect(find.text('Register as Pro'), findsNothing);
    });

    testWidgets('profile loading → skeleton, no identity yet', (tester) async {
      _phoneView(tester);
      final never = Completer<User?>(); // never completes
      addTearDown(() => never.complete(null));
      await tester.pumpWidget(_host(user: (ref) => never.future));
      await tester.pump(); // one frame; stays in loading

      // The profile card renders as a GxSkeleton while the user resolves.
      expect(find.byType(GxSkeleton), findsWidgets);
      expect(find.text('Ada Lovelace'), findsNothing);
      // Menu groups render regardless of the async profile state.
      expect(find.text('My Wallet'), findsOneWidget);
    });

    testWidgets('profile error → error text', (tester) async {
      _phoneView(tester);
      await tester.pumpWidget(
          _host(user: (ref) async => throw Exception('nope')));
      await settle(tester);

      expect(find.textContaining('Error loading profile'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsNothing);
    });

    testWidgets('stats error → "Stats unavailable"', (tester) async {
      _phoneView(tester);
      await tester.pumpWidget(_host(
        user: (ref) async => _user(),
        stats: (ref) async => throw Exception('stats boom'),
      ));
      await settle(tester);

      // Identity still renders; only the stats row degrades.
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('Stats unavailable'), findsOneWidget);
    });

    testWidgets('availability toggle → updateProfile captured + snack',
        (tester) async {
      _phoneView(tester);
      final profile = _FakeProfileRepo();
      await tester.pumpWidget(_host(
        user: (ref) async => _user(available: true),
        profile: profile,
      ));
      await settle(tester);

      // The toggle starts on (isAvailableForWork == true); flip it off.
      final sw = find.byType(Switch);
      expect(sw, findsOneWidget);
      await tester.ensureVisible(sw);
      await tester.pump();
      await tester.tap(sw);
      await tester.pump(); // run onChanged: updateProfile + invalidate + snack
      await tester.pump();

      // The write reached the repository with the flipped value.
      expect(profile.updatedUserId, 'u1');
      expect(profile.updatedData, {'isAvailableForWork': false});
      // The "hidden" success snack is shown.
      expect(find.text('You are currently hidden from search'), findsOneWidget);

      // Drain the ScaffoldMessenger auto-dismiss timer before teardown.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('availability toggle ON → "visible to clients" success snack',
        (tester) async {
      _phoneView(tester);
      final profile = _FakeProfileRepo();
      // Start hidden (isAvailableForWork == false) so flipping the switch turns
      // it ON → the `val ? …` branch → the "now visible" success message.
      await tester.pumpWidget(_host(
        user: (ref) async => _user(available: false),
        profile: profile,
      ));
      await settle(tester);

      final sw = find.byType(Switch);
      expect(sw, findsOneWidget);
      await tester.ensureVisible(sw);
      await tester.pump();
      await tester.tap(sw);
      await tester.pump(); // run onChanged: updateProfile + invalidate + snack
      await tester.pump();

      // The write reached the repository with the flipped-on value.
      expect(profile.updatedUserId, 'u1');
      expect(profile.updatedData, {'isAvailableForWork': true});
      // The "visible" success snack is shown (not the "hidden" one).
      expect(find.text('You are now visible to clients for booking'),
          findsOneWidget);
      expect(find.text('You are currently hidden from search'), findsNothing);

      // Drain the ScaffoldMessenger auto-dismiss timer before teardown.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('availability toggle error → "Failed to update" error snack',
        (tester) async {
      _phoneView(tester);
      // The repo throws → the onChanged `catch` runs → the error snack, and the
      // write is never captured (there is no fake to capture on a thrower).
      await tester.pumpWidget(_host(
        user: (ref) async => _user(available: true),
        profile: _ThrowingProfileRepo(),
      ));
      await settle(tester);

      final sw = find.byType(Switch);
      expect(sw, findsOneWidget);
      await tester.ensureVisible(sw);
      await tester.pump();
      await tester.tap(sw);
      await tester.pump(); // run onChanged: updateProfile throws → catch → snack
      await tester.pump();

      // The error snack is shown; neither success message appears.
      expect(find.text('Failed to update availability'), findsOneWidget);
      expect(find.text('You are currently hidden from search'), findsNothing);
      expect(find.text('You are now visible to clients for booking'),
          findsNothing);

      // Drain the ScaffoldMessenger auto-dismiss timer before teardown.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('log out → signOut called + lands on WelcomeScreen',
        (tester) async {
      _phoneView(tester);
      final auth = _FakeAuthRepo();
      await tester.pumpWidget(_host(
        user: (ref) async => _user(),
        auth: auth,
      ));
      await settle(tester);

      final logout = find.text('Log Out');
      expect(logout, findsOneWidget);
      await tester.ensureVisible(logout);
      await tester.pump();
      await tester.tap(logout);
      await tester.pump(); // run signOut future + pushAndRemoveUntil
      await tester.pump();

      expect(auth.signedOut, isTrue);
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });
  });
}
