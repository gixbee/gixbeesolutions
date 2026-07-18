import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/hiring_repository.dart';
import '../../shared/models/job_post.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../../shared/widgets/gx_fade.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import 'candidate_profile_screen.dart';

class HiringPipelineScreen extends ConsumerStatefulWidget {
  final String jobId;
  final String jobTitle;

  const HiringPipelineScreen({super.key, required this.jobId, required this.jobTitle});

  @override
  ConsumerState<HiringPipelineScreen> createState() => _HiringPipelineScreenState();
}

class _HiringPipelineScreenState extends ConsumerState<HiringPipelineScreen> {
  List<JobApplication> _applications = [];
  bool _isLoading = true;

  final List<ApplicationStatus> _stages = [
    ApplicationStatus.applied,
    ApplicationStatus.interview,
    ApplicationStatus.selected,
    ApplicationStatus.rejected,
  ];

  @override
  void initState() {
    super.initState();
    _fetchApplications();
  }

  Future<void> _fetchApplications() async {
    try {
      final repo = ref.read(hiringRepositoryProvider);
      // If jobId is 'all', we might want to fetch all. For now assume jobId works.
      final apps = await repo.getApplicationsForJob(widget.jobId);
      if (mounted) {
        setState(() {
          _applications = apps;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showGxSnack(context, 'Error loading candidates: $e',
            type: GxSnackType.error);
      }
    }
  }

  Color _getStageColor(ApplicationStatus stage, BuildContext context) {
    switch (stage) {
      case ApplicationStatus.applied: return Colors.blue.shade100;
      case ApplicationStatus.interview: return Colors.amber.shade100;
      case ApplicationStatus.selected: return Colors.green.shade100;
      case ApplicationStatus.rejected: return Colors.red.shade100;
      case ApplicationStatus.withdrawn: return Colors.grey.shade300;
    }
  }

  Future<void> _updateStatus(String appId, ApplicationStatus newStatus) async {
    try {
      await ref.read(hiringRepositoryProvider).updateApplicationStatus(appId, newStatus);
      _fetchApplications(); // Refresh list to get updated status from backend
      if (mounted) {
        showGxSnack(
            context, 'Candidate moved to ${newStatus.name.toUpperCase()}',
            type: GxSnackType.success);
      }
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Failed to update status: $e',
            type: GxSnackType.error);
      }
    }
  }

  void _showStatusUpdateDialog(JobApplication candidate) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('Move ${candidate.applicantName ?? 'Candidate'} to:'),
                titleTextStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
              ),
              const Divider(),
              ..._stages.map((stage) {
                return ListTile(
                  title: Text(stage.name.toUpperCase()),
                  trailing: candidate.status == stage ? const Icon(Icons.check, color: Colors.green) : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _updateStatus(candidate.id, stage);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKanbanColumn(ApplicationStatus stage, ColorScheme colorScheme) {
    final candidatesInStage = _applications.where((a) => a.status == stage).toList();

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: _getStageColor(stage, context).withValues(alpha: 0.8),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  stage.name.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${candidatesInStage.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: candidatesInStage.length,
              itemBuilder: (ctx, idx) {
                final candidate = candidatesInStage[idx];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: GixbeeTheme.accentBlue,
                              child: Text(
                                candidate.applicantName != null ? candidate.applicantName![0] : 'U',
                                style: TextStyle(color: context.gx.onAccent, fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                candidate.applicantName ?? 'Unknown User',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Applied on: ${candidate.createdAt != null ? candidate.createdAt!.toLocal().toString().split(' ')[0] : 'N/A'}',
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                        ),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GxPressable(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CandidateProfileScreen(application: candidate),
                                  ),
                                );
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  'View Profile',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: GixbeeTheme.accentBlue,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                              tooltip: 'Move candidate stage',
                              icon: const Icon(Icons.swap_horiz, size: 20),
                              onPressed: () => _showStatusUpdateDialog(candidate),
                            )
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hiring Pipeline', style: TextStyle(fontSize: 18)),
            Text(widget.jobTitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: GxFade(
        child: KeyedSubtree(
          key: ValueKey(_isLoading ? 'loading' : 'data'),
          child: _isLoading
        ? _buildSkeleton()
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _stages.map((stage) => _buildKanbanColumn(stage, colorScheme)).toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ── Skeleton kanban while loading (Gixbee 2026 — no centered spinner) ──
  Widget _buildSkeleton() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(3, (_) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              GxSkeleton(width: 220, height: 28, radius: 10),
              SizedBox(height: 12),
              GxSkeleton(width: 220, height: 96, radius: 16),
              SizedBox(height: 12),
              GxSkeleton(width: 220, height: 96, radius: 16),
            ],
          ),
        )),
      ),
    );
  }
}

