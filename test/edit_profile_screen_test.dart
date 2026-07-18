// Gixbee 2026 — composed-screen widget test (Pass 126).
//
// Extends the ProviderScope-override pattern (Passes 119–125) to
// `EditProfileScreen` (Profile → Edit Profile, accentPurple quad). Unlike the
// wallet/tracker screens — which own their `_isLoading` state and read a
// `Repository` in `initState` — this screen's data seam IS a real Riverpod
// `FutureProvider`: `currentUserProvider` (FutureProvider<User?> from
// auth_repository). The screen `ref.listen`s it in `build` and, exactly once,
// seeds the name field (`_nameController.text = user.name`) and the avatar
// (`_photoUrl = user.avatar`) via `whenData`.
//
// So the whole suite drives off `currentUserProvider.overrideWith(...)` — no
// fake repository, no mock package, no Dio, no network. Because the override
// fully supplies the value, the provider body (which would read
// `authTokenServiceProvider` + call `getProfile()` over the network) never runs.
//
// The screen renders its `Form` immediately (there is NO loading skeleton and
// NO infinite animation — the camera-badge spinner only shows while
// `_uploadingPhoto`, which no test triggers), so `pumpAndSettle` is safe here
// and used for the seeded cases. `_save` (awaits the provider + hits
// `profileRepository.updateProfile`) and `_pickPhoto` (image_picker platform
// channel) are never triggered, so no platform channel is touched. The avatar
// `NetworkImage` fails to load in the test HttpClient harness, which is a
// silent image-stream error (not an uncaught test exception), so it needs no
// handling here — same as the other avatar-bearing suites (worker_list).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/profile/edit_profile_screen.dart';
import 'package:gixbee/repositories/auth_repository.dart';
import 'package:gixbee/shared/models/user.dart';
import 'package:gixbee/shared/widgets/gx_text_field.dart';

/// Builds a [User] with just the fields `EditProfileScreen` seeds from
/// (`name` / `avatar`); the rest use the model defaults.
User _user({String? name, String? avatar}) => User(
      id: 'u1',
      phone: '+919999999999',
      name: name,
      avatar: avatar,
    );

/// Hosts the screen under a `ProviderScope` whose `currentUserProvider` is
/// replaced by [create]. EditProfileScreen IS its own `Scaffold` (AppBar +
/// gradient body), so it is used directly as `home`. A plain dark [ThemeData]
/// is used (not `GixbeeTheme`) so `Theme.of(context)` resolves without pulling
/// in google_fonts' runtime font fetch.
Widget _host(FutureOr<User?> Function(Ref ref) create) => ProviderScope(
      overrides: [currentUserProvider.overrideWith(create)],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const EditProfileScreen(),
      ),
    );

/// Reads the live text out of the single [GxTextField] (the Full Name input).
String _nameFieldText(WidgetTester tester) {
  final field = tester.widget<TextFormField>(find.byType(TextFormField));
  return field.controller?.text ?? '';
}

void _phoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('EditProfileScreen', () {
    testWidgets('chrome → AppBar, Full Name label, camera badge, Save button',
        (tester) async {
      _phoneView(tester);
      await tester.pumpWidget(_host((ref) async => _user(name: 'Ada Lovelace')));
      await tester.pumpAndSettle();

      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Full Name'), findsOneWidget);
      // Camera-badge icon (idle, not the uploading spinner).
      expect(find.byIcon(Icons.camera_alt), findsOneWidget);
      // The single Save Changes CTA.
      expect(find.text('Save Changes'), findsOneWidget);
    });

    testWidgets('seeds the name field from the resolved user', (tester) async {
      _phoneView(tester);
      await tester.pumpWidget(_host((ref) async => _user(name: 'Ada Lovelace')));
      await tester.pumpAndSettle();

      // The seeded name is rendered in the Full Name field.
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(_nameFieldText(tester), 'Ada Lovelace');
    });

    testWidgets('user with null name → field left empty (no seed)',
        (tester) async {
      _phoneView(tester);
      await tester.pumpWidget(_host((ref) async => _user(name: null)));
      await tester.pumpAndSettle();

      // Nothing to seed → the controller stays empty; chrome still renders.
      expect(_nameFieldText(tester), isEmpty);
      expect(find.byType(GxTextField), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);
    });

    testWidgets('logged-out (null user) → field empty, screen still renders',
        (tester) async {
      _phoneView(tester);
      await tester.pumpWidget(_host((ref) async => null));
      await tester.pumpAndSettle();

      expect(_nameFieldText(tester), isEmpty);
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);
    });

    testWidgets('while the profile is still loading → empty field, no crash',
        (tester) async {
      _phoneView(tester);
      final never = Completer<User?>();
      await tester.pumpWidget(_host((ref) => never.future));
      await tester.pump(); // build (AsyncLoading — listen has not fired)
      await tester.pump(const Duration(milliseconds: 200));

      // No data yet → no seed; the form renders immediately regardless.
      expect(_nameFieldText(tester), isEmpty);
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.byType(GxTextField), findsOneWidget);
    });

    testWidgets('typing into the empty field updates it', (tester) async {
      _phoneView(tester);
      await tester.pumpWidget(_host((ref) async => _user(name: null)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Grace Hopper');
      await tester.pump();

      expect(_nameFieldText(tester), 'Grace Hopper');
      expect(find.text('Grace Hopper'), findsOneWidget);
    });
  });
}
