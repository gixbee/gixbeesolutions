import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/worker_repository.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

/// Go Live setup card: languages the pro speaks (v126 language matching).
/// Self-contained — loads GET /workers/me on mount, toggling a chip PATCHes
/// /workers/me/languages immediately (optimistic, reverts on failure).
/// Going live requires at least one language; customers with a language
/// preference only notify overlapping pros.
class WorkerLanguagesCard extends ConsumerStatefulWidget {
  const WorkerLanguagesCard({super.key});

  @override
  ConsumerState<WorkerLanguagesCard> createState() =>
      _WorkerLanguagesCardState();
}

class _WorkerLanguagesCardState extends ConsumerState<WorkerLanguagesCard> {
  // Same list as the customer's language step.
  static const _languages = [
    'Malayalam', 'Tamil', 'English', 'Hindi', 'Telugu',
    'Kannada', 'Urdu', 'Bengali', 'Marathi',
  ];

  final Set<String> _selected = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _publish() {
    ref.read(workerSpokenLanguagesProvider.notifier).state =
        _selected.toList();
  }

  Future<void> _load() async {
    try {
      final me =
          await ref.read(workerRepositoryProvider).getMyWorkerProfile();
      if (!mounted) return;
      setState(() {
        _selected
          ..clear()
          ..addAll((me['languages'] as List? ?? []).map((e) => e.toString()));
        _loading = false;
      });
      _publish();
    } catch (e) {
      debugPrint('Languages load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String lang) async {
    final wasSelected = _selected.contains(lang);
    if (wasSelected &&
        _selected.length == 1 &&
        ref.read(workerLiveStateProvider)) {
      showGxSnack(
        context,
        'Select at least one language you speak, or go offline first.',
        type: GxSnackType.error,
      );
      return;
    }
    setState(() =>
        wasSelected ? _selected.remove(lang) : _selected.add(lang));
    _publish();
    try {
      await ref
          .read(workerRepositoryProvider)
          .setLanguages(_selected.toList());
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          wasSelected ? _selected.add(lang) : _selected.remove(lang));
      _publish();
      showGxSnack(context, _saveError(e), type: GxSnackType.error);
    }
  }

  String _saveError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] != null) {
        final m = data['message'];
        if (m is List && m.isNotEmpty) return m.first.toString();
        return m.toString();
      }
    }
    return 'Could not save languages. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.gx.card2,
        border: Border.all(color: context.gx.border, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(14),
      child: _loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final lang in _languages)
                      ChoiceChip(
                        label: Text(lang,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _selected.contains(lang)
                                    ? context.gx.onAccent
                                    : context.gx.ink.withValues(alpha: 0.7))),
                        selected: _selected.contains(lang),
                        onSelected: (_) => _toggle(lang),
                        selectedColor: context.gx.accent,
                        backgroundColor: context.gx.card2,
                        side: BorderSide(
                            color: _selected.contains(lang)
                                ? context.gx.accent
                                : context.gx.border),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _selected.isEmpty
                      ? 'Select at least one language before going live. '
                        'Customers are matched to pros who can talk to them.'
                      : 'You\'ll get jobs from customers speaking: ${_selected.join(', ')}',
                  style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: context.gx.ink.withValues(alpha: 0.45)),
                ),
              ],
            ),
    );
  }
}
