import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/worker_repository.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

/// Go Live setup card: languages the pro speaks (v126 language matching).
/// Self-contained — loads GET /workers/me on mount, toggling a chip PATCHes
/// /workers/me/languages immediately (optimistic, reverts on failure).
/// Customers' broadcast requests with a language preference only notify pros
/// with an overlap; pros with NOTHING selected still get all jobs (lenient),
/// which the caption explains.
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

  Future<void> _load() async {
    try {
      final me =
          await ref.read(workerRepositoryProvider).getMyWorkerProfile();
      if (!mounted) return;
      setState(() {
        _selected.addAll(
            (me['languages'] as List? ?? []).map((e) => e.toString()));
        _loading = false;
      });
    } catch (e) {
      debugPrint('Languages load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String lang) async {
    final wasSelected = _selected.contains(lang);
    setState(() =>
        wasSelected ? _selected.remove(lang) : _selected.add(lang));
    try {
      await ref
          .read(workerRepositoryProvider)
          .setLanguages(_selected.toList());
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          wasSelected ? _selected.add(lang) : _selected.remove(lang));
      showGxSnack(context, 'Could not save languages: $e',
          type: GxSnackType.error);
    }
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
                        selectedColor: GixbeeTheme.accentPurple,
                        backgroundColor: context.gx.card2,
                        side: BorderSide(
                            color: _selected.contains(lang)
                                ? GixbeeTheme.accentPurple
                                : context.gx.border),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _selected.isEmpty
                      ? 'Nothing selected — you receive ALL job requests. '
                        'Selecting languages filters out customers you can\'t talk to.'
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
