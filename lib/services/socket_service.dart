import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../core/config/app_config.dart';

final socketServiceProvider = Provider((ref) => SocketService());

class SocketService {
  io.Socket? _socket;
  StreamSubscription<Position>? _locationStreamSub;
  DateTime? _lastPresenceEmit;

  // ── Notification stream — booking events pushed from server ──
  final _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get notifications =>
      _notificationController.stream;

  // ── Connection stream — true on connect/reconnect, false on disconnect ──
  final _connectionController = StreamController<bool>.broadcast();

  /// Emits whenever the socket connects (`true`) or drops (`false`).
  /// Used by booking status polling to slow/fast the HTTP fallback.
  Stream<bool> get connectionChanges => _connectionController.stream;

  // ── Chat stream — `new_message` events pushed to the user's room ──
  final _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// User id used to (re)join the personal chat room after every connect.
  String? _userId;

  /// Active Instant Help / booking room — re-joined on every (re)connect so
  /// the customer keeps receiving `locationUpdated` after a socket blip.
  String? _activeJobId;

  /// Customer tracking-screen callback for live worker GPS.
  void Function(Map<String, dynamic>)? _locationUpdatedCallback;

  io.Socket? get socket => _socket;
  bool get isConnected => _socket?.connected ?? false;

  /// Join the personal room `user_<id>` so the server can push chat messages.
  /// Safe to call before connect — the id is cached and re-sent on (re)connect.
  void joinUserRoom(String userId) {
    _userId = userId;
    if (isConnected) {
      _socket!.emit('joinUserRoom', {'userId': userId});
    }
  }

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
      if (!_connectionController.isClosed) {
        _connectionController.add(true);
      }
      // Re-join personal + job rooms after every (re)connect.
      if (_userId != null) {
        _socket!.emit('joinUserRoom', {'userId': _userId});
      }
      if (_activeJobId != null) {
        _socket!.emit('joinJobRoom', {'jobId': _activeJobId});
        debugPrint('[Socket] Re-joined job room $_activeJobId');
      }
      _bindLocationUpdatedListener();
    });

    // ── Incoming chat messages (recipient receives) ───────────
    _socket!.on('new_message', (data) {
      debugPrint('[Socket] new_message received');
      if (!_messageController.isClosed) {
        _messageController.add(Map<String, dynamic>.from(data as Map));
      }
    });

    _socket!.onDisconnect((_) {
      debugPrint('[Socket] Disconnected');
      if (!_connectionController.isClosed) {
        _connectionController.add(false);
      }
    });

    _socket!.onConnectError((data) {
      debugPrint('[Socket] Connection error: $data');
    });

    _socket!.onReconnect((_) {
      debugPrint('[Socket] Reconnected');
      if (!_connectionController.isClosed) {
        _connectionController.add(true);
      }
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

    // Broadcast Instant Help: nobody accepted the first 90s wave, so the
    // backend widened the search and (maybe) notified more pros. The waiting
    // screen uses this to EXTEND its countdown instead of showing "no
    // workers" while the second wave is still running.
    _socket!.on('booking_search_expanded', (data) {
      debugPrint('[Socket] booking_search_expanded received');
      if (!_notificationController.isClosed) {
        _notificationController.add({
          ...Map<String, dynamic>.from(data as Map),
          '_event': 'booking_search_expanded',
        });
      }
    });

    _bindLocationUpdatedListener();
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

  /// Join `job_<id>` so this client receives worker `locationUpdated` events.
  /// Safe before connect — job id is cached and emitted on (re)connect.
  void joinJobRoom(String jobId) {
    _activeJobId = jobId;
    if (isConnected) {
      _socket!.emit('joinJobRoom', {'jobId': jobId});
    } else {
      debugPrint('[Socket] joinJobRoom queued until connect: $jobId');
    }
  }

  /// Leave the active job room (call from tracking screen dispose).
  void leaveJobRoom([String? jobId]) {
    final id = jobId ?? _activeJobId;
    if (id == null) return;
    if (isConnected) {
      _socket!.emit('leaveJobRoom', {'jobId': id});
    }
    if (_activeJobId == id) _activeJobId = null;
  }

  void onLocationUpdated(Function(Map<String, dynamic>) callback) {
    // AUDIT FIX: remove any previous handler first — screens registered a new
    // callback on every initState with no matching off(), so reopening the
    // tracking screen stacked duplicate listeners (each firing setState).
    _locationUpdatedCallback = callback;
    _bindLocationUpdatedListener();
  }

  void _bindLocationUpdatedListener() {
    _socket?.off('locationUpdated');
    final cb = _locationUpdatedCallback;
    if (cb == null || _socket == null) return;
    _socket!.on('locationUpdated', (data) {
      if (data is Map) {
        cb(Map<String, dynamic>.from(data));
      }
    });
  }

  /// Unsubscribe from location updates — call from the tracking screen's
  /// dispose so a dead State's setState is never invoked.
  void offLocationUpdated() {
    _locationUpdatedCallback = null;
    _socket?.off('locationUpdated');
  }

  // ── Worker-side: stream GPS to the job room ─────────────────

  /// Starts streaming the worker's GPS while Go Live is on (no job room).
  /// Instant Help matching requires Redis location — without this, live
  /// workers are never notified.
  ///
  /// BATTERY-SAVER profile: while merely live (nobody is watching a map),
  /// medium accuracy keeps the GPS chip mostly off — network/cell fixes are
  /// plenty for dispatch matching — and a 100 m movement gate plus a 30 s
  /// time gate cap the emit rate. The tight high-accuracy stream in
  /// [startLocationStream] runs only during an ACTIVE job, when a customer
  /// is actually tracking the pin. A pro live for an 8-hour shift should
  /// end the day with a working phone.
  void startLivePresenceStream(String userId) {
    stopLocationStream();
    debugPrint('[Socket] Starting live presence stream (battery-saver)');
    _lastPresenceEmit = null;
    _locationStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 100,
      ),
    ).listen(
      (position) {
        final now = DateTime.now();
        if (_lastPresenceEmit != null &&
            now.difference(_lastPresenceEmit!).inSeconds < 30) {
          return; // time gate: at most one presence emit per 30 s
        }
        _lastPresenceEmit = now;
        updateLocation(userId, position.latitude, position.longitude);
      },
      onError: (e) {
        debugPrint('[Socket] Live presence stream error: $e');
      },
    );
  }

  /// Starts streaming the worker's GPS location to the booking's Socket.IO room.
  /// Call after accepting a booking. Emits `updateLocation` every ~5 seconds.
  void startLocationStream(String userId, String jobId) {
    stopLocationStream(); // Cancel any existing stream
    // Ensure the worker is also in the job room (harmless if already joined).
    joinJobRoom(jobId);

    debugPrint('[Socket] Starting location stream for job $jobId');

    _locationStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Only emit if moved 10+ meters
      ),
    ).listen(
      (position) {
        updateLocation(userId, position.latitude, position.longitude, jobId: jobId);
        debugPrint('[Socket] Location update sent: ${position.latitude}, ${position.longitude}');
      },
      onError: (e) {
        debugPrint('[Socket] Location stream error: $e');
      },
    );
  }

  /// Stops the worker's GPS streaming.
  void stopLocationStream() {
    _locationStreamSub?.cancel();
    _locationStreamSub = null;
    debugPrint('[Socket] Location stream stopped');
  }

  void disconnect() {
    stopLocationStream();
    _activeJobId = null;
    _locationUpdatedCallback = null;
    _socket?.disconnect();
    if (!_connectionController.isClosed) {
      _connectionController.close();
    }
    if (!_notificationController.isClosed) {
      _notificationController.close();
    }
    if (!_messageController.isClosed) {
      _messageController.close();
    }
  }
}
