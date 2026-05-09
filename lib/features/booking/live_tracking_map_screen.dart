import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/socket_service.dart';
import '../../shared/models/worker.dart';
import '../../repositories/booking_repository.dart';
import 'arrival_otp_screen.dart';

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

  const LiveTrackingMapScreen({
    super.key,
    required this.bookingId,
    required this.worker,
    this.serviceAddress,
    this.customerLat,
    this.customerLng,
    this.arrivalOtp,
  });

  @override
  ConsumerState<LiveTrackingMapScreen> createState() => _LiveTrackingMapScreenState();
}

class _LiveTrackingMapScreenState extends ConsumerState<LiveTrackingMapScreen> {
  GoogleMapController? _mapController;
  LatLng? _workerLocation;
  LatLng? _customerLocation;
  Timer? _pollTimer;
  String _currentStatus = 'ACCEPTED';
  String? _arrivalOtp;
  bool _isMapReady = false;

  // Default: center of India (Nagpur)
  static const LatLng _defaultCenter = LatLng(21.1458, 79.0882);

  @override
  void initState() {
    super.initState();
    _arrivalOtp = widget.arrivalOtp;

    // Set customer location if provided
    if (widget.customerLat != null && widget.customerLng != null) {
      _customerLocation = LatLng(widget.customerLat!, widget.customerLng!);
    }

    // Join the Socket.IO room for this booking
    final socketService = ref.read(socketServiceProvider);
    socketService.joinJobRoom(widget.bookingId);

    // Listen for real-time location updates
    socketService.onLocationUpdated((data) {
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat != null && lng != null && mounted) {
        setState(() {
          _workerLocation = LatLng(lat, lng);
        });
        _fitMapBounds();
      }
    });

    // Start polling for status changes (ACCEPTED → ARRIVED → ACTIVE)
    _startStatusPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _startStatusPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      try {
        final statusData = await ref
            .read(bookingRepositoryProvider)
            .pollBookingStatus(widget.bookingId);
        final newStatus = statusData['status']?.toString().toUpperCase() ?? '';
        final otp = statusData['arrivalOtp']?.toString();

        if (mounted && newStatus != _currentStatus) {
          setState(() {
            _currentStatus = newStatus;
            if (otp != null && otp.isNotEmpty) _arrivalOtp = otp;
          });

          // If completed or cancelled, go back
          if (['COMPLETED', 'CANCELLED', 'REJECTED'].contains(newStatus)) {
            _pollTimer?.cancel();
            if (mounted) Navigator.pop(context);
          }
        }
      } catch (_) {}
    });
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
        CameraUpdate.newLatLngBounds(bounds, 80),
      );
    } else if (points.length == 1) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 15),
      );
    }
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    // Worker marker (moving)
    if (_workerLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('worker'),
        position: _workerLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(
          title: widget.worker.name,
          snippet: 'On the way',
        ),
      ));
    }

    // Customer marker (static)
    if (_customerLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('customer'),
        position: _customerLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Your Location',
          snippet: widget.serviceAddress ?? '',
        ),
      ));
    }

    return markers;
  }

  Set<Polyline> _buildPolylines() {
    if (_workerLocation == null || _customerLocation == null) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: [_workerLocation!, _customerLocation!],
        color: Colors.blueAccent,
        width: 4,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ),
    };
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final center = _workerLocation ?? _customerLocation ?? _defaultCenter;

    return Scaffold(
      body: Stack(
        children: [
          // ── Google Map ──
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: center,
              zoom: 14,
            ),
            markers: _buildMarkers(),
            polylines: _buildPolylines(),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
              setState(() => _isMapReady = true);
              // Fit bounds once map is ready
              Future.delayed(const Duration(milliseconds: 500), _fitMapBounds);
            },
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
    );
  }

  Widget _buildBottomPanel(ColorScheme cs) {
    final distance = _estimateDistance();
    final eta = distance != null ? (distance / 30 * 60).round() : null; // ~30 km/h avg

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
                    Text(
                      _getStatusText(),
                      style: TextStyle(
                        color: _getStatusColor(),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
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
                  if (eta != null && _workerLocation != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${eta < 1 ? "<1" : eta} min',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: cs.primary,
                            ),
                          ),
                          Text(
                            '${distance!.toStringAsFixed(1)} km',
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

              // Action buttons
              Row(
                children: [
                  // Call button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final url = Uri.parse('tel:+91${widget.worker.id}');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url);
                        }
                      },
                      icon: const Icon(Icons.call, size: 18),
                      label: const Text('Call'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // OTP / Arrived button
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _arrivalOtp != null ? _goToOtpScreen : null,
                      icon: Icon(
                        _currentStatus == 'ARRIVED'
                            ? Icons.verified_user_rounded
                            : Icons.directions_walk_rounded,
                        size: 18,
                      ),
                      label: Text(
                        _currentStatus == 'ARRIVED'
                            ? 'Verify Arrival OTP'
                            : 'Waiting for Arrival...',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // No location warning
              if (_workerLocation == null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      'Waiting for worker\'s location...',
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

  void _goToOtpScreen() {
    if (_arrivalOtp == null) return;
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
        return 'Work in progress';
      default:
        return 'Tracking';
    }
  }
}
