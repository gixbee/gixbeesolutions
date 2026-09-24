import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/models/job_post.dart';
import '../shared/models/talent_profile.dart';
import 'auth_repository.dart';

final hiringRepositoryProvider = Provider<HiringRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return HiringRepository(dio);
});

class MatchedJobsPage {
  final List<JobPost> items;
  final int total;
  final int page;
  const MatchedJobsPage({required this.items, required this.total, required this.page});
}

class HiringRepository {
  final Dio _dio;

  HiringRepository(this._dio);

  // Employer methods
  Future<void> postJob(JobPost jobData, {String? businessId}) async {
    final data = jobData.toJson();
    if (businessId != null) data['businessId'] = businessId;
    await _dio.post('/hiring/jobs', data: data);
  }

  Future<void> closeJob(String jobId) async {
    await _dio.patch('/hiring/jobs/$jobId');
  }

  Future<JobPost> getJob(String jobId) async {
    final res = await _dio.get('/hiring/jobs/$jobId');
    return JobPost.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<MatchedJobsPage> getMatchedJobsPage({int page = 1, int limit = 20}) async {
    final res = await _dio.get('/hiring/jobs/matched', queryParameters: {
      'page': page,
      'limit': limit,
    });
    final data = res.data;
    final total = data is Map ? (data['total'] as num?)?.toInt() ?? 0 : 0;
    return MatchedJobsPage(items: _jobList(data), total: total, page: page);
  }

  Future<List<JobApplication>> getApplicationsForJob(String jobId) async {
    return _allApplications('/hiring/jobs/$jobId/applications');
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
    return _allApplications('/hiring/my-applications');
  }

  Future<List<JobApplication>> _allApplications(String path) async {
    const pageSize = 100;
    final applications = <String, JobApplication>{};
    for (var page = 1; ; page++) {
      final res = await _dio.get(path, queryParameters: {
        'page': page,
        'limit': pageSize,
      });
      final rows = res.data as List;
      var added = 0;
      for (final row in rows) {
        final application = JobApplication.fromJson(Map<String, dynamic>.from(row as Map));
        if (!applications.containsKey(application.id)) added++;
        applications[application.id] = application;
      }
      if (rows.length < pageSize || added == 0) break;
    }
    return applications.values.toList();
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
    return (await getMatchedJobsPage()).items;
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

  Future<String> expressInterest(String jobId, {String? resumeUrl}) async {
    final res = await _dio.post('/hiring/jobs/$jobId/interest', data: {
      if (resumeUrl != null && resumeUrl.isNotEmpty) 'resumeUrl': resumeUrl,
    });
    final data = res.data;
    if (data is Map && data['status'] != null) return data['status'].toString();
    return 'APPLIED';
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
