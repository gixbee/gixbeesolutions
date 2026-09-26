import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../repositories/hiring_repository.dart';
import '../../shared/models/job_post.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../../shared/widgets/gx_empty.dart';
import '../../theme.dart';
import '../messages/chat_thread_screen.dart';

/// Tracks the user's job applications across statuses (mockup "job" tab 2).
/// Gixbee 2026 reskin: neutral header, segmented pill tabs, tracker cards
/// with status progress dots, withdraw via glass sheet.
class ApplicationTrackerScreen extends ConsumerStatefulWidget {
  const ApplicationTrackerScreen({super.key, this.focusApplicationId});

  /// When set (e.g. from Activity), scrolls to that application on the All tab.
  final String? focusApplicationId;

  @override
  ConsumerState<ApplicationTrackerScreen> createState() =>
      _ApplicationTrackerScreenState();
}

class _ApplicationTrackerScreenState
    extends ConsumerState<ApplicationTrackerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _segments = ['All', 'Active', 'Hired', 'Closed'];

  List<JobApplication> _applications = [];
  bool _isLoading = true;
  bool _focusApplicationPending = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {}); // keep segmented pills in sync w/ swipe
    });
    _fetchApplications();
  }

  Future<void> _fetchApplications() async {
    try {
      final apps =
          await ref.read(hiringRepositoryProvider).getMyApplications();
      if (mounted) {
        setState(() {
          _applications = apps;
          _isLoading = false;
        });
        _openFocusedApplication();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showGxSnack(context, 'Error loading applications: $e',
            type: GxSnackType.error);
      }
    }
  }

  void _openFocusedApplication() {
    final id = widget.focusApplicationId?.trim();
    if (id == null || id.isEmpty || !_focusApplicationPending) return;
    JobApplication? app;
    for (final a in _applications) {
      if (a.id == id) {
        app = a;
        break;
      }
    }
    if (app == null) return;
    _focusApplicationPending = false;
    final focused = app;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showApplicationDetail(focused);
    });
  }

  Future<void> _showApplicationDetail(JobApplication app) {
    return showGxSheet<void>(
      context,
      title: app.jobPost.title,
      child: _ApplicationCard(
        app: app,
        onWithdraw: () async {
          Navigator.pop(context);
          await _withdraw(app);
        },
        onMessage: () {
          Navigator.pop(context);
          _openChat(app);
        },
      ),
    );
  }

  Future<void> _withdraw(JobApplication app) async {
    final confirmed = await showGxSheet<bool>(
      context,
      title: 'Withdraw application?',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You will no longer be considered for '
            '"${app.jobPost.title}". This cannot be undone.',
            style: TextStyle(
              color: context.gx.ink.withValues(alpha: 0.65),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: GxButton(
                  label: 'Keep it',
                  onTap: () => Navigator.pop(context, false),
                  filled: false,
                  accent: GixbeeTheme.accentGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GxButton(
                  label: 'Withdraw',
                  onTap: () => Navigator.pop(context, true),
                  gradient: const [GixbeeTheme.brandRed, GixbeeTheme.brandRed],
                  accent: GixbeeTheme.brandRed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(hiringRepositoryProvider).withdrawApplication(app.id);
      await _fetchApplications();
      if (mounted) {
        showGxSnack(context, 'Application withdrawn',
            type: GxSnackType.success);
      }
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Failed to withdraw: $e',
            type: GxSnackType.error);
      }
    }
  }

  void _openChat(JobApplication app) {
    final employerId = app.jobPost.employerId;
    if (employerId.isEmpty) {
      showGxSnack(context, 'Employer contact unavailable');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          otherUserId: employerId,
          otherUserName: app.jobPost.employerName ?? 'Employer',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<JobApplication> _filter(ApplicationStatus? status) {
    if (status == null) return _applications;
    return _applications.where((a) => a.status == status).toList();
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
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: GixbeeTheme.accentGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.assignment_outlined,
                      color: GixbeeTheme.accentGreen, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'My Applications',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                        ),
                      ),
                      Text(
                        'Track applications you send from Jobs.',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── STATS ROW ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _StatBubble(
                  label: 'Applied',
                  count: _filter(ApplicationStatus.applied).length,
                  color: GixbeeTheme.accentGreen,
                ),
                _StatBubble(
                  label: 'Interview',
                  count: _filter(ApplicationStatus.interview).length,
                  color: GixbeeTheme.accentGreen,
                ),
                _StatBubble(
                  label: 'Hired',
                  count: _filter(ApplicationStatus.selected).length,
                  color: GixbeeTheme.accentGreen,
                ),
                _StatBubble(
                  label: 'Total',
                  count: _applications.length,
                  color: GixbeeTheme.brandRed,
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── SEGMENTED PILL TABS ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: List.generate(_segments.length, (i) {
                  final selected = _tabController.index == i;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _tabController.animateTo(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          gradient: selected
                              ? const LinearGradient(
                                  colors: [
                                    GixbeeTheme.accentGreen,
                                    GixbeeTheme.accentGreenDark,
                                  ])
                              : null,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _segments[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: selected
                                ? context.gx.onAccent
                                : cs.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          const SizedBox(height: 4),

          // ── APP LIST ──
          Expanded(
            child: _isLoading
                ? ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 5,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 12),
                    itemBuilder: (_, __) => const GxSkeleton(
                        width: double.infinity,
                        height: 140,
                        radius: 16),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildList(_applications),
                      _buildList(_applications
                          .where((a) =>
                              a.status == ApplicationStatus.applied ||
                              a.status == ApplicationStatus.interview)
                          .toList()),
                      _buildList(_filter(ApplicationStatus.selected)),
                      _buildList(_applications
                          .where((a) =>
                              a.status == ApplicationStatus.rejected ||
                              a.status == ApplicationStatus.withdrawn ||
                              a.status == ApplicationStatus.noShow)
                          .toList()),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<JobApplication> apps) {
    if (apps.isEmpty) {
      return const GxEmptyState(
        icon: Icons.inbox_outlined,
        title: 'No applications here',
        message:
            'Jobs you show interest in will show up here so you can track their status.',
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchApplications,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        itemCount: apps.length,
        itemBuilder: (context, i) {
          final app = apps[i];
          return _ApplicationCard(
            app: app,
            onWithdraw: () => _withdraw(app),
            onMessage: () => _openChat(app),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────
// STAT BUBBLE
// ─────────────────────────────────────
class _StatBubble extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatBubble(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: color,
              ),
            ),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────
// PROGRESS DOTS — Applied → Interview → Selected
// ─────────────────────────────────────
class _ProgressDots extends StatelessWidget {
  final int step; // 0 = applied, 1 = interview, 2 = selected
  const _ProgressDots({required this.step});

  static const _labels = ['Applied', 'Interview', 'Hired'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_labels.length * 2 - 1, (i) {
        if (i.isOdd) {
          // connector line (top margin centers it on the 10px dots)
          final done = (i ~/ 2) < step;
          return Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              color: done
                  ? GixbeeTheme.accentGreen.withValues(alpha: 0.7)
                  : cs.outlineVariant.withValues(alpha: 0.25),
            ),
          );
        }
        final idx = i ~/ 2;
        final reached = idx <= step;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: reached
                    ? GixbeeTheme.accentGreen
                    : cs.surfaceContainerHighest,
                border: Border.all(
                  color: reached
                      ? GixbeeTheme.accentGreen
                      : cs.outlineVariant.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _labels[idx],
              style: TextStyle(
                fontSize: 9,
                fontWeight:
                    reached ? FontWeight.w700 : FontWeight.w500,
                color: reached
                    ? GixbeeTheme.accentGreen
                    : cs.onSurfaceVariant,
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ─────────────────────────────────────
// APPLICATION CARD — tracker w/ progress dots
// ─────────────────────────────────────
class _ApplicationCard extends StatelessWidget {
  final JobApplication app;
  final VoidCallback onWithdraw;
  final VoidCallback onMessage;
  const _ApplicationCard({
    required this.app,
    required this.onWithdraw,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (statusLabel, statusColor) = switch (app.status) {
      ApplicationStatus.applied => ('Applied', GixbeeTheme.accentGold),
      ApplicationStatus.interview => ('Interview', GixbeeTheme.accentBlue),
      ApplicationStatus.selected => ('Hired', GixbeeTheme.accentGreen),
      ApplicationStatus.rejected => ('Not Selected', GixbeeTheme.brandRed),
      ApplicationStatus.withdrawn => ('Withdrawn', GixbeeTheme.textMed),
      ApplicationStatus.noShow => ('No-show', GixbeeTheme.brandRed),
    };
    final progressStep = switch (app.status) {
      ApplicationStatus.applied => 0,
      ApplicationStatus.interview => 1,
      ApplicationStatus.selected => 2,
      _ => -1, // rejected/withdrawn → no dots
    };

    return GxPressable(
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
            // Title + status chip
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    app.jobPost.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Meta
            Row(
              children: [
                Icon(Icons.person_outline,
                    size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(app.jobPost.employerName ?? 'Business Owner',
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 12)),
                const SizedBox(width: 12),
                Icon(Icons.location_on_outlined,
                    size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(app.jobPost.location,
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),

            // Progress dots (active pipeline only)
            if (progressStep >= 0) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _ProgressDots(step: progressStep),
              ),
            ],
            const SizedBox(height: 12),

            // Pay + date
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: GixbeeTheme.accentGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    app.jobPost.salaryMin != null
                        ? '₹${app.jobPost.salaryMin!.toInt()}'
                        : 'Competitive',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: GixbeeTheme.accentGreen,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Applied ${app.createdAt != null ? DateFormat.yMMMd().format(app.createdAt!) : ''}',
                  style:
                      TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                ),
              ],
            ),

            // Note (if present)
            if (app.coverLetter != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: statusColor.withValues(alpha: 0.06),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: statusColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        app.coverLetter!,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Action buttons for active applications
            if (app.status == ApplicationStatus.applied ||
                app.status == ApplicationStatus.interview ||
                app.status == ApplicationStatus.selected) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (app.status != ApplicationStatus.selected) ...[
                    Expanded(
                      child: GxButton(
                        label: 'Withdraw',
                        onTap: onWithdraw,
                        filled: false,
                        accent: GixbeeTheme.accentGreen,
                        height: 44,
                        radius: 12,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: GxButton(
                      label: 'Message',
                      icon: Icons.chat_outlined,
                      onTap: onMessage,
                      gradient: const [
                        GixbeeTheme.accentGreen,
                        GixbeeTheme.accentGreen
                      ],
                      accent: GixbeeTheme.accentGreen,
                      height: 44,
                      radius: 12,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
