class JobPost {
  final String id;
  final String title;
  final String description;
  final List<String> requiredSkills;
  final double? salaryMin;
  final double? salaryMax;
  final String jobType;
  final String experience;
  final String location;
  final bool isActive;
  final String employerId;
  final String? employerName;
  final DateTime? createdAt;
  final int? matchScore;
  final List<String> matchReasons;
  final List<String> matchWarnings;
  final double? distanceKm;
  final bool distanceExact;
  final bool businessVerified;
  final String? businessName;
  final String workMode;
  final String salaryPeriod;
  final double? lat;
  final double? lng;
  final String? sectorId;
  final String? positionId;
  final List<String> skillIds;
  final String? locationId;
  final String? addressText;

  JobPost({
    required this.id,
    required this.title,
    required this.description,
    required this.requiredSkills,
    this.salaryMin,
    this.salaryMax,
    required this.jobType,
    required this.experience,
    required this.location,
    required this.isActive,
    required this.employerId,
    this.employerName,
    this.createdAt,
    this.matchScore,
    this.matchReasons = const [],
    this.matchWarnings = const [],
    this.distanceKm,
    this.distanceExact = false,
    this.businessVerified = false,
    this.businessName,
    this.workMode = 'ONSITE',
    this.salaryPeriod = 'MONTHLY',
    this.lat,
    this.lng,
    this.sectorId,
    this.positionId,
    this.skillIds = const [],
    this.locationId,
    this.addressText,
  });

  factory JobPost.fromJson(Map<String, dynamic> json) {
    return JobPost(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      requiredSkills: _stringList(json['requiredSkills']),
      salaryMin: _num(json['salaryMin']),
      salaryMax: _num(json['salaryMax']),
      jobType: json['jobType'] ?? 'Full Time',
      experience: json['experience'] ?? 'Fresher',
      location: json['location'] ?? '',
      isActive: json['isActive'] ?? true,
      employerId: json['employer']?['id'] ?? json['employerId'] ?? '',
      employerName: json['employer']?['fullName'] ??
          json['employer']?['name'] ??
          json['businessName'],
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      matchScore: (json['matchScore'] as num?)?.toInt() ??
          (json['match'] is Map ? (json['match']['matchScore'] as num?)?.toInt() : null),
      matchReasons: _stringList(json['reasons'] ??
          (json['match'] is Map ? json['match']['reasons'] : null)),
      matchWarnings: _stringList(json['warnings'] ??
          (json['match'] is Map ? json['match']['warnings'] : null)),
      distanceKm: (json['distanceKm'] as num?)?.toDouble(),
      distanceExact: json['distanceExact'] == true,
      businessVerified: json['businessVerified'] == true,
      businessName: json['businessName'] as String?,
      workMode: json['workMode']?.toString() ?? 'ONSITE',
      salaryPeriod: json['salaryPeriod']?.toString() ?? 'MONTHLY',
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
    );
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }

  static double? _num(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'requiredSkills': requiredSkills,
      'salaryMin': salaryMin,
      'salaryMax': salaryMax,
      'jobType': jobType,
      'experience': experience,
      'location': location,
      'workMode': workMode,
      'salaryPeriod': salaryPeriod,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (sectorId != null && sectorId!.isNotEmpty) 'sectorId': sectorId,
      if (positionId != null && positionId!.isNotEmpty) 'positionId': positionId,
      if (skillIds.isNotEmpty) 'skillIds': skillIds,
      if (locationId != null && locationId!.isNotEmpty) 'locationId': locationId,
      if (addressText != null && addressText!.isNotEmpty) 'addressText': addressText,
    };
  }
}

class CandidateMatch {
  final String candidateId;
  final String name;
  final List<String> skills;
  final List<String> roles;
  final double experienceYears;
  final double? expectedSalary;
  final String availability;
  final double? distanceKm;
  final int? matchScore;
  final List<String> reasons;
  final List<String> warnings;

  const CandidateMatch({
    required this.candidateId,
    required this.name,
    this.skills = const [],
    this.roles = const [],
    this.experienceYears = 0,
    this.expectedSalary,
    this.availability = '',
    this.distanceKm,
    this.matchScore,
    this.reasons = const [],
    this.warnings = const [],
  });

  factory CandidateMatch.fromJson(Map<String, dynamic> json) {
    return CandidateMatch(
      candidateId: json['candidateId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Candidate',
      skills: JobPost._stringList(json['skills']),
      roles: JobPost._stringList(json['roles']),
      experienceYears: (json['experienceYears'] as num?)?.toDouble() ?? 0,
      expectedSalary: (json['expectedSalary'] as num?)?.toDouble(),
      availability: json['availability']?.toString() ?? '',
      distanceKm: (json['distanceKm'] as num?)?.toDouble(),
      matchScore: (json['matchScore'] as num?)?.toInt(),
      reasons: JobPost._stringList(json['reasons']),
      warnings: JobPost._stringList(json['warnings']),
    );
  }
}

enum ApplicationStatus { applied, interview, selected, rejected, withdrawn }

class JobApplication {
  final String id;
  final JobPost jobPost;
  final String applicantId;
  final String? applicantName;
  final String? coverLetter;
  final String? resumeUrl;
  final ApplicationStatus status;
  final DateTime? createdAt;

  JobApplication({
    required this.id,
    required this.jobPost,
    required this.applicantId,
    this.applicantName,
    this.coverLetter,
    this.resumeUrl,
    required this.status,
    this.createdAt,
  });

  factory JobApplication.fromJson(Map<String, dynamic> json) {
    return JobApplication(
      id: json['id'],
      jobPost: JobPost.fromJson(json['jobPost'] is Map
          ? Map<String, dynamic>.from(json['jobPost'] as Map)
          : const {}),
      applicantId: json['applicant']?['id'] ?? '',
      applicantName: json['applicant']?['fullName'],
      coverLetter: json['coverLetter'],
      resumeUrl: json['resumeUrl'],
      status: _statusFromString(json['status']),
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
    );
  }

  static ApplicationStatus _statusFromString(String? status) {
    switch (status?.toUpperCase()) {
      case 'APPLIED': return ApplicationStatus.applied;
      case 'INTERVIEW': return ApplicationStatus.interview;
      case 'SELECTED': return ApplicationStatus.selected;
      case 'REJECTED': return ApplicationStatus.rejected;
      case 'WITHDRAWN': return ApplicationStatus.withdrawn;
      default: return ApplicationStatus.applied;
    }
  }
}
