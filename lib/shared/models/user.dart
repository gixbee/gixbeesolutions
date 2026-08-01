class User {
  final String id;
  final String phone;
  final String? email;
  final String? name;
  final String? avatar;
  final bool isAvailableForWork;
  final String? role;
  final bool hasWorkerProfile;
  final bool instantHelpBlocked;
  final int lateCancelStrikeCount;
  final double? unblockCompensationAmountInr;
  final double? unblockCompensationDistanceKm;

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
    this.instantHelpBlocked = false,
    this.lateCancelStrikeCount = 0,
    this.unblockCompensationAmountInr,
    this.unblockCompensationDistanceKm,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      name: json['name'] as String?,
      avatar: (json['profileImageUrl'] ?? json['avatar']) as String?,
      isAvailableForWork: json['isAvailableForWork'] as bool? ?? true,
      role: json['role'] as String?,
      hasWorkerProfile: json['hasWorkerProfile'] as bool? ?? false,
      instantHelpBlocked: json['instantHelpBlocked'] as bool? ?? false,
      lateCancelStrikeCount: (json['lateCancelStrikeCount'] as num?)?.toInt() ?? 0,
      unblockCompensationAmountInr:
          (json['unblockCompensationAmountInr'] as num?)?.toDouble(),
      unblockCompensationDistanceKm:
          (json['unblockCompensationDistanceKm'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': phone,
      'email': email,
      'name': name,
      'profileImageUrl': avatar,
      'isAvailableForWork': isAvailableForWork,
      'role': role,
      'hasWorkerProfile': hasWorkerProfile,
      'instantHelpBlocked': instantHelpBlocked,
      'lateCancelStrikeCount': lateCancelStrikeCount,
      'unblockCompensationAmountInr': unblockCompensationAmountInr,
      'unblockCompensationDistanceKm': unblockCompensationDistanceKm,
    };
  }
}
