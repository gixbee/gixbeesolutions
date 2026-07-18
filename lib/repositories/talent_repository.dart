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

  Future<Map<String, dynamic>> addOrUpdateSkill(String skillName, double rate, String bio, Map<String, double> rateChart) async {
    final response = await _dio.post('/talent/skills', data: {
      'skillName': skillName,
      'rate': rate,
      'bio': bio,
      'rateChart': rateChart,
    });
    return response.data;
  }

  Future<void> removeSkill(String skillId) async {
    await _dio.post('/talent/skills/remove', data: {'skillId': skillId});
  }

  Future<void> toggleAlerts(bool enabled) async {
    await _dio.patch('/talent/alerts', data: {'enabled': enabled});
  }

  /// "Later" bookmark in the job-alerts feed (v126 Find a Job). Toggles the
  /// job id in the profile's savedJobIds; backend returns the updated list.
  Future<void> toggleSavedJob(String jobId) async {
    await _dio.post('/talent/saved-jobs/toggle', data: {'jobId': jobId});
  }

  /// DigiLocker verification readiness (Phase 5 — credential-blocked stub).
  /// Mirrors the UPI gateway-status read: the Register-as-Pro "Verify" sheet
  /// uses this to render live vs. "setup pending" without hard-coding the
  /// state. Returns the backend payload
  /// ({provider, available, needsApiKey, verified, message}); never reports a
  /// fake verified result.
  Future<Map<String, dynamic>> getVerificationStatus() async {
    final response = await _dio.get('/talent/verification/status');
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Uploads image bytes to the backend and returns the stored URL
  /// (e.g. "/uploads/1234.jpg"). Uses MultipartFile.fromBytes so it works
  /// identically on web and mobile (fromFile is not supported on web).
  Future<String> uploadImage(List<int> bytes, String filename) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _dio.post('/uploads/image', data: form);
    return response.data['url'] as String;
  }
}
