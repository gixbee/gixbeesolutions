import 'user.dart';

class TalentProfile {
  final String id;
  final User? user;
  final List<String> skills;
  final String? experience;
  final String? bio;
  final bool jobAlertsEnabled;
  final bool isActive;
  final double rating;

  TalentProfile({
    required this.id,
    this.user,
    required this.skills,
    this.experience,
    this.bio,
    this.jobAlertsEnabled = true,
    this.isActive = true,
    this.rating = 0.0,
  });

  factory TalentProfile.fromJson(Map<String, dynamic> json) {
    return TalentProfile(
      id: json['id'],
      user: json['user'] != null ? User.fromJson(json['user']) : null,
      skills: List<String>.from(json['skills'] ?? []),
      experience: json['experience'],
      bio: json['bio'],
      jobAlertsEnabled: json['jobAlertsEnabled'] ?? true,
      isActive: json['isActive'] ?? true,
      rating: (json['rating'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'skills': skills,
      'experience': experience,
      'bio': bio,
      'jobAlertsEnabled': jobAlertsEnabled,
      'isActive': isActive,
    };
  }
}
