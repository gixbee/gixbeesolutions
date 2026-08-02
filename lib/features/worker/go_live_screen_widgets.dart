import 'package:flutter/material.dart';

import '../../shared/widgets/gx_button.dart';
import '../../theme.dart';
import '../jobs/register_pro_screen.dart';

class GoLiveJobCreditsCard extends StatelessWidget {
  const GoLiveJobCreditsCard({
    super.key,
    required this.balance,
    required this.onBuyPack,
  });

  final int balance;
  final VoidCallback onBuyPack;

  @override
  Widget build(BuildContext context) {
    final isLow = balance == 0;
    final color = isLow ? const Color(0xFFF97316) : GixbeeTheme.accentGreen;
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLow ? Icons.lock_clock : Icons.confirmation_num_outlined,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isLow ? 'No job credits remaining' : 'Job Credits: $balance',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color.withValues(alpha: 0.9),
                  ),
                ),
              ),
              if (isLow)
                GxButton(
                  label: 'Buy Pack',
                  expand: false,
                  height: 36,
                  fontSize: 13,
                  onTap: onBuyPack,
                ),
            ],
          ),
          if (isLow) ...[
            const SizedBox(height: 6),
            const Text(
              'You need job credits to accept new bookings. Buy a pack now.',
              style: TextStyle(fontSize: 12, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }
}

class GoLiveStatCard extends StatelessWidget {
  const GoLiveStatCard({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: context.gx.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.gx.border),
      ),
      alignment: Alignment.center,
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: context.gx.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: context.gx.ink.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class GoLiveVerificationBadge extends StatelessWidget {
  const GoLiveVerificationBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'VERIFIED':
        return Row(children: [
          const Icon(Icons.verified_user,
              size: 12, color: GixbeeTheme.accentGreen),
          const SizedBox(width: 5),
          Text('Aadhaar Verified',
              style: TextStyle(
                  fontSize: 12, color: context.gx.ink.withValues(alpha: 0.55))),
        ]);
      case 'REJECTED':
        return const Row(children: [
          Icon(Icons.cancel, size: 12, color: Color(0xFFDC2626)),
          SizedBox(width: 5),
          Text('Verification Rejected',
              style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.w600)),
        ]);
      default:
        return const Row(children: [
          Icon(Icons.access_time, size: 12, color: GixbeeTheme.accentGold),
          SizedBox(width: 5),
          Text('Verification Pending',
              style: TextStyle(
                  fontSize: 12,
                  color: GixbeeTheme.accentGold,
                  fontWeight: FontWeight.w600)),
        ]);
    }
  }
}

class GoLiveNotAWorker extends StatelessWidget {
  const GoLiveNotAWorker({super.key, required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.badge_outlined,
                size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('Become a Gixbee Pro',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface)),
            const SizedBox(height: 8),
            Text(
              'Register your skills to start receiving instant jobs and go live.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 20),
            GxButton(
              label: 'Register as Pro',
              icon: Icons.assignment_ind_outlined,
              expand: false,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RegisterProScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
