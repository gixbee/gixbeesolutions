import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/worker_repository.dart';
import '../../theme.dart';
import 'go_live_screen.dart';

/// Center bottom-nav control: Online/Offline status and Go Online/Go Offline.
class WorkerAvailabilityFab extends ConsumerWidget {
  final VoidCallback onToggle;

  const WorkerAvailabilityFab({super.key, required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gx = context.gx;
    final isLive = ref.watch(workerLiveStateProvider);
    final busy = ref.watch(workerLiveToggleBusyProvider);
    final online = GixbeeTheme.accentGreen;
    final onlineDark = GixbeeTheme.accentGreenDark;

    return Semantics(
      button: true,
      enabled: !busy,
      label: isLive
          ? 'Online. Tap to go offline. Long press for Go Live dashboard.'
          : 'Offline. Tap to go online. Long press for Go Live dashboard.',
      child: SizedBox(
        width: 72,
        height: 58,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: isLive
                ? LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.error,
                      GixbeeTheme.brandRed,
                    ],
                  )
                : LinearGradient(colors: [onlineDark, online]),
            boxShadow: [
              BoxShadow(
                color: (isLive ? GixbeeTheme.brandRed : online)
                    .withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: busy ? null : onToggle,
              onLongPress: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GoLiveScreen()),
                );
              },
              child: busy
                  ? Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: gx.onAccent,
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isLive ? 'Online' : 'Offline',
                          style: TextStyle(
                            color: gx.onAccent,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isLive ? 'Go Offline' : 'Go Online',
                          style: TextStyle(
                            color: gx.onAccent,
                            fontSize: 7,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
