enum SkillType { manual, digital, care, education }

class Worker {
  final String id;
  final String name;
  final String title;
  final String bio;
  final String imageUrl;
  final double rating;
  final int completedJobs;
  final int reviewCount;
  final bool isFeatured;
  final double hourlyRate;
  final List<String> skills;
  final List<String> availabilityTags;
  final SkillType primaryType;
  final String status;

  Worker({
    required this.id,
    required this.name,
    required this.title,
    required this.bio,
    required this.imageUrl,
    required this.rating,
    required this.completedJobs,
    required this.reviewCount,
    required this.isFeatured,
    required this.hourlyRate,
    required this.skills,
    required this.availabilityTags,
    required this.primaryType,
    required this.status,
  });

  factory Worker.fromMap(Map<String, dynamic> map) {
    return Worker(
      id: map['id'],
      name: map['name'],
      title: map['title'],
      bio: map['bio'],
      imageUrl: map['image_url'],
      rating: (map['rating'] as num).toDouble(),
      completedJobs: map['completed_jobs'] ?? 0,
      reviewCount: map['review_count'] ?? 0,
      isFeatured: map['is_featured'] ?? false,
      hourlyRate: (map['hourly_rate'] as num).toDouble(),
      skills: List<String>.from(map['skills'] ?? []),
      availabilityTags: List<String>.from(map['availability_tags'] ?? []),
      primaryType: SkillType.values.firstWhere(
        (e) => e.toString().split('.').last == map['primary_type'],
        orElse: () => SkillType.manual,
      ),
      status: map['status'] ?? 'available',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'title': title,
      'bio': bio,
      'image_url': imageUrl,
      'rating': rating,
      'completed_jobs': completedJobs,
      'review_count': reviewCount,
      'is_featured': isFeatured,
      'hourly_rate': hourlyRate,
      'skills': skills,
      'availability_tags': availabilityTags,
      'primary_type': primaryType.toString().split('.').last,
      'status': status,
    };
  }
}
