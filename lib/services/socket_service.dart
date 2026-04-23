import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/app_config.dart';

final socketServiceProvider = Provider((ref) => SocketService());

class SocketService {
  io.Socket? _socket;
  
  io.Socket? get socket => _socket;

  void connect(String token) {
    _socket = io.io(AppConfig.socketUrl, io.OptionBuilder()
      .setTransports(['websocket'])
      .setAuth({'token': token})
      .enableAutoConnect()
      .build());

    _socket!.onConnect((_) {
      debugPrint('Connected to WebSocket server');
    });

    _socket!.onDisconnect((_) {
      debugPrint('Disconnected from WebSocket server');
    });

    _socket!.onConnectError((data) {
      debugPrint('Connection Error: $data');
    });
  }

  void updateLocation(String userId, double lat, double lng, {String? jobId}) {
    if (_socket?.connected ?? false) {
      _socket!.emit('updateLocation', {
        'userId': userId,
        'lat': lat,
        'lng': lng,
        if (jobId != null) 'jobId': jobId,
      });
    }
  }

  void joinJobRoom(String jobId) {
    _socket?.emit('joinJobRoom', {'jobId': jobId});
  }

  void onLocationUpdated(Function(Map<String, dynamic>) callback) {
    _socket?.on('locationUpdated', (data) => callback(data as Map<String, dynamic>));
  }

  void disconnect() {
    _socket?.disconnect();
  }
}
