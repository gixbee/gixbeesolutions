class User {
  final String id;
  final String phone;
  final String? email;
  final String? name;
  final String? avatar;

  User({
    required this.id,
    required this.phone,
    this.email,
    this.name,
    this.avatar,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      name: json['name'] as String?,
      avatar: json['avatar'] as String?,
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
