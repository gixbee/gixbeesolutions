// Gixbee 2026 — composed-screen widget test (Pass 120).
//
// Extends the ProviderScope-override pattern from `notifications_screen_test`
// (Pass 117), `my_bookings_screen_test` (Pass 118) and
// `worker_list_screen_test` (Pass 119) to a fourth real screen:
// `MessagesListScreen` (the chat inbox). It is driven entirely by the public,
// overridable `conversationsProvider`
// (a `FutureProvider.autoDispose<List<ChatConversation>>`), which we replace
// with a plain `ProviderScope` override to exercise each async branch
// (loading → skeletons, data → conversation cards, empty → GxEmptyState,
// error → inline error). No mock package (none is installed and none may be
// added), no Dio, no network.
//
// The screen's `initState` subscribes to `socketServiceProvider.messages`.
// The default `SocketService()` constructor is side-effect-free — it only
// creates two broadcast `StreamController`s and never opens a socket unless
// `connect()` is called (it isn't here) — so the real provider is safe to
// leave in place: the broadcast stream simply never emits during the test,
// and the subscription is cancelled in `dispose`.
//
// NOTE ON PUMPING: while the provider is loading, the screen shows
// `GxSkeleton`s, which drive a `..repeat()` controller and therefore never
// settle; the resolved branches fade in via `GxFade`. `pumpAndSettle` would
// time out on the loading frame, so this suite pumps explicit, bounded frames
// instead — never `pumpAndSettle`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/messages/messages_list_screen.dart';
import 'package:gixbee/repositories/chat_repository.dart';
import 'package:gixbee/shared/widgets/gx_empty.dart';
import 'package:gixbee/shared/widgets/gx_skeleton.dart';

/// Hosts the screen under a `ProviderScope` whose `conversationsProvider` is
/// replaced by [create]. A plain dark [ThemeData] is used (not `GixbeeTheme`)
/// so `Theme.of(context).colorScheme` resolves without pulling in google_fonts'
/// runtime font fetch.
Widget _host(FutureOr<List<ChatConversation>> Function() create) =>
    ProviderScope(
      overrides: [
        conversationsProvider.overrideWith((ref) => create()),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const MessagesListScreen(),
      ),
    );

ChatConversation _convo(String userId, String name, String last, int unread) =>
    ChatConversation(
      userId: userId,
      name: name,
      phoneNumber: '',
      lastMessage: last,
      lastAt: DateTime(2026, 1, 1),
      unread: unread,
    );

void main() {
  group('MessagesListScreen', () {
    testWidgets('loading → renders skeleton placeholders, not cards',
        (tester) async {
      // A future that never completes keeps the provider in AsyncLoading.
      final never = Completer<List<ChatConversation>>();
      await tester.pumpWidget(_host(() => never.future));
      await tester.pump(); // build (loading branch)
      await tester.pump(const Duration(milliseconds: 300)); // skeleton frame

      expect(find.byType(GxSkeleton), findsWidgets);
      // Neither the empty state nor any conversation should be showing yet.
      expect(find.byType(GxEmptyState), findsNothing);
      expect(find.text('No messages yet'), findsNothing);
    });

    testWidgets('data → renders one card per conversation', (tester) async {
      await tester.pumpWidget(_host(() async => [
            _convo('u1', 'Alice Plumber', 'On my way', 0),
            _convo('u2', 'Bob Electrician', 'Thanks!', 2),
          ]));
      await tester.pump(); // loading
      await tester.pump(); // provider resolves → data branch
      await tester.pump(const Duration(milliseconds: 400)); // GxFade settles

      expect(find.text('Alice Plumber'), findsOneWidget);
      expect(find.text('Bob Electrician'), findsOneWidget);
      // The unread conversation shows its count badge.
      expect(find.text('2'), findsOneWidget);
      // The empty state must not appear when there is data.
      expect(find.byType(GxEmptyState), findsNothing);
    });

    testWidgets('empty → renders the GxEmptyState placeholder', (tester) async {
      await tester.pumpWidget(_host(() async => <ChatConversation>[]));
      await tester.pump(); // loading
      await tester.pump(); // provider resolves → data branch (empty list)
      await tester.pump(const Duration(milliseconds: 400)); // GxFade settles

      expect(find.byType(GxEmptyState), findsOneWidget);
      expect(find.text('No messages yet'), findsOneWidget);
      expect(find.text('Chats with vendors and workers will appear here.'),
          findsOneWidget);
    });

    testWidgets('error → renders the inline error copy', (tester) async {
      await tester.pumpWidget(
          _host(() => Future<List<ChatConversation>>.error('boom')));
      await tester.pump(); // loading
      await tester.pump(); // provider resolves → error branch
      await tester.pump(const Duration(milliseconds: 400)); // GxFade settles

      expect(find.text('Could not load messages'), findsOneWidget);
      expect(find.byType(GxEmptyState), findsNothing);
    });

    testWidgets('search filters the visible conversations', (tester) async {
      await tester.pumpWidget(_host(() async => [
            _convo('u1', 'Alice Plumber', 'On my way', 0),
            _convo('u2', 'Bob Electrician', 'Thanks!', 0),
          ]));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Match on name: only Alice survives the filter.
      await tester.enterText(find.byType(TextField), 'alice');
      await tester.pump(); // setState → rebuild with filtered list
      await tester.pump(const Duration(milliseconds: 400)); // GxFade settles

      expect(find.text('Alice Plumber'), findsOneWidget);
      expect(find.text('Bob Electrician'), findsNothing);
    });

    testWidgets('search with no matches → renders the "No matches" empty state',
        (tester) async {
      await tester.pumpWidget(_host(() async => [
            _convo('u1', 'Alice Plumber', 'On my way', 0),
          ]));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.enterText(find.byType(TextField), 'zzz-no-such-name');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(GxEmptyState), findsOneWidget);
      expect(find.text('No matches'), findsOneWidget);
      expect(find.text('No conversations match your search.'), findsOneWidget);
    });

    testWidgets('header shows the title, search field and a refresh control',
        (tester) async {
      await tester.pumpWidget(_host(() async => <ChatConversation>[]));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Messages'), findsOneWidget);
      // The search pill is the only TextField on the screen.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    });
  });
}
