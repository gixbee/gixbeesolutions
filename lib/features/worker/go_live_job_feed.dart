import 'package:flutter/material.dart';

import '../../shared/widgets/gx_button.dart';
import '../../theme.dart';

class GoLiveJobFeed extends StatelessWidget {
  const GoLiveJobFeed({
    super.key,
    required this.jobs,
    required this.onOpenJob,
    required this.onDeclineJob,
  });

  final List<Map<String, dynamic>> jobs;
  final ValueChanged<Map<String, dynamic>> onOpenJob;
  final ValueChanged<Map<String, dynamic>> onDeclineJob;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'INCOMING JOBS',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.gx.ink.withValues(alpha: 0.55),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        if (jobs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: context.gx.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.gx.border),
            ),
            child: Column(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.gx.accent,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Waiting for job requests...',
                  style: TextStyle(
                    color: context.gx.ink.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          )
        else
          ...jobs.map(
            (job) => _GoLiveJobCard(
              job: job,
              onOpen: () => onOpenJob(job),
              onDecline: () => onDeclineJob(job),
            ),
          ),
      ],
    );
  }
}

class _GoLiveJobCard extends StatelessWidget {
  const _GoLiveJobCard({
    required this.job,
    required this.onOpen,
    required this.onDecline,
  });

  final Map<String, dynamic> job;
  final VoidCallback onOpen;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final skill = (job['skill'] ?? 'Service').toString();
    final customer =
        (job['customer_name'] ?? job['customerName'] ?? 'Customer').toString();
    final location = (job['serviceLocation'] ?? '').toString();
    final amount =
        job['amount'] is num ? (job['amount'] as num).toDouble() : 0.0;
    final isHourly =
        (job['type'] ?? 'INSTANT').toString().toUpperCase() == 'INSTANT';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.gx.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.gx.accent.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: context.gx.accent.withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: context.gx.accentGradient),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    Icon(Icons.flash_on, color: context.gx.onAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      skill,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: context.gx.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      customer,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.gx.ink.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              if (amount > 0)
                Text(
                  isHourly
                      ? '₹${amount.toStringAsFixed(0)}/hr'
                      : '₹${amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: GixbeeTheme.accentGold,
                  ),
                ),
            ],
          ),
          if (location.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.gx.card2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on, size: 14, color: context.gx.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.gx.ink.withValues(alpha: 0.87),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GxButton(
                  label: 'Decline',
                  filled: false,
                  onTap: onDecline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GxButton(
                  label: 'View Job',
                  gradient: const [
                    Color(0xFF059669),
                    Color(0xFF10B981),
                  ],
                  onTap: onOpen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
