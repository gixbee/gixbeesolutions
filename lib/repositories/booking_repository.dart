import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart'; // To get dioProvider

final bookingRepositoryProvider = Provider((ref) {
  final dio = ref.watch(dioProvider);
  return BookingRepository(dio);
});

class BookingRepository {
  final Dio _dio;

  BookingRepository(this._dio);

  Future<Map<String, dynamic>> createBooking({
    required String workerId,
    required DateTime scheduledAt,
    required double amount,
    required String address,
    String? description,
  }) async {
    try {
      final response = await _dio.post('/bookings', data: {
        'workerId': workerId,
        'scheduledAt': scheduledAt.toIso8601String(),
        'amount': amount,
        'serviceLocation': address,
        'description': description,
      });
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      debugPrint('CreateBooking failed: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getMyBookings() async {
    try {
      final response = await _dio.get('/bookings/my');
      return response.data as List<dynamic>;
    } catch (e) {
      debugPrint('GetMyBookings failed: $e');
      return [];
    }
  }

  /// Gate 1: Confirm the worker has arrived at the service location
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

  /// Gate 2: Confirm the job is complete
  Future<void> confirmCompletion({
    required String bookingId,
    required String otp,
  }) async {
    try {
      await _dio.post('/bookings/$bookingId/completion', data: {'otp': otp});
    } catch (e) {
      debugPrint('ConfirmCompletion failed: $e');
      rethrow;
    }
  }

  // Vendor approve/reject a booking request
  Future<void> updateBookingStatus(String bookingId, String status) async {
    await _dio.patch('/bookings/$bookingId/status', data: {'status': status});
  }

  // Customer confirm after vendor approves
  Future<void> confirmBooking(String bookingId) async {
    await _dio.patch('/bookings/$bookingId/confirm');
  }

  // Worker taps Arrived — triggers arrival OTP sent to user
  Future<void> markArrived(String bookingId) async {
    await _dio.patch('/bookings/$bookingId/arrive');
  }

  // Worker taps Finish — triggers completion OTP sent to user
  Future<void> markComplete(String bookingId) async {
    await _dio.patch('/bookings/$bookingId/complete');
  }

  // Get blocked calendar dates for a vendor
  Future<List<DateTime>> getCalendarDates(String vendorId) async {
    try {
      final res = await _dio.get('/bookings/calendar/$vendorId');
      final List<dynamic> datesStr = res.data;
      return datesStr.map((d) => DateTime.parse(d as String)).toList();
    } catch (e) {
      debugPrint('GetCalendarDates failed: $e');
      return [];
    }
  }

  // ─── STEP 4: INSTANT REQUEST + ACCEPT FLOW ────────────────

  /// Customer sends an instant service request
  Future<Map<String, dynamic>> sendInstantRequest({
    required String workerId,
    required String skill,
    required String serviceLocation,
    required double lat,
    required double lng,
    required double amount,
    Map<String, String>? onSiteContact,
  }) async {
    try {
      final response = await _dio.post('/bookings', data: {
        'workerId': workerId,
        'skill': skill,
        'serviceLocation': serviceLocation,
        'serviceLat': lat,
        'serviceLng': lng,
        'amount': amount,
        'type': 'INSTANT',
        'scheduledAt': DateTime.now().toIso8601String(),
        if (onSiteContact != null) 'onSiteContact': onSiteContact,
      });
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      debugPrint('SendInstantRequest failed: $e');
      rethrow;
    }
  }

  /// Worker accepts an incoming job request
  Future<void> acceptBooking(String bookingId) async {
    try {
      await _dio.patch('/bookings/$bookingId/accept');
    } catch (e) {
      debugPrint('AcceptBooking failed: $e');
      rethrow;
    }
  }

  /// Poll for REQUESTED bookings assigned to this worker (FCM fallback)
  Future<List<dynamic>> getPendingBookings() async {
    try {
      final response = await _dio.get('/bookings/pending');
      return response.data as List<dynamic>;
    } catch (e) {
      debugPrint('GetPendingBookings failed: $e');
      return [];
    }
  }

  /// Poll the booking status (customer waits for worker acceptance)
  Future<Map<String, dynamic>> pollBookingStatus(String bookingId) async {
    try {
      final response = await _dio.get('/bookings/$bookingId/status');
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      debugPrint('PollBookingStatus failed: $e');
      rethrow;
    }
  }

  /// Cancel a booking request
  Future<void> cancelBooking(String bookingId) async {
    try {
      await _dio.patch('/bookings/$bookingId/status', data: {'status': 'CANCELLED'});
    } catch (e) {
      debugPrint('CancelBooking failed: $e');
      rethrow;
    }
  }

  /// Get specific booking details
  Future<Map<String, dynamic>?> getBookingById(String id) async {
    try {
      final response = await _dio.get('/bookings/$id');
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      debugPrint('GetBookingById failed: $e');
      return null;
    }
  }
  /// Refresh completion OTP
  Future<String> refreshCompletionOtp(String bookingId) async {
    try {
      final response = await _dio.patch('/bookings/$bookingId/refresh-completion-otp');
      return response.data['completionOtp'] as String;
    } catch (e) {
      debugPrint('RefreshCompletionOtp failed: $e');
      rethrow;
    }
  }

  /// Submit a star rating for a completed job
  Future<void> submitRating(String bookingId, int rating) async {
    try {
      await _dio.post('/bookings/$bookingId/rating', data: {'rating': rating});
    } catch (e) {
      debugPrint('SubmitRating failed: $e');
      rethrow;
    }
  }
}
