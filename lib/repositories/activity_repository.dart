import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';

final activityRepositoryProvider = Provider((ref) {
  return ActivityRepository(ref.watch(dioProvider));
});

class ActivityFeedPage {
  final List<Map<String, dynamic>> items;
  final int page;
  final int limit;
  final bool hasMore;
  final List<String> categoriesAvailable;

  ActivityFeedPage({
    required this.items,
    required this.page,
    required this.limit,
    required this.hasMore,
    required this.categoriesAvailable,
  });

  factory ActivityFeedPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final cats = json['categoriesAvailable'];
    return ActivityFeedPage(
      items: items,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 20,
      hasMore: json['hasMore'] == true,
      categoriesAvailable: cats is List
          ? cats.map((e) => e.toString()).toList()
          : const [],
    );
  }
}

class ActivityRepository {
  ActivityRepository(this._dio);
  final Dio _dio;

  /// `GET /activity/feed` — unified, server-sorted activity page.
  Future<ActivityFeedPage> fetchFeed({
    String? category,
    required String phase,
    String? statusGroup,
    required int page,
    int limit = 20,
  }) async {
    try {
      final response = await _dio.get(
        '/activity/feed',
        queryParameters: {
          if (category != null && category.isNotEmpty && category != 'all')
            'category': category,
          'phase': phase,
          if (statusGroup != null && statusGroup.isNotEmpty)
            'statusGroup': statusGroup,
          'page': page,
          'limit': limit,
        },
      );
      return ActivityFeedPage.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } catch (e) {
      debugPrint('Activity feed failed: $e');
      rethrow;
    }
  }
}
