import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../core/config/app_config.dart';
import '../../theme.dart';
import '../../services/ola_maps_style_service.dart';
import '../../shared/widgets/gx_button.dart';
import '../profile/addresses/location_search_delegate.dart';

/// Result of a pin-drop: the exact coordinates the user confirmed, plus a
/// best-effort reverse-geocoded address label.
class PinnedLocation {
  final double lat;
  final double lng;
  final String address;
  const PinnedLocation({
    required this.lat,
    required this.lng,
    required this.address,
  });
}

/// Uber/Grab-style "move the map, drop the pin" screen.
///
/// Why this exists: typed Indian addresses ("near SBI, Kazhakkoottam")
/// forward-geocode wrongly or not at all, and on web the geocoder is absent
/// entirely — the old flow then silently fell back to the *city centre*,
/// corrupting dispatch matching, the worker's route, and the GPS-strike
/// destination. Here the user visually confirms the real spot; the confirmed
/// pin becomes the booking's serviceLat/serviceLng.
///
/// The pin is a FIXED overlay at screen centre (not a map annotation) — the
/// map moves under it, and on every camera-idle we reverse-geocode the
/// centre for the address label. This is the standard, cheap approach: no
/// per-frame annotation churn.
class LocationPinScreen extends StatefulWidget {
  /// Where to open the map. Best available guess — a forward-geocode of the
  /// typed address, the user's home pick, or the city centre. NEVER used as
  /// the booking coordinate; only as the initial camera target the user then
  /// adjusts.
  final double initialLat;
  final double initialLng;

  /// Typed address text to show as the starting label (until the user moves
  /// the map and reverse-geocoding replaces it).
  final String? initialAddress;

  const LocationPinScreen({
    super.key,
    required this.initialLat,
    required this.initialLng,
    this.initialAddress,
  });

  @override
  State<LocationPinScreen> createState() => _LocationPinScreenState();
}

