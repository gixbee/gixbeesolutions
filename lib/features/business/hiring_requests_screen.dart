import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../repositories/matching_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_empty.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import '../jobs/hiring_progress_screen.dart';
import '../jobs/pending_payments_screen.dart';

/// Employer's Smart Hiring requests list.
class HiringRequestsScreen extends ConsumerStatefulWidget {
  const HiringRequestsScreen({super.key, this.businessId});
  final String? businessId;

  @override
  ConsumerState<HiringRequestsScreen> createState() =>
      _HiringRequestsScreenState();
}

class _HiringRequestsScreenState extends ConsumerState<HiringRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(matchingRepositoryProvider).listRequests(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _requests = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showGxSnack(context, 'Could not load requests: $e',
          type: GxSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gx.bg,
      appBar: AppBar(title: const Text('Hiring requests'), actions: [IconButton(tooltip: 'Pending payments', icon: const Icon(Icons.receipt_long),
        onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const PendingPaymentsScreen())); if (mounted) _load(); })]),
      body: DribbbleBackground(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Candidates come from Find a Job → Job Types. '
                'Interested seekers appear here for shortlist / hire — their Offers tab shows your decision.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: context.gx.ink.withValues(alpha: 0.55),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _requests.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 100),
                                GxEmptyState(
                                  icon: Icons.work_outline,
                                  title: 'No hiring requests',
                                  message:
                                      'Start Hire Employee to run a 24 h Smart Match against Find a Job Job Types.',
                                  accent: GixbeeTheme.accentBlue,
                                ),
                              ],
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 40),
                              itemCount: _requests.length,
                              itemBuilder: (_, i) {
                                final r = _requests[i];
                                final status = '${r['status'] ?? ''}';
                                final interested = r['interestedCount'] ?? 0;
                          final deadline = DateTime.tryParse(
                              r['deadlineAt']?.toString() ?? '');
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Material(
                              color: context.gx.card,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => HiringRequestDetailScreen(
                                        requestId: r['id'].toString(),
                                      ),
                                    ),
                                  );
                                  _load();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${r['jobType'] ?? ''}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16,
                                                color: context.gx.ink,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            status.replaceAll('_', ' '),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: status == 'DELIVERED'
                                                  ? GixbeeTheme.accentGreen
                                                  : status ==
                                                          'GUARANTEE_FAILED'
                                                      ? GixbeeTheme.brandRed
                                                      : GixbeeTheme.accentBlue,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        [
                                          '$interested interested',
                                          'target ${r['targetInterested'] ?? ''}',
                                          if (deadline != null)
                                            'until ${DateFormat.MMMd().add_jm().format(deadline.toLocal())}',
                                        ].join(' · '),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: context.gx.ink
                                              .withValues(alpha: 0.55),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class HiringRequestDetailScreen extends ConsumerStatefulWidget {
  final String requestId;

  const HiringRequestDetailScreen({super.key, required this.requestId});

  @override
  ConsumerState<HiringRequestDetailScreen> createState() =>
      _HiringRequestDetailScreenState();
}

