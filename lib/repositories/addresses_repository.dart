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
/// is an optional short tag ("Home", "Work").
class SavedAddress {
  final String id;
  final String line;
  final String? label;

  const SavedAddress({required this.id, required this.line, this.label});

  factory SavedAddress.fromJson(Map<String, dynamic> json) => SavedAddress(
        id: json['id']?.toString() ?? '',
        line: json['line']?.toString() ?? '',
        label: json['label']?.toString(),
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

  /// Saves a new address; returns the created record.
  Future<SavedAddress> add(String line, {String? label}) async {
    final response = await _dio.post('/addresses', data: {
      'line': line,
      if (label != null && label.isNotEmpty) 'label': label,
    });
    return SavedAddress.fromJson(Map<String, dynamic>.from(response.data));
  }

  /// Removes a saved address by id.
  Future<void> remove(String id) async {
    await _dio.delete('/addresses/$id');
  }
}
