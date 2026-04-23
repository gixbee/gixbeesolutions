import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final locationServiceProvider = Provider((ref) => LocationService());

final currentAddressProvider =
    StateProvider<String>((ref) => 'Select Location');
final locationLoadingProvider = StateProvider<bool>((ref) => false);

class LocationService {
  Future<Position?> getCurrentPosition() async {
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

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 10),
      ),
    );
  }

  Future<String> getAddressFromLatLng(Position position) async {
    // The 'geocoding' package does not support Flutter Web
    if (kIsWeb) {
      return "Web Location (${position.latitude.toStringAsFixed(2)}, ${position.longitude.toStringAsFixed(2)})";
    }

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 5));

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
