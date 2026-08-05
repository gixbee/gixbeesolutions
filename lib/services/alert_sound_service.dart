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
  bool _contextReady = false;

  /// Bumped by every start/stop. `play()` is several awaits long, so a stop
  /// that lands mid-flight would otherwise be overtaken by the play that
  /// completes after it — leaving the loop ringing with nobody to stop it.
  int _loopGeneration = 0;

  /// Screens currently asking for the ring (FCM card + socket card can stack).
  /// The loop only stops once the last one releases it.
  int _loopHolders = 0;

  Timer? _loopSafetyTimer;

  /// Hard ceiling — a request expires in 90s, so the ring can never outlive
  /// the card even if a stop is somehow missed.
  static const _maxLoopDuration = Duration(seconds: 100);

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
  ///
  /// Every caller MUST pair this with exactly one [stopIncomingJobAlert].
  Future<void> startIncomingJobAlert() async {
    _loopHolders++;
    if (!_soundOn) return;
    if (_loopHolders > 1) return; // already ringing for another card

    final generation = ++_loopGeneration;
    _loopSafetyTimer?.cancel();
    _loopSafetyTimer = Timer(_maxLoopDuration, () {
      debugPrint('[AlertSound] safety stop — loop exceeded max duration');
      _loopHolders = 0;
      unawaited(_hardStopLoop());
    });

    await _configureAudioContext();
    if (generation != _loopGeneration) return _hardStopLoop();
    try {
      await _loopPlayer.setReleaseMode(ReleaseMode.loop);
      await _loopPlayer.setVolume(1.0);
      if (generation != _loopGeneration) return _hardStopLoop();
      await _loopPlayer.play(AssetSource('sounds/booking_alert.wav'));
    } catch (e) {
      debugPrint('[AlertSound] incoming loop failed: $e');
      try {
        if (generation != _loopGeneration) return _hardStopLoop();
        await _loopPlayer.play(AssetSource('sounds/gixbee_alert.wav'));
      } catch (e2) {
        debugPrint('[AlertSound] incoming fallback failed: $e2');
      }
    }
    // A stop that raced ahead of the awaits above wins.
    if (generation != _loopGeneration) await _hardStopLoop();
  }

  Future<void> stopIncomingJobAlert() async {
    if (_loopHolders > 0) _loopHolders--;
    if (_loopHolders > 0) return; // another card is still showing
    await _hardStopLoop();
  }

  /// Unconditional silence, ignoring holder counts. Used by the safety timer,
  /// lifecycle teardown and anything that must guarantee quiet (voice calls).
  Future<void> _hardStopLoop() async {
    _loopGeneration++;
    _loopHolders = 0;
    _loopSafetyTimer?.cancel();
    _loopSafetyTimer = null;
    try {
      await _loopPlayer.stop();
    } catch (e) {
      debugPrint('[AlertSound] stop failed: $e');
    }
    // audioplayers keeps the loop release mode on the native player; reset it
    // so a stray resume can't restart the loop.
    try {
      await _loopPlayer.setReleaseMode(ReleaseMode.release);
    } catch (_) {}
  }

  /// Silence everything right now (call start, logout, forced teardown).
  Future<void> stopAll() async {
    await _hardStopLoop();
    try {
      await _oneshotPlayer.stop();
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
    _loopGeneration++;
    _loopHolders = 0;
    _loopSafetyTimer?.cancel();
    _loopSafetyTimer = null;
    unawaited(_loopPlayer.stop().catchError((_) {}));
    unawaited(_oneshotPlayer.stop().catchError((_) {}));
  }
}
