import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_config.dart';
import '../../theme.dart';
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
import 'cancel_booking_screen.dart';
import 'report_issue_sheet.dart';
import 'live_tracking_bottom_panel.dart';
import 'live_tracking_route_service.dart';
import 'voice_call_screen.dart';

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
  final String? customerName;

  const LiveTrackingMapScreen({
    super.key,
    required this.bookingId,
    required this.worker,
    this.serviceAddress,
    this.customerLat,
    this.customerLng,
    this.arrivalOtp,
    this.isWorker = false,
    this.customerName,
  });

  @override
  ConsumerState<LiveTrackingMapScreen> createState() =>
      _LiveTrackingMapScreenState();
}

class _LiveTrackingMapScreenState extends ConsumerState<LiveTrackingMapScreen> {
  // Ola Maps (MapLibre-spec vector tiles) rendered via maplibre_gl.
  // AUDIT FIX: no private _pollTimer any more — status comes from the shared
  // bookingStatusProvider (single poll per booking, app-wide).
  // NOTE: maplibre_gl 0.21+ renamed the public classes (Maplibre* → MapLibre*).
  // pubspec resolves 0.26.x, so these are MapLibreMap / MapLibreMapController.
  MapLibreMapController? _mapController;
  bool _currentStatusNavigatingAway = false;
  bool _styleReady = false;
  Circle? _workerCircle;
  Circle? _customerCircle;
  Line? _routeLine;
  bool _syncingAnnotations = false;
  bool _annotationSyncQueued = false;
  LatLng? _workerLocation;
  LatLng? _customerLocation;
  String _currentStatus = 'ACCEPTED';
  bool _workerNoProgress = false;
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

  /// Don't mount MapLibre until we have real coords (avoids Nagpur default).
  bool _coordsReady = false;

  // Job timer: starts when the arrival OTP flips the booking ACTIVE
  // (startedAt) and ticks every second for the full elapsed wall time.
  DateTime? _startedAt;
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
  final LiveTrackingRouteService _routeService = LiveTrackingRouteService();

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
      final lat =
          readCoord(booking?['serviceLat']) ?? readCoord(widget.customerLat);
      final lng =
          readCoord(booking?['serviceLng']) ?? readCoord(widget.customerLng);
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
      final pos = await ref.read(locationServiceProvider).getCurrentPosition();
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
              final p =
                  await ref.read(locationServiceProvider).getCurrentPosition();
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

  /// Serialised entry point. Callers fire this from GPS, socket, poll and
  /// style-loaded paths, and the body awaits before storing its annotation
  /// handles — two concurrent runs would both add a line and leak one of them
  /// (a stale straight fallback that never gets updated again).
  Future<void> _syncMapAnnotations() async {
    if (_syncingAnnotations) {
      _annotationSyncQueued = true;
      return;
    }
    _syncingAnnotations = true;
    try {
      do {
        _annotationSyncQueued = false;
        await _applyMapAnnotations();
      } while (_annotationSyncQueued && mounted);
    } finally {
      _syncingAnnotations = false;
    }
  }

