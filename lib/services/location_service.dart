import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

final locationServiceProvider = Provider((ref) => LocationService());

final currentAddressProvider =
    StateProvider<String>((ref) => 'Select Location');
final locationLoadingProvider = StateProvider<bool>((ref) => false);

class LocationService {
  final Geocoding _geocoding = Geocoding();

  /// Current GPS fix. Returns null when services/permission are blocked,
  /// or when the fix times out / fails.
  ///
  /// [fallbackToLastKnown]: if the live fix fails (common indoors / cold
  /// start), return the OS last-known position when available. Prefer this
  /// for Go Live — a slightly stale coord is far better than a failed
  /// toggle that never reaches the server.
  Future<Position?> getCurrentPosition({
    bool fallbackToLastKnown = false,
  }) async {
    bool serviceEnabled;
    LocationPermission permission;

    if (kIsWeb) {
      // On web, we skip the native service check as it can fail
      permission = await Geolocator.checkPermission();
    } else {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        return null;
      }
      permission = await Geolocator.checkPermission();
    }

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permissions are denied');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint(
          'Location permissions are permanently denied, we cannot request permissions.');
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (e) {
      debugPrint('getCurrentPosition failed: $e');
      if (fallbackToLastKnown) {
        try {
          final last = await Geolocator.getLastKnownPosition();
          if (last != null) {
            debugPrint(
                'Using last-known position (${last.latitude}, ${last.longitude})');
            return last;
          }
        } catch (lastErr) {
          debugPrint('getLastKnownPosition failed: $lastErr');
        }
      }
      return null;
    }
  }

  /// Why a GPS fix is currently impossible:
  /// - 'service_off'    — device location is disabled (needs the LOCATION
  ///                      settings screen, not app settings)
  /// - 'denied_forever'  — permission permanently denied (needs APP settings)
  /// - 'denied'          — denied but re-promptable
  /// - null              — nothing blocking; a fix should be attainable.
  Future<String?> gpsBlockReason() async {
    if (kIsWeb) return null;
    if (!await Geolocator.isLocationServiceEnabled()) return 'service_off';
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      return 'denied_forever';
    }
    if (permission == LocationPermission.denied) return 'denied';
    return null;
  }

  /// Opens the device's LOCATION settings (for 'service_off').
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Opens this app's settings page (for 'denied_forever').
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Fires when the user toggles the device location switch.
  Stream<ServiceStatus> serviceStatusStream() {
    if (kIsWeb) return const Stream.empty();
    return Geolocator.getServiceStatusStream();
  }

  Future<String> getAddressFromLatLng(Position position) async {
    // The 'geocoding' package does not support Flutter Web
    if (kIsWeb) {
      return "Web Location (${position.latitude.toStringAsFixed(2)}, ${position.longitude.toStringAsFixed(2)})";
    }

    try {
      List<Placemark> placemarks = await _geocoding
          .placemarkFromCoordinates(
            position.latitude,
            position.longitude,
          )
          .timeout(const Duration(seconds: 5));

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        return "${place.subLocality ?? place.locality}, ${place.locality ?? place.administrativeArea}";
      }
    } catch (e) {
      debugPrint('Error getting address: $e');
    }
    return "Unknown Location";
  }
}
