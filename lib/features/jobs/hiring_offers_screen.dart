import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'hiring_progress_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../repositories/matching_repository.dart';
import 'hiring_catalog.dart';
import 'hiring_flow.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_empty.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import '../messages/chat_thread_screen.dart';

/// Smart Hiring alerts — Interested / Not Interested + employer decisions.
/// Counterpart to List My Business → Hire Employee matching.
class HiringOffersScreen extends ConsumerStatefulWidget {
  /// Jump to Profiles tab — required before employers can match you.
  final VoidCallback? onGoToProfiles;

  const HiringOffersScreen({super.key, this.onGoToProfiles});

  @override
  ConsumerState<HiringOffersScreen> createState() => _HiringOffersScreenState();
}

class _HiringOffersScreenState extends ConsumerState<HiringOffersScreen> {
  List<Map<String, dynamic>> _offers = [];
  bool _loading = true;
  String _filter = 'All';
  int _prefCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(matchingRepositoryProvider);
      final list = await repo.listOffers();
      var prefs = <Map<String, dynamic>>[];
      try {
        prefs = await repo.listPreferences();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _offers = list;
        _prefCount = prefs.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showGxSnack(context, 'Could not load offers: $e',
          type: GxSnackType.error);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    switch (_filter) {
      case 'Open':
        return _offers.where((o) => o['open'] == true).toList();
      case 'Interested':
        return _offers
            .where((o) => o['response'] == 'INTERESTED')
            .toList();
      case 'Closed':
        return _offers
            .where((o) =>
                o['response'] == 'NOT_INTERESTED' ||
                o['decision'] == 'REJECTED' ||
                o['decision'] == 'HIRED')
            .toList();
      default:
        return _offers;
    }
  }

  Future<void> _respond(Map<String, dynamic> offer, bool interested) async {
    final requestId = offer['requestId']?.toString();
    if (requestId == null) return;
    try {
      await ref.read(matchingRepositoryProvider).respondToOffer(
            requestId,
            interested: interested,
          );
      if (!mounted) return;
      showGxSnack(
        context,
        interested ? 'Marked Interested' : 'Marked Not Interested',
        type: GxSnackType.success,
      );
      _load();
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message']?.toString() ?? e.message)
          : e.message;
      if (!mounted) return;
      showGxSnack(context, msg ?? 'Could not respond',
          type: GxSnackType.error);
    }
  }

  Future<void> _progressAction(Map<String, dynamic> offer, String action) async {
    final interestId = offer['id']?.toString();
    if (interestId == null || interestId.isEmpty) return;
    try {
      await ref
          .read(matchingRepositoryProvider)
          .updateApplication(interestId, action, {});
      if (!mounted) return;
      showGxSnack(context, 'Updated', type: GxSnackType.success);
      _load();
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message']?.toString() ?? e.message)
          : e.message;
      if (!mounted) return;
      showGxSnack(context, msg ?? 'Could not update', type: GxSnackType.error);
    }
  }

  String _statusLabel(Map<String, dynamic> o) {
    return hiringPipelineLabel(
      response: o['response']?.toString() ?? 'PENDING',
      decision: o['decision']?.toString() ?? 'PENDING',
      progress: {
        'invited': o['invited'] == true,
        'stage': o['pipelineStage'],
        'contactShared': o['contactShared'] == true,
      },
    ).replaceAll('_', ' ');
  }

  Color _statusColor(Map<String, dynamic> o) {
    final d = o['decision']?.toString();
    if (d == 'HIRED') return GixbeeTheme.accentGreen;
    if (d == 'SHORTLISTED') return GixbeeTheme.accentBlue;
    if (d == 'REJECTED') return GixbeeTheme.brandRed;
    if (o['open'] == true) return GixbeeTheme.brandOrange;
    return context.gx.ink.withValues(alpha: 0.45);
  }

