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
  Future<void> applyToJob(String jobId,
      {String? coverLetter, String? resumeUrl}) async {
    await _dio.post('/hiring/jobs/$jobId/apply', data: {
      'coverLetter': coverLetter,
      if (resumeUrl != null) 'resumeUrl': resumeUrl,
    });
  }

  Future<void> withdrawApplication(String applicationId) async {
    await _dio.post('/hiring/applications/$applicationId/withdraw');
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
    try {
      final res = await _dio.get('/hiring/jobs/matched', queryParameters: {
        'page': 1,
        'limit': 20,
      });
      return _jobList(res.data);
    } catch (_) {
      final res = await _dio.get('/hiring/jobs');
      return _jobList(res.data);
    }
  }

  Future<List<JobPost>> getMyJobs({String? businessId}) async {
    final res = await _dio.get('/hiring/my-jobs', queryParameters: {
      if (businessId != null) 'businessId': businessId,
    });
    return _jobList(res.data);
  }

  Future<List<CandidateMatch>> recommendedCandidates(String jobId) async {
    final res = await _dio.get('/hiring/jobs/$jobId/matches');
    final data = res.data;
    final raw = data is Map ? data['items'] : data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((json) => CandidateMatch.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }

  Future<void> expressInterest(String jobId) async {
    await _dio.post('/hiring/jobs/$jobId/interest', data: {});
  }

  Future<void> notInterested(String jobId, String reason) async {
    await _dio.post('/hiring/jobs/$jobId/not-interested', data: {'reason': reason});
  }

  Future<void> inviteCandidate(String jobId, String candidateId) async {
    await _dio.post('/hiring/jobs/$jobId/matches/$candidateId/invite');
  }

  List<JobPost> _jobList(dynamic data) {
    final raw = data is List
        ? data
        : (data is Map ? data['items'] : null);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((json) => JobPost.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }

  Future<void> toggleJobAlerts(bool enabled) async {
    await _dio.patch('/talent/alerts', data: {'enabled': enabled});
  }
}
