// Gixbee 2026 — composed-screen widget test (Pass 125).
//
// Extends the ProviderScope-override + fake-repository pattern (Passes 119–124)
// to `WalletScreen` (Profile → My Wallet, accentPurple quad). Like the other
// composed screens, this one has NO public `FutureProvider` seam: its
// `initState` reads `ref.read(walletRepositoryProvider)` and awaits
// `getBalance()` then `getTransactions()`, keeping its own `_isLoading` /
// `_balance` / `_transactions` local state.
//
// We swap in a `_FakeWalletRepo extends WalletRepository` whose `getBalance`
// and `getTransactions` return whatever the test seeds — no mock package (none
// is installed and none may be added), no Dio call, no network. The fake still
// calls `super(Dio())` to satisfy the base constructor, but that Dio is never
// used because both methods the screen hits are overridden.
//
// RAZORPAY NOTE (the concern the Pass 124 report flagged for this screen):
// `initState` constructs a `Razorpay()` platform-channel object. That
// constructor only registers a MethodChannel *incoming* handler
// (`setMethodCallHandler`) + an in-Dart event emitter, and the `.on(...)`
// listener registrations are pure Dart — none of them INVOKE the platform.
// `.open()` (the only outgoing `invokeMethod`) is reached solely from the
// "Proceed to Pay" tap, which no test triggers, and `dispose()`'s
// `_razorpay.clear()` is pure Dart. Even in the worst case, flutter_test's
// binary messenger returns null for a channel with no mock handler (it does
// NOT raise MissingPluginException), so constructing `Razorpay()` in a widget
// test is side-effect-free — no channel mock is needed.
//
// The AppBar ('My Wallet' + refresh action) sits OUTSIDE the `GxFade`, so it
// renders in every state and is asserted independent of the load branch. The
// loading→data swap crosses a `GxFade`/`AnimatedSwitcher` (280 ms) whose
// outgoing skeleton drives a `..repeat()` controller that never settles, so
// this suite pumps explicit, bounded frames instead of `pumpAndSettle`.
//
// A phone-sized viewport is set per test: WalletScreen composes a fixed balance
// card + a fixed-content "Add Money" panel, which overflows the default 800×600
// test surface. `tester.view` is sized to a realistic phone (400×866 logical)
// and reset on teardown so the fixed content lays out without a RenderFlex
// overflow.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/profile/wallet_screen.dart';
import 'package:gixbee/repositories/wallet_repository.dart';
import 'package:gixbee/shared/widgets/gx_skeleton.dart';

/// A hand-rolled fake `WalletRepository`. Only `getBalance` + `getTransactions`
/// are exercised by the screen's `initState`; every other method is inherited
/// (and never hit). `super(Dio())` satisfies the base ctor without opening any
/// connection.
class _FakeWalletRepo extends WalletRepository {
  _FakeWalletRepo({required this.balance, required this.transactions})
      : super(Dio());

  final Future<double> Function() balance;
  final Future<List<dynamic>> Function() transactions;

  @override
  Future<double> getBalance() => balance();

  @override
  Future<List<dynamic>> getTransactions() => transactions();
}

/// Builds a transaction map in the shape `WalletScreen` reads
/// (`type` / `description` / `amount` / `createdAt`).
Map<String, dynamic> _tx(String type, String description, num amount) => {
      'type': type,
      'description': description,
      'amount': amount,
      'createdAt': '2026-01-15T10:30:00.000Z',
    };

