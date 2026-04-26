class User {
  final String id;
  final String phone;
  final String? email;
  final String? name;
  final String? avatar;
  final bool isAvailableForWork;
  final String? role;
  final bool hasWorkerProfile;

  bool get isWorker => role == 'OPERATOR' || hasWorkerProfile;

  User({
    required this.id,
    required this.phone,
    this.email,
    this.name,
    this.avatar,
    this.isAvailableForWork = true,
    this.role,
    this.hasWorkerProfile = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      name: json['name'] as String?,
      avatar: json['profileImageUrl'] as String?, // map backend profileImageUrl to avatar
      isAvailableForWork: json['isAvailableForWork'] as bool? ?? true,
      role: json['role'] as String?,
      hasWorkerProfile: json['hasWorkerProfile'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': phone,
      'email': email,
      'name': name,
      'avatar': avatar,
    };
  }
}
