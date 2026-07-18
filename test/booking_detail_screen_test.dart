// Gixbee 2026 — composed-screen widget test (Pass 126).
//
// Extends the ProviderScope-override pattern from the Pass 117–125 suites
// (`notifications_screen`, `my_bookings`, `worker_list`, `wallet`, …) to
// `BookingDetailScreen` (Bookings tab / active-booking pill → booking detail).
//
// This screen is a `ConsumerWidget` driven entirely by two inputs we fully
// control from the test:
//   1. its required `Map<String, dynamic> booking` prop (status / OTPs /
//      counterpart / amount / scheduledAt / id), and
//   2. the public, overridable `currentUserProvider` (a
//      `FutureProvider<User?>`) — which decides `isAssignedWorker`
//      (customer view vs. the assigned-worker Accept/Decline view).
// We replace `currentUserProvider` with a plain `ProviderScope` override so no
// Dio / network is touched, and we exercise each visible branch: the status
// hero + progress dots, the initials-fallback avatar, the Security-PIN OTP
// cards (Arrival on ACCEPTED, Completion on ACTIVE), the Track-Live-Location
// CTA (ACTIVE only), the COMPLETED "PROFESSIONAL" relabel, the terminal
// CANCELLED no-dots path, and the worker Accept/Decline bar.
//
// AVATAR = INITIALS ONLY: every fixture omits `profileImageUrl`, so the avatar
// falls to the purple-gradient initials Container and the screen never builds a
// `NetworkImage` — no HTTP shim is needed under the test harness.
//
// PUMPING: this screen has no skeletons and no repeating animations, but
// `currentUserProvider` is async, so after `pumpWidget` we pump a couple of
// bounded frames to let the override future resolve and the screen rebuild —
// never `pumpAndSettle` (kept consistent with the sibling suites).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/jobs/booking_detail_screen.dart';
import 'package:gixbee/repositories/auth_repository.dart';
import 'package:gixbee/shared/models/user.dart';

/// A minimal signed-in [User]; only `id` matters for `isAssignedWorker`.
User _user(String id) => User(id: id, phone: '+910000000000', name: 'Me');

/// Hosts [BookingDetailScreen] under a `ProviderScope` whose
/// `currentUserProvider` resolves to [user] (or null = signed-out / customer).
/// A plain dark [ThemeData] is used (not `GixbeeTheme`) so `Theme.of(context)`
/// resolves without pulling in google_fonts' runtime font fetch — the screen's
/// own colours come from `GixbeeTheme`'s static consts, not the ambient theme.
Widget _host(Map<String, dynamic> booking, {User? user}) => ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) async => user),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: BookingDetailScreen(booking: booking),
      ),
    );

/// pumpWidget + two bounded frames so the async `currentUserProvider` override
/// resolves and the screen settles on its final (data) build.
Future<void> _pumpScreen(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(w);
  await tester.pump(); // flush the override future's microtask
  await tester.pump(); // rebuild with the resolved user
}

