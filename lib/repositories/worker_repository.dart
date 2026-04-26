import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/models/worker.dart';
import 'auth_repository.dart'; // To get dioProvider

final workerRepositoryProvider = Provider((ref) {
  final dio = ref.watch(dioProvider);
  return WorkerRepository(dio);
});

final workersProvider = FutureProvider<List<Worker>>((ref) async {
  final repository = ref.watch(workerRepositoryProvider);
  return repository.getWorkers();
});

/// Holds the user's selected location for discovering nearby workers (OLX-style)
final selectedLocationProvider = StateProvider<({double lat, double lng, String address})?>(
  (ref) => null,
);

/// Fetches nearby workers based on the selected location
final nearbyWorkersProvider = FutureProvider.autoDispose<List<Worker>>((ref) async {
  final location = ref.watch(selectedLocationProvider);
  if (location == null) {
    // No location selected, fall back to all workers
    return ref.watch(workerRepositoryProvider).getWorkers();
  }
  return ref.watch(workerRepositoryProvider).getNearbyWorkers(
    lat: location.lat,
    lng: location.lng,
  );
});

class WorkerRepository {
  final Dio _dio;

  WorkerRepository(this._dio);

  Future<List<Worker>> getWorkers() async {
    try {
      final response = await _dio.get('/workers');
      final data = response.data as List;
      return data.map((item) => Worker.fromMap(item as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error fetching workers: $e');
      rethrow;
    }
  }

  Future<Worker> getWorkerById(String id) async {
    try {
      final response = await _dio.get('/workers/$id');
      return Worker.fromMap(response.data as Map<String, dynamic>);
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Worker>> getNearbyWorkers({
    required double lat,
    required double lng,
    String? skill,
  }) async {
    try {
      final params = <String, dynamic>{
        'lat': lat.toString(),
        'lng': lng.toString(),
      };
      if (skill != null) params['skill'] = skill;
      final response = await _dio.get('/workers/nearby', queryParameters: params);
      final data = response.data as List;
      return data.map((item) => Worker.fromMap(item as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error fetching nearby workers: $e');
      // Fallback to all workers if nearby API fails
      return getWorkers();
    }
  }
}

