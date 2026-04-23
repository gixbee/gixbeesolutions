import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/models/worker.dart';
import 'auth_repository.dart'; // To get dioProvider

final workerRepositoryProvider = Provider((ref) {
  final dio = ref.watch(dioProvider);
  return WorkerRepository(dio);
});

final workersProvider = FutureProvider<List<Worker>>((ref) async {
  final repository = ref.watch(workerRepositoryProvider);
  return repository.getWorkers();
});

class WorkerRepository {
  final Dio _dio;

  WorkerRepository(this._dio);

  Future<List<Worker>> getWorkers() async {
    try {
      final response = await _dio.get('/workers');
      final data = response.data as List;
      return data.map((item) => Worker.fromMap(item as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error fetching workers: $e');
      rethrow;
    }
  }

  Future<Worker> getWorkerById(String id) async {
    try {
      final response = await _dio.get('/workers/$id');
      return Worker.fromMap(response.data as Map<String, dynamic>);
    } catch (e) {
      rethrow;
    }
  }
}
