import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/hiring_repository.dart';
import '../../shared/models/job_post.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import '../jobs/match_explanation.dart';
import '../messages/chat_thread_screen.dart';

class RecommendedCandidatesScreen extends ConsumerStatefulWidget {
  final String? businessId;
  const RecommendedCandidatesScreen({super.key, this.businessId});

  @override
  ConsumerState<RecommendedCandidatesScreen> createState() =>
      _RecommendedCandidatesScreenState();
}

class _RecommendedCandidatesScreenState
    extends ConsumerState<RecommendedCandidatesScreen> {
  List<JobPost> _jobs = [];
  String? _jobId;
  List<CandidateMatch> _people = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    try {
      final jobs = await ref
          .read(hiringRepositoryProvider)
          .getMyJobs(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _jobs = jobs.where((j) => j.isActive).toList();
        _jobId = _jobs.isEmpty ? null : _jobs.first.id;
        _loading = false;
      });
      if (_jobId != null) await _loadPeople(_jobId!);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showGxSnack(context, 'Could not load jobs: $e', type: GxSnackType.error);
    }
  }

  Future<void> _loadPeople(String jobId) async {
    setState(() => _loading = true);
    try {
      final people =
          await ref.read(hiringRepositoryProvider).recommendedCandidates(jobId);
      if (!mounted) return;
      setState(() {
        _people = people;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showGxSnack(context, 'Could not load candidates: $e',
          type: GxSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: const Text('Recommended Candidates')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (_jobs.isEmpty)
                  const Text('Publish a job to see recommended candidates.')
                else
                  DropdownButton<String>(
                    isExpanded: true,
                    value: _jobId,
                    items: [
                      for (final job in _jobs)
                        DropdownMenuItem(value: job.id, child: Text(job.title)),
                    ],
                    onChanged: (id) {
                      if (id == null) return;
                      setState(() => _jobId = id);
                      _loadPeople(id);
                    },
                  ),
                const SizedBox(height: 12),
                for (final person in _people) _card(context, person),
              ],
            ),
    );
  }

  Widget _card(BuildContext context, CandidateMatch person) {
    final role = person.roles.isEmpty ? 'Candidate' : person.roles.first;
    final km = person.distanceKm == null
        ? ''
        : '${person.distanceKm!.toStringAsFixed(1)} km away';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(person.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Text(role),
          Text('${person.experienceYears.toStringAsFixed(0)} years experience'),
          if (km.isNotEmpty) Text(km),
          if (person.expectedSalary != null && person.expectedSalary! > 0)
            Text('Expected ₹${person.expectedSalary!.toInt()}/month'),
          const SizedBox(height: 8),
          MatchExplanationBlock(
            score: person.matchScore,
            reasons: person.reasons,
            warnings: person.warnings,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GxButton(
                  label: 'View Profile',
                  filled: false,
                  accent: GixbeeTheme.accentBlue,
                  height: 42,
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(person.name),
                        content: Text(
                          '${person.roles.join(', ')}\n${person.skills.join(', ')}\n${person.experienceYears} years',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GxButton(
                  label: 'Invite to Chat',
                  accent: GixbeeTheme.accentBlue,
                  gradient: const [GixbeeTheme.accentBlue, Color(0xFF1D4ED8)],
                  height: 42,
                  onTap: _jobId == null
                      ? null
                      : () async {
                          try {
                            await ref.read(hiringRepositoryProvider).inviteCandidate(
                                  _jobId!,
                                  person.candidateId,
                                );
                            if (!context.mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatThreadScreen(
                                  otherUserId: person.candidateId,
                                  otherUserName: person.name,
                                ),
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            showGxSnack(context, 'Could not invite: $e',
                                type: GxSnackType.error);
                          }
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
