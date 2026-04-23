import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/models/job_post.dart';
import '../shared/models/talent_profile.dart';
import 'auth_repository.dart';

final hiringRepositoryProvider = Provider<HiringRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return HiringRepository(dio);
});

class HiringRepository {
  final Dio _dio;

  HiringRepository(this._dio);

  // Employer methods
  Future<void> postJob(JobPost jobData) async {
    await _dio.post('/hiring/jobs', data: jobData.toJson());
  }

  Future<List<JobApplication>> getApplicationsForJob(String jobId) async {
    final res = await _dio.get('/hiring/jobs/$jobId/applications');
    return (res.data as List).map((json) => JobApplication.fromJson(json)).toList();
  }

  Future<void> updateApplicationStatus(String applicationId, ApplicationStatus status) async {
    await _dio.patch('/hiring/applications/$applicationId/status', data: {
      'status': status.name.toUpperCase(),
    });
  }

  // Talent methods
  Future<void> applyToJob(String jobId, {String? coverLetter}) async {
    await _dio.post('/hiring/jobs/$jobId/apply', data: {
      'coverLetter': coverLetter,
    });
  }

  Future<List<JobApplication>> getMyApplications() async {
    final res = await _dio.get('/hiring/my-applications'); 
    return (res.data as List).map((json) => JobApplication.fromJson(json)).toList();
  }

  // Talent Profile endpoints
  Future<void> saveTalentProfile(TalentProfile profile) async {
    await _dio.post('/talent/profile', data: profile.toJson());
  }

  Future<TalentProfile> getTalentProfile() async {
    final res = await _dio.get('/talent/profile');
    return TalentProfile.fromJson(res.data);
  }

  Future<List<JobPost>> getMatchingJobs() async {
    final res = await _dio.get('/hiring/jobs'); // For now, get all jobs
    return (res.data as List).map((json) => JobPost.fromJson(json)).toList();
  }

  Future<void> toggleJobAlerts(bool enabled) async {
    await _dio.patch('/talent/alerts', data: {'enabled': enabled});
  }
}
