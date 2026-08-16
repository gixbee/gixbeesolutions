import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../repositories/hiring_repository.dart';
import '../../repositories/talent_repository.dart';
import '../../shared/models/job_post.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../../shared/widgets/gx_text_field.dart';
import '../../shared/widgets/gx_empty.dart';
import '../../theme.dart';

/// Browse available gig/job postings near the user (mockup "job" tab 1).
/// Gixbee 2026 reskin: neutral header, squircle filter chips, bento job
/// cards (logo block, pay pill, location row), apply via gx_sheet.
///
/// Classic board only — Smart Hiring offers live on the Offers tab.
class JobAlertsScreen extends ConsumerStatefulWidget {
  /// Opens the Applications tab in [FindJobModule] after a successful apply.
  final VoidCallback? onOpenApplications;

  const JobAlertsScreen({super.key, this.onOpenApplications});

  @override
  ConsumerState<JobAlertsScreen> createState() => _JobAlertsScreenState();
}

class _JobAlertsScreenState extends ConsumerState<JobAlertsScreen> {
  String _selectedFilter = 'All';

  final _filters = [
    'All',
    'Saved',
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
  final Set<String> _appliedJobIds = {};

  // v126 alert actions: "Later" bookmarks persist on the talent profile
  // (savedJobIds via POST /talent/saved-jobs/toggle); "Skip" hides for this
  // session only.
  final Set<String> _savedJobIds = {};
  final Set<String> _skippedJobIds = {};

  // Filter-sheet state (wired: pay range + experience actually filter).
  RangeValues _payRange = const RangeValues(0, 2000);
  String? _selectedExp;

  bool get _filtersActive =>
      _payRange != const RangeValues(0, 2000) || _selectedExp != null;

  @override
  void initState() {
    super.initState();
    _fetchJobs();
    _fetchSavedJobs();
  }

  Future<void> _fetchSavedJobs() async {
    try {
      final profile = await ref.read(talentRepositoryProvider).getProfile();
      final saved = (profile['savedJobIds'] as List? ?? [])
          .map((e) => e.toString())
          .toSet();
      if (mounted) setState(() => _savedJobIds.addAll(saved));
    } catch (e) {
      debugPrint('Fetching saved jobs failed: $e');
    }
  }

  Future<void> _toggleSaved(JobPost job) async {
    // Optimistic toggle; revert on failure.
    final wasSaved = _savedJobIds.contains(job.id);
    setState(() =>
        wasSaved ? _savedJobIds.remove(job.id) : _savedJobIds.add(job.id));
    try {
      await ref.read(talentRepositoryProvider).toggleSavedJob(job.id);
      if (mounted && !wasSaved) {
        showGxSnack(context, 'Saved for later', type: GxSnackType.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() => wasSaved
            ? _savedJobIds.add(job.id)
            : _savedJobIds.remove(job.id));
        showGxSnack(context, 'Could not update: $e', type: GxSnackType.error);
      }
    }
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
        showGxSnack(context, 'Error loading jobs: $e',
            type: GxSnackType.error);
      }
    }
  }

  List<JobPost> get _filteredJobs {
    Iterable<JobPost> out = _jobs;
    if (_selectedFilter == 'Saved') {
      out = out.where((j) => _savedJobIds.contains(j.id));
    } else {
      // Session-skipped alerts stay hidden everywhere except the Saved view.
      out = out.where((j) => !_skippedJobIds.contains(j.id));
      if (_selectedFilter != 'All' && _selectedFilter != 'Nearby') {
        out = out.where((j) => j.jobType == _selectedFilter);
      }
    }
    if (_payRange != const RangeValues(0, 2000)) {
      out = out.where((j) {
        final min = j.salaryMin;
        final max = j.salaryMax ?? j.salaryMin;
        if (min == null) return true; // "Competitive Pay" — keep visible
        return max! >= _payRange.start && min <= _payRange.end;
      });
    }
    if (_selectedExp != null) {
      out = out.where((j) => j.experience == _selectedExp);
    }
    return out.toList();
  }

  /// Optional-note + optional-résumé glass sheet, then POST the application.
  Future<void> _applyToJob(JobPost job) async {
    final noteCtrl = TextEditingController();
    // Captured across the StatefulBuilder rebuilds so the outer POST can read
    // the uploaded résumé URL after the sheet closes.
    String? resumeUrl;
    String? resumeName;
    var uploadingResume = false;

    final labelStyle = TextStyle(
      color: context.gx.ink.withValues(alpha: 0.45),
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2,
    );

    final confirmed = await showGxSheet<bool>(
      context,
      title: 'Apply for this job',
      child: StatefulBuilder(
        builder: (ctx, setSheet) {
          // Pick an image of the résumé/CV → upload via the shared
          // /uploads/image endpoint (same pattern as register-pro certificates).
          Future<void> pickResume() async {
            final messenger = ScaffoldMessenger.of(ctx);
            try {
              final x = await ImagePicker().pickImage(
                source: ImageSource.gallery,
                maxWidth: 1600,
                imageQuality: 85,
              );
              if (x == null) return;
              setSheet(() => uploadingResume = true);
              final bytes = await x.readAsBytes();
              final url = await ref
                  .read(talentRepositoryProvider)
                  .uploadImage(bytes, x.name);
              setSheet(() {
                resumeUrl = url;
                resumeName = x.name;
                uploadingResume = false;
              });
            } catch (e) {
              setSheet(() => uploadingResume = false);
              messenger.showSnackBar(
                gxSnackBar('Résumé upload failed: $e',
                    type: GxSnackType.error),
              );
            }
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                job.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: context.gx.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                job.employerName ?? 'Business Owner',
                style: TextStyle(
                  color: context.gx.ink.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              Text('NOTE FOR THE EMPLOYER', style: labelStyle),
              const SizedBox(height: 8),
              GxTextField(
                controller: noteCtrl,
                accent: GixbeeTheme.accentGreen,
                maxLines: 3,
                hint: 'Add a short note (optional)…',
              ),
              const SizedBox(height: 16),
              Text('RÉSUMÉ (OPTIONAL)', style: labelStyle),
              const SizedBox(height: 8),
              GxButton(
                label: resumeUrl == null
                    ? 'Attach résumé'
                    : 'Résumé attached',
                icon: resumeUrl == null
                    ? Icons.attach_file_rounded
                    : Icons.check_circle_outline,
                onTap: pickResume,
                loading: uploadingResume,
                filled: false,
                accent: GixbeeTheme.accentGreen,
              ),
              if (resumeName != null) ...[
                const SizedBox(height: 6),
                Text(
                  resumeName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.gx.ink.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              GxButton(
                label: 'Send Application',
                icon: Icons.send_rounded,
                onTap: () => Navigator.pop(ctx, true),
                gradient: const [GixbeeTheme.accentGreen, Color(0xFF047857)],
                accent: GixbeeTheme.accentGreen,
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;
    try {
      final note = noteCtrl.text.trim();
      await ref.read(hiringRepositoryProvider).applyToJob(
            job.id,
            coverLetter: note.isEmpty ? null : note,
            resumeUrl: resumeUrl,
          );
      if (mounted) {
        setState(() => _appliedJobIds.add(job.id));
        _showInterestedConfirmation(job);
      }
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Failed to apply: $e', type: GxSnackType.error);
      }
    }
  }

  /// v126 "interested" screen: confirm the profile was shared and point to
  /// the tracker tab.
  void _showInterestedConfirmation(JobPost job) {
    showGxSheet<void>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Icon(Icons.check_circle_rounded,
              color: GixbeeTheme.accentGreen, size: 52),
          const SizedBox(height: 14),
          Text(
            'Profile shared with ${job.employerName ?? 'the employer'}',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w900, color: context.gx.ink),
          ),
          const SizedBox(height: 8),
          Text(
            'They can now view your profile and contact you. '
            'Track classic board applications under the Apps tab. '
            'Smart Hiring matches appear under Offers (needs Job Types).',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: context.gx.ink.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 18),
          if (widget.onOpenApplications != null) ...[
            GxButton(
              label: 'View my applications',
              accent: GixbeeTheme.accentGreen,
              gradient: const [GixbeeTheme.accentGreen, Color(0xFF047857)],
              onTap: () {
                Navigator.pop(context);
                widget.onOpenApplications!();
              },
            ),
            const SizedBox(height: 10),
          ],
          GxButton(
            label: 'Back to jobs',
            filled: widget.onOpenApplications != null ? false : true,
            accent: GixbeeTheme.accentGreen,
            gradient: widget.onOpenApplications != null
                ? null
                : const [GixbeeTheme.accentGreen, Color(0xFF047857)],
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  void _showFilterSheet() {
    var range = _payRange;
    var exp = _selectedExp;
    showGxSheet<void>(
      context,
      title: 'Filters',
      child: StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PAY RANGE',
              style: TextStyle(
                color: context.gx.ink.withValues(alpha: 0.45),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            RangeSlider(
              values: range,
              min: 0,
              max: 2000,
              divisions: 20,
              labels: RangeLabels(
                '₹${range.start.toInt()}',
                '₹${range.end.toInt()}',
              ),
              activeColor: GixbeeTheme.accentGreen,
              onChanged: (val) => setSheet(() => range = val),
            ),
            const SizedBox(height: 12),
            Text(
              'EXPERIENCE LEVEL',
              style: TextStyle(
                color: context.gx.ink.withValues(alpha: 0.45),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children:
                  ['Fresher', '1-3 Years', '3-5 Years', '5+ Years'].map((e) {
                final selected = exp == e;
                return ChoiceChip(
                  label: Text(e),
                  selected: selected,
                  selectedColor:
                      GixbeeTheme.accentGreen.withValues(alpha: 0.18),
                  onSelected: (_) =>
                      setSheet(() => exp = selected ? null : e),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GxButton(
                    label: 'Reset',
                    onTap: () {
                      setState(() {
                        _payRange = const RangeValues(0, 2000);
                        _selectedExp = null;
                      });
                      Navigator.pop(ctx);
                    },
                    filled: false,
                    accent: GixbeeTheme.accentGreen,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GxButton(
                    label: 'Apply',
                    onTap: () {
                      setState(() {
                        _payRange = range;
                        _selectedExp = exp;
                      });
                      Navigator.pop(ctx);
                    },
                    gradient: const [
                      GixbeeTheme.accentGreen,
                      GixbeeTheme.accentGreen
                    ],
                    accent: GixbeeTheme.accentGreen,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── NEUTRAL HEADER ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                GxPressable(
                  onTap: () => Navigator.pop(context),
                  child: const _RoundIconButton(
                      icon: Icons.arrow_back, semanticLabel: 'Go back'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Find a Job',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                          color: context.gx.ink,
                        ),
                      ),
                      Text(
                        '${_jobs.length} open gigs near you',
                        style: TextStyle(
                          color: context.gx.ink.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                GxPressable(
                  onTap: _showFilterSheet,
                  child: Stack(
                    children: [
                      const _RoundIconButton(
                          icon: Icons.tune_rounded, semanticLabel: 'Filters'),
                      if (_filtersActive)
                        Positioned(
                          right: 2,
                          top: 2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: GixbeeTheme.accentGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
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
                return GxPressable(
                  onTap: () => setState(() => _selectedFilter = f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected
                          ? GixbeeTheme.accentGreen.withValues(alpha: 0.16)
                          : cs.surfaceContainerHighest
                              .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected
                            ? GixbeeTheme.accentGreen.withValues(alpha: 0.5)
                            : cs.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      f,
                      style: TextStyle(
                        color: selected
                            ? GixbeeTheme.accentGreen
                            : cs.onSurface,
                        fontSize: 12.5,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // ── JOB LIST ──
          Expanded(
            child: _isLoading
                ? ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 6,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, __) => const GxSkeleton(
                        width: double.infinity, height: 150, radius: 16),
                  )
                : _filteredJobs.isEmpty
                    ? GxEmptyState(
                        icon: Icons.search_off,
                        title: 'No jobs available right now',
                        message:
                            'New openings appear here as employers post them. Pull to refresh or check back soon.',
                        accent: GixbeeTheme.accentGreen,
                        actionLabel: 'Refresh',
                        onAction: _fetchJobs,
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchJobs,
                        child: ListView.builder(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _filteredJobs.length,
                          itemBuilder: (context, i) => _JobBentoCard(
                            job: _filteredJobs[i],
                            applied: _appliedJobIds
                                .contains(_filteredJobs[i].id),
                            saved: _savedJobIds
                                .contains(_filteredJobs[i].id),
                            onApply: () =>
                                _applyToJob(_filteredJobs[i]),
                            onSave: () =>
                                _toggleSaved(_filteredJobs[i]),
                            onSkip: () => setState(() =>
                                _skippedJobIds.add(_filteredJobs[i].id)),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────
// ROUND ICON BUTTON (header)
// ─────────────────────────────────────
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String? semanticLabel;
  const _RoundIconButton({required this.icon, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final container = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface,
        shape: BoxShape.circle,
        border: Border.all(color: context.gx.border),
      ),
      child: Icon(icon, size: 19, color: context.gx.ink),
    );
    if (semanticLabel == null) return container;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: container,
    );
  }
}

// ─────────────────────────────────────
// BENTO JOB CARD — logo block · pay pill · location row
// ─────────────────────────────────────
class _JobBentoCard extends StatelessWidget {
  final JobPost job;
  final bool applied;
  final bool saved;
  final VoidCallback onApply;
  final VoidCallback onSave;
  final VoidCallback onSkip;
  const _JobBentoCard(
      {required this.job,
      required this.applied,
      required this.saved,
      required this.onApply,
      required this.onSave,
      required this.onSkip});

  String get _payLabel {
    if (job.salaryMin != null && job.salaryMax != null) {
      return '₹${job.salaryMin!.toInt()}–₹${job.salaryMax!.toInt()}';
    }
    if (job.salaryMin != null) return '₹${job.salaryMin!.toInt()}';
    return 'Competitive';
  }

  IconData get _typeIcon => switch (job.jobType) {
        'Electrician' => Icons.electrical_services,
        'Plumbing' => Icons.plumbing,
        'Cleaning' => Icons.cleaning_services,
        'Painting' => Icons.format_paint,
        'Tech' => Icons.computer,
        'Events' => Icons.celebration,
        _ => Icons.work_outline,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GxPressable(
      onTap: applied ? null : onApply,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top: logo block + title/employer + type badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: GixbeeTheme.accentGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_typeIcon,
                      color: GixbeeTheme.accentGreen, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        job.employerName ?? 'Business Owner',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: GixbeeTheme.accentGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    job.jobType.toUpperCase(),
                    style: const TextStyle(
                      color: GixbeeTheme.accentGreen,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

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

            // Location row
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 13, color: GixbeeTheme.accentGreen),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    job.location.isEmpty ? 'Kochi' : job.location,
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.schedule,
                    size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  job.createdAt != null
                      ? DateFormat.yMMMd().format(job.createdAt!)
                      : '',
                  style:
                      TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(
                height: 1,
                thickness: 1,
                color: cs.outlineVariant.withValues(alpha: 0.15),
              ),
            ),

            // Bottom: pay pill + experience + apply
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: GixbeeTheme.accentGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _payLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: GixbeeTheme.accentGreen,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    job.experience,
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // v126 alert actions: Later (persisted bookmark) + Skip
                // (session hide) beside the primary Interested action.
                Semantics(
                  button: true,
                  label: saved ? 'Remove from saved' : 'Save for later',
                  child: GxPressable(
                    onTap: onSave,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        saved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_outline_rounded,
                        size: 20,
                        color: saved
                            ? GixbeeTheme.accentGreen
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                if (!applied)
                  Semantics(
                    button: true,
                    label: 'Skip this job',
                    child: GxPressable(
                      onTap: onSkip,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.close_rounded,
                            size: 20, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                applied
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color:
                                  Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle,
                                size: 15, color: Colors.green),
                            SizedBox(width: 5),
                            Text('Applied',
                                style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12)),
                          ],
                        ),
                      )
                    : GxButton(
                        label: 'Interested',
                        icon: Icons.send_rounded,
                        onTap: onApply,
                        gradient: const [
                          GixbeeTheme.accentGreen,
                          GixbeeTheme.accentGreen
                        ],
                        accent: GixbeeTheme.accentGreen,
                        expand: false,
                        height: 40,
                        radius: 999,
                        fontSize: 12,
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
