import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
      final phone = fallbackPhone?.trim();
      if (phone != null && phone.isNotEmpty) {
        final uri = Uri.parse('tel:$phone');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }
      if (context.mounted) {
        showGxSnack(
          context,
          ctrl.lastError ?? 'Could not start in-app call',
          type: GxSnackType.error,
        );
      }
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

  @override
  void initState() {
    super.initState();
    final ctrl = ref.read(voiceCallControllerProvider);
    _sub = ctrl.phaseChanges.listen((phase) {
      if (!mounted) return;
      setState(() {});
      if (phase == VoiceCallPhase.ended || phase == VoiceCallPhase.idle) {
        _maybePop();
      }
    });
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
    super.dispose();
  }

  Future<void> _fallbackDial() async {
    final phone = widget.fallbackPhone?.trim();
    if (phone == null || phone.isEmpty) {
      showGxSnack(context, 'Phone number not available');
      return;
    }
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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