  @override
  Widget build(BuildContext context) {
    final catalog =
        ref.watch(hiringCatalogProvider).value ?? HiringCatalog.fallback;
    final filters = ['All', 'Open', 'Interested', 'Closed'];
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Alerts',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: context.gx.ink,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Smart matches from employers using Hire Employee. '
              'Invite to Chat or mark Interested to open in-app chat. '
              'Phone stays locked until you share it.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: context.gx.ink.withValues(alpha: 0.55),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _filtered.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 80),
                              GxEmptyState(
                                icon: Icons.notifications_active_outlined,
                                title: _prefCount == 0
                                    ? 'Add a Profile first'
                                    : 'No alerts yet',
                                message: _prefCount == 0
                                    ? 'Employers using Hire Employee match against your career profiles. Add one on the Profiles tab to receive alerts here.'
                                    : 'When a verified employer runs Smart Hiring for your profiles, alerts appear here.',
                                actionLabel: _prefCount == 0 &&
                                        widget.onGoToProfiles != null
                                    ? 'Go to Profiles'
                                    : null,
                                onAction: _prefCount == 0
                                    ? widget.onGoToProfiles
                                    : null,
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) {
                              final o = _filtered[i];
                              final salaryLine = formatOfferSalary(o);
                              final empLabel = catalog
                                  .labelForCode(o['employmentType']?.toString());
                              final notified = DateTime.tryParse(
                                  o['notifiedAt']?.toString() ?? '');
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Material(
                                  color: context.gx.card,
                                  borderRadius: BorderRadius.circular(16),
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
                                                '${o['jobType'] ?? 'Opening'}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16,
                                                  color: context.gx.ink,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              _statusLabel(o),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: _statusColor(o),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          [
                                            if ((o['businessName'] ?? '')
                                                .toString()
                                                .isNotEmpty)
                                              '${o['businessName']}',
                                            if (empLabel.isNotEmpty) empLabel,
                                            if (salaryLine.isNotEmpty) salaryLine,
                                            if ((o['location'] ?? '')
                                                .toString()
                                                .isNotEmpty)
                                              '${o['location']}',
                                            if (notified != null)
                                              DateFormat.MMMd()
                                                  .add_jm()
                                                  .format(notified.toLocal()),
                                          ].where((s) => s.isNotEmpty).join(' · '),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: context.gx.ink
                                                .withValues(alpha: 0.55),
                                          ),
                                        ),
                                        if ((o['skills'] as List?)
                                                ?.isNotEmpty ==
                                            true) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            (o['skills'] as List).join(', '),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: context.gx.ink
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
                                        ],
                                        if (o['invited'] == true &&
                                            o['response'] == 'PENDING') ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            'This employer invited you to chat.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: context.gx.ink
                                                  .withValues(alpha: 0.6),
                                            ),
                                          ),
                                        ],
                                        if (hiringCanChat(
                                          response:
                                              o['response']?.toString() ??
                                                  'PENDING',
                                          decision:
                                              o['decision']?.toString() ??
                                                  'PENDING',
                                        )) ...[
                                          const SizedBox(height: 12),
                                          GxButton(
                                            label: 'Open chat',
                                            filled: false,
                                            accent: GixbeeTheme.accentGreen,
                                            onTap: (o['employerId'] ?? '')
                                                    .toString()
                                                    .isEmpty
                                                ? null
                                                : () => Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            ChatThreadScreen(
                                                          otherUserId:
                                                              '${o['employerId']}',
                                                          otherUserName:
                                                              '${o['businessName'] ?? 'Employer'}',
                                                        ),
                                                      ),
                                                    ),
                                          ),
                                          const SizedBox(height: 8),
                                          GxButton(
                                            label: 'Application progress',
                                            filled: false,
                                            onTap: () async {
                                              await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      HiringProgressScreen(
                                                    interestId: '${o['id']}',
                                                  ),
                                                ),
                                              );
                                              if (mounted) _load();
                                            },
                                          ),
                                          if (o['contactRequested'] == true &&
                                              o['contactShared'] != true) ...[
                                            const SizedBox(height: 8),
                                            GxButton(
                                              label: 'Share my contact',
                                              onTap: () => _progressAction(
                                                  o, 'share-contact'),
                                            ),
                                            const SizedBox(height: 8),
                                            GxButton(
                                              label: 'Keep contact locked',
                                              filled: false,
                                              onTap: () => _progressAction(
                                                  o, 'decline-contact'),
                                            ),
                                          ],
                                        ],
                                        if (o['response'] == 'PENDING' &&
                                            o['invited'] == true) ...[
                                          const SizedBox(height: 14),
                                          Row(
                                            children: [
                                              if (o['open'] == true) ...[
                                                Expanded(
                                                  child: GxButton(
                                                    label: 'Not Interested',
                                                    filled: false,
                                                    onTap: () =>
                                                        _respond(o, false),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                              ],
                                              Expanded(
                                                child: GxButton(
                                                  label: 'Accept invite',
                                                  onTap: () => _progressAction(
                                                      o, 'accept-invite'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ] else if (o['open'] == true) ...[
                                          const SizedBox(height: 14),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: GxButton(
                                                  label: 'Not Interested',
                                                  filled: false,
                                                  onTap: () =>
                                                      _respond(o, false),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: GxButton(
                                                  label: "I'm Interested",
                                                  onTap: () =>
                                                      _respond(o, true),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
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
    );
  }
}
