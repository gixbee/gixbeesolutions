// Gixbee 2026 — composed-screen widget test (Pass 127): OffersScreen.
//
// Unlike the Pass 117–125 screens, OffersScreen has NO data seam: it is a pure
// `ConsumerWidget` that renders three hard-coded promo cards from static
// content (no provider, no repository, no Dio, no network). So no
// `ProviderScope` override is needed — a bare `ProviderScope` + `MaterialApp`
// hosts it. The one interaction, "Claim Offer", copies the promo code to the
// clipboard (`Clipboard.setData`) and confirms via a `showGxSnack` toast; this
// suite mocks the `SystemChannels.platform` clipboard channel to capture the
// copied code and drains the SnackBar's auto-dismiss Timer before teardown.
//
// A plain dark ThemeData is used (not GixbeeTheme) so `colorScheme.secondary` /
// `.tertiary` (the 2nd/3rd cards' accents) resolve without google_fonts'
// runtime font fetch. DribbbleBackground is a StatelessWidget with no repeating
// animation, so bounded pumps suffice (never `pumpAndSettle`).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/jobs/offers_screen.dart';
import 'package:gixbee/shared/widgets/gx_button.dart';

/// Hosts the screen under a bare `ProviderScope` (no overrides needed — the
/// screen reads no providers) + a dark `MaterialApp`.
Widget _host() => ProviderScope(
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const OffersScreen(),
      ),
    );

void main() {
  group('OffersScreen', () {
    testWidgets('renders the AppBar title and all three offer cards',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump();

      expect(find.text('Special Offers'), findsOneWidget);
      expect(find.text('Summer Special'), findsOneWidget);
      expect(find.text('Referral Bonus'), findsOneWidget);
      expect(find.text('New Professional'), findsOneWidget);
    });

    testWidgets('renders each promo code and a Claim Offer button per card',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump();

      expect(find.text('SUMMER20'), findsOneWidget);
      expect(find.text('GIXFRIEND'), findsOneWidget);
      expect(find.text('FIRSTPRO'), findsOneWidget);
      expect(
          find.widgetWithText(GxButton, 'Claim Offer'), findsNWidgets(3));
    });

    testWidgets('renders exactly three claimable offer buttons',
        (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump();

      expect(find.byType(GxButton), findsNWidgets(3));
    });

    testWidgets("tapping Claim Offer copies that card's code and toasts",
        (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      String? copied;
      messenger.setMockMethodCallHandler(SystemChannels.platform,
          (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(_host());
      await tester.pump();

      // The first card is the Summer Special (code SUMMER20).
      await tester.tap(find.widgetWithText(GxButton, 'Claim Offer').first);
      await tester.pump(); // run async _claimOffer (clipboard write)
      await tester.pump(); // showGxSnack enqueues the toast
      await tester.pump(const Duration(milliseconds: 400)); // toast animates in

      expect(copied, 'SUMMER20');
      expect(find.textContaining('copied'), findsOneWidget);

      // Drain the SnackBar's auto-dismiss Timer (3s) so teardown sees no
      // pending Timer.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
