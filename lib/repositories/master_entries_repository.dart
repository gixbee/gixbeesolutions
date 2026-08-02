import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart';

final masterEntriesRepositoryProvider = Provider<MasterEntriesRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return MasterEntriesRepository(dio);
});

class MasterEntry {
  final String id;
  final String label;
  final String type;
  final String? code;
  final String? value;
  final String? icon;
  final String? category;
  final bool? isActive;

  MasterEntry({
    required this.id,
    required this.label,
    required this.type,
    this.code,
    this.value,
    this.icon,
    this.category,
    this.isActive,
  });

  factory MasterEntry.fromJson(Map<String, dynamic> json) {
    return MasterEntry(
      id: json['id'] as String,
      label: json['label'] as String? ?? '',
      type: json['type'] as String? ?? '',
      code: json['code'] as String?,
      value: json['value'] as String?,
      icon: json['icon'] as String?,
      category: json['category'] as String?,
      isActive: json['isActive'] as bool?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'type': type,
        'code': code,
        'value': value,
        'icon': icon,
        'category': category,
        'isActive': isActive,
      };
}

class MasterEntriesRepository {
  final Dio _dio;

  MasterEntriesRepository(this._dio);

  Future<List<MasterEntry>> getByType(
    String type, {
    String? cityId,
    String? category,
  }) async {
    final res = await _dio.get('/master-entries', queryParameters: {
      'type': type,
      'isActive': 'true',
      if (cityId != null) 'cityId': cityId,
      if (category != null) 'category': category,
    });
    return (res.data as List)
        .map((json) => MasterEntry.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
