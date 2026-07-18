import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'auth_repository.dart'; // dioProvider

final favouritesRepositoryProvider = Provider((ref) {
  final dio = ref.watch(dioProvider);
  return FavouritesRepository(dio);
});

/// Per-worker favourite status. `family` keyed by workerId so each worker card
/// resolves its own saved-state independently. Auto-disposed when no longer
/// watched.
final isFavouriteProvider =
    FutureProvider.family<bool, String>((ref, workerId) async {
  return ref.watch(favouritesRepositoryProvider).isFavourite(workerId);
});

class FavouritesRepository {
  final Dio _dio;

  FavouritesRepository(this._dio);

  /// Whether the signed-in user has saved this worker.
  Future<bool> isFavourite(String workerId) async {
    final response = await _dio.get('/favourites/$workerId');
    return response.data['favourited'] as bool? ?? false;
  }

  /// Saves the worker to favourites (idempotent on the backend).
  Future<void> add(String workerId) async {
    await _dio.post('/favourites/$workerId');
  }

  /// Removes the worker from favourites.
  Future<void> remove(String workerId) async {
    await _dio.delete('/favourites/$workerId');
  }

  /// The signed-in user's saved worker ids (newest first).
  Future<List<String>> getMyFavouriteIds() async {
    final response = await _dio.get('/favourites');
    final list = (response.data as List?) ?? [];
    return list
        .map((e) => (e as Map)['workerId']?.toString())
        .whereType<String>()
        .toList();
  }
}
