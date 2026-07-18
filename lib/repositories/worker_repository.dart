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

/// Local mirror of the worker's own Go-Live state.
/// Updated optimistically by [GoLiveScreen] after a successful toggle so the
/// bottom-nav indicator stays in sync without an extra round-trip.
final workerLiveStateProvider = StateProvider<bool>((ref) => false);

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
  Future<List<Map<String, dynamic>>> getWorkerPackages(String workerId) async {
    try {
      final response = await _dio.get('/workers/$workerId/packages');
      final data = response.data as List;
      return data.map((item) => item as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('Error fetching worker packages: $e');
      rethrow;
    }
  }

  /// Toggles the worker's Go-Live state on the server.
  ///
  /// Hits `POST /workers/live-toggle` (JWT identifies the worker). The backend
  /// enforces the min-wallet-balance and 2-toggles/day rules and returns the
  /// resulting state. Throws [DioException] on a 400 so the UI can surface the
  /// server message (e.g. "Minimum Rs.12 wallet balance required").
  Future<({bool isActive, String message})> goLiveToggle() async {
    final response = await _dio.post('/workers/live-toggle');
    final data = Map<String, dynamic>.from(response.data);
    return (
      isActive: data['isActive'] == true,
      message: (data['message'] ?? '') as String,
    );
  }

  /// Go-Live dashboard for the authed worker.
  ///
  /// `GET /workers/me/dashboard` → `{skills, activeSkills, isActive,
  /// earnings: {total, today, thisWeek, jobsCompleted, recent: [...]}}`.
  Future<Map<String, dynamic>> getGoLiveDashboard() async {
    final response = await _dio.get('/workers/me/dashboard');
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// `GET /workers/me` — own worker profile incl. languages + verification.
  Future<Map<String, dynamic>> getMyWorkerProfile() async {
    final response = await _dio.get('/workers/me');
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// `PATCH /workers/me/languages` — languages this pro speaks (v126
  /// language matching; broadcast fan-outs only notify overlapping pros).
  Future<void> setLanguages(List<String> languages) async {
    await _dio.patch('/workers/me/languages', data: {'languages': languages});
  }

  /// `PATCH /workers/me/service-radius` — how far this pro will travel for
  /// instant jobs. Jobs beyond it are never broadcast to them. The server
  /// clamps to 1..50 km, so the returned value is the source of truth.
  Future<int> setServiceRadius(int radiusKm) async {
    final response = await _dio.patch(
      '/workers/me/service-radius',
      data: {'serviceRadiusKm': radiusKm},
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return (data['serviceRadiusKm'] as num?)?.toInt() ?? radiusKm;
  }

  /// Per-service activation: which skills accept instant jobs while live.
  ///
  /// `PATCH /workers/me/active-skills`. An empty list means "all services
  /// active" (backend back-compat default).
  Future<List<String>> setActiveSkills(List<String> skills) async {
    final response =
        await _dio.patch('/workers/me/active-skills', data: {'skills': skills});
    final data = Map<String, dynamic>.from(response.data as Map);
    return List<String>.from(data['activeSkills'] as List? ?? const []);
  }

  /// Registers a new worker profile.
  Future<void> registerWorker({
    required List<String> skills,
    required double hourlyRate,
    String? bio,
  }) async {
    try {
      await _dio.post('/workers/register', data: {
        'skills': skills,
        'hourlyRate': hourlyRate,
        'bio': bio,
      });
    } on DioException catch (e) {
      if (e.response?.statusCode == 400) {
        // Ignored if profile already exists.
        return;
      }
      rethrow;
    }
  }
}

