import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/business_repository.dart';
import '../../repositories/hall_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_text_field.dart';

class HallOperatorsScreen extends ConsumerStatefulWidget {
  const HallOperatorsScreen({
    super.key,
    required this.business,
    required this.hallId,
  });
  final Business business;
  final String hallId;

  @override
  ConsumerState<HallOperatorsScreen> createState() =>
      _HallOperatorsScreenState();
}

class _HallOperatorsScreenState extends ConsumerState<HallOperatorsScreen> {
  List<Map<String, dynamic>> _ops = [];
  final _search = TextEditingController();
  List<UserLookupResult> _hits = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ops = await ref
          .read(hallRepositoryProvider)
          .listOperators(widget.business.id, widget.hallId);
      if (!mounted) return;
      setState(() {
        _ops = ops;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showGxSnack(context, '$e', type: GxSnackType.error);
    }
  }

  Future<void> _searchUsers(String q) async {
    final hits =
        await ref.read(businessRepositoryProvider).searchUsers(q, limit: 15);
    if (!mounted) return;
    setState(() => _hits = hits);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hall operators')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Operators can manage calendar and view assigned requests for this hall only. They cannot approve enquiries or edit packages.',
                ),
                const SizedBox(height: 12),
                ..._ops.map((o) {
                  return ListTile(
                    title: Text((o['name'] as String?) ?? o['userId'] as String),
                    subtitle: Text((o['phoneNumber'] as String?) ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () async {
                        await ref.read(hallRepositoryProvider).removeOperator(
                              widget.business.id,
                              widget.hallId,
                              o['userId'] as String,
                            );
                        _load();
                      },
                    ),
                  );
                }),
                const Divider(),
                GxTextField(
                  controller: _search,
                  label: 'Search users to add',
                  onChanged: (v) {
                    if (v.trim().length >= 2) _searchUsers(v);
                  },
                ),
                ..._hits.map((u) {
                  return ListTile(
                    title: Text(u.name),
                    subtitle: Text(u.phoneNumber ?? u.id),
                    trailing: TextButton(
                      child: const Text('Add'),
                      onPressed: () async {
                        try {
                          await ref.read(hallRepositoryProvider).addOperator(
                                widget.business.id,
                                widget.hallId,
                                u.id,
                              );
                          _search.clear();
                          setState(() => _hits = []);
                          _load();
                        } catch (e) {
                          if (!context.mounted) return;
                          showGxSnack(context, '$e', type: GxSnackType.error);
                        }
                      },
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
