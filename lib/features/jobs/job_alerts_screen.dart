import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/hiring_repository.dart';
import '../../shared/models/job_post.dart';
import 'package:intl/intl.dart';

/// Browse available gig/job postings near the user.
/// Features: filter chips, job cards with pay & distance, apply button.
class JobAlertsScreen extends ConsumerStatefulWidget {
  const JobAlertsScreen({super.key});

  @override
  ConsumerState<JobAlertsScreen> createState() => _JobAlertsScreenState();
}

class _JobAlertsScreenState extends ConsumerState<JobAlertsScreen> {
  String _selectedFilter = 'All';

  final _filters = [
    'All',
    'Nearby',
    'Electrician',
    'Plumbing',
    'Cleaning',
    'Painting',
    'Tech',
    'Events',
  ];

  List<JobPost> _jobs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchJobs();
  }

  Future<void> _fetchJobs() async {
    try {
      final jobs = await ref.read(hiringRepositoryProvider).getMatchingJobs();
      if (mounted) {
        setState(() {
          _jobs = jobs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading jobs: $e')));
      }
    }
  }

  List<JobPost> get _filteredJobs {
    if (_selectedFilter == 'All') return _jobs;
    return _jobs.where((j) => j.jobType == _selectedFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── HEADER ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Find a Job',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_jobs.length} open gigs near you',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.tune_rounded, color: cs.primary),
                  onPressed: () {}, // TODO: advanced filter sheet
                ),
              ],
            ),
          ),

          // ── FILTER CHIPS ──
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final f = _filters[i];
                final selected = _selectedFilter == f;
                return FilterChip(
                  label: Text(f),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedFilter = f),
                  selectedColor:
                      const Color(0xFF54A0FF).withValues(alpha: 0.15),
                  checkmarkColor: const Color(0xFF54A0FF),
                  side: BorderSide(
                    color: selected
                        ? const Color(0xFF54A0FF)
                        : cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // ── JOB LIST ──
          Expanded(
            child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _filteredJobs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off,
                                size: 48,
                                color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                            const SizedBox(height: 12),
                            Text('No jobs available right now',
                                style: TextStyle(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: _filteredJobs.length,
                        itemBuilder: (context, i) =>
                            _JobCard(job: _filteredJobs[i]),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────
// JOB CARD
// ─────────────────────────────────────
class _JobCard extends ConsumerWidget {
  final JobPost job;
  const _JobCard({required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: title + urgency badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    job.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SkillBadge(skill: job.jobType),
              ],
            ),
            const SizedBox(height: 8),

            // Description
            Text(
              job.description,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),

            // Meta row
            Row(
              children: [
                _MetaChip(
                    icon: Icons.location_on_outlined,
                    text: job.location,
                    color: cs.primary),
                const SizedBox(width: 8),
                _MetaChip(
                    icon: Icons.person_outline,
                    text: job.employerName ?? 'Business Owner',
                    color: cs.secondary),
                const SizedBox(width: 8),
                _MetaChip(
                    icon: Icons.schedule,
                    text: job.createdAt != null ? DateFormat.yMMMd().format(job.createdAt!) : '',
                    color: cs.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: 12),

            // Bottom row: pay + apply
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.salaryMin != null ? '₹${job.salaryMin}' : 'Competitive Pay',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: cs.primary,
                      ),
                    ),
                    Text(
                      job.experience,
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 11),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    try {
                      await ref.read(hiringRepositoryProvider).applyToJob(job.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Applied for "${job.title}"')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to apply: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Apply',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _MetaChip(
      {required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(text,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _SkillBadge extends StatelessWidget {
  final String skill;
  const _SkillBadge({required this.skill});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        skill.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}


