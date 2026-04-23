import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/hiring_repository.dart';
import '../../shared/models/job_post.dart';
import 'package:intl/intl.dart';

/// Tracks the user's job applications across different statuses.
class ApplicationTrackerScreen extends ConsumerStatefulWidget {
  const ApplicationTrackerScreen({super.key});

  @override
  ConsumerState<ApplicationTrackerScreen> createState() => _ApplicationTrackerScreenState();
}

class _ApplicationTrackerScreenState extends ConsumerState<ApplicationTrackerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<JobApplication> _applications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchApplications();
  }

  Future<void> _fetchApplications() async {
    try {
      final apps = await ref.read(hiringRepositoryProvider).getMyApplications();
      if (mounted) {
        setState(() {
          _applications = apps;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading applications: $e')));
      }
    }
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
          // ── HEADER ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'My Applications',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
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
                  color: Colors.orange,
                ),
                _StatBubble(
                  label: 'Interview',
                  count: _filter(ApplicationStatus.interview).length,
                  color: const Color(0xFF54A0FF),
                ),
                _StatBubble(
                  label: 'Selected',
                  count: _filter(ApplicationStatus.selected).length,
                  color: Colors.green,
                ),
                _StatBubble(
                  label: 'Total',
                  count: _applications.length,
                  color: cs.primary,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── TABS ──
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: cs.primary,
            labelPadding: const EdgeInsets.symmetric(horizontal: 16),
            tabs: const [
              Tab(text: 'All'),
              Tab(text: 'Active'),
              Tab(text: 'Completed'),
              Tab(text: 'Rejected'),
            ],
          ),

          // ── APP LIST ──
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _AppList(apps: _applications),
                    _AppList(apps: _applications.where((a) =>
                        a.status == ApplicationStatus.applied ||
                        a.status == ApplicationStatus.interview ||
                        a.status == ApplicationStatus.selected).toList()),
                    _AppList(apps: _filter(ApplicationStatus.selected)),
                    _AppList(apps: _filter(ApplicationStatus.rejected)),
                  ],
                ),
          ),
        ],
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
          borderRadius: BorderRadius.circular(12),
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────
// APPLICATION LIST
// ─────────────────────────────────────
class _AppList extends StatelessWidget {
  final List<JobApplication> apps;
  const _AppList({required this.apps});

  @override
  Widget build(BuildContext context) {
    if (apps.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 48,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text('No applications here',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: apps.length,
      itemBuilder: (context, i) => _ApplicationCard(app: apps[i]),
    );
  }
}

// ─────────────────────────────────────
// APPLICATION CARD
// ─────────────────────────────────────
class _ApplicationCard extends StatelessWidget {
  final JobApplication app;
  const _ApplicationCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (statusLabel, statusColor) = switch (app.status) {
      ApplicationStatus.applied => ('Applied', Colors.orange),
      ApplicationStatus.interview => ('Interview', const Color(0xFF54A0FF)),
      ApplicationStatus.selected => ('Selected', Colors.green),
      ApplicationStatus.rejected => ('Rejected', Colors.red),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
          // Title + status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  app.jobPost.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Meta
          Row(
            children: [
              Icon(Icons.person_outline, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(app.jobPost.employerName ?? 'Business Owner',
                  style:
                      TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
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
          const SizedBox(height: 8),

          // Pay + date
          Row(
            children: [
              Text(
                app.jobPost.salaryMin != null ? '₹${app.jobPost.salaryMin}' : 'Competitive Pay',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                'Applied ${app.createdAt != null ? DateFormat.yMMMd().format(app.createdAt!) : ''}',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
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
                borderRadius: BorderRadius.circular(8),
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
          if (app.status == ApplicationStatus.interview ||
              app.status == ApplicationStatus.selected) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (app.status == ApplicationStatus.selected)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.chat_outlined, size: 16),
                      label: const Text('Message',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                if (app.status == ApplicationStatus.interview) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {},
                      child: const Text('Withdraw',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.phone_outlined, size: 16),
                      label: const Text('Call',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

