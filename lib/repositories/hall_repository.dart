import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart';

final hallRepositoryProvider = Provider<HallRepository>((ref) {
  return HallRepository(ref.watch(dioProvider));
});

class HallRepository {
  HallRepository(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> getVenue(String businessId) async {
    final res = await _dio.get('/businesses/$businessId/venue');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> patchVenue(
    String businessId,
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.patch('/businesses/$businessId/venue', data: data);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> listHalls(String businessId) async {
    final res = await _dio.get('/businesses/$businessId/halls');
    return (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createHall(
    String businessId,
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.post('/businesses/$businessId/halls', data: data);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> getHall(String businessId, String hallId) async {
    final res = await _dio.get('/businesses/$businessId/halls/$hallId');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> patchHall(
    String businessId,
    String hallId,
    Map<String, dynamic> data,
  ) async {
    final res =
        await _dio.patch('/businesses/$businessId/halls/$hallId', data: data);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> archiveHall(String businessId, String hallId) async {
    await _dio.delete('/businesses/$businessId/halls/$hallId');
  }

  Future<Map<String, dynamic>> getPackage(
    String businessId,
    String hallId,
  ) async {
    final res =
        await _dio.get('/businesses/$businessId/halls/$hallId/package');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> savePackage(
    String businessId,
    String hallId,
    Map<String, dynamic> package,
  ) async {
    final res = await _dio.put(
      '/businesses/$businessId/halls/$hallId/package',
      data: {'package': package},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> getCalendar(
    String businessId,
    String hallId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final res = await _dio.get(
      '/businesses/$businessId/halls/$hallId/calendar',
      queryParameters: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> createBlock(
    String businessId,
    String hallId,
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.post(
      '/businesses/$businessId/halls/$hallId/blocks',
      data: data,
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> releaseBlock(String businessId, String blockId) async {
    await _dio.post('/businesses/$businessId/blocks/$blockId/release');
  }

  Future<List<Map<String, dynamic>>> listOperators(
    String businessId,
    String hallId,
  ) async {
    final res =
        await _dio.get('/businesses/$businessId/halls/$hallId/operators');
    return (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> addOperator(
    String businessId,
    String hallId,
    String userId,
  ) async {
    await _dio.post(
      '/businesses/$businessId/halls/$hallId/operators',
      data: {'userId': userId},
    );
  }

  Future<void> removeOperator(
    String businessId,
    String hallId,
    String userId,
  ) async {
    await _dio.delete(
      '/businesses/$businessId/halls/$hallId/operators/$userId',
    );
  }

  Future<List<Map<String, dynamic>>> listMedia(
    String businessId,
    String hallId,
  ) async {
    final res = await _dio.get('/businesses/$businessId/halls/$hallId/media');
    return (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> addMedia(
    String businessId,
    String hallId,
    String url, {
    int sortOrder = 0,
  }) async {
    final res = await _dio.post(
      '/businesses/$businessId/halls/$hallId/media',
      data: {'url': url, 'sortOrder': sortOrder},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> removeMedia(
    String businessId,
    String hallId,
    String mediaId,
  ) async {
    await _dio.delete(
      '/businesses/$businessId/halls/$hallId/media/$mediaId',
    );
  }
}
