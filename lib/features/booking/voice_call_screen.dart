import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/alert_sound_service.dart';
import '../../services/voice_call_controller.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

/// Full-screen in-app voice call UI (ringing → connected → hang up).
class VoiceCallScreen extends ConsumerStatefulWidget {
  final bool incoming;
  final String? fallbackPhone;
  final Map<String, dynamic>? incomingInvite;

  const VoiceCallScreen({
    super.key,
    this.incoming = false,
    this.fallbackPhone,
    this.incomingInvite,
  });

  /// Start an outgoing call; pops when ended.
  static Future<void> startOutgoing(
    BuildContext context, {
    required String bookingId,
    required String callerName,
    String? peerName,
    String? fallbackPhone,
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
      // Never dial the SIM behind the user's back — say why the in-app call
      // could not start and let them choose the carrier call.
      if (!context.mounted) return;
      final reason = e is VoiceCallException
          ? e.message
          : (ctrl.lastError ?? 'Could not start the in-app call');
      await _offerPhoneFallback(
        context,
        reason: reason,
        phone: fallbackPhone,
        needsMicSettings: e is VoiceCallException && e.needsMicSettings,
      );
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VoiceCallScreen(
          incoming: false,
          fallbackPhone: fallbackPhone,
        ),
      ),
    );
  }

  static Future<void> _offerPhoneFallback(
    BuildContext context, {
    required String reason,
    required String? phone,
    bool needsMicSettings = false,
  }) async {
    final number = phone?.trim();
    final canDial = number != null && number.isNotEmpty;

    if (!canDial && !needsMicSettings) {
      showGxSnack(context, reason, type: GxSnackType.error);
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('In-app call unavailable'),
        content: Text(
          canDial
              ? '$reason\n\nCall on your phone instead? Standard carrier '
                  'charges apply and your number will be visible.'
              : reason,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Not now'),
          ),
          if (needsMicSettings)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'settings'),
              child: const Text('Open settings'),
            ),
          if (canDial)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'dial'),
              child: const Text('Call on phone'),
            ),
        ],
      ),
    );

    if (choice == 'settings') {
      await openAppSettings();
      return;
    }
    if (choice == 'dial' && canDial) {
      final uri = Uri.parse('tel:$number');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        showGxSnack(context, 'Could not open the dialer',
            type: GxSnackType.error);
      }
    }
  }

  /// Present an incoming invite (from socket / FCM).
  static Future<void> showIncoming(
    BuildContext context, {
    required Map<String, dynamic> invite,
    String? fallbackPhone,
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
          fallbackPhone: fallbackPhone,
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
  bool _ringing = false;

  @override
  void initState() {
    super.initState();
    final ctrl = ref.read(voiceCallControllerProvider);
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
    // server-side session alive, which blocked the next call.
    final ctrl = ref.read(voiceCallControllerProvider);
    if (ctrl.phase != VoiceCallPhase.idle &&
        ctrl.phase != VoiceCallPhase.ended) {
      unawaited(ctrl.hangup());
    }
    super.dispose();
  }

  Future<void> _fallbackDial() async {
    final phone = widget.fallbackPhone?.trim();
    if (phone == null || phone.isEmpty) {
      showGxSnack(context, 'Phone number not available');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Switch to a phone call?'),
        content: const Text(
          'This ends the in-app call and dials through your carrier. '
          'Standard charges apply and your number will be visible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay in app'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Call on phone'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Leave no half-open WebRTC session behind — it would block the next
    // in-app call for the whole ring window.
    await ref.read(voiceCallControllerProvider).hangup();

    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      showGxSnack(context, 'Could not open the dialer', type: GxSnackType.error);
    }
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

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
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
                  child: const Text('Close', style: TextStyle(color: Colors.white70)),
                ),
              ),
              const Spacer(),
              CircleAvatar(
                radius: 48,
                backgroundColor: GixbeeTheme.accentGreen.withValues(alpha: 0.25),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'G',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _statusLabel(phase),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (ctrl.lastError != null) ...[
                const SizedBox(height: 12),
                Text(
                  ctrl.lastError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFF87171), fontSize: 13),
                ),
              ],
              const Spacer(),
              if (phase == VoiceCallPhase.incomingRinging) ...[
                Row(
                  children: [
                    Expanded(
                      child: _RoundAction(
                        color: const Color(0xFFEF4444),
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
                      color: Colors.white24,
                      icon: ctrl.muted
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded,
                      label: ctrl.muted ? 'Unmute' : 'Mute',
                      onTap: () async {
                        await ctrl.toggleMute();
                        setState(() {});
                      },
                    ),
                    _RoundAction(
                      color: const Color(0xFFEF4444),
                      icon: Icons.call_end_rounded,
                      label: 'Hang up',
                      onTap: () => ctrl.hangup(),
                    ),
                    _RoundAction(
                      color: Colors.white24,
                      icon: Icons.phone_rounded,
                      label: 'Phone',
                      onTap: _fallbackDial,
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
                'Audio stays in the app. Use Phone if the call fails.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
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
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _RoundAction({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
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
              child: Icon(icon, color: Colors.white, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }
}
