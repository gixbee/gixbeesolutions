import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'booking_repository.dart';
import '../core/config/app_config.dart';
import '../services/socket_service.dart';

/// Terminal booking statuses — HTTP fallback stops once we see one.
const _terminalStatuses = {
  'COMPLETED',
  'CANCELLED',
  'REJECTED',
};

bool _isTerminalStatus(String? status) =>
    _terminalStatuses.contains((status ?? '').toUpperCase());

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
/// - Terminal status → stop HTTP polling entirely (socket already delivered)
final bookingStatusProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, bookingId) {
  final repo = ref.watch(bookingRepositoryProvider);
  final socketService = ref.watch(socketServiceProvider);
  final controller = StreamController<Map<String, dynamic>>();

  Timer? timer;
  var inFlight = false;
  var disposed = false;
  var terminal = false;

  Future<void> tick() async {
    if (disposed || inFlight || terminal) return;
    inFlight = true;
    try {
      final data = await repo.pollBookingStatus(bookingId);
      if (!disposed && !controller.isClosed) {
        controller.add(data);
        if (_isTerminalStatus(data['status']?.toString())) {
          terminal = true;
          timer?.cancel();
          timer = null;
        }
      }
    } catch (e) {
      // Transient poll failures are non-fatal: keep the last good value and
      // retry on the next tick rather than erroring the whole stream.
      debugPrint('Booking status poll failed ($bookingId): $e');
    } finally {
      inFlight = false;
    }
  }

  void start() {
    if (disposed || terminal) return;
    timer?.cancel();
    final seconds = socketService.isConnected
        ? AppConfig.bookingPollBackoffSeconds
        : AppConfig.bookingPollIntervalSeconds;
    timer = Timer.periodic(Duration(seconds: seconds), (_) => tick());
  }

  final socketSub = socketService.notifications.listen((data) {
    final event = data['_event'] as String?;
    if (event == 'booking_status_update' ||
        event == 'booking_accepted' ||
        event == 'booking_cancelled') {
      final targetId = (data['bookingId'] ?? data['id'])?.toString();
      if (targetId == bookingId && !disposed && !controller.isClosed) {
        debugPrint(
            '[BookingStatusProvider] Instant socket push received for $bookingId: ${data['status'] ?? event}');
        controller.add(Map<String, dynamic>.from(data));
        if (_isTerminalStatus(data['status']?.toString()) ||
            event == 'booking_cancelled') {
          terminal = true;
          timer?.cancel();
          timer = null;
        }
      }
    }
  });

  // Re-tune poll interval when socket drops/reconnects (fast when offline).
  final connectSub = socketService.connectionChanges.listen((connected) {
    if (disposed || terminal) return;
    if (connected) {
      // Fresh push path is back — slow the fallback.
      start();
    } else {
      tick();
      start();
    }
  });

  // Pause polling while backgrounded; refresh immediately on resume.
  final lifecycleListener = AppLifecycleListener(
    onPause: () => timer?.cancel(),
    onResume: () {
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
