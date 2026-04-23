import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart';

final talentRepositoryProvider = Provider((ref) {
  final dio = ref.watch(dioProvider);
  return TalentRepository(dio);
});

final talentProfileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return await ref.watch(talentRepositoryProvider).getProfile();
});

class TalentRepository {
  final Dio _dio;

  TalentRepository(this._dio);

  Future<Map<String, dynamic>> getProfile() async {
    final response = await _dio.get('/talent/profile');
    return response.data;
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final response = await _dio.post('/talent/profile', data: data);
    return response.data;
  }

  Future<Map<String, dynamic>> addOrUpdateSkill(String skillName, double rate) async {
    final response = await _dio.post('/talent/skills', data: {
      'skillName': skillName,
      'rate': rate,
    });
    return response.data;
  }

  Future<void> removeSkill(String skillId) async {
    await _dio.post('/talent/skills/remove', data: {'skillId': skillId});
  }

  Future<void> toggleAlerts(bool enabled) async {
    await _dio.patch('/talent/alerts', data: {'enabled': enabled});
  }
}
