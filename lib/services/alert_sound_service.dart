import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'notification_service.dart';

final alertSoundServiceProvider = Provider((ref) {
  final svc = AlertSoundService(ref);
  ref.onDispose(svc.dispose);
  return svc;
});

/// Swiggy-style in-app sounds:
/// - [startIncomingJobAlert] loops while the worker accept card is open
/// - [playJobAccepted] one-shot when the customer’s request is accepted
///
/// Honours Settings → Notification sound. FCM/local banners still use the
/// platform channel chime; this covers socket-driven UI when no tray banner
/// would play (or when the card is already on screen).
class AlertSoundService {
  AlertSoundService(this._ref) {
    unawaited(_configureAudioContext());
  }

  final Ref _ref;
  final AudioPlayer _loopPlayer = AudioPlayer();
  final AudioPlayer _oneshotPlayer = AudioPlayer();
  bool _looping = false;
  bool _contextReady = false;

  bool get _soundOn {
    try {
      return _ref.read(notificationServiceProvider).soundEnabled;
    } catch (_) {
      return true;
    }
  }

  Future<void> _configureAudioContext() async {
    if (_contextReady) return;
    try {
      // Notification/ringtone usage so the chime is audible like a
      // delivery-partner alert (not ducked as media).
      final ctx = AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notificationRingtone,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
      );
      await AudioPlayer.global.setAudioContext(ctx);
      await _loopPlayer.setAudioContext(ctx);
      await _oneshotPlayer.setAudioContext(ctx);
      _contextReady = true;
    } catch (e) {
      debugPrint('[AlertSound] audio context setup failed: $e');
    }
  }

  /// Ring until [stopIncomingJobAlert] — Swiggy delivery-partner style.
  Future<void> startIncomingJobAlert() async {
    if (!_soundOn) return;
    if (_looping) return;
    _looping = true;
    await _configureAudioContext();
    try {
      await _loopPlayer.setReleaseMode(ReleaseMode.loop);
      await _loopPlayer.setVolume(1.0);
      await _loopPlayer.play(AssetSource('sounds/booking_alert.wav'));
    } catch (e) {
      debugPrint('[AlertSound] incoming loop failed: $e');
      try {
        await _loopPlayer.play(AssetSource('sounds/gixbee_alert.wav'));
      } catch (e2) {
        debugPrint('[AlertSound] incoming fallback failed: $e2');
        _looping = false;
      }
    }
  }

  Future<void> stopIncomingJobAlert() async {
    _looping = false;
    try {
      await _loopPlayer.stop();
    } catch (_) {}
  }

  /// Customer: “pro accepted your request” confirmation chime.
  Future<void> playJobAccepted() async {
    if (!_soundOn) return;
    await _configureAudioContext();
    try {
      await _oneshotPlayer.stop();
      await _oneshotPlayer.setReleaseMode(ReleaseMode.release);
      await _oneshotPlayer.setVolume(1.0);
      await _oneshotPlayer.play(AssetSource('sounds/job_accepted.wav'));
    } catch (e) {
      debugPrint('[AlertSound] accepted chime failed: $e');
      try {
        await _oneshotPlayer.play(AssetSource('sounds/gixbee_alert.wav'));
      } catch (_) {}
    }
  }

  void dispose() {
    unawaitedStop();
    _loopPlayer.dispose();
    _oneshotPlayer.dispose();
  }

  void unawaitedStop() {
    _looping = false;
    unawaited(_loopPlayer.stop().catchError((_) {}));
    unawaited(_oneshotPlayer.stop().catchError((_) {}));
  }
}
