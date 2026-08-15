import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    String? location,
    int experienceMin = 0,
    List<String> skills = const [],
  }) async {
    final res = await _dio.get('/hiring/match/estimate', queryParameters: {
      'jobType': jobType,
      'salary': salary,
      if (location != null && location.isNotEmpty) 'location': location,
      'experienceMin': experienceMin,
      if (skills.isNotEmpty) 'skills': skills.join(','),
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

  Future<List<Map<String, dynamic>>> listRequests() async {
    final res = await _dio.get('/hiring/match/requests');
    return (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> getRequestDetail(String id) async {
    final res = await _dio.get('/hiring/match/requests/$id');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> resolveGuarantee(
    String requestId, {
    required String choice, // CREDIT | REFUND
  }) async {
    final res = await _dio.post(
      '/hiring/match/requests/$requestId/resolve',
      data: {'choice': choice},
    );
    return Map<String, dynamic>.from(res.data as Map);
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
  Future<List<Map<String, dynamic>>> listMyJobPosts() async {
    final res = await _dio.get('/hiring/my-jobs');
    return (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
