import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../repositories/auth_repository.dart';
import 'socket_service.dart';

final voiceCallControllerProvider =
    Provider((ref) => VoiceCallController(ref));

enum VoiceCallPhase {
  idle,
  outgoingRinging,
  incomingRinging,
  connecting,
  connected,
  ended,
}

/// Coordinates signaling (Socket.IO) + WebRTC peer connection for booking voice.
class VoiceCallController {
  VoiceCallController(this._ref);

  final Ref _ref;

  final _phaseController = StreamController<VoiceCallPhase>.broadcast();
  Stream<VoiceCallPhase> get phaseChanges => _phaseController.stream;

  VoiceCallPhase phase = VoiceCallPhase.idle;
  String? bookingId;
  String? callId;
  String? peerName;
  String? peerId;
  bool muted = false;
  String? lastError;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final List<RTCIceCandidate> _pendingRemoteIce = [];
  bool _remoteDescriptionSet = false;
  StreamSubscription<Map<String, dynamic>>? _signalSub;
  bool _isCaller = false;

  SocketService get _socket => _ref.read(socketServiceProvider);
  Dio get _dio => _ref.read(dioProvider);

  void _setPhase(VoiceCallPhase next) {
    phase = next;
    if (!_phaseController.isClosed) _phaseController.add(next);
  }

