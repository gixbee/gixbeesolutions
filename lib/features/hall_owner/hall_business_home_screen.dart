import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/hall_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/glass_container.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import 'hall_enquiries_inbox_screen.dart';
import 'hall_manage_screen.dart';

class HallBusinessHomeScreen extends ConsumerStatefulWidget {
  const HallBusinessHomeScreen({super.key, required this.business});
  final Business business;

  @override
  ConsumerState<HallBusinessHomeScreen> createState() =>
      _HallBusinessHomeScreenState();
}

class _HallBusinessHomeScreenState
    extends ConsumerState<HallBusinessHomeScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(hallRepositoryProvider).listHalls(widget.business.id);
  }

  void _reload() {
    setState(() {
      _future = ref.read(hallRepositoryProvider).listHalls(widget.business.id);
    });
  }

  Future<void> _addHall() async {
    try {
      final hall = await ref.read(hallRepositoryProvider).createHall(
        widget.business.id,
        {'name': 'Hall', 'spaceType': 'indoor', 'useHallName': true},
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HallManageScreen(
            business: widget.business,
            hallId: hall['id'] as String,
          ),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, '$e', type: GxSnackType.error);
    }
  }

  Future<void> _toggleListing(Map<String, dynamic> hall, bool on) async {
    try {
      await ref.read(hallRepositoryProvider).patchHall(
        widget.business.id,
        hall['id'] as String,
        {'listingActive': on},
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, '$e', type: GxSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.business.name),
        actions: [
          IconButton(
            tooltip: 'Enquiries',
            icon: const Icon(Icons.inbox_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      HallEnquiriesInboxScreen(business: widget.business),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addHall,
        icon: const Icon(Icons.add),
        label: const Text('Add hall'),
      ),
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('${snap.error}'));
          }
          final halls = snap.data ?? [];
          if (halls.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No halls yet. Add your first hall to continue.'),
                  const SizedBox(height: 16),
                  GxButton(label: 'Add hall', onTap: _addHall),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: halls.length,
            itemBuilder: (context, i) {
              final h = halls[i];
              final active = h['listingActive'] != false;
              final saved = h['packageSaved'] == true;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(16),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              (h['name'] as String?) ?? 'Hall',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                              ),
                            ),
                          ),
                          Switch(
                            value: active,
                            onChanged: (v) => _toggleListing(h, v),
                          ),
                        ],
                      ),
                      Text(
                        saved
                            ? 'Package saved · ${(h['spaceType'] as String?) ?? 'indoor'}'
                            : 'Package incomplete — save Price & packages',
                        style: TextStyle(
                          color: saved
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Colors.orange.shade800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GxButton(
                        label: 'Manage',
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HallManageScreen(
                                business: widget.business,
                                hallId: h['id'] as String,
                              ),
                            ),
                          );
                          _reload();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
