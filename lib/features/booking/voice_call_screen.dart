import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/alert_sound_service.dart';
import '../../services/voice_call_controller.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

/// Full-screen in-app voice call UI (ringing → connected → hang up).
///
/// There is deliberately no `tel:` escape hatch anywhere in this flow. Calls
/// stay on WebRTC so neither side ever learns the other's phone number.
class VoiceCallScreen extends ConsumerStatefulWidget {
  final bool incoming;
  final Map<String, dynamic>? incomingInvite;

  const VoiceCallScreen({
    super.key,
    this.incoming = false,
    this.incomingInvite,
  });

  /// Start an outgoing call; pops when ended.
  static Future<void> startOutgoing(
    BuildContext context, {
    required String bookingId,
    required String callerName,
    String? peerName,
  }) async {
    final container = ProviderScope.containerOf(context);
    final ctrl = container.read(voiceCallControllerProvider);
    try {
      await ctrl.startOutgoing(
        bookingId: bookingId,
        callerName: callerName,
        peerDisplayName: peerName,
      );
    } catch (e) {
      if (!context.mounted) return;
      final reason = e is VoiceCallException
          ? e.message
          : (ctrl.lastError ?? 'Could not start the in-app call');
      if (e is VoiceCallException && e.needsMicSettings) {
        await _promptMicSettings(context, reason);
      } else {
        showGxSnack(context, reason, type: GxSnackType.error);
      }
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const VoiceCallScreen(incoming: false),
      ),
    );
  }

  static Future<void> _promptMicSettings(
    BuildContext context,
    String reason,
  ) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Microphone needed'),
        content: Text(reason),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (open == true) await openAppSettings();
  }

  /// Present an incoming invite (from socket / FCM).
  static Future<void> showIncoming(
    BuildContext context, {
    required Map<String, dynamic> invite,
  }) async {
    final container = ProviderScope.containerOf(context);
    final ctrl = container.read(voiceCallControllerProvider);
    await ctrl.presentIncoming(invite);
    if (!context.mounted) return;
    if (ctrl.phase != VoiceCallPhase.incomingRinging) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VoiceCallScreen(
          incoming: true,
          incomingInvite: invite,
        ),
      ),
    );
  }

  @override
  ConsumerState<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends ConsumerState<VoiceCallScreen> {
  StreamSubscription<VoiceCallPhase>? _sub;
  bool _popping = false;
  AlertSoundService? _alertSound;
  VoiceCallController? _ctrl;
  bool _ringing = false;

  @override
  void initState() {
    super.initState();
    final ctrl = ref.read(voiceCallControllerProvider);
    _ctrl = ctrl;
    _alertSound = ref.read(alertSoundServiceProvider);
    if (widget.incoming) _startRing();
    _sub = ctrl.phaseChanges.listen((phase) {
      if (!mounted) return;
      if (phase != VoiceCallPhase.incomingRinging) _stopRing();
      setState(() {});
      if (phase == VoiceCallPhase.ended || phase == VoiceCallPhase.idle) {
        _maybePop();
      }
    });
  }

  void _startRing() {
    if (_ringing) return;
    _ringing = true;
    unawaited(_alertSound?.startIncomingJobAlert() ?? Future<void>.value());
  }

  void _stopRing() {
    if (!_ringing) return;
    _ringing = false;
    unawaited(_alertSound?.stopIncomingJobAlert() ?? Future<void>.value());
  }

  void _maybePop() {
    if (_popping || !mounted) return;
    _popping = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _stopRing();
    // Swipe-back / system back used to leave the peer connection and the
    // server-side session alive, which blocked the next call. Use the
    // controller captured in initState — reading a provider here throws
    // ("Using ref when a widget has been unmounted"), which aborted dispose
    // before the hangup and crashed the frame.
    final ctrl = _ctrl;
    if (ctrl != null &&
        ctrl.phase != VoiceCallPhase.idle &&
        ctrl.phase != VoiceCallPhase.ended) {
      unawaited(ctrl.hangup());
    }
    super.dispose();
  }

  String _statusLabel(VoiceCallPhase phase) {
    switch (phase) {
      case VoiceCallPhase.outgoingRinging:
        return 'Calling…';
      case VoiceCallPhase.incomingRinging:
        return 'Incoming call';
      case VoiceCallPhase.connecting:
        return 'Connecting…';
      case VoiceCallPhase.connected:
        return 'Connected';
      case VoiceCallPhase.ended:
        return 'Call ended';
      case VoiceCallPhase.idle:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(voiceCallControllerProvider);
    // Rebuild via phase stream + setState; also read fields:
    final phase = ctrl.phase;
    final name = ctrl.peerName ?? 'Gixbee';
    final gx = context.gx;

    final cs = Theme.of(context).colorScheme;
    // Immersive call UI stays on the dark void canvas in both themes.
    final onDark = GixbeeTheme.textHigh;

    return Scaffold(
      backgroundColor: GixbeeTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () async {
                    if (phase == VoiceCallPhase.incomingRinging) {
                      await ctrl.rejectIncoming();
                    } else {
                      await ctrl.hangup();
                    }
                  },
                  child: Text(
                    'Close',
                    style: TextStyle(color: onDark.withValues(alpha: 0.7)),
                  ),
                ),
              ),
              const Spacer(),
              CircleAvatar(
                radius: 48,
                backgroundColor: GixbeeTheme.accentGreen.withValues(alpha: 0.25),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'G',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: onDark,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: onDark,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _statusLabel(phase),
                style: TextStyle(
                  color: onDark.withValues(alpha: 0.65),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (ctrl.lastError != null) ...[
                const SizedBox(height: 12),
                Text(
                  ctrl.lastError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.error, fontSize: 13),
                ),
              ],
              const Spacer(),
              if (phase == VoiceCallPhase.incomingRinging) ...[
                Row(
                  children: [
                    Expanded(
                      child: _RoundAction(
                        color: cs.error,
                        icon: Icons.call_end_rounded,
                        label: 'Decline',
                        onTap: () => ctrl.rejectIncoming(),
                      ),
                    ),
                    const SizedBox(width: 28),
                    Expanded(
                      child: _RoundAction(
                        color: GixbeeTheme.accentGreen,
                        icon: Icons.call_rounded,
                        label: 'Accept',
                        onTap: () => ctrl.acceptIncoming(),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _RoundAction(
                      color: ctrl.muted
                          ? onDark
                          : onDark.withValues(alpha: 0.24),
                      iconColor: ctrl.muted
                          ? GixbeeTheme.grabText
                          : onDark,
                      icon: ctrl.muted
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded,
                      label: ctrl.muted ? 'Unmute' : 'Mute',
                      onTap: () async {
                        await ctrl.toggleMute();
                        if (mounted) setState(() {});
                      },
                    ),
                    _RoundAction(
                      color: cs.error,
                      icon: Icons.call_end_rounded,
                      label: 'Hang up',
                      onTap: () => ctrl.hangup(),
                    ),
                    _RoundAction(
                      color: ctrl.speakerOn
                          ? onDark
                          : onDark.withValues(alpha: 0.24),
                      iconColor: ctrl.speakerOn
                          ? GixbeeTheme.grabText
                          : onDark,
                      icon: ctrl.speakerOn
                          ? Icons.volume_up_rounded
                          : Icons.hearing_rounded,
                      label: ctrl.speakerOn ? 'Speaker' : 'Earpiece',
                      onTap: () async {
                        await ctrl.toggleSpeaker();
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'In-app voice · Gixbee',
                style: TextStyle(
                  color: gx.ink.withValues(alpha: 0.0),
                  fontSize: 1,
                ),
              ),
              Text(
                'Calls stay inside Gixbee. Phone numbers are never shared.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: onDark.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final Color color;
  final Color iconColor;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _RoundAction({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = GixbeeTheme.textHigh,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = GixbeeTheme.textHigh.withValues(alpha: 0.7);
    return Semantics(
      button: true,
      label: label,
      child: Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 68,
              height: 68,
              child: Icon(icon, color: iconColor, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(color: labelColor, fontSize: 13),
        ),
      ],
      ),
    );
  }
}
