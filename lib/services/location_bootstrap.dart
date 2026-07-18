import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../repositories/cities_repository.dart';
import '../repositories/worker_repository.dart'; // selectedLocationProvider
import 'location_service.dart';

/// Completes the location chain (v126 "Choose location" logic):
///
///   app start → restore last saved location → else GPS auto-detect →
///   reverse-geocode address → snap to nearest serviceable city →
///   feeds scope to that city. Every explicit pick (home picker) is
///   persisted so the app never asks twice.
///
/// State lives in the existing providers (currentAddressProvider,
/// selectedLocationProvider, currentCityProvider); this file only
/// orchestrates + persists them.
const _kLocationKey = 'gx_saved_location';
const _storage = FlutterSecureStorage();

/// Apply a location to all providers and persist it.
Future<void> applyLocation(
  WidgetRef ref, {
  required String address,
  required double lat,
  required double lng,
  CityEntry? city,
}) async {
  ref.read(currentAddressProvider.notifier).state = address;
  ref.read(selectedLocationProvider.notifier).state =
      (lat: lat, lng: lng, address: address);
  ref.read(currentCityProvider.notifier).state = city;

  try {
    await _storage.write(
      key: _kLocationKey,
      value: jsonEncode({
        'address': address,
        'lat': lat,
        'lng': lng,
        if (city != null)
          'city': {
            'id': city.id,
            'name': city.name,
            'state': city.state,
            'lat': city.lat,
            'lng': city.lng,
          },
      }),
    );
  } catch (e) {
    debugPrint('Location persist failed: $e');
  }
}

/// Idempotent bootstrap — call once from MainWrapper. Restores the saved
/// location; when none exists, silently tries GPS (no dialogs beyond the OS
/// permission prompt). Failures leave the "Select Location" state untouched
/// so the user can still pick manually.
Future<void> ensureLocationInitialized(WidgetRef ref) async {
  if (ref.read(selectedLocationProvider) != null) return; // already set

  // 1. Restore last saved pick.
  try {
    final raw = await _storage.read(key: _kLocationKey);
    if (raw != null) {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final cityData = data['city'] as Map<String, dynamic>?;
      final city = cityData == null
          ? null
          : CityEntry(
              id: cityData['id'] as String,
              name: cityData['name'] as String,
              state: cityData['state'] as String,
              lat: (cityData['lat'] as num).toDouble(),
              lng: (cityData['lng'] as num).toDouble(),
            );
      ref.read(currentAddressProvider.notifier).state =
          data['address'] as String;
      ref.read(selectedLocationProvider.notifier).state = (
        lat: (data['lat'] as num).toDouble(),
        lng: (data['lng'] as num).toDouble(),
        address: data['address'] as String,
      );
      ref.read(currentCityProvider.notifier).state = city;
      return;
    }
  } catch (e) {
    debugPrint('Location restore failed: $e');
  }

  // 2. First run — GPS auto-detect.
  try {
    final pos = await ref.read(locationServiceProvider).getCurrentPosition();
    if (pos == null) return; // denied/off — user picks manually later
    final address = await ref
        .read(locationServiceProvider)
        .getAddressFromLatLng(pos)
        .timeout(const Duration(seconds: 8));

    // Snap to the nearest serviceable city so feeds scope correctly.
    List<CityEntry> cities = const [];
    try {
      cities = await ref.read(citiesProvider.future);
    } catch (e) {
      debugPrint('Cities load for location bootstrap failed: $e');
    }
    final city = nearestCity(cities, pos.latitude, pos.longitude);

    await applyLocation(
      ref,
      address: address,
      lat: pos.latitude,
      lng: pos.longitude,
      city: city,
    );
  } catch (e) {
    debugPrint('Location auto-detect failed: $e');
  }
}
