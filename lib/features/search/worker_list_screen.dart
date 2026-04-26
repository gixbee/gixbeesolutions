import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/worker_repository.dart';
import '../../shared/models/worker.dart';
import '../profile/worker_profile_card.dart';

class WorkerListScreen extends ConsumerStatefulWidget {
  final String? category;
  final bool isInstant;

  const WorkerListScreen({super.key, this.category, this.isInstant = true});

  @override
  ConsumerState<WorkerListScreen> createState() => _WorkerListScreenState();
}

class _WorkerListScreenState extends ConsumerState<WorkerListScreen> {
  String _searchQuery = '';

  List<Worker> _filterWorkers(List<Worker> workers) {
    return workers.where((worker) {
      final matchesCategory = widget.category == null ||
          worker.skills.any((s) =>
              s.toLowerCase().contains(widget.category!.toLowerCase())) ||
          worker.primaryType
              .toString()
              .contains(widget.category!.toLowerCase());

      final matchesSearch =
          worker.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              worker.title.toLowerCase().contains(_searchQuery.toLowerCase());

      return matchesCategory && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final workersAsync = ref.watch(workersProvider);
    final title =
        widget.category != null ? '${widget.category} Experts' : 'Find Talent';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: workersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (workers) {
          final filteredWorkers = _filterWorkers(workers);
          return RefreshIndicator(
            onRefresh: () async {
              return await ref.refresh(workersProvider.future);
            },
            child: Column(
              children: [
                // Search Bar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search for ${widget.category ?? "workers"}...',
                      hintStyle:
                          TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                      prefixIcon: Icon(Icons.search,
                          color: Theme.of(context).primaryColor),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

                // Worker List
                Expanded(
                  child: filteredWorkers.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                            Center(
                              child: Text(
                                'No workers found. Pull to refresh.',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5)),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filteredWorkers.length,
                          itemBuilder: (context, index) {
                            return WorkerProfileCard(
                                worker: filteredWorkers[index],
                                isInstant: widget.isInstant,
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
