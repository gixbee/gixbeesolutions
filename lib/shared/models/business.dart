class Business {
  final String id;
  final String name;
  final String type;
  final String? description;
  final String? specialty;
  final String? phone;
  final String? address;
  final String ownerId;
  final String status;
  final DateTime? createdAt;

  Business({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    this.specialty,
    this.phone,
    this.address,
    required this.ownerId,
    required this.status,
    this.createdAt,
  });

  factory Business.fromJson(Map<String, dynamic> json) {
    return Business(
      id: json['id'],
      name: json['name'],
      type: json['type'],
      description: json['description'],
      specialty: json['specialty'],
      phone: json['phone'],
      address: json['address'],
      ownerId: json['owner']?['id'] ?? json['ownerId'] ?? '',
      status: json['status'] ?? 'PENDING',
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'description': description,
      'specialty': specialty,
      'phone': phone,
      'address': address,
    };
  }
}
