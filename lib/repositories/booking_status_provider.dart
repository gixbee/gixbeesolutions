import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'booking_repository.dart';
import '../core/config/app_config.dart';

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
/// Interval is a **fallback** (FCM + Socket.IO are primary). Backend serves
/// status from Redis when warm so these ticks stay cheap.
final bookingStatusProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, bookingId) {
  final repo = ref.watch(bookingRepositoryProvider);
  final controller = StreamController<Map<String, dynamic>>();

  Timer? timer;
  var inFlight = false;
  var disposed = false;

  Future<void> tick() async {
    if (disposed || inFlight) return; // never stack overlapping requests
    inFlight = true;
    try {
      final data = await repo.pollBookingStatus(bookingId);
      if (!disposed && !controller.isClosed) controller.add(data);
    } catch (e) {
      // Transient poll failures are non-fatal: keep the last good value and
      // retry on the next tick rather than erroring the whole stream.
      debugPrint('Booking status poll failed ($bookingId): $e');
    } finally {
      inFlight = false;
    }
  }

  void start() {
    timer?.cancel();
    timer = Timer.periodic(
      Duration(seconds: AppConfig.bookingPollIntervalSeconds),
      (_) => tick(),
    );
  }

  // Pause polling while backgrounded; refresh immediately on resume.
  final lifecycleListener = AppLifecycleListener(
    onPause: () => timer?.cancel(),
    onResume: () {
      tick();
      start();
    },
  );

  tick(); // immediate first value
  start();

  ref.onDispose(() {
    disposed = true;
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
