import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'auth_repository.dart'; // dioProvider

final addressesRepositoryProvider = Provider((ref) {
  final dio = ref.watch(dioProvider);
  return AddressesRepository(dio);
});

/// The signed-in user's saved addresses (newest first). autoDispose so the
/// booking sheet re-fetches each time it opens and after an add/remove.
final myAddressesProvider =
    FutureProvider.autoDispose<List<SavedAddress>>((ref) async {
  return ref.watch(addressesRepositoryProvider).getMyAddresses();
});

/// A user's saved booking address. `line` is the full free-text address; `label`
/// is an optional short tag ("Home", "Work"). `lat`/`lng` are the CONFIRMED
/// map-pin coordinates — present only when the user pinned this address at
/// least once. With coords, Instant Help reuses the pin one-tap (no map);
/// without, the pin confirm is still required before dispatch.
class SavedAddress {
  final String id;
  final String line;
  final String? label;
  final double? lat;
  final double? lng;

  const SavedAddress({
    required this.id,
    required this.line,
    this.label,
    this.lat,
    this.lng,
  });

  /// True when this address carries a confirmed pin and can skip the map.
  bool get hasPin => lat != null && lng != null;

  factory SavedAddress.fromJson(Map<String, dynamic> json) => SavedAddress(
        id: json['id']?.toString() ?? '',
        line: json['line']?.toString() ?? '',
        label: json['label']?.toString(),
        lat: double.tryParse('${json['lat'] ?? ''}'),
        lng: double.tryParse('${json['lng'] ?? ''}'),
      );
}

class AddressesRepository {
  final Dio _dio;

  AddressesRepository(this._dio);

  /// The signed-in user's saved addresses (newest first).
  Future<List<SavedAddress>> getMyAddresses() async {
    final response = await _dio.get('/addresses');
    final list = (response.data as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => SavedAddress.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Saves a new address; returns the created record. Pass [lat]/[lng] from a
  /// CONFIRMED LocationPinScreen pin so future bookings skip the map.
  Future<SavedAddress> add(
    String line, {
    String? label,
    double? lat,
    double? lng,
  }) async {
    final response = await _dio.post('/addresses', data: {
      'line': line,
      if (label != null && label.isNotEmpty) 'label': label,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    return SavedAddress.fromJson(Map<String, dynamic>.from(response.data));
  }

  /// Backfills a confirmed pin onto a saved address that has no coords yet.
  /// Fire-and-forget from the booking flow — next time it's one-tap.
  Future<void> updateCoords(String id, double lat, double lng) async {
    await _dio.patch('/addresses/$id/coords', data: {'lat': lat, 'lng': lng});
  }

  /// Removes a saved address by id.
  Future<void> remove(String id) async {
    await _dio.delete('/addresses/$id');
  }
}