class _LocationPinScreenState extends State<LocationPinScreen>
    with WidgetsBindingObserver {
  MapLibreMapController? _controller;
  String? _styleJson;
  bool _styleLoading = true;
  String? _styleError;

  /// Fresh key each visit — reusing a disposed MapLibre view renders blank.
  late final Key _mapKey = UniqueKey();

  /// Current map-centre coordinate (updated on camera idle).
  late LatLng _center = LatLng(widget.initialLat, widget.initialLng);

  String _address = '';
  bool _geocoding = false;
  int _geocodeSeq = 0; // guards against out-of-order reverse-geocode results

  @override
  void initState() {
    super.initState();
    _address = widget.initialAddress?.trim() ?? '';
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadStyle());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Do NOT dispose the controller (disposing + recreating the platform view
    // yields a blank map on the next open, per the tracking screen's note).
    _controller = null;
    super.dispose();
  }

  /// Same white-map bug can strike when the app is backgrounded and resumed
  /// while this screen is visible (system reclaims the GL surface). A nudge
  /// on resume forces a redraw, identical to the showSearch fix above.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller?.animateCamera(CameraUpdate.zoomBy(0.0001));
    }
  }

  Future<void> _loadStyle() async {
    if (AppConfig.olaMapsApiKey.isEmpty) {
      if (!mounted) return;
      setState(() {
        _styleLoading = false;
        _styleError = 'Ola Maps key not configured';
      });
      return;
    }
    final json = await OlaMapsStyleService().buildStyleJson();
    if (!mounted) return;
    setState(() {
      _styleJson = json;
      _styleLoading = false;
      _styleError = json == null ? 'Could not load Ola Maps' : null;
    });
  }

  /// Reverse-geocode the current centre into a readable label. Sequence-
  /// guarded so a slow earlier lookup can't overwrite a newer one. Silently
  /// leaves the last good label on failure (e.g. web, where the platform
  /// geocoder is unavailable) — the coordinate is still valid regardless.
  Future<void> _reverseGeocode(LatLng target) async {
    final seq = ++_geocodeSeq;
    setState(() => _geocoding = true);
    try {
      final placemarks = await Geocoding()
          .placemarkFromCoordinates(target.latitude, target.longitude)
          .timeout(const Duration(seconds: 5));
      if (!mounted || seq != _geocodeSeq) return;
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String?>[
          p.name,
          p.subLocality,
          p.locality,
          p.administrativeArea,
        ];
        final label = parts
            .where((s) => s != null && s.trim().isNotEmpty)
            .toSet() // de-dupe (name often repeats locality)
            .join(', ');
        if (label.isNotEmpty) setState(() => _address = label);
      }
    } catch (_) {
      // keep last good label; coordinate is what matters
    } finally {
      if (mounted && seq == _geocodeSeq) setState(() => _geocoding = false);
    }
  }

  void _onCameraIdle() {
    final c = _controller;
    if (c == null) return;
    final target = c.cameraPosition?.target;
    if (target == null) return;
    _center = target;
    unawaited(_reverseGeocode(target));
  }

  void _confirm() {
    Navigator.pop(
      context,
      PinnedLocation(
        lat: _center.latitude,
        lng: _center.longitude,
        address: _address.trim().isNotEmpty
            ? _address.trim()
            : (widget.initialAddress?.trim() ?? ''),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gx.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _buildMap(context)),

            // Fixed centre pin overlay. Sits slightly above true centre so
            // the tip (not the middle of the icon) marks the spot.
            IgnorePointer(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on,
                          size: 44, color: context.gx.accentSoft),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Back button
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: context.gx.card,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8),
                  ],
                ),
                child: IconButton(
                  icon: Icon(Icons.arrow_back, color: context.gx.ink),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),

            // Search bar overlay
            Positioned(
              top: 16,
              left: 64,
              right: 16,
              child: GestureDetector(
                onTap: () async {
                  final place = await showSearch<OlaPlace?>(
                    context: context,
                    delegate: LocationSearchDelegate(),
                  );
                  if (place != null && _controller != null) {
                    // Place selected — animate to it. animateCamera also
                    // forces the GL surface to redraw (see note below).
                    await _controller!.animateCamera(
                      CameraUpdate.newLatLngZoom(
                        LatLng(place.lat, place.lng),
                        16.0,
                      ),
                    );
                  } else {
                    // maplibre_gl 0.21 Android bug: showSearch() pushes a
                    // full opaque route that hides the platform view; when
                    // it pops the GL surface is not redrawn and the map
                    // stays permanently white. A sub-pixel zoom nudge is
                    // the minimal trigger to force a redraw without visibly
                    // moving the map. The selected-place path above already
                    // recovered via animateCamera — this covers the dismiss
                    // path that previously left a white canvas.
                    _controller?.animateCamera(CameraUpdate.zoomBy(0.0001));
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: context.gx.card,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search,
                          size: 20, color: context.gx.ink.withValues(alpha: 0.5)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Search an area or address...',
                            style: TextStyle(
                                fontSize: 14,
                                color: context.gx.ink.withValues(alpha: 0.5))),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom confirm panel
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomPanel(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(BuildContext context) {
    if (_styleLoading) {
      return Container(
        color: context.gx.card,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }
    if (_styleJson == null) {
      // No map (missing key / load failure). Rather than block the booking,
      // let the user confirm the starting coordinate with a plain notice —
      // better a slightly-off pin they accepted than a silent city-centre.
      return Container(
        color: context.gx.card,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined,
                size: 48, color: context.gx.ink.withValues(alpha: 0.25)),
            const SizedBox(height: 12),
            Text(
              'Map unavailable\n(${_styleError ?? 'Ola Maps unavailable'})',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: context.gx.ink.withValues(alpha: 0.45)),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _styleLoading = true;
                  _styleError = null;
                });
                unawaited(_loadStyle());
              },
              child: const Text('Retry map'),
            ),
          ],
        ),
      );
    }

    return MapLibreMap(
      key: _mapKey,
      styleString: _styleJson!,
      initialCameraPosition:
          CameraPosition(target: _center, zoom: 16.5),
      trackCameraPosition: true,
      myLocationEnabled: false,
      compassEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      onMapCreated: (c) => _controller = c,
      onStyleLoadedCallback: () {
        if (!mounted) return;
        // Seed the initial address label from the starting coordinate.
        unawaited(_reverseGeocode(_center));
      },
      onCameraIdle: _onCameraIdle,
    );
  }

  Widget _buildBottomPanel(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.gx.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SELECTED LOCATION',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: context.gx.ink.withValues(alpha: 0.45))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.place_rounded,
                      size: 18, color: context.gx.accentSoft),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _address.isNotEmpty
                          ? _address
                          : 'Pin location selected',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.gx.ink),
                    ),
                  ),
                  if (_geocoding)
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              const SizedBox(height: 16),
              GxButton(
                label: 'Confirm this location',
                icon: Icons.check_rounded,
                onTap: _confirm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
