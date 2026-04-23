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
  });

  factory JobPost.fromJson(Map<String, dynamic> json) {
    return JobPost(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      requiredSkills: List<String>.from(json['requiredSkills'] ?? []),
      salaryMin: json['salaryMin']?.toDouble(),
      salaryMax: json['salaryMax']?.toDouble(),
      jobType: json['jobType'] ?? 'Full Time',
      experience: json['experience'] ?? 'Fresher',
      location: json['location'] ?? '',
      isActive: json['isActive'] ?? true,
      employerId: json['employer']?['id'] ?? json['employerId'] ?? '',
      employerName: json['employer']?['fullName'] ?? json['employer']?['name'],
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
    );
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
    };
  }
}

enum ApplicationStatus { applied, interview, selected, rejected }

class JobApplication {
  final String id;
  final JobPost jobPost;
  final String applicantId;
  final String? applicantName;
  final String? coverLetter;
  final ApplicationStatus status;
  final DateTime? createdAt;

  JobApplication({
    required this.id,
    required this.jobPost,
    required this.applicantId,
    this.applicantName,
    this.coverLetter,
    required this.status,
    this.createdAt,
  });

  factory JobApplication.fromJson(Map<String, dynamic> json) {
    return JobApplication(
      id: json['id'],
      jobPost: JobPost.fromJson(json['jobPost']),
      applicantId: json['applicant']?['id'] ?? '',
      applicantName: json['applicant']?['fullName'],
      coverLetter: json['coverLetter'],
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
      default: return ApplicationStatus.applied;
    }
  }
}
