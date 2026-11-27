import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'booking_repository.dart';
import '../core/config/app_config.dart';
import '../services/socket_service.dart';
import '../shared/utils/booking_flags.dart';

/// Terminal booking statuses — HTTP fallback stops once we see one.
const _terminalStatuses = {
  'CANCELLED',
  'REJECTED',
};

/// Still matching / awaiting accept — keep HTTP fallback fast even when the
/// socket looks connected (accept can land in DB before the push arrives).
const _openMatchStatuses = {
  'REQUESTED',
  'PENDING',
  'CUSTOM_REQUESTED',
};

bool _isTerminalStatus(String? status) =>
    _terminalStatuses.contains((status ?? '').toUpperCase());

bool _isOpenMatchStatus(String? status) =>
    _openMatchStatuses.contains((status ?? '').toUpperCase());

/// Bridge for status changes that arrive over FCM instead of the socket —
/// background pushes, or a foreground push while the socket is down.
///
/// Callers publish only the booking id: the push body is a hint, so the
/// affected stream answers with an immediate poll and keeps the server as the
/// single source of truth.
class BookingStatusNudge {
  final _controller = StreamController<String>.broadcast();

  Stream<String> get stream => _controller.stream;

  void poke(String bookingId) {
    if (bookingId.isEmpty || _controller.isClosed) return;
    _controller.add(bookingId);
  }

  void dispose() => _controller.close();
}

final bookingStatusNudgeProvider = Provider<BookingStatusNudge>((ref) {
  final nudge = BookingStatusNudge();
  ref.onDispose(nudge.dispose);
  return nudge;
});

/// AUDIT FIX — single source of truth for live booking status.
///
/// Before: the tracking screen (5s), the home active-booking card (10s) and
/// the in-job controls (5s) each ran their own `Timer.periodic` hitting
/// `GET /bookings/:id/status` — up to 3 concurrent polls for the SAME booking.
///
/// Now: one `StreamProvider.family` per bookingId. Riverpod shares a single
/// stream across every widget watching the same id, and `autoDispose` tears
/// the timer down when the last listener goes away. The poll also pauses
/// while the app is backgrounded and fires an immediate refresh on resume.
///
/// Interval is a **fallback** (FCM + Socket.IO are primary):
/// - Socket connected → slow poll ([AppConfig.bookingPollBackoffSeconds])
/// - Socket down → fast poll ([AppConfig.bookingPollIntervalSeconds])
/// - Completed and unpaid → keep polling until the API confirms payment
/// - Terminal status or completed and paid → stop polling
final bookingStatusProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, bookingId) {
  final repo = ref.watch(bookingRepositoryProvider);
  final socketService = ref.watch(socketServiceProvider);
  final controller = StreamController<Map<String, dynamic>>();

  Timer? timer;
  var inFlight = false;
  var refreshQueued = false;
  var paused = false;
  var disposed = false;
  var terminal = false;
  String? lastStatus;
  late void Function() start;

  Future<void> tick({bool queueIfBusy = false}) async {
    if (disposed || paused || terminal) return;
    if (inFlight) {
      refreshQueued = refreshQueued || queueIfBusy;
      return;
    }
    inFlight = true;
    try {
      final data = await repo.pollBookingStatus(bookingId);
      if (!disposed && !controller.isClosed) {
        final prev = lastStatus;
        lastStatus = data['status']?.toString().toUpperCase();
        controller.add(data);
        if (_isTerminalStatus(lastStatus) ||
            (lastStatus == 'COMPLETED' && bookingFlagTrue(data['isPaid']))) {
          terminal = true;
          timer?.cancel();
          timer = null;
        } else if (prev != lastStatus) {
          // Open → accepted (etc.): retune poll interval immediately.
          start();
        }
      }
    } catch (e) {
      // Transient poll failures are non-fatal: keep the last good value and
      // retry on the next tick rather than erroring the whole stream.
      debugPrint('Booking status poll failed ($bookingId): $e');
    } finally {
      inFlight = false;
      if (refreshQueued) {
        refreshQueued = false;
        unawaited(tick());
      }
    }
  }

  start = () {
    if (disposed || paused || terminal) return;
    timer?.cancel();
    // Fast while matching (or socket down); backoff only after accept when
    // the socket is healthy.
    final seconds = !socketService.isLiveForPolling ||
            _isOpenMatchStatus(lastStatus) ||
            lastStatus == 'COMPLETED'
        ? AppConfig.bookingPollIntervalSeconds
        : AppConfig.bookingPollBackoffSeconds;
    timer = Timer.periodic(Duration(seconds: seconds), (_) => tick());
  };

  final socketSub = socketService.notifications.listen((data) {
    final event = data['_event'] as String?;
    if (event == 'booking_status_update' ||
        event == 'booking_accepted' ||
        event == 'booking_cancelled') {
      final targetId = (data['bookingId'] ?? data['id'])?.toString();
      if (targetId == bookingId && !disposed && !controller.isClosed) {
        debugPrint(
            '[BookingStatusProvider] Instant socket push received for $bookingId: ${data['status'] ?? event}');
        unawaited(tick(queueIfBusy: true));
      }
    }
  });

  final nudgeSub =
      ref.watch(bookingStatusNudgeProvider).stream.listen((nudgedId) {
    if (nudgedId != bookingId || disposed || terminal) return;
    debugPrint('[BookingStatusProvider] FCM nudge for $bookingId — polling');
    tick(queueIfBusy: true);
  });

  // Re-tune poll interval when socket drops/reconnects (fast when offline).
  final connectSub = socketService.connectionChanges.listen((connected) {
    if (disposed || terminal) return;
    if (connected) {
      tick();
      start();
    } else {
      tick();
      start();
    }
  });

  // Pause polling while backgrounded; refresh immediately on resume.
  final lifecycleListener = AppLifecycleListener(
    onPause: () {
      paused = true;
      timer?.cancel();
    },
    onResume: () {
      paused = false;
      if (terminal) return;
      tick();
      start();
    },
  );

  tick(); // immediate first value
  start();

  ref.onDispose(() {
    disposed = true;
    socketSub.cancel();
    nudgeSub.cancel();
    connectSub.cancel();
    timer?.cancel();
    lifecycleListener.dispose();
    controller.close();
  });

  return controller.stream;
});

/// Convenience: the uppercase status string ('' until the first poll lands).
final bookingStatusStringProvider =
    Provider.autoDispose.family<String, String>((ref, bookingId) {
  final data = ref.watch(bookingStatusProvider(bookingId)).value;
  return data?['status']?.toString().toUpperCase() ?? '';
});
