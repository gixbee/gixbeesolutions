import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart';

final rentalsRepositoryProvider = Provider<RentalsRepository>((ref) {
  return RentalsRepository(ref.watch(dioProvider));
});

/// Public rentals catalog (available items).
final rentalItemsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(rentalsRepositoryProvider).getItems();
});

/// Rentals: customers browse + reserve date ranges; owners list items and
/// confirm/handover/complete reservations. Identity rides the JWT.
class RentalsRepository {
  final Dio _dio;

  RentalsRepository(this._dio);

  List<Map<String, dynamic>> _asList(dynamic data) => (data as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  // ── Catalog / items ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getItems() async {
    final res = await _dio.get('/rentals');
    return _asList(res.data);
  }

  /// Item + `bookedRanges` [{start,end}] so the date picker can block them.
  Future<Map<String, dynamic>> getItemDetail(String id) async {
    final res = await _dio.get('/rentals/$id');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> getMyItems() async {
    final res = await _dio.get('/rentals/my-items');
    return _asList(res.data);
  }

  Future<void> createItem({
    required String name,
    required double hourlyRate,
    double? dailyRate,
    int minHoursToRent = 1,
    String? description,
    String? imageUrl,
  }) async {
    await _dio.post('/rentals', data: {
      'name': name,
      'hourlyRate': hourlyRate,
      if (dailyRate != null) 'dailyRate': dailyRate,
      'minHoursToRent': minHoursToRent,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (imageUrl != null) 'imageUrl': imageUrl,
    });
  }

  Future<void> updateItem(String id, Map<String, dynamic> data) async {
    await _dio.patch('/rentals/$id', data: data);
  }

  /// Item photo upload (shared /uploads/image endpoint) → stored URL.
  Future<String> uploadImage(List<int> bytes, String filename) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _dio.post('/uploads/image', data: form);
    return response.data['url'] as String;
  }

  // ── Reservations ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> reserve({
    required String itemId,
    required DateTime start,
    required DateTime end,
  }) async {
    final res = await _dio.post('/rentals/$itemId/reserve', data: {
      'startTime': start.toIso8601String(),
      'endTime': end.toIso8601String(),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> myReservations() async {
    final res = await _dio.get('/rentals/reservations/my');
    return _asList(res.data);
  }

  Future<List<Map<String, dynamic>>> ownerReservations() async {
    final res = await _dio.get('/rentals/reservations/owner');
    return _asList(res.data);
  }

  Future<void> decide(String reservationId, String action) async {
    // action: confirm | reject | start | complete | cancel
    try {
      await _dio.patch('/rentals/reservations/$reservationId/$action');
    } catch (e) {
      debugPrint('Reservation $action failed: $e');
      rethrow;
    }
  }
}
