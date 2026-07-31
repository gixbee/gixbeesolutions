import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import '../../core/config/app_config.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_button.dart';
import '../../services/socket_service.dart';
import '../../services/location_service.dart';
import '../../services/ola_maps_style_service.dart';
import '../../repositories/auth_repository.dart';
import '../../shared/models/worker.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/booking_status_provider.dart';
import '../../repositories/worker_repository.dart';
import '../../shared/widgets/gx_snackbar.dart';
import 'arrival_otp_screen.dart';
import 'completion_otp_screen.dart';
import 'report_issue_sheet.dart';

/// Live map screen shown to the **customer** after a worker accepts their booking.
/// Displays the worker's real-time GPS location on a Google Map with the
/// customer's service address pinned.
class LiveTrackingMapScreen extends ConsumerStatefulWidget {
  final String bookingId;
  final Worker worker;
  final String? serviceAddress;
  final double? customerLat;
  final double? customerLng;
  final String? arrivalOtp;
  final bool isWorker;

  const LiveTrackingMapScreen({
    super.key,
    required this.bookingId,
    required this.worker,
    this.serviceAddress,
    this.customerLat,
    this.customerLng,
    this.arrivalOtp,
    this.isWorker = false,
  });

  @override
  ConsumerState<LiveTrackingMapScreen> createState() => _LiveTrackingMapScreenState();
}

class _LiveTrackingMapScreenState extends ConsumerState<LiveTrackingMapScreen> {
  // Ola Maps (MapLibre-spec vector tiles) rendered via maplibre_gl.
  // AUDIT FIX: no private _pollTimer any more — status comes from the shared
  // bookingStatusProvider (single poll per booking, app-wide).
  // NOTE: maplibre_gl 0.21+ renamed the public classes (Maplibre* → MapLibre*).
  // pubspec resolves 0.26.x, so these are MapLibreMap / MapLibreMapController.
  MapLibreMapController? _mapController;
  bool _currentStatus_navigatingAway = false;
  bool _styleReady = false;
  Circle? _workerCircle;
  Circle? _customerCircle;
  Line? _routeLine;
  LatLng? _workerLocation;
  LatLng? _customerLocation;
  String _currentStatus = 'ACCEPTED';
  String? _arrivalOtp;
  bool _isMapReady = false;

  /// Pre-hydrated Ola style JSON (api_key on every tile URL). Null while
  /// loading / on failure — MapLibre never sees a bare style URL alone.
  String? _olaStyleJson;
  bool _olaStyleLoading = true;
  String? _olaStyleError;

  /// Fresh platform-view key each visit — reusing a disposed MapLibre view
  /// after back+reopen often renders a full-screen blank.
  late final Key _mapViewKey = UniqueKey();

  late final SocketService _socketService;
  StreamSubscription<Map<String, dynamic>>? _statusSocketSub;

  /// Don't mount MapLibre until we have real coords (avoids Nagpur default).
  bool _coordsReady = false;

  // Pause state (v126 Instant Help): carried in the /status poll payload.
  bool _pauseRequested = false;
  bool _paused = false;
  bool _pauseActionBusy = false;

  // Job timer (mockup parity): starts when the arrival OTP flips the booking
  // ACTIVE (startedAt), ticks every second, freezes while paused, and
  // subtracts accumulated approved pause minutes.
  DateTime? _startedAt;
  int _pausedMinutes = 0;
  Duration _elapsed = Duration.zero;
  Timer? _jobTicker;

  /// Worker-only: HTTP location heartbeat so Redis stays warm for the
  /// customer's status-poll fallback even if the socket blips.
  Timer? _workerHttpHeartbeat;

  // Directions API state
  List<LatLng> _routePoints = [];
  String? _routeDistanceText;
  String? _routeEtaText;
  DateTime? _lastRouteFetch;

  // Default: center of India (Nagpur)
  static const LatLng _defaultCenter = LatLng(21.1458, 79.0882);

