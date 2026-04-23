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
  final bool? isActive;

  MasterEntry({
    required this.id,
    required this.label,
    required this.type,
    this.code,
    this.isActive,
  });

  factory MasterEntry.fromJson(Map<String, dynamic> json) {
    return MasterEntry(
      id: json['id'],
      label: json['label'],
      type: json['type'],
      code: json['code'],
      isActive: json['isActive'],
    );
  }
}

class MasterEntriesRepository {
  final Dio _dio;

  MasterEntriesRepository(this._dio);

  Future<List<MasterEntry>> getByType(String type) async {
    final res = await _dio.get('/master-entries', queryParameters: {
      'type': type,
      'isActive': 'true',
    });
    return (res.data as List).map((json) => MasterEntry.fromJson(json)).toList();
  }
}
