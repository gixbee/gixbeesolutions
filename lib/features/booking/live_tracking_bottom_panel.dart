import 'package:flutter/material.dart';

import '../../shared/models/worker.dart';
import '../../shared/widgets/gx_button.dart';
import '../../theme.dart';
import 'live_tracking_status_presentation.dart';

class LiveTrackingBottomPanel extends StatelessWidget {
  const LiveTrackingBottomPanel({
    super.key,
    required this.worker,
    required this.status,
    required this.isWorker,
    required this.workerNoProgress,
    required this.hasWorkerLocation,
    required this.hasCustomerLocation,
    required this.elapsedLabel,
    required this.showTimer,
    required this.onCall,
    required this.onPrimaryAction,
    required this.onWorkerArrived,
    required this.onCancelFree,
    required this.onReportIssue,
    this.etaText,
    this.distanceText,
  });

  final Worker worker;
  final String status;
  final bool isWorker;
  final bool workerNoProgress;
  final bool hasWorkerLocation;
  final bool hasCustomerLocation;
  final String elapsedLabel;
  final bool showTimer;
  final String? etaText;
  final String? distanceText;
  final VoidCallback onCall;
  final VoidCallback? onPrimaryAction;
  final VoidCallback onWorkerArrived;
  final Future<void> Function() onCancelFree;
  final VoidCallback onReportIssue;

  bool get _workActive =>
      status == 'ACTIVE' ||
      status == 'IN_PROGRESS' ||
      status == 'WORK_IN_PROGRESS';

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final muted = gx.ink.withValues(alpha: 0.55);
    final error = Theme.of(context).colorScheme.error;
    final statusColor = liveTrackingStatusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: gx.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: gx.ink.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: gx.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(liveTrackingStatusIcon(status),
                        size: 16, color: statusColor),
                    const SizedBox(width: 6),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        liveTrackingStatusText(status),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: NetworkImage(worker.imageUrl),
                    onBackgroundImageError: (_, __) {},
                    child: worker.imageUrl.isEmpty
                        ? Text(worker.name.isNotEmpty ? worker.name[0] : '?')
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          worker.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: gx.ink,
                          ),
                        ),
                        Text(worker.title,
                            style: TextStyle(color: muted, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (etaText != null && hasWorkerLocation)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: gx.accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            etaText!,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: gx.accent,
                            ),
                          ),
                          if (distanceText != null)
                            Text(distanceText!,
                                style: TextStyle(fontSize: 10, color: muted)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (!isWorker && workerNoProgress && status == 'ACCEPTED') ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Your pro does not appear to be heading your way. '
                        'You can cancel at no cost.',
                        style: TextStyle(
                            fontSize: 13, height: 1.35, color: gx.ink),
                      ),
                      const SizedBox(height: 10),
                      GxButton(
                        label: 'Cancel free',
                        onTap: onCancelFree,
                        gradient: [error, error],
                        accent: error,
                      ),
                    ],
                  ),
                ),
              ],
              if (showTimer)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: gx.accentSoft.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.timer_outlined,
                                size: 16, color: gx.accentSoft),
                            const SizedBox(width: 8),
                            Text('Job timer',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: muted)),
                          ],
                        ),
                        Text(
                          elapsedLabel,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: gx.accentSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (status == 'ACTIVE' || status == 'IN_PROGRESS')
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Center(
                    child: TextButton.icon(
                      onPressed: onReportIssue,
                      icon: Icon(Icons.flag_outlined, size: 14, color: muted),
                      label: Text('Report an issue',
                          style: TextStyle(fontSize: 12, color: muted)),
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: GxButton(
                      label: 'Call',
                      icon: Icons.call,
                      filled: false,
                      height: 48,
                      radius: 12,
                      fontSize: 14,
                      onTap: onCall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GxButton(
                      label: isWorker
                          ? 'Navigate to Customer'
                          : (_workActive
                              ? 'Work in Progress · On-Site'
                              : (status == 'ARRIVED'
                                  ? 'Verify Arrival OTP'
                                  : 'Waiting for Arrival...')),
                      icon: isWorker
                          ? Icons.navigation_rounded
                          : (_workActive
                              ? Icons.build_circle_rounded
                              : (status == 'ARRIVED'
                                  ? Icons.verified_user_rounded
                                  : Icons.directions_walk_rounded)),
                      height: 48,
                      radius: 12,
                      fontSize: 14,
                      onTap: onPrimaryAction,
                    ),
                  ),
                ],
              ),
              if (isWorker &&
                  (status == 'ACCEPTED' || status == 'ARRIVED')) ...[
                const SizedBox(height: 10),
                GxButton(
                  label: 'I have arrived — enter OTP',
                  icon: Icons.pin_rounded,
                  height: 48,
                  radius: 12,
                  fontSize: 14,
                  onTap: onWorkerArrived,
                ),
              ],
              if (!hasWorkerLocation) ...[
                const SizedBox(height: 12),
                _LocationWaitRow(
                  text: isWorker
                      ? 'Waiting for your GPS…'
                      : 'Waiting for worker\'s location...',
                  color: muted,
                ),
              ],
              if (isWorker && hasWorkerLocation && !hasCustomerLocation) ...[
                const SizedBox(height: 8),
                _LocationWaitRow(
                    text: 'Waiting for customer location…', color: muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationWaitRow extends StatelessWidget {
  const _LocationWaitRow({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.info_outline, size: 14, color: color),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}
