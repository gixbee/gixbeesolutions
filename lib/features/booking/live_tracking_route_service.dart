import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/config/app_config.dart';

class LiveTrackingRouteResult {
  const LiveTrackingRouteResult({
    required this.points,
    this.distanceText,
    this.etaText,
  });

  final List<LatLng> points;
  final String? distanceText;
  final String? etaText;
}

class LiveTrackingRouteService {
  LiveTrackingRouteService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
              ),
            );

  final Dio _dio;

  Future<LiveTrackingRouteResult?> fetchRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (AppConfig.olaMapsApiKey.isEmpty) return null;

    try {
      final response = await _dio.post(
        AppConfig.olaDirectionsUrl,
        queryParameters: {
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          'api_key': AppConfig.olaMapsApiKey,
        },
      );
      if (response.statusCode != 200 || response.data is! Map) return null;

      final data = response.data as Map;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty || routes.first is! Map) return null;

      final route = routes.first as Map;
      final legs = route['legs'] as List?;
      final leg = legs != null && legs.isNotEmpty && legs.first is Map
          ? legs.first as Map
          : null;
      final polyline = route['overview_polyline']?.toString();
      final points = polyline == null ? <LatLng>[] : decodePolyline(polyline);

      String? distanceText = leg?['readable_distance']?.toString();
      String? etaText = leg?['readable_duration']?.toString();
      final rawDistance = leg?['distance'];
      final rawDuration = leg?['duration'];
      if (distanceText == null && rawDistance is num) {
        distanceText = '${(rawDistance / 1000).toStringAsFixed(1)} km';
      }
      if (etaText == null && rawDuration is num) {
        etaText = '${(rawDuration / 60).ceil()} min';
      }

      return LiveTrackingRouteResult(
        points: points,
        distanceText: distanceText,
        etaText: etaText,
      );
    } catch (error) {
      debugPrint('Failed to fetch Ola route: $error');
      return null;
    }
  }

  static List<LatLng> decodePolyline(String encoded) {
    final polyline = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : result >> 1;

      polyline.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return polyline;
  }

  static double estimateDistanceKm(LatLng origin, LatLng destination) {
    const earthRadiusKm = 6371.0;
    final dLat = (destination.latitude - origin.latitude) * math.pi / 180;
    final dLng = (destination.longitude - origin.longitude) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(origin.latitude * math.pi / 180) *
            math.cos(destination.latitude * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }
}
