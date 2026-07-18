class Business {
  final String id;
  final String name;
  final String type;
  final String? description;
  final String? specialty;
  final String? phone;
  final String? address;
  final String? documentUrl;

  /// Structured city scope — City.id from the serviceable-cities master
  /// (backend `cityId`, nullable). Set from the home's selected city when
  /// listing; `address` stays the free-text display string.
  final String? cityId;
  final String ownerId;
  final String status;
  final DateTime? createdAt;

  /// User ids granted operator access to this unit (backend `operatorIds`,
  /// a TypeORM simple-array). Empty when none.
  final List<String> operatorIds;

  /// Days the unit is marked unavailable (backend `offlineDays`,
  /// a simple-json array of ISO date strings). Empty when none.
  final List<DateTime> offlineDays;

  Business({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    this.specialty,
    this.phone,
    this.address,
    this.documentUrl,
    this.cityId,
    required this.ownerId,
    required this.status,
    this.createdAt,
    this.operatorIds = const [],
    this.offlineDays = const [],
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
      documentUrl: json['documentUrl'],
      cityId: json['cityId'],
      ownerId: json['owner']?['id'] ?? json['ownerId'] ?? '',
      status: json['status'] ?? 'PENDING',
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      operatorIds: _parseStringList(json['operatorIds']),
      offlineDays: _parseDateList(json['offlineDays']),
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
      'documentUrl': documentUrl,
      // Only send when set — the backend DTO validates cityId as a UUID.
      if (cityId != null) 'cityId': cityId,
    };
  }
}

/// Tolerant parse for the backend `operatorIds` simple-array, which can arrive
/// as a JSON list or (older rows) a comma-joined string.
List<String> _parseStringList(dynamic v) {
  if (v == null) return const [];
  if (v is List) {
    return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }
  if (v is String) {
    return v.isEmpty ? const [] : v.split(',').where((s) => s.isNotEmpty).toList();
  }
  return const [];
}

/// Tolerant parse for the backend `offlineDays` simple-json array of ISO date
/// strings. Unparseable entries are skipped rather than failing the whole list.
List<DateTime> _parseDateList(dynamic v) {
  if (v is List) {
    return v
        .map((e) => DateTime.tryParse(e.toString()))
        .whereType<DateTime>()
        .toList();
  }
  return const [];
}
