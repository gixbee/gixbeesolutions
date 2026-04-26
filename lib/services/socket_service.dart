import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/app_config.dart';

final socketServiceProvider = Provider((ref) => SocketService());

class SocketService {
  io.Socket? _socket;

  // ── Notification stream — booking events pushed from server ──
  final _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get notifications =>
      _notificationController.stream;

  io.Socket? get socket => _socket;
  bool get isConnected => _socket?.connected ?? false;

  void connect(String token) {
    _socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(10000)
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[Socket] Connected');
    });

    _socket!.onDisconnect((_) {
      debugPrint('[Socket] Disconnected');
    });

    _socket!.onConnectError((data) {
      debugPrint('[Socket] Connection error: $data');
    });

    _socket!.onReconnect((_) {
      debugPrint('[Socket] Reconnected');
    });

    // ── Incoming booking events (worker receives) ─────────────
    _socket!.on('new_booking_request', (data) {
      debugPrint('[Socket] new_booking_request received');
      if (!_notificationController.isClosed) {
        _notificationController.add({
          ...Map<String, dynamic>.from(data as Map),
          '_event': 'new_booking_request',
        });
      }
    });

    _socket!.on('booking_accepted', (data) {
      debugPrint('[Socket] booking_accepted received');
      if (!_notificationController.isClosed) {
        _notificationController.add({
          ...Map<String, dynamic>.from(data as Map),
          '_event': 'booking_accepted',
        });
      }
    });

    _socket!.on('booking_cancelled', (data) {
      debugPrint('[Socket] booking_cancelled received');
      if (!_notificationController.isClosed) {
        _notificationController.add({
          ...Map<String, dynamic>.from(data as Map),
          '_event': 'booking_cancelled',
        });
      }
    });

    _socket!.on('booking_status_update', (data) {
      debugPrint('[Socket] booking_status_update received');
      if (!_notificationController.isClosed) {
        _notificationController.add({
          ...Map<String, dynamic>.from(data as Map),
          '_event': 'booking_status_update',
        });
      }
    });
  }

  // ── Outgoing events ──────────────────────────────────────────

  void updateLocation(String userId, double lat, double lng, {String? jobId}) {
    if (isConnected) {
      _socket!.emit('updateLocation', {
        'userId': userId,
        'lat': lat,
        'lng': lng,
        if (jobId != null) 'jobId': jobId,
      });
    }
  }

  void joinJobRoom(String jobId) {
    if (isConnected) {
      _socket?.emit('joinJobRoom', {'jobId': jobId});
    }
  }

  void onLocationUpdated(Function(Map<String, dynamic>) callback) {
    _socket?.on(
      'locationUpdated',
      (data) => callback(data as Map<String, dynamic>),
    );
  }

  void disconnect() {
    _socket?.disconnect();
    if (!_notificationController.isClosed) {
      _notificationController.close();
    }
  }
}