  /// Keep the worker/customer dots and the route line in sync with state.
  /// MapLibre annotations are imperative (add/update handles), unlike the
  /// declarative google_maps_flutter marker sets this replaced.
  Future<void> _applyMapAnnotations() async {
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
        if (!mounted || _startedAt == null) return;
        final worked = DateTime.now().difference(_startedAt!);
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

  Future<void> _dialCounterpart() async {
    final me = ref.read(currentUserProvider).value;
    final callerName = (me?.name?.trim().isNotEmpty == true)
        ? me!.name!.trim()
        : 'Gixbee user';
    final peerName = widget.isWorker
        ? 'Customer'
        : (widget.worker.name.trim().isNotEmpty
            ? widget.worker.name.trim()
            : 'Gixbee user');
    await VoiceCallScreen.startOutgoing(
      context,
      bookingId: widget.bookingId,
      callerName: callerName,
      peerName: peerName,
    );
  }

  void _applyStatusData(Map<String, dynamic> statusData) {
    if (!mounted) return;
    final newStatus = statusData['status']?.toString().toUpperCase() ?? '';
    final otp = statusData['arrivalOtp']?.toString();
    final noProgress = statusData['workerNoProgress'] == true;

    if (noProgress && !_workerNoProgress && !widget.isWorker) {
      setState(() => _workerNoProgress = true);
    }

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

    // Arrival OTP verified → job ACTIVE → navigate to CompletionOtpScreen.
    //
    // GUARD: _currentStatusNavigatingAway prevents stacked navigations when
    // this is called from both the socket subscription AND the ref.listen
    // poll in the same frame. Both paths are intentional (belt + suspenders)
    // but only one should push the route.
    if (newStatus == 'ACTIVE' ||
        newStatus == 'IN_PROGRESS' ||
        newStatus == 'WORK_IN_PROGRESS') {
      // Update the status label immediately so the UI shows "Work in progress"
      // even if navigation takes a beat (e.g. addPostFrameCallback fires on
      // the following frame).
      if (newStatus != _currentStatus) {
        setState(() => _currentStatus = newStatus);
      }
      if (_currentStatusNavigatingAway) return;
      _currentStatusNavigatingAway = true;
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
    if (_lastRouteFetch != null &&
        DateTime.now().difference(_lastRouteFetch!).inSeconds < 30) {
      return;
    }

    _lastRouteFetch = DateTime.now();
    final result = await _routeService.fetchRoute(
      origin: _workerLocation!,
      destination: _customerLocation!,
    );
    if (!mounted || result == null) return;
    setState(() {
      if (result.points.isNotEmpty) _routePoints = result.points;
      _routeDistanceText = result.distanceText;
      _routeEtaText = result.etaText;
    });
    _syncMapAnnotations();
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

    final gx = context.gx;
    final shadow = gx.ink.withValues(alpha: 0.12);

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
                        color: gx.card,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: shadow,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: IconButton(
                        tooltip: 'Go back',
                        icon: Icon(Icons.arrow_back, color: gx.ink),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const Spacer(),
                    // Re-center button
                    Container(
                      decoration: BoxDecoration(
                        color: gx.card,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: shadow,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: IconButton(
                        tooltip: 'Re-center map',
                        icon: Icon(Icons.my_location, color: gx.ink),
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
              child: _buildExtractedBottomPanel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtractedBottomPanel() {
    final fallbackDistance =
        _workerLocation != null && _customerLocation != null
            ? LiveTrackingRouteService.estimateDistanceKm(
                _workerLocation!,
                _customerLocation!,
              )
            : null;
    final fallbackEta =
        fallbackDistance != null ? (fallbackDistance / 30 * 60).round() : null;
    final displayEta = _routeEtaText ??
        (fallbackEta != null
            ? '${fallbackEta < 1 ? "<1" : fallbackEta} min'
            : null);
    final displayDistance = _routeDistanceText ??
        (fallbackDistance != null
            ? '${fallbackDistance.toStringAsFixed(1)} km'
            : null);

    return LiveTrackingBottomPanel(
      bookingId: widget.bookingId,
      worker: widget.worker,
      status: _currentStatus,
      isWorker: widget.isWorker,
      workerNoProgress: _workerNoProgress,
      hasWorkerLocation: _workerLocation != null,
      hasCustomerLocation: _customerLocation != null,
      elapsedLabel: _elapsedLabel,
      showTimer:
          (_currentStatus == 'ACTIVE' || _currentStatus == 'IN_PROGRESS') &&
              _startedAt != null,
      etaText: displayEta,
      distanceText: displayDistance,
      onCall: _dialCounterpart,
      onPrimaryAction: widget.isWorker
          ? _openCustomerNavigation
          : (_currentStatus == 'ACTIVE' ||
                  _currentStatus == 'IN_PROGRESS' ||
                  _currentStatus == 'WORK_IN_PROGRESS')
              ? _goToCompletionScreen
              : (_arrivalOtp != null ? _goToOtpScreen : null),
      onWorkerArrived: _goToWorkerArrivalScreen,
      onCancelFree: _cancelFree,
      customerName: widget.customerName,
      onReportIssue: () => showReportIssueSheet(
        context,
        ref,
        bookingId: widget.bookingId,
        isWorker: widget.isWorker,
      ),
    );
  }

  Future<void> _cancelFree() async {
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CancelBookingScreen(bookingId: widget.bookingId),
      ),
    );
    if (done == true && mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _goToCompletionScreen() {
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

  void _goToWorkerArrivalScreen() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ArrivalOtpScreen(
          bookingId: widget.bookingId,
          workerName: widget.worker.name,
          arrivalOtp: '',
          isWorker: true,
        ),
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
}
