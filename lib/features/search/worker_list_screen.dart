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
  String? _selectedSkill;
  double? _maxRate;
  double _minRating = 0.0;

  @override
  void initState() {
    super.initState();
    _selectedSkill = widget.category;
  }

  List<Worker> _filterWorkers(List<Worker> workers) {
    return workers.where((worker) {
      final matchesSkill = _selectedSkill == null ||
          _selectedSkill == 'All' ||
          worker.skills.any((s) => s.toLowerCase().contains(_selectedSkill!.toLowerCase())) ||
          worker.primaryType.toString().contains(_selectedSkill!.toLowerCase());

      final matchesSearch = _searchQuery.isEmpty ||
          worker.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          worker.title.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesRate = _maxRate == null || worker.hourlyRate <= _maxRate!;
      final matchesRating = worker.rating >= _minRating;

      return matchesSkill && matchesSearch && matchesRate && matchesRating;
    }).toList();
  }

  void _showFilterModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Advanced Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  
                  const Text('Minimum Rating', style: TextStyle(color: Colors.grey)),
                  Slider(
                    value: _minRating,
                    min: 0,
                    max: 5,
                    divisions: 5,
                    label: _minRating.toString(),
                    onChanged: (val) {
                      setModalState(() => _minRating = val);
                      setState(() => _minRating = val);
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Max Hourly Rate', style: TextStyle(color: Colors.grey)),
                      Text(_maxRate == null ? 'Any' : '₹${_maxRate!.toInt()}/hr', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: _maxRate ?? 1000,
                    min: 100,
                    max: 1000,
                    divisions: 9,
                    onChanged: (val) {
                      setModalState(() => _maxRate = val);
                      setState(() => _maxRate = val);
                    },
                  ),
                  
                  const SizedBox(height: 24),
                  
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setModalState(() {
                              _minRating = 0.0;
                              _maxRate = null;
                            });
                            setState(() {
                              _minRating = 0.0;
                              _maxRate = null;
                            });
                          },
                          child: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final workersAsync = ref.watch(workersProvider);
    final title = 'Find Talent';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _showFilterModal,
          ),
        ],
      ),
      body: workersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (workers) {
          final filteredWorkers = _filterWorkers(workers);
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search workers, locations...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                    prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.primary),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

              // Quick Filters Row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _buildQuickFilter(
                      icon: Icons.work_outline, 
                      label: _selectedSkill ?? 'Any Work',
                      onTap: () {
                        // Simple mock list for switching skills
                        final skills = ['Any Work', 'Electrician', 'Plumber', 'Cleaner', 'Painter', 'Carpenter'];
                        showDialog(
                          context: context,
                          builder: (ctx) => SimpleDialog(
                            title: const Text('Select Work Type'),
                            children: skills.map((s) => SimpleDialogOption(
                              onPressed: () {
                                setState(() => _selectedSkill = s == 'Any Work' ? null : s);
                                Navigator.pop(ctx);
                              },
                              child: Text(s),
                            )).toList(),
                          )
                        );
                      }
                    ),
                    const SizedBox(width: 8),
                    _buildQuickFilter(
                      icon: Icons.star_border, 
                      label: _minRating > 0 ? '${_minRating}+ Stars' : 'Any Rating',
                      onTap: _showFilterModal,
                      isActive: _minRating > 0,
                    ),
                    const SizedBox(width: 8),
                    _buildQuickFilter(
                      icon: Icons.currency_rupee, 
                      label: _maxRate != null ? 'Up to ₹${_maxRate!.toInt()}' : 'Any Price',
                      onTap: _showFilterModal,
                      isActive: _maxRate != null,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Worker List
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    return await ref.refresh(workersProvider.future);
                  },
                  child: filteredWorkers.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_off, size: 64, color: Colors.white.withValues(alpha: 0.2)),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No workers match your filters.\nTry adjusting your search.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                                  ),
                                ],
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
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuickFilter({required IconData icon, required String label, required VoidCallback onTap, bool isActive = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? colorScheme.primary.withValues(alpha: 0.2) : colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? colorScheme.primary : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? colorScheme.primary : Colors.grey),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: isActive ? colorScheme.primary : Colors.grey, fontSize: 13)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 16, color: isActive ? colorScheme.primary : Colors.grey),
          ],
        ),
      ),
    );
  }
}
