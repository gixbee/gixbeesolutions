import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart';

final bookingRepositoryProvider = Provider((ref) {
  final dio = ref.watch(dioProvider);
  return BookingRepository(dio);
});

/// Shared provider that all booking screens watch.
/// Invalidate this after any mutation (accept, decline, complete, etc.)
final myBookingsProvider =
    FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final repo = ref.watch(bookingRepositoryProvider);
  return repo.getMyBookings();
});

class BookingRepository {
  final Dio _dio;

  BookingRepository(this._dio);

  // ── Create ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createBooking({
    required String workerId,
    required DateTime scheduledAt,
    required double amount,
    required String address,
    String? description,
    String? skill,
    String? addressId,
    String paymentMethod = 'WALLET',
  }) async {
    try {
      final response = await _dio.post('/bookings', data: {
        'workerId': workerId,
        'scheduledAt': scheduledAt.toIso8601String(),
        'amount': amount,
        'serviceLocation': address,
        if (description != null) 'description': description,
        if (skill != null) 'skill': skill,
        if (addressId != null) 'addressId': addressId,
        'paymentMethod': paymentMethod,
      });
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      debugPrint('CreateBooking failed: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> sendInstantRequest({
    required String workerId,
    required String skill,
    required String serviceLocation,
    required double lat,
    required double lng,
    required double amount,
    Map<String, dynamic>? onSiteContact,
    String paymentMethod = 'WALLET',
  }) async {
    try {
      final response = await _dio.post('/bookings', data: {
        'workerId': workerId,
        'skill': skill,
        'serviceLocation': serviceLocation,
        'serviceLat': lat,
        'serviceLng': lng,
        'amount': amount,
        'scheduledAt': DateTime.now().toIso8601String(),
        'type': 'INSTANT',
        if (onSiteContact != null) 'onSiteContact': onSiteContact,
        'paymentMethod': paymentMethod,
      });
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      debugPrint('SendInstantRequest failed: $e');
      rethrow;
    }
  }


  /// v126 broadcast dispatch: no worker chosen — the backend notifies every
  /// nearby live pro for [skill]; the first to accept is assigned. Returns
  /// the raw payload: { booking: {...}, notified: n }. When notified == 0 the
  /// caller should go straight to the no-workers screen.
  Future<Map<String, dynamic>> sendBroadcastRequest({
    required String skill,
    required String serviceLocation,
    required double lat,
    required double lng,
    required double amount,
    String? description,
    List<String>? preferredLanguages,
    String? addressId,
    Map<String, dynamic>? onSiteContact,
    String paymentMethod = 'WALLET',
  }) async {
    try {
      final response = await _dio.post('/bookings/instant', data: {
        'skill': skill,
        'serviceLocation': serviceLocation,
        'serviceLat': lat,
        'serviceLng': lng,
        'amount': amount,
        if (description != null) 'description': description,
        if (preferredLanguages != null && preferredLanguages.isNotEmpty)
          'preferredLanguages': preferredLanguages,
        if (addressId != null) 'addressId': addressId,
        if (onSiteContact != null) 'onSiteContact': onSiteContact,
        'paymentMethod': paymentMethod,
      });
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      debugPrint('SendBroadcastRequest failed: $e');
      rethrow;
    }
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<List<dynamic>> getMyBookings({
    String? status,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page.toString(),
        'limit': limit.toString(),
      };
      if (status != null) queryParams['status'] = status;
      final response =
          await _dio.get('/bookings/my', queryParameters: queryParams);
      return response.data as List<dynamic>;
    } catch (e) {
      debugPrint('GetMyBookings failed: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getBookingById(String id) async {
    try {
      final response = await _dio.get('/bookings/$id');
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      debugPrint('GetBookingById failed: $e');
      return null;
    }
  }

  /// Poll booking status from Redis cache (fast, used by WaitingForWorkerScreen)
  Future<Map<String, dynamic>> pollBookingStatus(String bookingId) async {
    try {
      final response = await _dio.get('/bookings/$bookingId/status');
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      debugPrint('PollBookingStatus failed: $e');
      rethrow;
    }
  }

  /// Returns all REQUESTED bookings assigned to the current worker.
  /// Used by the IncomingJobScreen queue and the 5-second poll fallback.
  Future<List<dynamic>> getPendingBookings() async {
    try {
      final response = await _dio.get('/bookings/pending');
      return response.data as List<dynamic>;
    } catch (e) {
      debugPrint('GetPendingBookings failed: $e');
      return [];
    }
  }

  // ── Worker Actions ────────────────────────────────────────────────────────

  /// Worker accepts one booking.
  /// Backend auto-cancels all other REQUESTED bookings for this worker.
  Future<void> acceptBooking(String bookingId) async {
    try {
      await _dio.patch('/bookings/$bookingId/accept');
    } catch (e) {
      debugPrint('AcceptBooking failed: $e');
      rethrow;
    }
  }

  /// Worker explicitly declines one pending booking request.
  /// Backend notifies the customer and removes it from the queue.
  /// Other pending requests remain unaffected.
  Future<void> rejectBooking(String bookingId) async {
    try {
      await _dio.patch('/bookings/$bookingId/reject');
    } catch (e) {
      debugPrint('RejectBooking failed: $e');
      rethrow;
    }
  }

  /// Gate 1: Worker confirms arrival at the service location.
  /// Triggers backend to mark booking ACTIVE.
  Future<void> markArrived(String bookingId) async {
    try {
      await _dio.patch('/bookings/$bookingId/arrive');
    } catch (e) {
      debugPrint('MarkArrived failed: $e');
      rethrow;
    }
  }

  /// Gate 1: Verify arrival OTP entered by worker.
  Future<void> confirmArrival({
    required String bookingId,
    required String otp,
  }) async {
    try {
      await _dio.post('/bookings/$bookingId/arrival', data: {'otp': otp});
    } catch (e) {
      debugPrint('ConfirmArrival failed: $e');
      rethrow;
    }
  }

  /// Gate 2: Worker marks job as complete.
  /// Triggers backend to send completion OTP to customer.
  Future<void> markComplete(String bookingId) async {
    try {
      await _dio.patch('/bookings/$bookingId/complete');
    } catch (e) {
      debugPrint('MarkComplete failed: $e');
      rethrow;
    }
  }

  /// Gate 2: Verify completion OTP entered by worker.
  Future<Map<String, dynamic>> confirmCompletion({
    required String bookingId,
    required String otp,
  }) async {
    try {
      final response = await _dio.post(
        '/bookings/$bookingId/completion',
        data: {'otp': otp},
      );
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      debugPrint('ConfirmCompletion failed: $e');
      rethrow;
    }
  }

  /// Refresh completion OTP (customer requests a new one)
  Future<String> refreshCompletionOtp(String bookingId) async {
    try {
      final response = await _dio.patch(
        '/bookings/$bookingId/refresh-completion-otp',
      );
      return response.data['completionOtp'] as String;
    } catch (e) {
      debugPrint('RefreshCompletionOtp failed: $e');
      rethrow;
    }
  }

  // ── Customer Actions ──────────────────────────────────────────────────────

  /// Cancels a booking with a reason and returns the refund outcome
  /// (`refundAmount`, `refundMethod`). The backend refunds WALLET-settled
  /// payments by reversing the settlement (worker debit + customer credit);
  /// directly collected payments (cash/UPI) are not wallet-credited —
  /// `refundMethod` is `DIRECT` and the parties settle offline.
  Future<Map<String, dynamic>> cancelBooking(
    String bookingId, {
    String reason = 'Not specified',
  }) async {
    try {
      final response = await _dio.patch(
        '/bookings/$bookingId/cancel',
        data: {'reason': reason},
      );
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      debugPrint('CancelBooking failed: $e');
      rethrow;
    }
  }

  // ── Rating & Dispute ──────────────────────────────────────────────────────

  Future<void> submitRating(String bookingId, int rating) async {
    try {
      await _dio.post('/bookings/$bookingId/rating', data: {'rating': rating});
    } catch (e) {
      debugPrint('SubmitRating failed: $e');
      rethrow;
    }
  }

  /// Worker rates the customer after completion (v126 parity — both sides
  /// rate). Backend validates the caller is this booking's operator.
  Future<void> rateCustomer(String bookingId, int rating) async {
    try {
      await _dio.post('/bookings/$bookingId/rate-customer',
          data: {'rating': rating});
    } catch (e) {
      debugPrint('RateCustomer failed: $e');
      rethrow;
    }
  }

  // ── Pause / resume (v126 Instant Help) ────────────────────────────────────
  // Worker asks → customer approves/declines → worker resumes. Status stays
  // ACTIVE; poll payload carries `pauseRequested` / `paused` / `pausedMinutes`.

  Future<void> requestPause(String bookingId) async {
    try {
      await _dio.patch('/bookings/$bookingId/pause-request');
    } catch (e) {
      debugPrint('RequestPause failed: $e');
      rethrow;
    }
  }

  Future<void> respondPause(String bookingId, {required bool approve}) async {
    try {
      await _dio.patch(
          '/bookings/$bookingId/${approve ? 'pause-approve' : 'pause-decline'}');
    } catch (e) {
      debugPrint('RespondPause failed: $e');
      rethrow;
    }
  }

  Future<void> resumeWork(String bookingId) async {
    try {
      await _dio.patch('/bookings/$bookingId/resume');
    } catch (e) {
      debugPrint('ResumeWork failed: $e');
      rethrow;
    }
  }

  Future<void> reportDispute(String bookingId, String reason) async {
    try {
      await _dio.post(
        '/bookings/$bookingId/dispute',
        data: {'reason': reason},
      );
    } catch (e) {
      debugPrint('ReportDispute failed: $e');
      rethrow;
    }
  }

  // ── Generic status update (admin / override) ──────────────────────────────

  Future<void> markPaid(String bookingId) async {
    try {
      await _dio.patch('/bookings/$bookingId/mark-paid');
    } catch (e) {
      debugPrint('MarkPaid failed: $e');
      rethrow;
    }
  }

  Future<void> updateBookingStatus(String bookingId, String status) async {
    try {
      await _dio.patch(
        '/bookings/$bookingId/status',
        data: {'status': status},
      );
    } catch (e) {
      debugPrint('UpdateBookingStatus failed: $e');
      rethrow;
    }
  }
}
