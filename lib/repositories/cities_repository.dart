import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'auth_repository.dart';

/// A serviceable city from the admin cities master (GET /cities). The home
/// location picker lists these (replacing the old hardcoded list), and the
/// picked city's [id] scopes location-specific content: bannersProvider /
/// dealsProvider send `cityId` so the backend returns global entries plus the
/// ones targeted at this city (OLX-style city scoping, managed from the
/// super-admin portal's Cities page).
class CityEntry {
  final String id;
  final String name;
  final String state;
  final double lat;
  final double lng;

  const CityEntry({
    required this.id,
    required this.name,
    required this.state,
    required this.lat,
    required this.lng,
  });

  String get displayName => '$name, $state';

  factory CityEntry.fromJson(Map<String, dynamic> json) {
    return CityEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      state: json['state'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
    );
  }
}

final citiesRepositoryProvider = Provider<CitiesRepository>((ref) {
  return CitiesRepository(ref.watch(dioProvider));
});

class CitiesRepository {
  final Dio _dio;

  CitiesRepository(this._dio);

  Future<List<CityEntry>> getActive() async {
    final res =
        await _dio.get('/cities', queryParameters: {'isActive': 'true'});
    return (res.data as List)
        .map((json) => CityEntry.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

/// Active serviceable cities. Empty list on failure — callers fall back to
/// their own defaults (the picker keeps a small hardcoded list) so the picker
/// never renders blank when the backend is unreachable.
final citiesProvider = FutureProvider<List<CityEntry>>((ref) async {
  try {
    return await ref.watch(citiesRepositoryProvider).getActive();
  } catch (e) {
    debugPrint('Error fetching cities: $e');
    return const [];
  }
});

/// The serviceable city the user is currently browsing in — set when a city
/// is picked in the home location picker, or resolved from GPS via
/// [nearestCity]. Null = unknown/global (feeds show only global content).
/// City-scoped feeds (banners, deals) watch this and refetch on change.
final currentCityProvider = StateProvider<CityEntry?>((ref) => null);

/// Nearest city to (lat, lng) within [maxKm] — used to map a GPS fix onto a
/// serviceable city. Returns null when nothing is close enough (user is
/// outside every launch city). Haversine, good enough at city scale.
CityEntry? nearestCity(
  List<CityEntry> cities,
  double lat,
  double lng, {
  double maxKm = 100,
}) {
  CityEntry? best;
  var bestKm = maxKm;
  for (final c in cities) {
    const r = 6371.0; // Earth radius, km
    final dLat = (c.lat - lat) * math.pi / 180;
    final dLng = (c.lng - lng) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat * math.pi / 180) *
            math.cos(c.lat * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final km = 2 * r * math.asin(math.min(1, math.sqrt(a)));
    if (km <= bestKm) {
      bestKm = km;
      best = c;
    }
  }
  return best;
}
