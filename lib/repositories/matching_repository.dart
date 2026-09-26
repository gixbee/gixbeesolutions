import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_data_cache.dart';
import 'auth_repository.dart';

final matchingRepositoryProvider = Provider<MatchingRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return MatchingRepository(dio);
});

/// Smart Hiring client for `/hiring/match/*` (FRD Find a Job + Hire Employee).
class MatchingRepository {
  final Dio _dio;

  MatchingRepository(this._dio);

  // ── Candidate: Job Type preferences ────────────────────────────────────

  Future<List<Map<String, dynamic>>> listPreferences() async {
    final res = await _dio.get('/hiring/match/preferences');
    return (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createPreference(Map<String, dynamic> body) async {
    final res = await _dio.post('/hiring/match/preferences', data: body);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> updatePreference(
    String id,
    Map<String, dynamic> body,
  ) async {
    final res = await _dio.patch('/hiring/match/preferences/$id', data: body);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> deletePreference(String id) async {
    await _dio.delete('/hiring/match/preferences/$id');
  }

  /// Shared employment types + category catalog (V147-02).
  Future<Map<String, dynamic>> catalog() async {
    final res = await _dio.get('/hiring/match/catalog');
    return Map<String, dynamic>.from(res.data as Map);
  }

  // ── Candidate: offers ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listOffers() async {
    final res = await _dio.get('/hiring/match/offers');
    return (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> respondToOffer(
    String requestId, {
    required bool interested,
  }) async {
    final res = await _dio.post(
      '/hiring/match/offers/$requestId/respond',
      data: {'interested': interested},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  // ── Employer: estimate / pricing / requests ────────────────────────────

  Future<Map<String, dynamic>> estimate({
    required String jobType,
    required num salary,
    num? salaryMin,
    num? salaryMax,
    bool salaryNegotiable = false,
    String? employmentType,
    String? location,
    int experienceMin = 0,
    List<String> skills = const [],
    String? positionId,
    List<String> specializationIds = const [],
    List<String> skillIds = const [],
    String? qualificationId,
    bool qualificationRequired = false,
    String? salaryPeriod,
    String? locationId,
    String? workMode,
    List<String> languageIds = const [],
  }) async {
    final max = salaryMax ?? salary;
    final res = await _dio.get('/hiring/match/estimate', queryParameters: {
      'jobType': jobType,
      'salary': max,
      if (salaryMin != null && salaryMin > 0) 'salaryMin': salaryMin,
      if (salaryMax != null && salaryMax > 0) 'salaryMax': salaryMax,
      if (salaryNegotiable) 'salaryNegotiable': 'true',
      if (employmentType != null && employmentType.isNotEmpty)
        'employmentType': employmentType,
      if (location != null && location.isNotEmpty) 'location': location,
      'experienceMin': experienceMin,
      if (skills.isNotEmpty) 'skills': skills.join(','),
      if (positionId != null && positionId.isNotEmpty) 'positionId': positionId,
      if (specializationIds.isNotEmpty) 'specializationIds': specializationIds.join(','),
      if (skillIds.isNotEmpty) 'skillIds': skillIds.join(','),
      if (qualificationId != null && qualificationId.isNotEmpty) 'qualificationId': qualificationId,
      if (qualificationRequired) 'qualificationRequired': 'true',
      if (salaryPeriod != null && salaryPeriod.isNotEmpty) 'salaryPeriod': salaryPeriod,
      if (locationId != null && locationId.isNotEmpty) 'locationId': locationId,
      if (workMode != null && workMode.isNotEmpty) 'workMode': workMode,
      if (languageIds.isNotEmpty) 'languageIds': languageIds.join(','),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> pricing() async {
    final res = await _dio.get('/hiring/match/pricing');
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Creates a request when hiring credit covers the fee (or fee is ₹0).
  /// Otherwise returns `{ needsPayment: true, fee, creditApplied, amountDue }`.
  Future<Map<String, dynamic>> createRequest(Map<String, dynamic> body) async {
    final res = await _dio.post('/hiring/match/requests', data: body);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> listRequests({String? businessId}) async {
    final res = await _dio.get('/hiring/match/requests', queryParameters: {if (businessId != null) 'businessId': businessId});
    return (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> getRequestDetail(String id) async {
    final res = await _dio.get('/hiring/match/requests/$id');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> applicationProgress(String interestId) async {
    final res = await _dio.get('/hiring/match/interests/$interestId/progress');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> updateApplication(String interestId, String action, Map<String, dynamic> body) async {
    await _dio.post('/hiring/match/interests/$interestId/progress/$action', data: body);
  }

  Future<List<Map<String, dynamic>>> pendingPayments() async {
    final response = await _dio.get('/payments/pending');
    return (response.data as List).map((v) => Map<String, dynamic>.from(v as Map)).toList();
  }

  Future<void> verifyPayment(String orderId, String paymentId) async {
    await _dio.post('/payments/orders/$orderId/verify', data: {'paymentId': paymentId});
  }

  Future<String> paymentStatus(String orderId) async {
    final response = await _dio.get('/payments/orders/$orderId');
    return '${response.data['status']}';
  }

  Future<Map<String, dynamic>> setDecision(
    String interestId, {
    required String decision, // SHORTLISTED | REJECTED | HIRED
  }) async {
    final res = await _dio.patch(
      '/hiring/match/interests/$interestId/decision',
      data: {'decision': decision},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> closeRequest(String requestId) async {
    final res = await _dio.post('/hiring/match/requests/$requestId/close');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> hiringCreditBalance() async {
    final res = await _dio.get('/hiring/match/credit');
    return Map<String, dynamic>.from(res.data as Map);
  }

  // ── Razorpay order helpers (via payments) ──────────────────────────────

  Future<Map<String, dynamic>> createHiringMatchOrder(
    Map<String, dynamic> body,
  ) async {
    final res = await _dio.post('/payments/hiring-match/order', data: body);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> createExtraJobTypeOrder(
    Map<String, dynamic> body,
  ) async {
    final res = await _dio.post('/payments/extra-job-type/order', data: body);
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Classic employer job posts (for Candidates picker).
  Future<Map<String, dynamic>> hiringCatalogue() async {
    final res = await _dio.get('/hiring/catalogue');
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Server-side cache invalidation counters (`GET /cache/versions`).
  Future<Map<String, int>> fetchCacheVersions() async {
    final res = await _dio.get('/cache/versions');
    final list = (res.data['versions'] as List?) ?? [];
    final out = <String, int>{};
    for (final row in list) {
      if (row is! Map) continue;
      final domain = row['domain']?.toString();
      final version = row['version'];
      if (domain != null && domain.isNotEmpty && version is num) {
        out[domain] = version.toInt();
      }
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> searchHiringPositions({
    String query = '',
    String? sectorId,
    int limit = 30,
  }) async {
    final res = await _dio.get('/hiring/catalogue/positions', queryParameters: {
      if (query.isNotEmpty) 'q': query,
      if (sectorId != null && sectorId.isNotEmpty) 'sectorId': sectorId,
      'limit': limit,
    });
    return ((res.data['items'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> hiringPosition(String id) async {
    final res = await _dio.get('/hiring/catalogue/positions/$id');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> searchHiringLocations(String query, {int offset = 0}) async {
    final normalized = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length > 80) {
      throw StateError('Location search query is too long');
    }
    var mayUseAppCache = false;
    try {
      final versions = await fetchCacheVersions();
      final locV = versions['location_master'];
      if (locV != null) {
        AppDataCache.instance.setServerVersions(locationMaster: locV);
        mayUseAppCache = true;
      }
    } catch (_) {
      // Version unknown — do not reuse app cache; still hit network.
    }
    final cacheKey = '$normalized:$offset';
    if (mayUseAppCache) {
      final hit = AppDataCache.instance.locationPage(cacheKey);
      if (hit != null) return hit;
    }

    final res = await _dio.get('/hiring/locations/search', queryParameters: {
      'q': query,
      'limit': 20,
      'offset': offset,
    });
    final items = ((res.data['items'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    AppDataCache.instance.putLocationPage(cacheKey, items);
    return items;
  }

  Future<List<Map<String, dynamic>>> listMyJobPosts({String? businessId}) async {
    final res = await _dio.get('/hiring/my-jobs', queryParameters: {
      if (businessId != null) 'businessId': businessId,
    });
    return (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