void main() {
  group('BookingDetailScreen', () {
    testWidgets('REQUESTED (customer) → status hero, summary + payment total',
        (tester) async {
      await _pumpScreen(
        tester,
        _host({
          'id': 'BK12345678XYZ',
          'status': 'REQUESTED',
          'skill': 'Plumbing',
          'amount': 500,
          'scheduledAt': '2026-07-10T14:30:00',
          'customer': {'name': 'Asha Rao'},
        }),
      );

      // AppBar + status hero.
      expect(find.text('Booking Details'), findsOneWidget);
      expect(find.text('REQUESTED'), findsOneWidget);
      // Ref ID = first 8 chars of the id, upper-cased.
      expect(find.text('Ref ID: BK123456'), findsOneWidget);
      // Progress dots render on the happy path (step 0) → the step labels show.
      expect(find.text('Requested'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      // Counterpart card: initials-fallback avatar (no network image).
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      // Section labels + payment: service fee AND total both read ₹500.
      expect(find.text('SERVICE SUMMARY'), findsOneWidget);
      expect(find.text('PAYMENT DETAILS'), findsOneWidget);
      expect(find.text('₹500'), findsNWidgets(2));
      expect(find.text('Plumbing'), findsOneWidget);
    });

    testWidgets('ACCEPTED (customer) → Security PIN + Arrival OTP + Message',
        (tester) async {
      await _pumpScreen(
        tester,
        _host(
          {
            'id': 'BK000001',
            'status': 'ACCEPTED',
            'amount': 300,
            'scheduledAt': '2026-07-10T09:00:00',
            'arrivalOtp': '4821',
            'operator': {'id': 'op1', 'name': 'Ravi Kumar'},
            'customer': {'id': 'cust99', 'name': 'Asha'},
          },
          user: _user('cust99'), // != operator → customer view
        ),
      );

      expect(find.text('SECURITY PIN'), findsOneWidget);
      expect(find.text('Arrival OTP'), findsOneWidget);
      expect(find.text('4821'), findsOneWidget);
      // Operator shown as the counterpart, not-yet-completed label.
      expect(find.text('ASSIGNED PROFESSIONAL'), findsOneWidget);
      expect(find.text('Ravi Kumar'), findsOneWidget);
      // Counterpart exists → the Message CTA is present.
      expect(find.text('Message'), findsOneWidget);
    });

    testWidgets('ACTIVE (customer) → Completion OTP + Track Live Location',
        (tester) async {
      await _pumpScreen(
        tester,
        _host(
          {
            'id': 'BK000002',
            'status': 'ACTIVE',
            'amount': 300,
            'scheduledAt': '2026-07-10T09:00:00',
            'completionOtp': '7777',
            'operator': {'id': 'op1', 'name': 'Ravi Kumar'},
            'customer': {'id': 'cust99', 'name': 'Asha'},
          },
          user: _user('cust99'),
        ),
      );

      expect(find.text('Completion OTP'), findsOneWidget);
      expect(find.text('7777'), findsOneWidget);
      // The ACTIVE-only live-tracking CTA.
      expect(find.text('Track Live Location'), findsOneWidget);
    });

    testWidgets('COMPLETED → relabels to PROFESSIONAL, no cancel action',
        (tester) async {
      await _pumpScreen(
        tester,
        _host(
          {
            'id': 'BK000003',
            'status': 'COMPLETED',
            'totalAmount': 800,
            'scheduledAt': '2026-07-10T09:00:00',
            'operator': {'id': 'op1', 'name': 'Ravi Kumar'},
            'customer': {'id': 'cust99', 'name': 'Asha'},
          },
          user: _user('cust99'),
        ),
      );

      // COMPLETED uses the shorter 'PROFESSIONAL' section label (exact match —
      // does not collide with the longer 'ASSIGNED PROFESSIONAL' string).
      expect(find.text('PROFESSIONAL'), findsOneWidget);
      expect(find.text('ASSIGNED PROFESSIONAL'), findsNothing);
      expect(find.text('COMPLETED'), findsOneWidget);
      expect(find.text('₹800'), findsNWidgets(2));
      // Terminal state: no cancel round-action, and no ACTIVE-only tracking CTA.
      expect(find.byIcon(Icons.cancel_outlined), findsNothing);
      expect(find.text('Track Live Location'), findsNothing);
    });

    testWidgets('REQUESTED (assigned worker) → Accept/Decline bar',
        (tester) async {
      await _pumpScreen(
        tester,
        _host(
          {
            'id': 'BK000004',
            'status': 'REQUESTED',
            'amount': 450,
            'scheduledAt': '2026-07-10T09:00:00',
            'operator': {'id': 'w1', 'name': 'Bob Worker'},
            'customer': {'id': 'c1', 'name': 'Asha'},
          },
          user: _user('w1'), // == operator → assigned-worker view
        ),
      );

      expect(find.text('Accept Job'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      // Worker view is not offered the customer cancel round-action.
      expect(find.byIcon(Icons.cancel_outlined), findsNothing);
    });

    testWidgets('CANCELLED → terminal, no progress dots', (tester) async {
      await _pumpScreen(
        tester,
        _host(
          {
            'id': 'BK000005',
            'status': 'CANCELLED',
            'amount': 300,
            'scheduledAt': '2026-07-10T09:00:00',
            'operator': {'id': 'op1', 'name': 'Ravi Kumar'},
            'customer': {'id': 'cust99', 'name': 'Asha'},
          },
          user: _user('cust99'),
        ),
      );

      expect(find.text('CANCELLED'), findsOneWidget);
      // step == null for terminal states → the progress-dot label row is absent.
      expect(find.text('Requested'), findsNothing);
      expect(find.text('Done'), findsNothing);
      // Counterpart still messageable, but no cancel action on a cancelled job.
      expect(find.text('Message'), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsNothing);
    });
  });
}
