import 'dart:async';
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
    num? asNum(dynamic value) {
      if (value is num) return value;
      if (value is String) return num.tryParse(value);
      return null;
    }

    return CityEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      lat: asNum(json['lat'])?.toDouble() ?? 0,
      lng: asNum(json['lng'])?.toDouble() ?? 0,
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
        .where((c) => c.id.isNotEmpty && c.name.isNotEmpty)
        .toList();
  }
}

/// Active serviceable cities. List is small; Redis caches `GET /cities` on the API.
final citiesProvider = FutureProvider<List<CityEntry>>((ref) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(hours: 6), link.close);
  ref.onDispose(timer.cancel);
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

/// Map a cached/saved city onto the live GET /cities master.
///
/// The phone persists the city UUID. After a DB re-seed those ids 404 on
/// `businesses.cityId` (FK). Prefer the same id, then name+state, then
/// nearest pin, otherwise null (do not send a dead UUID).
CityEntry? resolveLiveCity(
  List<CityEntry> cities,
  CityEntry? saved, {
  double? lat,
  double? lng,
}) {
  if (saved != null) {
    for (final c in cities) {
      if (c.id == saved.id) return c;
    }
    final name = saved.name.trim().toLowerCase();
    final state = saved.state.trim().toLowerCase();
    for (final c in cities) {
      if (c.name.trim().toLowerCase() == name &&
          c.state.trim().toLowerCase() == state) {
        return c;
      }
    }
    for (final c in cities) {
      if (c.name.trim().toLowerCase() == name) return c;
    }
  }
  if (lat != null && lng != null) {
    return nearestCity(cities, lat, lng);
  }
  return null;
}

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

/// Common Indian aliases → catalog official names (lowercase).
const cityAliases = <String, String>{
  'trivandrum': 'thiruvananthapuram',
  'tvm': 'thiruvananthapuram',
  'cochin': 'kochi',
  'calicut': 'kozhikode',
  'bengaluru': 'bangalore',
  'bombay': 'mumbai',
  'madras': 'chennai',
};

String canonicalizeCityQuery(String raw) {
  final q = raw.trim().toLowerCase();
  return cityAliases[q] ?? q;
}

Set<String> citySearchKeys(CityEntry c) {
  final name = c.name.trim().toLowerCase();
  final keys = <String>{
    name,
    c.state.trim().toLowerCase(),
    c.displayName.trim().toLowerCase(),
  };
  for (final e in cityAliases.entries) {
    if (e.value == name) keys.add(e.key);
  }
  return keys;
}

bool cityMatchesQuery(CityEntry c, String raw) {
  final q = raw.trim().toLowerCase();
  if (q.isEmpty) return true;
  final expanded = canonicalizeCityQuery(q);
  for (final key in citySearchKeys(c)) {
    if (key.contains(q) || (expanded != q && key.contains(expanded))) {
      return true;
    }
  }
  return false;
}

/// Match a typed city name onto the live master. Exact display/name first,
/// then aliases (Trivandrum → Thiruvananthapuram), then prefix, then contains.
CityEntry? matchTypedCity(List<CityEntry> cities, String raw) {
  final q = raw.trim().toLowerCase();
  if (q.isEmpty) return null;
  final expanded = canonicalizeCityQuery(q);
  for (final c in cities) {
    final name = c.name.toLowerCase();
    if (c.displayName.toLowerCase() == q || name == q || name == expanded) {
      return c;
    }
  }
  for (final c in cities) {
    if (c.name.toLowerCase().startsWith(q) ||
        c.displayName.toLowerCase().startsWith(q) ||
        c.name.toLowerCase().startsWith(expanded)) {
      return c;
    }
  }
  for (final c in cities) {
    if (cityMatchesQuery(c, raw)) return c;
  }
  return null;
}
