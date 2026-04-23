import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart'; // To get dioProvider

final profileRepositoryProvider = Provider((ref) {
  final dio = ref.watch(dioProvider);
  return ProfileRepository(dio);
});

final userStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  final repo = ref.watch(profileRepositoryProvider);
  // Issue #20: Use real user ID from auth provider instead of placeholder
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return {'bookings': 0, 'reviews': 0, 'saved': 0};
  
  return repo.getUserStats(user.id);
});

class ProfileRepository {
  final Dio _dio;

  ProfileRepository(this._dio);

  Future<Map<String, int>> getUserStats(String userId) async {
    try {
      final response = await _dio.get('/users/$userId/stats');
      final data = response.data as Map<String, dynamic>;
      
      return {
        'bookings': data['bookingsCount'] ?? 0,
        'reviews': data['reviewsCount'] ?? 0,
        'saved': data['savedCount'] ?? 0,
      };
    } catch (e) {
      // Return default values on failure
      return {'bookings': 0, 'reviews': 0, 'saved': 0};
    }
  }

  Future<void> updateProfile({
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _dio.patch('/users/$userId', data: data);
    } catch (e) {
      debugPrint('Error updating profile: $e');
      rethrow;
    }
  }
}