  @override
  void initState() {
    super.initState();
    _arrivalOtp = widget.arrivalOtp;

    // Set customer location if provided by the opener.
    if (widget.customerLat != null && widget.customerLng != null) {
      _customerLocation = LatLng(widget.customerLat!, widget.customerLng!);
    }

    // Join the Socket.IO room for this booking (queued if not connected yet;
    // re-emitted on every reconnect via SocketService).
    _socketService = ref.read(socketServiceProvider);
    _socketService.joinJobRoom(widget.bookingId);

    // Real-time status transitions via socket — don't wait for the 5-second
    // HTTP poll. When the worker verifies the arrival OTP the backend emits
    // booking_status_update with status:ACTIVE immediately; this catches it
    // in ~10ms instead of up to 5 seconds, fixing the "customer stuck on
    // tracking map after work started" bug.
    _statusSocketSub = _socketService.notifications.listen((event) {
      if (!mounted) return;
      final eventName = event['_event']?.toString();
      if (eventName != 'booking_status_update') return;
      final targetId =
          (event['bookingId'] ?? event['id'])?.toString();
      if (targetId != null && targetId != widget.bookingId) return;
      _applyStatusData(Map<String, dynamic>.from(event));
    });

    // Listen for real-time location updates (customer sees the worker move).
    _socketService.onLocationUpdated((data) {
      final lat = readCoord(data['lat']);
      final lng = readCoord(data['lng']);
      if (lat != null && lng != null && mounted) {
        _applyWorkerLocation(lat, lng);
      }
    });

    unawaited(_bootstrapMapAndLocations());
  }

  void _applyWorkerLocation(double lat, double lng) {
    if (!mounted) return;
    setState(() {
      _workerLocation = LatLng(lat, lng);
    });
    _syncMapAnnotations();
    _fitMapBounds();
    unawaited(_fetchRoute());
  }

  Future<void> _bootstrapMapAndLocations() async {
    // 1) Resolve real coordinates FIRST so the map never opens on Nagpur.
    await Future.wait([
      _loadBookingCoords(),
      if (widget.isWorker) _seedWorkerLocation(),
    ]);
    if (!mounted) return;

    setState(() => _coordsReady = true);

    // 2) Then load (or reuse cached) Ola style and create the map once.
    await _loadOlaStyle();
  }

  Future<void> _loadOlaStyle() async {
    if (AppConfig.olaMapsApiKey.isEmpty) {
      if (!mounted) return;
      setState(() {
        _olaStyleLoading = false;
        _olaStyleError = 'Ola Maps key not configured';
      });
      return;
    }
    final json = await OlaMapsStyleService().buildStyleJson();
    if (!mounted) return;
    setState(() {
      _olaStyleJson = json;
      _olaStyleLoading = false;
      _olaStyleError = json == null ? 'Could not load Ola Maps style' : null;
    });
  }

