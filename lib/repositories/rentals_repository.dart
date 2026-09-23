import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart';
import 'cities_repository.dart';
import 'worker_repository.dart';

final rentalsRepositoryProvider = Provider<RentalsRepository>((ref) {
  return RentalsRepository(ref.watch(dioProvider));
});

/// Nearby verified rental stores — scoped to the customer's GPS / city.
final rentalStoresProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final location = ref.watch(selectedLocationProvider);
  final city = ref.watch(currentCityProvider);
  if (location == null && city == null) return <Map<String, dynamic>>[];
  return ref.watch(rentalsRepositoryProvider).getStores(
        lat: location?.lat,
        lng: location?.lng,
        cityId: city?.id,
      );
});

/// Inventory for one nearby store.
final rentalStoreItemsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, businessId) async {
  if (businessId.isEmpty) return <Map<String, dynamic>>[];
  final location = ref.watch(selectedLocationProvider);
  final city = ref.watch(currentCityProvider);
  return ref.watch(rentalsRepositoryProvider).getItems(
        lat: location?.lat,
        lng: location?.lng,
        cityId: city?.id,
        businessId: businessId,
      );
});

/// Public rentals catalog — scoped to the customer's GPS / city.
final rentalItemsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final location = ref.watch(selectedLocationProvider);
  final city = ref.watch(currentCityProvider);
  if (location == null && city == null) return <Map<String, dynamic>>[];
  return ref.watch(rentalsRepositoryProvider).getItems(
        lat: location?.lat,
        lng: location?.lng,
        cityId: city?.id,
      );
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

  Future<List<Map<String, dynamic>>> getStores({
    double? lat,
    double? lng,
    String? cityId,
  }) async {
    final res = await _dio.get('/rentals/stores', queryParameters: {
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (cityId != null && cityId.isNotEmpty) 'cityId': cityId,
    });
    return _asList(res.data);
  }

  Future<List<Map<String, dynamic>>> getItems({
    double? lat,
    double? lng,
    String? cityId,
    String? businessId,
  }) async {
    final res = await _dio.get('/rentals', queryParameters: {
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (cityId != null && cityId.isNotEmpty) 'cityId': cityId,
      if (businessId != null && businessId.isNotEmpty) 'businessId': businessId,
    });
    return _asList(res.data);
  }

  /// Item + `bookedRanges` [{start,end}] so the date picker can block them.
  Future<Map<String, dynamic>> getItemDetail(String id) async {
    final res = await _dio.get('/rentals/$id');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> getMyItems({String? businessId}) async {
    final res = await _dio.get('/rentals/my-items', queryParameters: {if (businessId != null) 'businessId': businessId});
    return _asList(res.data);
  }

  Future<void> createItem({
    required String name,
    required double hourlyRate,
    double? dailyRate,
    int minHoursToRent = 1,
    String? description,
    String? imageUrl,
    List<String>? imageUrls,
    required String businessId,
    int quantity = 1,
    required String pickupAddress,
    double? pickupLat,
    double? pickupLng,
    bool deliveryAvailable = false,
    double deliveryFee = 0,
    double depositPerUnit = 0,
    double advanceAmount = 0,
    double advancePercent = 0,
    String pickupInstructions = '',
    double lateFeePerHour = 0,
    String condition = 'GOOD',
    String category = 'OTHER',
    String cancellationPolicy = 'FLEXIBLE',
    String? availableFrom,
    String? availableUntil,
    List<int>? availableWeekdays,
    int? slotStartMinute,
    int? slotEndMinute,
  }) async {
    await _dio.post('/rentals', data: {
      'name': name,
      'businessId': businessId, 'quantity': quantity, 'pickupAddress': pickupAddress,
      if (pickupLat != null) 'pickupLat': pickupLat,
      if (pickupLng != null) 'pickupLng': pickupLng,
      'deliveryAvailable': deliveryAvailable, 'deliveryFee': deliveryFee, 'depositPerUnit': depositPerUnit,
      'advanceAmount': advanceAmount,
      'advancePercent': advancePercent,
      'pickupInstructions': pickupInstructions,
      'lateFeePerHour': lateFeePerHour,
      'condition': condition,
      'category': category,
      'cancellationPolicy': cancellationPolicy,
      if (availableFrom != null) 'availableFrom': availableFrom,
      if (availableUntil != null) 'availableUntil': availableUntil,
      'availableWeekdays': availableWeekdays ?? const [1, 2, 3, 4, 5, 6, 7],
      if (slotStartMinute != null) 'slotStartMinute': slotStartMinute,
      if (slotEndMinute != null) 'slotEndMinute': slotEndMinute,
      'hourlyRate': hourlyRate,
      if (dailyRate != null) 'dailyRate': dailyRate,
      'minHoursToRent': minHoursToRent,
      if (description != null && description.isNotEmpty)
        'description': description,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (imageUrls != null) 'imageUrls': imageUrls,
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
    int quantity = 1,
    String fulfillment = 'PICKUP',
    String deliveryAddress = '',
  }) async {
    final res = await _dio.post('/rentals/$itemId/reserve', data: {
      'startTime': start.toUtc().toIso8601String(),
      'endTime': end.toUtc().toIso8601String(),
      'quantity': quantity, 'fulfillment': fulfillment, 'deliveryAddress': deliveryAddress,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> myReservations() async {
    final res = await _dio.get('/rentals/reservations/my');
    return _asList(res.data);
  }

  Future<List<Map<String, dynamic>>> ownerReservations({String? businessId}) async {
    final res = await _dio.get('/rentals/reservations/owner', queryParameters: {if (businessId != null) 'businessId': businessId});
    return _asList(res.data);
  }

  Future<Map<String, dynamic>> createAdvanceOrder(String reservationId) async {
    final res = await _dio.post('/rentals/reservations/$reservationId/advance-order');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> verifyOtp(String reservationId, String kind, String code) async {
    await _dio.post('/rentals/reservations/$reservationId/otp', data: {
      'kind': kind,
      'code': code,
    });
  }

  Future<void> settle(String reservationId, {double lateFee = 0, double damageAmount = 0}) async {
    await _dio.post('/rentals/reservations/$reservationId/settle', data: {
      'lateFee': lateFee,
      'damageAmount': damageAmount,
    });
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

  Future<void> acknowledge(String id, String action) async {
    await _dio.patch('/rentals/reservations/$id/ack/$action');
  }
}