/// Hosts the screen under a `ProviderScope` whose `walletRepositoryProvider` is
/// replaced by a [_FakeWalletRepo]. WalletScreen IS its own `Scaffold` (AppBar +
/// body + ScaffoldMessenger), so it is used directly as `home`. A plain dark
/// [ThemeData] is used (not `GixbeeTheme`) so `Theme.of(context)` resolves
/// without pulling in google_fonts' runtime font fetch.
Widget _host({
  required Future<double> Function() balance,
  required Future<List<dynamic>> Function() transactions,
}) =>
    ProviderScope(
      overrides: [
        walletRepositoryProvider.overrideWithValue(
          _FakeWalletRepo(balance: balance, transactions: transactions),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const WalletScreen(),
      ),
    );

/// Gives the tester a realistic phone viewport (400×866 logical) so the fixed
/// balance card + "Add Money" panel lay out without a RenderFlex overflow, and
/// resets it after the test.
void _phoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('WalletScreen', () {
    testWidgets('loading → renders skeletons, AppBar present, no balance figure',
        (tester) async {
      _phoneView(tester);
      // Balance future that never completes keeps `_isLoading` true.
      final never = Completer<double>();
      await tester.pumpWidget(_host(
        balance: () => never.future,
        transactions: () async => const <dynamic>[],
      ));
      await tester.pump(); // build (loading branch)
      await tester.pump(const Duration(milliseconds: 300)); // skeleton frame

      expect(find.byType(GxSkeleton), findsWidgets);
      // The AppBar sits outside the GxFade, so it renders in every state.
      expect(find.text('My Wallet'), findsOneWidget);
      // The balance card (and its figure) has not been built yet.
      expect(find.text('₹0.00'), findsNothing);
    });

    testWidgets('data (funded) → balance figure, gate message, transactions',
        (tester) async {
      _phoneView(tester);
      await tester.pumpWidget(_host(
        balance: () async => 100.0,
        transactions: () async => [
          _tx('CREDIT', 'Top-up via UPI', 100),
          _tx('DEBIT', 'Booking payment', 50),
        ],
      ));
      await tester.pump(); // loading
      await tester.pump(); // getBalance resolves
      await tester.pump(); // getTransactions resolves → setState → data branch
      await tester.pump(const Duration(milliseconds: 400)); // GxFade settles

      // Balance figure (two-decimal) is unique to the balance hero card.
      expect(find.text('₹100.00'), findsOneWidget);
      // 100 ≥ ₹12 minimum → the "enough balance" gate line.
      expect(find.text('You have enough balance to book services.'),
          findsOneWidget);
      // Seeded transactions render by description.
      expect(find.text('Top-up via UPI'), findsOneWidget);
      expect(find.text('Booking payment'), findsOneWidget);
      // Skeletons are gone once loading finished.
      expect(find.byType(GxSkeleton), findsNothing);
    });

    testWidgets('low balance → warning gate line + red minimum note',
        (tester) async {
      _phoneView(tester);
      await tester.pumpWidget(_host(
        balance: () async => 5.0, // < ₹12 minimum
        transactions: () async => const <dynamic>[],
      ));
      await tester.pump(); // loading
      await tester.pump(); // getBalance resolves
      await tester.pump(); // getTransactions resolves → data branch
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('₹5.00'), findsOneWidget);
      expect(find.text('Low balance! Add funds to book a service.'),
          findsOneWidget);
      // The red min-requirement note only shows when low.
      expect(
        find.text(
            'Note: A minimum balance of ₹12 is required to connect with workers.'),
        findsOneWidget,
      );
      // No transactions seeded.
      expect(find.text('No transactions yet.'), findsOneWidget);
    });

    testWidgets('empty transactions (funded) → empty-list placeholder',
        (tester) async {
      _phoneView(tester);
      await tester.pumpWidget(_host(
        balance: () async => 100.0,
        transactions: () async => const <dynamic>[],
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('No transactions yet.'), findsOneWidget);
      // Funded → "enough balance" gate, and no red min note.
      expect(find.text('You have enough balance to book services.'),
          findsOneWidget);
      expect(
        find.text(
            'Note: A minimum balance of ₹12 is required to connect with workers.'),
        findsNothing,
      );
      expect(find.byType(GxSkeleton), findsNothing);
    });

    testWidgets('getBalance throws → caught, falls back to a ₹0 empty wallet',
        (tester) async {
      _phoneView(tester);
      await tester.pumpWidget(_host(
        balance: () => Future<double>.error(StateError('boom')),
        transactions: () async => const <dynamic>[],
      ));
      await tester.pump(); // loading
      await tester.pump(); // getBalance errors → caught, _isLoading=false
      await tester.pump(const Duration(milliseconds: 400)); // GxFade settles

      // The catch leaves the defaults (_balance 0.0, _transactions []) rather
      // than crashing — the data branch renders a ₹0 low-balance wallet. (No
      // showGxSnack in this screen's catch, so there is no pending Timer.)
      expect(find.text('₹0.00'), findsOneWidget);
      expect(find.text('No transactions yet.'), findsOneWidget);
      // Skeletons must be gone once loading finished.
      expect(find.byType(GxSkeleton), findsNothing);
    });

    testWidgets('chrome → AppBar refresh action + Add Money / Recent labels',
        (tester) async {
      _phoneView(tester);
      await tester.pumpWidget(_host(
        balance: () async => 100.0,
        transactions: () async => const <dynamic>[],
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('My Wallet'), findsOneWidget);
      // The AppBar refresh IconButton.
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      // Panel section labels + the primary CTA.
      expect(find.text('Add Money'), findsOneWidget);
      expect(find.text('Recent Transactions'), findsOneWidget);
      expect(find.text('Proceed to Pay'), findsOneWidget);
    });
  });
}
