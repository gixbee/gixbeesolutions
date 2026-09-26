import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/hiring_repository.dart';
import '../../shared/models/job_post.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../../shared/widgets/gx_fade.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import 'candidate_profile_screen.dart';

List<ApplicationStatus> nextApplicationStages(ApplicationStatus current) {
  switch (current) {
    case ApplicationStatus.applied:
      return const [ApplicationStatus.interview, ApplicationStatus.rejected];
    case ApplicationStatus.interview:
      return const [ApplicationStatus.selected, ApplicationStatus.rejected];
    default:
      return const [];
  }
}

String applicationStageLabel(ApplicationStatus stage) {
  switch (stage) {
    case ApplicationStatus.applied:
      return 'Applied';
    case ApplicationStatus.interview:
      return 'Interview';
    case ApplicationStatus.selected:
      return 'Hired';
    case ApplicationStatus.rejected:
      return 'Not Selected';
    case ApplicationStatus.withdrawn:
      return 'Withdrawn';
    case ApplicationStatus.noShow:
      return 'No-show';
  }
}

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

  /// Semantic pipeline stage accent — matches application_tracker_screen.
  Color _stageAccent(ApplicationStatus stage) {
    return switch (stage) {
      ApplicationStatus.applied => GixbeeTheme.accentGold,
      ApplicationStatus.interview => GixbeeTheme.accentBlue,
      ApplicationStatus.selected => GixbeeTheme.accentGreen,
      ApplicationStatus.rejected => GixbeeTheme.brandRed,
      ApplicationStatus.withdrawn => GixbeeTheme.textMed,
      ApplicationStatus.noShow => GixbeeTheme.brandRed,
    };
  }

  Future<void> _closeJob() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close this job?'),
        content: const Text('New candidates will no longer see this posting.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep open')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Close')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(hiringRepositoryProvider).closeJob(widget.jobId);
      if (!mounted) return;
      showGxSnack(context, 'Job closed', type: GxSnackType.success);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showGxSnack(context, 'Could not close job: $e', type: GxSnackType.error);
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
    showGxSheet(
      context,
      title: 'Move ${candidate.applicantName ?? 'Candidate'} to',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: nextApplicationStages(candidate.status).map((stage) {
          final accent = _stageAccent(stage);
          return Semantics(
            button: true,
            label: 'Move to ${applicationStageLabel(stage)}',
            selected: candidate.status == stage,
            child: ListTile(
              leading: Icon(Icons.circle, size: 12, color: accent),
              title: Text(applicationStageLabel(stage)),
              trailing: candidate.status == stage
                  ? Icon(Icons.check, color: GixbeeTheme.accentGreen)
                  : null,
              onTap: () {
                Navigator.pop(context);
                _updateStatus(candidate.id, stage);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildKanbanColumn(ApplicationStatus stage) {
    final gx = context.gx;
    final stageAccent = _stageAccent(stage);
    final candidatesInStage = _applications.where((a) => a.status == stage).toList();

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: gx.card2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gx.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: stageAccent.withValues(alpha: 0.18),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: stageAccent.withValues(alpha: 0.35))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  stage.name.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: stageAccent,
                    fontSize: 13,
                    letterSpacing: 0.4,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: gx.card.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: gx.border),
                  ),
                  child: Text(
                    '${candidatesInStage.length}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: gx.ink.withValues(alpha: 0.75),
                    ),
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
                              backgroundColor: gx.accent.withValues(alpha: 0.18),
                              child: Text(
                                candidate.applicantName != null ? candidate.applicantName![0] : 'U',
                                style: TextStyle(color: gx.accent, fontSize: 12, fontWeight: FontWeight.w700),
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
                          style: TextStyle(color: gx.ink.withValues(alpha: 0.55), fontSize: 12),
                        ),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Semantics(
                              button: true,
                              label: 'View ${candidate.applicantName ?? 'candidate'} profile',
                              child: GxPressable(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CandidateProfileScreen(application: candidate),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Text(
                                    'View Profile',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: gx.accent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Semantics(
                              button: true,
                              label: 'Move ${candidate.applicantName ?? 'candidate'} to another stage',
                              child: IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                tooltip: 'Move candidate stage',
                                icon: Icon(Icons.swap_horiz, size: 20, color: gx.ink.withValues(alpha: 0.7)),
                                onPressed: () => _showStatusUpdateDialog(candidate),
                              ),
                            ),
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
    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: _closeJob,
            child: const Text('Close'),
          ),
        ],
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
              children: _stages.map(_buildKanbanColumn).toList(),
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