  Future<void> _loadBookingCoords() async {
    // Always refresh from booking — opener may have passed null when
    // serviceLat arrived as a string Decimal from the API.
    try {
      final booking = await ref
          .read(bookingRepositoryProvider)
          .getBookingById(widget.bookingId);
      if (booking != null) {
        final st = booking['status']?.toString().toUpperCase() ?? '';
        if (st == 'ACTIVE' || st == 'IN_PROGRESS' || st == 'WORK_IN_PROGRESS') {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => CompletionOtpScreen(
                  bookingId: widget.bookingId,
                  workerName: widget.worker.name,
                  isWorker: widget.isWorker,
                ),
              ),
            );
          }
          return;
        }
      }
      final lat = readCoord(booking?['serviceLat']) ??
          readCoord(widget.customerLat);
      final lng = readCoord(booking?['serviceLng']) ??
          readCoord(widget.customerLng);
      if (lat != null && lng != null && mounted) {
        setState(() => _customerLocation = LatLng(lat, lng));
        _syncMapAnnotations();
        _fitMapBounds();
        unawaited(_fetchRoute());
      }
    } catch (e) {
      debugPrint('Load booking coords failed: $e');
      final lat = readCoord(widget.customerLat);
      final lng = readCoord(widget.customerLng);
      if (lat != null && lng != null && mounted) {
        setState(() => _customerLocation = LatLng(lat, lng));
      }
    }
  }

  Future<void> _seedWorkerLocation() async {
    try {
      final pos =
          await ref.read(locationServiceProvider).getCurrentPosition();
      final user = await ref.read(currentUserProvider.future);
      if (pos == null || !mounted) return;
      setState(() {
        _workerLocation = LatLng(pos.latitude, pos.longitude);
      });
      _syncMapAnnotations();
      _fitMapBounds();
      _fetchRoute();
      if (user != null) {
        _socketService.startLocationStream(user.id, widget.bookingId);
        _socketService.updateLocation(
          user.id,
          pos.latitude,
          pos.longitude,
          jobId: widget.bookingId,
        );
        // Keep Redis warm for customer poll fallback.
        unawaited(_pushWorkerHttpLocation(pos.latitude, pos.longitude));
        _workerHttpHeartbeat?.cancel();
        _workerHttpHeartbeat = Timer.periodic(
          const Duration(seconds: 15),
          (_) async {
            try {
              final p = await ref
                  .read(locationServiceProvider)
                  .getCurrentPosition();
              if (p == null) return;
              await _pushWorkerHttpLocation(p.latitude, p.longitude);
            } catch (_) {}
          },
        );
      }
    } catch (e) {
      debugPrint('Seed worker location failed: $e');
    }
  }

  Future<void> _pushWorkerHttpLocation(double lat, double lng) async {
    try {
      await ref.read(workerRepositoryProvider).updateMyLocation(
            lat: lat,
            lng: lng,
          );
    } catch (e) {
      debugPrint('Worker HTTP location push failed: $e');
    }
  }

  Future<void> _openCustomerNavigation() async {
    final dest = _customerLocation;
    if (dest == null) {
      if (mounted) {
        showGxSnack(
          context,
          'Customer location not available yet. Try again in a moment.',
          type: GxSnackType.error,
        );
      }
      return;
    }
    final lat = dest.latitude;
    final lng = dest.longitude;
    final candidates = <Uri>[
      Uri.parse('google.navigation:q=$lat,$lng&mode=d'),
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
      ),
      Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
    ];
    for (final url in candidates) {
      try {
        final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
        if (ok) return;
      } catch (_) {}
    }
    if (mounted) {
      showGxSnack(
        context,
        'Could not open Maps. Install Google Maps and try again.',
        type: GxSnackType.error,
      );
    }
  }

  /// Keep the worker/customer dots and the route line in sync with state.
  /// MapLibre annotations are imperative (add/update handles), unlike the
  /// declarative google_maps_flutter marker sets this replaced.
  Future<void> _syncMapAnnotations() async {
    final c = _mapController;
    if (c == null || !_styleReady) return;
    try {
      // Worker dot (violet, moving).
      if (_workerLocation != null) {
        final opts = CircleOptions(
          geometry: _workerLocation,
          circleRadius: 9,
          circleColor: '#8B5CF6',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2.5,
        );
        if (_workerCircle == null) {
          _workerCircle = await c.addCircle(opts);
        } else {
          await c.updateCircle(_workerCircle!, opts);
        }
      }
      // Customer dot (green, static).
      if (_customerLocation != null && _customerCircle == null) {
        _customerCircle = await c.addCircle(CircleOptions(
          geometry: _customerLocation,
          circleRadius: 9,
          circleColor: '#10B981',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2.5,
        ));
      }
      // Route line: real road route when fetched, straight line as fallback.
      final points = _routePoints.isNotEmpty
          ? _routePoints
          : (_workerLocation != null && _customerLocation != null)
              ? [_workerLocation!, _customerLocation!]
              : const <LatLng>[];
      if (points.length >= 2) {
        final lineOpts = LineOptions(
          geometry: points,
          lineColor: '#448AFF',
          lineWidth: 4,
          lineOpacity: 0.9,
        );
        if (_routeLine == null) {
          _routeLine = await c.addLine(lineOpts);
        } else {
          await c.updateLine(_routeLine!, lineOpts);
        }
      }
    } catch (e) {
      debugPrint('Map annotation sync failed: $e');
    }
  }

  @override
  void dispose() {
    _jobTicker?.cancel();
    _workerHttpHeartbeat?.cancel();
    _statusSocketSub?.cancel();
    // AUDIT FIX: detach the socket listener registered in initState so this
    // dead State's setState can't be called and listeners don't stack.
    _socketService.offLocationUpdated();
    _socketService.leaveJobRoom(widget.bookingId);
    // Do NOT dispose MapLibreMapController here — disposing then recreating
    // the platform view on the next open often yields a full-screen blank.
    _mapController = null;
    super.dispose();
  }

  /// Fetch startedAt once the job goes ACTIVE, then tick the visible timer.
  Future<void> _startJobTimer() async {
    if (_startedAt != null) return;
    try {
      final booking = await ref
          .read(bookingRepositoryProvider)
          .getBookingById(widget.bookingId);
      final raw = booking?['startedAt']?.toString();
      if (raw == null) return;
      _startedAt = DateTime.tryParse(raw);
      if (_startedAt == null) return;
      _jobTicker?.cancel();
      _jobTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_paused) return; // frozen while the customer-approved pause runs
        final worked = DateTime.now().difference(_startedAt!) -
            Duration(minutes: _pausedMinutes);
        setState(() => _elapsed = worked.isNegative ? Duration.zero : worked);
      });
    } catch (e) {
      debugPrint('Job timer init failed: $e');
    }
  }

  String get _elapsedLabel {
    final h = _elapsed.inHours.toString().padLeft(2, '0');
    final m = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// AUDIT FIX: consume the SHARED booking-status poll (one per booking,
  /// app-wide) instead of running a private Timer here. Called from build via
  /// ref.listen, so state transitions are handled exactly once per new value.
  void _applyStatusData(Map<String, dynamic> statusData) {
    if (!mounted) return;
    final newStatus = statusData['status']?.toString().toUpperCase() ?? '';
    final otp = statusData['arrivalOtp']?.toString();

    // Poll fallback: operator lat/lng from Redis when socket is slow/down.
    if (!widget.isWorker) {
      final opLat = readCoord(statusData['operatorLat']);
      final opLng = readCoord(statusData['operatorLng']);
      if (opLat != null && opLng != null) {
        final prev = _workerLocation;
        final moved = prev == null ||
            (prev.latitude - opLat).abs() > 0.00001 ||
            (prev.longitude - opLng).abs() > 0.00001;
        if (moved) {
          _applyWorkerLocation(opLat, opLng);
        }
      }
    }

    // Pause flags change without a status transition — sync every update.
    final pauseRequested = statusData['pauseRequested'] == true;
    final paused = statusData['paused'] == true;
    final pausedMinutes =
        (statusData['pausedMinutes'] as num?)?.toInt() ?? _pausedMinutes;
    if (pauseRequested != _pauseRequested ||
        paused != _paused ||
        pausedMinutes != _pausedMinutes) {
      setState(() {
        _pauseRequested = pauseRequested;
        _paused = paused;
        _pausedMinutes = pausedMinutes;
      });
    }

    // Arrival OTP verified → job ACTIVE → navigate to CompletionOtpScreen.
    //
    // GUARD: _currentStatus_navigatingAway prevents stacked navigations when
    // this is called from both the socket subscription AND the ref.listen
    // poll in the same frame. Both paths are intentional (belt + suspenders)
    // but only one should push the route.
    if (newStatus == 'ACTIVE' || newStatus == 'IN_PROGRESS' || newStatus == 'WORK_IN_PROGRESS') {
      // Update the status label immediately so the UI shows "Work in progress"
      // even if navigation takes a beat (e.g. addPostFrameCallback fires on
      // the following frame).
      if (newStatus != _currentStatus) {
        setState(() => _currentStatus = newStatus);
      }
      if (_currentStatus_navigatingAway) return;
      _currentStatus_navigatingAway = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CompletionOtpScreen(
              bookingId: widget.bookingId,
              workerName: widget.worker.name,
              isWorker: widget.isWorker,
            ),
          ),
        );
      });
      return;
    }

    // Arrival OTP verified → job ACTIVE → start the visible work timer.
    if ((newStatus == 'ACTIVE' || newStatus == 'IN_PROGRESS') &&
        _startedAt == null) {
      _startJobTimer();
    }

    if (newStatus != _currentStatus) {
      setState(() {
        _currentStatus = newStatus;
        if (otp != null && otp.isNotEmpty) _arrivalOtp = otp;
      });

      // If completed or cancelled, leave the screen safely without build-phase or unmounted navigation crashes.
      if (['COMPLETED', 'CANCELLED', 'REJECTED'].contains(newStatus)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        });
      }
    }
  }

  void _fitMapBounds() {
    if (_mapController == null || !_isMapReady) return;

    final points = <LatLng>[];
    if (_workerLocation != null) points.add(_workerLocation!);
    if (_customerLocation != null) points.add(_customerLocation!);

    if (points.length >= 2) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b),
          points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b),
        ),
        northeast: LatLng(
          points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b),
          points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b),
        ),
      );
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(bounds,
            left: 60, top: 120, right: 60, bottom: 340),
      );
    } else if (points.length == 1) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 15),
      );
    }
  }

  Future<void> _fetchRoute() async {
    if (_workerLocation == null || _customerLocation == null) return;
    
    // Don't fetch if fetched less than 30 seconds ago to avoid spamming the API
    if (_lastRouteFetch != null && DateTime.now().difference(_lastRouteFetch!).inSeconds < 30) {
      return;
    }
    
    _lastRouteFetch = DateTime.now();

    // Ola Maps Directions (replaces Google Directions). Key comes from
    // --dart-define=OLA_MAPS_API_KEY; without it we keep the haversine
    // fallback ETA and the straight-line route — never a fake road route.
    if (AppConfig.olaMapsApiKey.isEmpty) return;

    try {
      final origin = '${_workerLocation!.latitude},${_workerLocation!.longitude}';
      final destination = '${_customerLocation!.latitude},${_customerLocation!.longitude}';

      // Ola's Directions API is a POST with query parameters.
      // NOTE: deliberately a separate bare Dio (NOT dioProvider) — the shared
      // client attaches the user's JWT, which must never be sent to Ola.
      // AUDIT FIX: added timeouts so a stalled route call can't hang forever.
      final response = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      )).post(
        AppConfig.olaDirectionsUrl,
        queryParameters: {
          'origin': origin,
          'destination': destination,
          'api_key': AppConfig.olaMapsApiKey,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes[0];
          final legs = route['legs'] as List?;
          final leg = (legs != null && legs.isNotEmpty) ? legs[0] : null;

          // overview_polyline is a plain encoded-polyline string.
          final polylineStr = route['overview_polyline']?.toString();
          final points =
              polylineStr == null ? <LatLng>[] : _decodePolyline(polylineStr);

          // Prefer readable fields; fall back to raw metres/seconds.
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

          if (mounted) {
            setState(() {
              if (points.isNotEmpty) _routePoints = points;
              _routeDistanceText = distanceText;
              _routeEtaText = etaText;
            });
            _syncMapAnnotations();
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch Ola route: $e');
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> polyline = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      polyline.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return polyline;
  }

  double? _estimateDistance() {
    if (_workerLocation == null || _customerLocation == null) return null;
    // Haversine formula
    const r = 6371.0; // Earth radius in km
    final dLat = (_customerLocation!.latitude - _workerLocation!.latitude) * math.pi / 180;
    final dLng = (_customerLocation!.longitude - _workerLocation!.longitude) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_workerLocation!.latitude * math.pi / 180) *
            math.cos(_customerLocation!.latitude * math.pi / 180) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  Widget _buildMapLayer(BuildContext context) {
    final center = _workerLocation ?? _customerLocation ?? _defaultCenter;

    if (_olaStyleLoading || !_coordsReady) {
      return Container(
        color: context.gx.card,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    if (_olaStyleJson == null) {
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
              'Map preview unavailable\n(${_olaStyleError ?? 'Ola Maps unavailable'})',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: context.gx.ink.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _olaStyleLoading = true;
                  _olaStyleError = null;
                });
                unawaited(_loadOlaStyle());
              },
              child: const Text('Retry map'),
            ),
          ],
        ),
      );
    }

    // UniqueKey forces a fresh Android platform view after back+reopen.
    return MapLibreMap(
      key: _mapViewKey,
      styleString: _olaStyleJson!,
      initialCameraPosition: CameraPosition(target: center, zoom: 15),
      myLocationEnabled: widget.isWorker,
      compassEnabled: false,
      rotateGesturesEnabled: false,
      trackCameraPosition: false,
      onMapCreated: (controller) {
        _mapController = controller;
      },
      onStyleLoadedCallback: () {
        if (!mounted) return;
        setState(() {
          _styleReady = true;
          _isMapReady = true;
        });
        // Reset annotation handles — they belong to the previous native map.
        _workerCircle = null;
        _customerCircle = null;
        _routeLine = null;
        _syncMapAnnotations();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          _fitMapBounds();
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Shared booking-status poll (one per booking, app-wide). Each new value
    // drives the same transitions the old private timer handled.
    ref.listen<AsyncValue<Map<String, dynamic>>>(
      bookingStatusProvider(widget.bookingId),
      (_, next) {
        final data = next.value;
        if (data != null) _applyStatusData(data);
      },
    );

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SizedBox.expand(
        child: Stack(
          children: [
            // ── Ola Map (MapLibre-spec vector tiles) ──
            Positioned.fill(
              child: _buildMapLayer(context),
            ),

            // ── Top Bar ──
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Back button
                    Container(
                      decoration: BoxDecoration(
                        color: cs.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: IconButton(
                        tooltip: 'Go back',
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const Spacer(),
                    // Re-center button
                    Container(
                      decoration: BoxDecoration(
                        color: cs.surface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: IconButton(
                        tooltip: 'Re-center map',
                        icon: const Icon(Icons.my_location),
                        onPressed: _fitMapBounds,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Bottom Info Panel ──
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomPanel(cs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanel(ColorScheme cs) {
    // Priority: Real API distance/ETA > Fallback Math estimate
    final fallbackDistance = _estimateDistance();
    final fallbackEta = fallbackDistance != null ? (fallbackDistance / 30 * 60).round() : null;

    final displayEta = _routeEtaText ?? (fallbackEta != null ? '${fallbackEta < 1 ? "<1" : fallbackEta} min' : null);
    final displayDistance = _routeDistanceText ?? (fallbackDistance != null ? '${fallbackDistance.toStringAsFixed(1)} km' : null);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor().withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_getStatusIcon(), size: 16, color: _getStatusColor()),
                    const SizedBox(width: 6),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _getStatusText(),
                        style: TextStyle(
                          color: _getStatusColor(),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Worker info row
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: NetworkImage(widget.worker.imageUrl),
                    onBackgroundImageError: (_, __) {},
                    child: widget.worker.imageUrl.isEmpty
                        ? Text(widget.worker.name.isNotEmpty ? widget.worker.name[0] : '?')
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.worker.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          widget.worker.title,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ETA chip
                  if (displayEta != null && _workerLocation != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: context.gx.accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            displayEta,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: context.gx.accent,
                            ),
                          ),
                          if (displayDistance != null)
                            Text(
                              displayDistance,
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Job timer (starts at arrival-OTP entry, freezes while paused).
              if ((_currentStatus == 'ACTIVE' ||
                      _currentStatus == 'IN_PROGRESS') &&
                  _startedAt != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: (_paused
                              ? GixbeeTheme.accentGold
                              : context.gx.accentSoft)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _paused
                                  ? Icons.pause_circle_outline_rounded
                                  : Icons.timer_outlined,
                              size: 16,
                              color: _paused
                                  ? GixbeeTheme.accentGold
                                  : context.gx.accentSoft,
                            ),
                            const SizedBox(width: 8),
                            Text(_paused ? 'Job timer · paused' : 'Job timer',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurfaceVariant)),
                          ],
                        ),
                        Text(_elapsedLabel,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                                color: _paused
                                    ? GixbeeTheme.accentGold
                                    : context.gx.accentSoft)),
                      ],
                    ),
                  ),
                ),

              // Pause / resume controls (v126) — only during active work.
              if (_currentStatus == 'ACTIVE' || _currentStatus == 'IN_PROGRESS')
                _pauseSection(cs),

              // Action buttons
              Row(
                children: [
                  // Call button
                  Expanded(
                    child: GxButton(
                      label: 'Call',
                      icon: Icons.call,
                      filled: false,
                      height: 48,
                      radius: 12,
                      fontSize: 14,
                      onTap: () async {
                        final url = Uri.parse('tel:+91${widget.worker.id}');
                        try {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        } catch (e) {
                          debugPrint('Could not launch call: $e');
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Worker sees navigation prompt; Customer sees OTP button
                  if (widget.isWorker)
                    Expanded(
                      flex: 2,
                      child: GxButton(
                        label: 'Navigate to Customer',
                        icon: Icons.navigation_rounded,
                        height: 48,
                        radius: 12,
                        fontSize: 14,
                        onTap: _openCustomerNavigation,
                      ),
                    )
                  else
                    Expanded(
                      flex: 2,
                      child: GxButton(
                        label: (_currentStatus == 'ACTIVE' || _currentStatus == 'IN_PROGRESS' || _currentStatus == 'WORK_IN_PROGRESS')
                            ? 'Work in Progress · On-Site'
                            : (_currentStatus == 'ARRIVED'
                                ? 'Verify Arrival OTP'
                                : 'Waiting for Arrival...'),
                        icon: (_currentStatus == 'ACTIVE' || _currentStatus == 'IN_PROGRESS' || _currentStatus == 'WORK_IN_PROGRESS')
                            ? Icons.build_circle_rounded
                            : (_currentStatus == 'ARRIVED'
                                ? Icons.verified_user_rounded
                                : Icons.directions_walk_rounded),
                        onTap: (_currentStatus == 'ACTIVE' || _currentStatus == 'IN_PROGRESS' || _currentStatus == 'WORK_IN_PROGRESS')
                            ? () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CompletionOtpScreen(
                                      bookingId: widget.bookingId,
                                      workerName: widget.worker.name,
                                      isWorker: widget.isWorker,
                                    ),
                                  ),
                                );
                              }
                            : (_arrivalOtp != null ? _goToOtpScreen : null),
                        height: 48,
                        radius: 12,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),

              // v126 w3: the WORKER's arrival gate — visible while heading
              // to the customer. Opens the OTP entry (mark arrived → ask the
              // customer for the code → timer starts on verify).
              if (widget.isWorker &&
                  (_currentStatus == 'ACCEPTED' ||
                      _currentStatus == 'ARRIVED')) ...[
                const SizedBox(height: 10),
                GxButton(
                  label: 'I have arrived — enter OTP',
                  icon: Icons.pin_rounded,
                  height: 48,
                  radius: 12,
                  fontSize: 14,
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ArrivalOtpScreen(
                          bookingId: widget.bookingId,
                          workerName: widget.worker.name,
                          arrivalOtp: '', // worker mode: entered, not shown
                          isWorker: true,
                        ),
                      ),
                    );
                  },
                ),
              ],

              // No location warning
              if (_workerLocation == null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      widget.isWorker
                          ? 'Waiting for your GPS…'
                          : 'Waiting for worker\'s location...',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                    ),
                  ],
                ),
              ],
              if (widget.isWorker &&
                  _workerLocation != null &&
                  _customerLocation == null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      'Waiting for customer location…',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Pause / resume + report (v126 Instant Help c12–c14 / w5–w7) ──────────

  Future<void> _pauseAction(Future<void> Function() action) async {
    if (_pauseActionBusy) return;
    setState(() => _pauseActionBusy = true);
    try {
      await action();
      // Refresh the SHARED poll immediately so the UI doesn't wait for the
      // next 5s tick (and every other widget sees the new state too).
      ref.invalidate(bookingStatusProvider(widget.bookingId));
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Action failed: $e', type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _pauseActionBusy = false);
    }
  }

  Widget _pauseSection(ColorScheme cs) {
    final repo = ref.read(bookingRepositoryProvider);

    Widget child;
    if (widget.isWorker) {
      if (_paused) {
        child = GxButton(
          label: 'Resume work — timer continues',
          icon: Icons.play_arrow_rounded,
          height: 44,
          radius: 12,
          fontSize: 13,
          onTap: _pauseActionBusy
              ? null
              : () => _pauseAction(() => repo.resumeWork(widget.bookingId)),
        );
      } else if (_pauseRequested) {
        child = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('Pause requested — waiting for customer',
                style: TextStyle(
                    fontSize: 12.5, color: cs.onSurfaceVariant)),
          ],
        );
      } else {
        child = GxButton(
          label: 'Request pause',
          icon: Icons.pause_rounded,
          filled: false,
          height: 44,
          radius: 12,
          fontSize: 13,
          onTap: _pauseActionBusy
              ? null
              : () => _pauseAction(() => repo.requestPause(widget.bookingId)),
        );
      }
    } else {
      if (_pauseRequested) {
        child = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${widget.worker.name} asked to pause the job timer',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GxButton(
                    label: 'Approve pause',
                    height: 44,
                    radius: 12,
                    fontSize: 13,
                    onTap: _pauseActionBusy
                        ? null
                        : () => _pauseAction(() =>
                            repo.respondPause(widget.bookingId, approve: true)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GxButton(
                    label: 'Decline',
                    filled: false,
                    height: 44,
                    radius: 12,
                    fontSize: 13,
                    onTap: _pauseActionBusy
                        ? null
                        : () => _pauseAction(() => repo
                            .respondPause(widget.bookingId, approve: false)),
                  ),
                ),
              ],
            ),
          ],
        );
      } else if (_paused) {
        child = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.pause_circle_outline_rounded,
                size: 16, color: GixbeeTheme.accentGold),
            const SizedBox(width: 8),
            Text('Timer paused — resumes when work continues',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ],
        );
      } else {
        child = const SizedBox.shrink();
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          const SizedBox(height: 6),
          Center(
            child: TextButton.icon(
              onPressed: () => showReportIssueSheet(context, ref,
                  bookingId: widget.bookingId, isWorker: widget.isWorker),
              icon: Icon(Icons.flag_outlined,
                  size: 14, color: context.gx.ink.withValues(alpha: 0.5)),
              label: Text('Report an issue',
                  style: TextStyle(
                      fontSize: 12,
                      color: context.gx.ink.withValues(alpha: 0.5))),
            ),
          ),
        ],
      ),
    );
  }

  void _goToOtpScreen() {
    if (!mounted || _arrivalOtp == null) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ArrivalOtpScreen(
          bookingId: widget.bookingId,
          workerName: widget.worker.name,
          arrivalOtp: _arrivalOtp!,
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (_currentStatus) {
      case 'ACCEPTED':
        return Colors.blue;
      case 'ARRIVED':
        return Colors.green;
      case 'ACTIVE':
      case 'IN_PROGRESS':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  IconData _getStatusIcon() {
    switch (_currentStatus) {
      case 'ACCEPTED':
        return Icons.directions_car_rounded;
      case 'ARRIVED':
        return Icons.place_rounded;
      case 'ACTIVE':
      case 'IN_PROGRESS':
        return Icons.build_rounded;
      default:
        return Icons.directions_car_rounded;
    }
  }

  String _getStatusText() {
    switch (_currentStatus) {
      case 'ACCEPTED':
        return 'Worker is on the way';
      case 'ARRIVED':
        return 'Worker has arrived';
      case 'ACTIVE':
      case 'IN_PROGRESS':
        if (_paused) return 'Paused — timer stopped';
        if (_pauseRequested) return 'Pause requested';
        return 'Work in progress';
      default:
        return 'Tracking';
    }
  }
}
