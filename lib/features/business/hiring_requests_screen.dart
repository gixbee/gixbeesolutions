import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../repositories/matching_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_empty.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import '../jobs/hiring_progress_screen.dart';
import '../jobs/hiring_flow.dart';
import '../jobs/pending_payments_screen.dart';
import '../messages/chat_thread_screen.dart';
import 'hiring_location_pay.dart';

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
                'Matching recommends people both ways. Invite to chat, or wait for Interested — phone stays locked until they share.',
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
                        '${d['jobStatus'] ?? status}'.replaceAll('_', ' '),
                        '${d['interestedCount'] ?? 0} interested',
                        '${d['notifiedCount'] ?? 0} recommended',
                        '₹${d['salaryOffered']}/mo',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 13,
                        color: context.gx.ink.withValues(alpha: 0.55),
                      ),
                    ),
                    if (status == 'COLLECTING' ||
                        status == 'DELIVERED' ||
                        status == 'GUARANTEE_FAILED' ||
                        status == 'RESOLVED_CREDIT' ||
                        status == 'RESOLVED_REFUND') ...[
                      const SizedBox(height: 14),
                      GxButton(
                        label: 'Close this job',
                        filled: false,
                        accent: GixbeeTheme.brandRed,
                        onTap: () async {
                          try {
                            await ref
                                .read(matchingRepositoryProvider)
                                .closeRequest(widget.requestId);
                            if (mounted) _load();
                          } on DioException catch (e) {
                            if (!context.mounted) return;
                            showGxSnack(
                              context,
                              '${e.response?.data is Map ? e.response!.data['message'] : e.message}',
                              type: GxSnackType.error,
                            );
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      'Recommended candidates',
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
                              ? 'Matching nearby profiles… check back soon.'
                              : 'No recommended candidates on this job.',
                          style: TextStyle(
                            color: context.gx.ink.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    else
                      for (final c in candidates)
                        _CandidateCard(
                          candidate: Map<String, dynamic>.from(c as Map),
                          jobClosed: d['jobStatus'] == 'CLOSED' ||
                              d['filled'] == true,
                          onDecision: _setDecision,
                          onInvite: (id) async {
                            await ref
                                .read(matchingRepositoryProvider)
                                .updateApplication(id, 'invite', {});
                            if (mounted) _load();
                          },
                          onRequestContact: (id) async {
                            await ref
                                .read(matchingRepositoryProvider)
                                .updateApplication(id, 'request-contact', {});
                            if (mounted) _load();
                          },
                          onView: (id) {
                            unawaited(ref
                                .read(matchingRepositoryProvider)
                                .updateApplication(id, 'view', {}));
                          },
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
  final bool jobClosed;
  final Future<void> Function(String interestId, String decision) onDecision;
  final Future<void> Function(String interestId) onInvite;
  final Future<void> Function(String interestId) onRequestContact;
  final void Function(String interestId) onView;

  const _CandidateCard({
    required this.candidate,
    required this.jobClosed,
    required this.onDecision,
    required this.onInvite,
    required this.onRequestContact,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final decision = candidate['decision']?.toString() ?? 'PENDING';
    final response = candidate['response']?.toString() ?? 'PENDING';
    final interestId = candidate['interestId']?.toString() ?? '';
    final candidateId = candidate['candidateId']?.toString() ?? '';
    final phone = candidate['phone']?.toString();
    final invited = candidate['invited'] == true;
    final canChat = hiringCanChat(response: response, decision: decision);
    final stage = hiringPipelineLabel(
      response: response,
      decision: decision,
      progress: {
        'invited': invited,
        'stage': candidate['pipelineStage'],
        'contactShared': candidate['contactShared'] == true,
      },
    );
    final reasons = (candidate['matchReasons'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];

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
                    stage,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: decision == 'HIRED'
                          ? GixbeeTheme.accentGreen
                          : decision == 'SHORTLISTED' || canChat
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
                    '₹${candidate['expectedSalary']}/${hiringSalaryUnitLabel(candidate['expectedSalaryPeriod']?.toString() ?? 'MONTHLY')}',
                  if (candidate['experienceYears'] != null)
                    '${candidate['experienceYears']} yrs',
                  if (candidate['availableOn'] != null)
                    'Available ${candidate['availableOn']}'
                  else if (candidate['noticePeriod'] != null)
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
              if (candidate['bio'] case final String bio when bio.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(bio),
              ],
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
              if (reasons.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Why they match: ${reasons.join(' · ')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.gx.ink.withValues(alpha: 0.55),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                phone != null && phone.isNotEmpty
                    ? 'Phone: $phone'
                    : 'Phone locked  ·  Email locked',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: phone != null && phone.isNotEmpty
                      ? GixbeeTheme.accentBlue
                      : context.gx.ink.withValues(alpha: 0.45),
                ),
              ),
              if (response == 'PENDING' && !jobClosed) ...[
                const SizedBox(height: 12),
                GxButton(
                  label: invited ? 'Invite sent' : 'Invite to Chat',
                  accent: GixbeeTheme.brandOrange,
                  onTap: invited
                      ? null
                      : () {
                          onView(interestId);
                          onInvite(interestId);
                        },
                ),
              ],
              if (canChat) ...[
                if (!jobClosed) ...[
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
                          label: decision == 'SHORTLISTED'
                              ? 'Shortlisted'
                              : 'Shortlist',
                          accent: GixbeeTheme.accentBlue,
                          onTap: decision == 'SHORTLISTED'
                              ? null
                              : () => onDecision(interestId, 'SHORTLISTED'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                GxButton(
                  label: 'Open chat',
                  filled: false,
                  accent: GixbeeTheme.accentGreen,
                  onTap: candidateId.isEmpty
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatThreadScreen(
                                otherUserId: candidateId,
                                otherUserName:
                                    '${candidate['name'] ?? 'Candidate'}',
                              ),
                            ),
                          ),
                ),
                if (candidate['contactShared'] != true) ...[
                  const SizedBox(height: 8),
                  GxButton(
                    label: candidate['contactRequested'] == true
                        ? 'Contact requested'
                        : 'Request contact',
                    filled: false,
                    accent: GixbeeTheme.accentBlue,
                    onTap: candidate['contactRequested'] == true
                        ? null
                        : () => onRequestContact(interestId),
                  ),
                ],
              ],
              if (decision == 'SHORTLISTED' || decision == 'HIRED') ...[
                const SizedBox(height: 8),
                GxButton(
                  label: 'Interview, offer & joining',
                  accent: GixbeeTheme.accentGreen,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          HiringProgressScreen(interestId: interestId),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
