import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../repositories/matching_repository.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_empty.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

/// Smart Hiring offers — Interested / Not Interested + employer decisions.
class HiringOffersScreen extends ConsumerStatefulWidget {
  const HiringOffersScreen({super.key});

  @override
  ConsumerState<HiringOffersScreen> createState() => _HiringOffersScreenState();
}

class _HiringOffersScreenState extends ConsumerState<HiringOffersScreen> {
  List<Map<String, dynamic>> _offers = [];
  bool _loading = true;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(matchingRepositoryProvider).listOffers();
      if (!mounted) return;
      setState(() {
        _offers = list;
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

  String _statusLabel(Map<String, dynamic> o) {
    final decision = o['decision']?.toString();
    if (decision == 'SHORTLISTED') return 'Shortlisted';
    if (decision == 'REJECTED') return 'Rejected';
    if (decision == 'HIRED') return 'Hired';
    final response = o['response']?.toString();
    if (response == 'INTERESTED') return 'Pending';
    if (response == 'NOT_INTERESTED') return 'Passed';
    if (o['open'] == true) return 'New offer';
    return 'Closed';
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
    final filters = ['All', 'Open', 'Interested', 'Closed'];
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Offers',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: context.gx.ink,
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
                            children: const [
                              SizedBox(height: 80),
                              GxEmptyState(
                                icon: Icons.notifications_active_outlined,
                                title: 'No offers yet',
                                message:
                                    'When employers run Smart Hiring matches, offers appear here.',
                                accent: GixbeeTheme.accentGreen,
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) {
                              final o = _filtered[i];
                              final salary = o['salaryOffered'];
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
                                            if (salary != null)
                                              '₹${salary}/mo',
                                            if ((o['location'] ?? '')
                                                .toString()
                                                .isNotEmpty)
                                              '${o['location']}',
                                            if (notified != null)
                                              DateFormat.MMMd()
                                                  .add_jm()
                                                  .format(notified.toLocal()),
                                          ].join(' · '),
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
                                        if (o['open'] == true) ...[
                                          const SizedBox(height: 14),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: GxButton(
                                                  label: 'Not Interested',
                                                  filled: false,
                                                  accent:
                                                      GixbeeTheme.accentGreen,
                                                  onTap: () =>
                                                      _respond(o, false),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: GxButton(
                                                  label: 'Interested',
                                                  accent:
                                                      GixbeeTheme.accentGreen,
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
