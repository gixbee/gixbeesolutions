import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/location_bootstrap.dart';
import '../../services/location_service.dart';
import '../../theme.dart';
import 'dribbble_background.dart';
import 'gx_empty.dart';

/// Copy for the blocking location gate. Kept as functions so widget tests
/// can assert titles without mounting Geolocator.
String locationRequiredTitle(String reason) {
  switch (reason) {
    case 'service_off':
      return 'Turn on location';
    case 'denied_forever':
      return 'Allow location access';
    default:
      return 'Allow location access';
  }
}

String locationRequiredMessage(String reason) {
  switch (reason) {
    case 'service_off':
      return 'Gixbee needs device location to show nearby services and jobs. Turn location on to continue.';
    case 'denied_forever':
      return 'Location is off for Gixbee. Open Settings, allow location, then return to the app.';
    default:
      return 'Gixbee needs location permission to show nearby services and jobs.';
  }
}

String locationRequiredAction(String reason) {
  switch (reason) {
    case 'service_off':
      return 'Turn on location';
    case 'denied_forever':
      return 'Open settings';
    default:
      return 'Allow location';
  }
}

/// Full-screen blocking panel — not dismissible.
class LocationRequiredPanel extends StatelessWidget {
  final String reason;
  final VoidCallback? onEnable;

  const LocationRequiredPanel({
    super.key,
    required this.reason,
    required this.onEnable,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: context.gx.bg,
        body: DribbbleBackground(
          child: SafeArea(
            child: GxEmptyState(
              icon: Icons.location_off_rounded,
              title: locationRequiredTitle(reason),
              message: locationRequiredMessage(reason),
              actionLabel: locationRequiredAction(reason),
              onAction: onEnable,
            ),
          ),
        ),
      ),
    );
  }
}

/// Sits above the whole app (MaterialApp.builder). If device location or
/// the app permission is off, the rest of Gixbee cannot be used until it
/// is turned back on.
class LocationRequiredHost extends ConsumerStatefulWidget {
  final Widget child;

  const LocationRequiredHost({super.key, required this.child});

  @override
  ConsumerState<LocationRequiredHost> createState() =>
      _LocationRequiredHostState();
}

class _LocationRequiredHostState extends ConsumerState<LocationRequiredHost>
    with WidgetsBindingObserver {
  String? _reason;
  bool _busy = false;
  bool _askedOnce = false;
  StreamSubscription<dynamic>? _serviceSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_evaluate(requestIfDenied: true));
    if (!kIsWeb) {
      _serviceSub = ref
          .read(locationServiceProvider)
          .serviceStatusStream()
          .listen((_) => unawaited(_evaluate()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serviceSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_evaluate());
    }
  }

  Future<void> _evaluate({bool requestIfDenied = false}) async {
    if (kIsWeb) {
      if (mounted && _reason != null) setState(() => _reason = null);
      return;
    }
    final svc = ref.read(locationServiceProvider);
    var reason = await svc.gpsBlockReason();
    if (requestIfDenied && reason == 'denied' && !_askedOnce) {
      _askedOnce = true;
      await svc.getCurrentPosition();
      reason = await svc.gpsBlockReason();
    }
    if (!mounted) return;
    final wasBlocked = _reason != null;
    if (_reason != reason) {
      setState(() => _reason = reason);
    }
    if (wasBlocked && reason == null) {
      unawaited(refreshLiveLocationFromGps(ref));
    }
  }

  Future<void> _onEnable() async {
    if (_busy) return;
    final svc = ref.read(locationServiceProvider);
    setState(() => _busy = true);
    try {
      switch (_reason) {
        case 'service_off':
          await svc.openLocationSettings();
          break;
        case 'denied_forever':
          await svc.openAppSettings();
          break;
        case 'denied':
          await svc.getCurrentPosition();
          final still = await svc.gpsBlockReason();
          if (still == 'denied' || still == 'denied_forever') {
            await svc.openAppSettings();
          }
          break;
        default:
          await svc.getCurrentPosition();
      }
      await _evaluate();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (reason != null)
          Positioned.fill(
            child: LocationRequiredPanel(
              reason: reason,
              onEnable: _onEnable,
            ),
          ),
      ],
    );
  }
}
