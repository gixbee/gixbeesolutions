import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/hiring_repository.dart';
import '../../shared/models/job_post.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import 'match_explanation.dart';

class MatchedJobDetailScreen extends ConsumerWidget {
  final JobPost job;
  const MatchedJobDetailScreen({super.key, required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final business = job.businessName ?? job.employerName ?? 'Employer';
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: const Text('Job')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text(job.title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Text(business, style: TextStyle(color: cs.onSurfaceVariant))),
              if (job.businessVerified)
                const Text('Verified',
                    style: TextStyle(
                        color: GixbeeTheme.accentGreen,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
            ],
          ),
          const SizedBox(height: 14),
          Text(_pay(job), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('${_mode(job.workMode)} · ${job.jobType}'),
          if (job.distanceExact && job.distanceKm != null)
            Text('${job.distanceKm!.toStringAsFixed(1)} km away'),
          const SizedBox(height: 16),
          Text(job.description),
          const SizedBox(height: 16),
          if (job.requiredSkills.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final skill in job.requiredSkills)
                  Chip(label: Text(skill)),
              ],
            ),
          const SizedBox(height: 18),
          const Text('Why this matches you',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          MatchExplanationBlock(
            score: job.matchScore,
            reasons: job.matchReasons,
            warnings: job.matchWarnings,
            verified: job.businessVerified,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GxButton(
            label: "I'm Interested",
            onTap: () async {
              try {
                await ref.read(hiringRepositoryProvider).expressInterest(job.id);
                if (!context.mounted) return;
                showGxSnack(context, 'Interest sent', type: GxSnackType.success);
                Navigator.pop(context, true);
              } catch (e) {
                if (!context.mounted) return;
                showGxSnack(context, 'Could not send interest: $e',
                    type: GxSnackType.error);
              }
            },
            gradient: const [GixbeeTheme.accentGreen, Color(0xFF047857)],
            accent: GixbeeTheme.accentGreen,
          ),
        ),
      ),
    );
  }

  String _pay(JobPost job) {
    final period = switch (job.salaryPeriod) {
      'HOURLY' => 'hour',
      'DAILY' => 'day',
      'WEEKLY' => 'week',
      'PER_JOB' => 'job',
      _ => 'month',
    };
    if (job.salaryMin != null && job.salaryMax != null && job.salaryMin != job.salaryMax) {
      return '₹${job.salaryMin!.toInt()} – ₹${job.salaryMax!.toInt()} / $period';
    }
    if (job.salaryMin != null) return '₹${job.salaryMin!.toInt()} / $period';
    return 'Pay not listed';
  }

  String _mode(String mode) => switch (mode) {
        'REMOTE' => 'Remote',
        'HYBRID' => 'Hybrid',
        _ => 'On-site',
      };
}