class _HiringRequestDetailScreenState
    extends ConsumerState<HiringRequestDetailScreen> {
  Map<String, dynamic>? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await ref
          .read(matchingRepositoryProvider)
          .getRequestDetail(widget.requestId);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showGxSnack(context, 'Could not load: $e', type: GxSnackType.error);
    }
  }

  Future<void> _setDecision(String interestId, String decision) async {
    try {
      await ref.read(matchingRepositoryProvider).setDecision(
            interestId,
            decision: decision,
          );
      if (!mounted) return;
      showGxSnack(context, 'Updated: $decision', type: GxSnackType.success);
      _load();
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message']?.toString() ?? e.message)
          : e.message;
      if (!mounted) return;
      showGxSnack(context, msg ?? 'Update failed', type: GxSnackType.error);
    }
  }

  Future<void> _resolve(String choice) async {
    try {
      await ref.read(matchingRepositoryProvider).resolveGuarantee(
            widget.requestId,
            choice: choice,
          );
      if (!mounted) return;
      showGxSnack(
        context,
        choice == 'CREDIT'
            ? 'Gixbee Credit added for your next hire'
            : 'Refund requested',
        type: GxSnackType.success,
      );
      _load();
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message']?.toString() ?? e.message)
          : e.message;
      if (!mounted) return;
      showGxSnack(context, msg ?? 'Could not resolve',
          type: GxSnackType.error);
    }
  }

  Future<void> _showGuaranteeSheet() async {
    final choice = await showGxSheet<String>(
      context,
      title: 'Hiring guarantee',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'We couldn\'t deliver the minimum interested candidates in 24 hours. Choose a remedy:',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: context.gx.ink.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 16),
          GxButton(
            label: 'Gixbee Credit (instant)',
            accent: GixbeeTheme.accentBlue,
            onTap: () => Navigator.pop(context, 'CREDIT'),
          ),
          const SizedBox(height: 10),
          GxButton(
            label: 'Full refund',
            filled: false,
            accent: GixbeeTheme.accentBlue,
            onTap: () => Navigator.pop(context, 'REFUND'),
          ),
        ],
      ),
    );
    if (choice != null) await _resolve(choice);
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final status = d?['status']?.toString() ?? '';
    final candidates = (d?['candidates'] as List?) ?? [];

    return Scaffold(
      backgroundColor: context.gx.bg,
      appBar: AppBar(
        title: Text(d?['jobType']?.toString() ?? 'Shortlist'),
      ),
      body: DribbbleBackground(
        child: _loading || d == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  children: [
                    Text(
                      [
                        status.replaceAll('_', ' '),
                        '${d['interestedCount'] ?? 0} interested',
                        '${d['notifiedCount'] ?? 0} notified',
                        '₹${d['salaryOffered']}/mo',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 13,
                        color: context.gx.ink.withValues(alpha: 0.55),
                      ),
                    ),
                    if (status == 'GUARANTEE_FAILED' && d['refundStatus'] != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        d['refundStatus'] == 'failed'
                            ? 'The refund could not be completed. Contact support with this hiring request.'
                            : 'Your refund is being processed. Pull down to check its status.',
                        style: TextStyle(color: context.gx.ink),
                      ),
                    ] else if (status == 'GUARANTEE_FAILED') ...[
                      const SizedBox(height: 14),
                      GxButton(
                        label: 'Choose credit or refund',
                        accent: GixbeeTheme.brandRed,
                        onTap: _showGuaranteeSheet,
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      'Interested candidates',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: context.gx.ink,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (candidates.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text(
                          status == 'COLLECTING'
                              ? 'Collecting interest… check back soon.'
                              : 'No interested candidates on this request.',
                          style: TextStyle(
                            color: context.gx.ink.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    else
                      for (final c in candidates)
                        _CandidateCard(
                          candidate: Map<String, dynamic>.from(c as Map),
                          onDecision: _setDecision,
                        ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final Map<String, dynamic> candidate;
  final Future<void> Function(String interestId, String decision) onDecision;

  const _CandidateCard({
    required this.candidate,
    required this.onDecision,
  });

  @override
  Widget build(BuildContext context) {
    final decision = candidate['decision']?.toString() ?? 'PENDING';
    final interestId = candidate['interestId']?.toString() ?? '';
    final phone = candidate['phone']?.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: context.gx.card,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${candidate['name'] ?? 'Candidate'}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: context.gx.ink,
                      ),
                    ),
                  ),
                  Text(
                    decision,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: decision == 'HIRED'
                          ? GixbeeTheme.accentGreen
                          : decision == 'SHORTLISTED'
                              ? GixbeeTheme.accentBlue
                              : context.gx.ink.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (candidate['expectedSalary'] != null)
                    '₹${candidate['expectedSalary']}/mo',
                  if (candidate['experienceYears'] != null)
                    '${candidate['experienceYears']} yrs',
                  if (candidate['noticePeriod'] != null)
                    '${candidate['noticePeriod']}',
                  if ((candidate['preferredLocation'] ?? '')
                      .toString()
                      .isNotEmpty)
                    '${candidate['preferredLocation']}',
                ].join(' · '),
                style: TextStyle(
                  fontSize: 12,
                  color: context.gx.ink.withValues(alpha: 0.55),
                ),
              ),
              if ((candidate['skills'] as List?)?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(
                  (candidate['skills'] as List).join(', '),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.gx.ink.withValues(alpha: 0.5),
                  ),
                ),
              ],
              if (phone != null && phone.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Phone: $phone',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: GixbeeTheme.accentBlue,
                    )),
              ],
              if (decision == 'PENDING') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GxButton(
                        label: 'Reject',
                        filled: false,
                        accent: GixbeeTheme.accentBlue,
                        onTap: () => onDecision(interestId, 'REJECTED'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GxButton(
                        label: 'Shortlist',
                        accent: GixbeeTheme.accentBlue,
                        onTap: () => onDecision(interestId, 'SHORTLISTED'),
                      ),
                    ),
                  ],
                ),
              ],
              if (decision != 'PENDING') ...[
                const SizedBox(height: 10),
                GxButton(
                  label: 'Interview, offer & joining',
                  accent: GixbeeTheme.accentGreen,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => HiringProgressScreen(interestId: interestId))),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
