import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
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

/// Approximate live-pro counts per trade around the selected location
/// ("~8 live nearby" on the Instant Help grid). Empty map when no location
/// is picked yet or the fetch fails — the grid then simply shows no counts.
final nearbyCountsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final location = ref.watch(selectedLocationProvider);
  if (location == null) return const {};
  try {
    return await ref.watch(workerRepositoryProvider).getNearbyCounts(
          lat: location.lat,
          lng: location.lng,
        );
  } catch (e) {
    debugPrint('Nearby counts fetch failed: $e');
    return const {};
  }
});

/// The worker's own strike ledger (Profile → Strikes & Appeals). Refreshed
/// on every open; invalidate after filing an appeal.
final myStrikesProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(workerRepositoryProvider).getMyStrikes();
});

class WorkerRepository {
  final Dio _dio;

  WorkerRepository(this._dio);

  /// GET /workers/nearby-counts — approximate live counts per trade label.
  /// Server caches ~45s; values are upper bounds, render with "~".
  Future<Map<String, int>> getNearbyCounts({
    required double lat,
    required double lng,
  }) async {
    final response = await _dio.get(
      '/workers/nearby-counts',
      queryParameters: {'lat': lat, 'lng': lng},
    );
    final data = response.data;
    if (data is! Map) return const {};
    return data.map(
      (k, v) => MapEntry('$k', (v is num) ? v.toInt() : 0),
    );
  }

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
  /// Hits `POST /workers/live-toggle` (JWT identifies the worker). Pass
  /// [active] for an idempotent desired-state update (safe to retry after
  /// a timeout). Optional [lat]/[lng] warm Redis so Instant Help can match
  /// this worker immediately.
  Future<({bool isActive, String message})> goLiveToggle({
    double? lat,
    double? lng,
    bool? active,
  }) async {
    final response = await _dio.post(
      '/workers/live-toggle',
      data: {
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (active != null) 'active': active,
      },
      // Profile heal + Redis warm can exceed the default 15s on a cold
      // container / weak mobile link — a timeout after the DB save is what
      // used to desync the UI from server truth.
      options: Options(
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    final data = Map<String, dynamic>.from(response.data);
    return (
      isActive: data['isActive'] == true,
      message: (data['message'] ?? '') as String,
    );
  }

  /// `PATCH /workers/me/location` — keep Redis GPS warm while live.
  Future<void> updateMyLocation({
    required double lat,
    required double lng,
  }) async {
    await _dio.patch(
      '/workers/me/location',
      data: {'lat': lat, 'lng': lng},
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

  /// Periodic fee plan ("N jobs, then pay"): pay the period fee to unlock
  /// the next batch of included jobs. `POST /workers/me/pay-period-fee`
  /// — charged from the Gixbee wallet; resets the per-period counter.
  /// DEV FALLBACK ONLY — production uses [createPeriodFeeOrder] + Razorpay.
  Future<Map<String, dynamic>> payPeriodFee() async {
    final response = await _dio.post('/workers/me/pay-period-fee');
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Direct Razorpay checkout for the period fee — the production path.
  /// `POST /payments/period-fee/order` → {orderId, amount(paise), currency,
  /// keyId}. The server sets the price; the webhook unlocks the jobs.
  Future<Map<String, dynamic>> createPeriodFeeOrder() async {
    final response = await _dio.post('/payments/period-fee/order');
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

  /// `GET /workers/me/strikes` → `{strikeCount, suspended, threshold,
  /// strikes: [{id, type, reason, status, appealMessage, resolutionNote,
  /// createdAt, ...}]}`. Fair-penalty ledger — every strike carries a
  /// written reason and can be appealed once.
  Future<Map<String, dynamic>> getMyStrikes() async {
    final response = await _dio.get('/workers/me/strikes');
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// `POST /workers/me/strikes/:id/appeal` — file the one allowed appeal.
  Future<String> appealStrike(String strikeId, String message) async {
    final response = await _dio.post(
      '/workers/me/strikes/$strikeId/appeal',
      data: {'message': message},
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return (data['message'] ?? 'Appeal submitted.') as String;
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