  Future<bool> ensureMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<List<Map<String, dynamic>>> _loadIceServers(String bookingId) async {
    try {
      final res = await _dio.get('/bookings/$bookingId/webrtc-config');
      final raw = res.data['iceServers'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (e) {
      debugPrint('[VoiceCall] ICE config failed: $e');
    }
    return [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ];
  }

  Future<void> startOutgoing({
    required String bookingId,
    required String callerName,
    String? peerDisplayName,
  }) async {
    if (phase != VoiceCallPhase.idle && phase != VoiceCallPhase.ended) {
      throw StateError('Call already in progress');
    }
    lastError = null;
    this.bookingId = bookingId;
    peerName = peerDisplayName ?? 'Gixbee user';
    _isCaller = true;

    if (!await ensureMicPermission()) {
      lastError = 'Microphone permission is required for in-app calls';
      _setPhase(VoiceCallPhase.ended);
      throw StateError(lastError!);
    }

    _bindSignalListeners();
    _setPhase(VoiceCallPhase.outgoingRinging);

    final ack = await _socket.emitVoiceCallInvite(
      bookingId: bookingId,
      callerName: callerName,
    );
    if (ack != null) {
      callId = ack['callId']?.toString();
      peerId = ack['calleeId']?.toString();
    }
  }

  /// Callee: show ringing UI (invite already received).
  Future<void> presentIncoming(Map<String, dynamic> invite) async {
    if (phase != VoiceCallPhase.idle && phase != VoiceCallPhase.ended) {
      // Busy — reject politely.
      final bid = invite['bookingId']?.toString();
      if (bid != null) {
        _socket.emitVoiceCallReject(
          bookingId: bid,
          callId: invite['callId']?.toString(),
        );
      }
      return;
    }
    bookingId = invite['bookingId']?.toString();
    callId = invite['callId']?.toString();
    peerId = invite['callerId']?.toString();
    peerName = invite['callerName']?.toString() ?? 'Incoming call';
    _isCaller = false;
    _bindSignalListeners();
    _setPhase(VoiceCallPhase.incomingRinging);
  }

  Future<void> acceptIncoming() async {
    if (bookingId == null) return;
    if (!await ensureMicPermission()) {
      lastError = 'Microphone permission is required';
      await rejectIncoming();
      return;
    }
    _setPhase(VoiceCallPhase.connecting);
    await _socket.emitVoiceCallAccept(
      bookingId: bookingId!,
      callId: callId,
    );
    await _ensurePeerConnection();
  }

  Future<void> rejectIncoming() async {
    if (bookingId != null) {
      _socket.emitVoiceCallReject(bookingId: bookingId!, callId: callId);
    }
    await _teardown(endedByUs: true);
  }

  Future<void> hangup() async {
    if (bookingId != null) {
      _socket.emitVoiceCallHangup(bookingId: bookingId!, callId: callId);
    }
    await _teardown(endedByUs: true);
  }

  Future<void> toggleMute() async {
    muted = !muted;
    final tracks = _localStream?.getAudioTracks() ?? [];
    for (final t in tracks) {
      t.enabled = !muted;
    }
    if (!_phaseController.isClosed) _phaseController.add(phase);
  }

  void _bindSignalListeners() {
    _signalSub?.cancel();
    _signalSub = _socket.voiceCalls.listen(_onVoiceEvent);
  }

  Future<void> _onVoiceEvent(Map<String, dynamic> data) async {
    final event = data['_event']?.toString();
    final bid = data['bookingId']?.toString();
    if (bookingId != null && bid != null && bid != bookingId) return;

    switch (event) {
      case 'voice_call_invite':
        // Handled by UI / main_wrapper via presentIncoming.
        break;
      case 'voice_call_accept':
        if (!_isCaller) break;
        callId ??= data['callId']?.toString();
        _setPhase(VoiceCallPhase.connecting);
        await _ensurePeerConnection();
        await _createAndSendOffer();
        break;
      case 'voice_call_reject':
      case 'voice_call_hangup':
        lastError = event == 'voice_call_reject' ? 'Call declined' : 'Call ended';
        await _teardown(endedByUs: false);
        break;
      case 'voice_call_signal':
        await _handleRemoteSignal(data['signal']);
        break;
    }
  }

  Future<void> _ensurePeerConnection() async {
    if (_pc != null) return;
    final bid = bookingId!;
    final iceServers = await _loadIceServers(bid);

    _pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });

    _pc!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      _socket.emitVoiceCallSignal(
        bookingId: bid,
        callId: callId,
        signal: {
          'type': 'candidate',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      );
    };

    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('[VoiceCall] connectionState=$state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setPhase(VoiceCallPhase.connected);
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (phase == VoiceCallPhase.connected ||
            phase == VoiceCallPhase.connecting) {
          lastError = 'Connection lost';
          unawaited(_teardown(endedByUs: false));
        }
      }
    };

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
  }

  Future<void> _createAndSendOffer() async {
    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
    });
    await _pc!.setLocalDescription(offer);
    _socket.emitVoiceCallSignal(
      bookingId: bookingId!,
      callId: callId,
      signal: {
        'type': 'offer',
        'sdp': offer.sdp,
      },
    );
  }

  Future<void> _handleRemoteSignal(dynamic raw) async {
    if (raw is! Map) return;
    final signal = Map<String, dynamic>.from(raw);
    final type = signal['type']?.toString();
    await _ensurePeerConnection();

    if (type == 'offer') {
      await _pc!.setRemoteDescription(
        RTCSessionDescription(signal['sdp']?.toString(), 'offer'),
      );
      _remoteDescriptionSet = true;
      await _flushPendingIce();
      final answer = await _pc!.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await _pc!.setLocalDescription(answer);
      _socket.emitVoiceCallSignal(
        bookingId: bookingId!,
        callId: callId,
        signal: {
          'type': 'answer',
          'sdp': answer.sdp,
        },
      );
      _setPhase(VoiceCallPhase.connecting);
    } else if (type == 'answer') {
      await _pc!.setRemoteDescription(
        RTCSessionDescription(signal['sdp']?.toString(), 'answer'),
      );
      _remoteDescriptionSet = true;
      await _flushPendingIce();
    } else if (type == 'candidate') {
      final cand = RTCIceCandidate(
        signal['candidate']?.toString(),
        signal['sdpMid']?.toString(),
        signal['sdpMLineIndex'] is int
            ? signal['sdpMLineIndex'] as int
            : int.tryParse('${signal['sdpMLineIndex'] ?? ''}'),
      );
      if (!_remoteDescriptionSet) {
        _pendingRemoteIce.add(cand);
      } else {
        try {
          await _pc!.addCandidate(cand);
        } catch (e) {
          debugPrint('[VoiceCall] addCandidate failed: $e');
        }
      }
    }
  }

  Future<void> _flushPendingIce() async {
    for (final c in _pendingRemoteIce) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    }
    _pendingRemoteIce.clear();
  }

  Future<void> _teardown({required bool endedByUs}) async {
    _signalSub?.cancel();
    _signalSub = null;
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    _pendingRemoteIce.clear();
    _remoteDescriptionSet = false;
    muted = false;
    _isCaller = false;
    bookingId = null;
    callId = null;
    peerId = null;
    _setPhase(VoiceCallPhase.ended);
    // Reset to idle shortly so another call can start.
    Future.delayed(const Duration(milliseconds: 400), () {
      if (phase == VoiceCallPhase.ended) _setPhase(VoiceCallPhase.idle);
      peerName = null;
    });
  }

  void dispose() {
    unawaited(_teardown(endedByUs: true));
    _phaseController.close();
  }
}
