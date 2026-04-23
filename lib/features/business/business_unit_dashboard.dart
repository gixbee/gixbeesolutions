import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../jobs/post_job_screen.dart';
import 'hiring_pipeline_screen.dart';

class BusinessUnitDashboard extends ConsumerWidget {
  const BusinessUnitDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Temporary mock data
    final List<Map<String, dynamic>> myBusinesses = [
      {
        'id': 'b1',
        'name': 'Gixbee Plumbing Services',
        'type': 'SERVICE',
        'status': 'VERIFIED'
      },
      {
        'id': 'b2',
        'name': 'City Construction HR',
        'type': 'HIRING',
        'status': 'VERIFIED'
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Businesses'),
        centerTitle: true,
      ),
      body: myBusinesses.isEmpty
        ? const Center(child: Text('No businesses registered yet.'))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: myBusinesses.length,
            itemBuilder: (context, index) {
              final biz = myBusinesses[index];
              final isHiring = biz['type'] == 'HIRING';

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              biz['name'],
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('VERIFIED', style: TextStyle(fontSize: 10, color: Colors.green)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Unit Type: ${biz['type']}', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                      const Divider(height: 24),
                      
                      // Action buttons based on type
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (isHiring) ...[
                            OutlinedButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const PostJobScreen()),
                              ),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Post Job'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const HiringPipelineScreen(jobId: 'all', jobTitle: 'All Active Postings'),
                                ),
                              ),
                              icon: const Icon(Icons.people, size: 16),
                              label: const Text('Candidates'),
                            ),
                          ] else ...[
                            OutlinedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.calendar_month, size: 16),
                              label: const Text('Manage Calendar'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.person_add, size: 16),
                              label: const Text('Operators'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Future: Route to ListBusinessTypeScreen
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Business'),
      ),
    );
  }
}
