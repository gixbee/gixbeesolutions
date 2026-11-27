import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/auth_repository.dart';
import '../../repositories/worker_repository.dart';
import '../../services/location_service.dart';
import '../../services/socket_service.dart';

/// Keeps Redis GPS + socket live presence in sync when the worker is online
/// from the bottom-nav control or the Go Live screen.
final workerLivePresenceProvider = Provider<WorkerLivePresence>((ref) {
  final presence = WorkerLivePresence(ref);
  ref.onDispose(presence.dispose);
  return presence;
});

class WorkerLivePresence {
  WorkerLivePresence(this._ref);

  final Ref _ref;
  Timer? _locationHeartbeat;
  bool _started = false;

  bool get isStarted => _started;

  Future<void> start() async {
    if (_started) return;
    final user = await _ref.read(currentUserProvider.future);
    if (user == null) return;
    _started = true;

    final socket = _ref.read(socketServiceProvider);
    socket.joinUserRoom(user.id);
    socket.startLivePresenceStream(user.id);

    _locationHeartbeat?.cancel();
    Future<void> pushLoc() async {
      try {
        final pos = await _ref
            .read(locationServiceProvider)
            .getCurrentPosition();
        if (pos == null) return;
        await _ref.read(workerRepositoryProvider).updateMyLocation(
              lat: pos.latitude,
              lng: pos.longitude,
            );
      } catch (_) {}
    }

    unawaited(pushLoc());
    _locationHeartbeat = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(pushLoc()),
    );
  }

  void stop() {
    _started = false;
    _locationHeartbeat?.cancel();
    _locationHeartbeat = null;
    _ref.read(socketServiceProvider).stopLocationStream();
  }

  void dispose() {
    stop();
  }
}
