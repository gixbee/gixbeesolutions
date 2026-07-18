import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/models/business.dart';
import 'auth_repository.dart';

final businessRepositoryProvider = Provider<BusinessRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return BusinessRepository(dio);
});

class BusinessRepository {
  final Dio _dio;

  BusinessRepository(this._dio);

  Future<Business> registerBusiness(Business business) async {
    final res = await _dio.post('/businesses', data: business.toJson());
    return Business.fromJson(res.data);
  }

  Future<List<Business>> getMyBusinesses() async {
    final res = await _dio.get('/businesses/my');
    return (res.data as List).map((json) => Business.fromJson(json)).toList();
  }

  Future<void> addOperator(String businessId, String userId, String role) async {
    await _dio.post('/businesses/$businessId/operators', data: {'userId': userId, 'role': role});
  }

  Future<void> initiateOwnershipTransfer(String businessId, String newOwnerId) async {
    await _dio.post('/businesses/$businessId/transfer', data: {'newOwnerId': newOwnerId});
  }

  Future<void> addOfflineDay(String businessId, DateTime date) async {
    await _dio.post('/businesses/$businessId/calendar/offline', data: {'date': date.toIso8601String()});
  }

  /// Uploads document/image bytes to the backend and returns the stored URL
  /// (e.g. "/uploads/1234.jpg"). Uses MultipartFile.fromBytes so it works
  /// identically on web and mobile (fromFile is not supported on web).
  /// Hits the existing disk-storage endpoint used by talent uploads.
  Future<String> uploadImage(List<int> bytes, String filename) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _dio.post('/uploads/image', data: form);
    return response.data['url'] as String;
  }

  /// Name/phone lookup so an operator can be picked by a human-readable query
  /// instead of pasting a raw user id (P106 operator picker). Hits the backend
  /// `GET /admin-user-list/search` (lean projection: id/name/phone/role/photo).
  /// An empty/whitespace query short-circuits to [] with no network call,
  /// matching the backend's own short-circuit. Errors bubble to the caller.
  Future<List<UserLookupResult>> searchUsers(String query,
      {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final res = await _dio.get('/admin-user-list/search',
        queryParameters: {'q': q, 'limit': limit});
    return (res.data as List)
        .map((j) => UserLookupResult.fromJson(j as Map<String, dynamic>))
        .toList();
  }
}

/// Lean user-lookup result for the operator picker (P106). Mirrors the backend
/// `GET /admin-user-list/search` projection — no wallet/fcmToken/flags.
class UserLookupResult {
  final String id;
  final String name;
  final String? phoneNumber;
  final String? role;
  final String? profileImageUrl;

  const UserLookupResult({
    required this.id,
    required this.name,
    this.phoneNumber,
    this.role,
    this.profileImageUrl,
  });

  factory UserLookupResult.fromJson(Map<String, dynamic> json) =>
      UserLookupResult(
        id: json['id'] as String,
        name: (json['name'] ?? '') as String,
        phoneNumber: json['phoneNumber'] as String?,
        role: json['role'] as String?,
        profileImageUrl: json['profileImageUrl'] as String?,
      );
}
