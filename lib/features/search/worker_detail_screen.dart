import 'package:flutter/material.dart';
import '../../shared/models/worker.dart';
import '../../shared/widgets/glass_container.dart';
import '../booking/event_location_picker_screen.dart';
import '../booking/presence_check_screen.dart';
import '../booking/booking_type_selector.dart';

class WorkerDetailScreen extends StatelessWidget {
  final Worker worker;
  final bool isInstant;

  const WorkerDetailScreen({super.key, required this.worker, this.isInstant = true});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Amazon-Style Image Header
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Image.network(
                worker.imageUrl,
                fit: BoxFit.cover,
              ),
            ),
            actions: [
              CircleAvatar(
                backgroundColor: Colors.black26,
                child: IconButton(
                  icon: const Icon(Icons.share, color: Colors.white),
                  onPressed: () {},
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: Colors.black26,
                child: IconButton(
                  icon: const Icon(Icons.favorite_border, color: Colors.white),
                  onPressed: () {},
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & Rating
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              worker.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Text(
                              worker.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: colorScheme.secondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.star,
                                  color: Colors.amber, size: 20),
                              const SizedBox(width: 4),
                              Text(
                                worker.rating.toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          Text(
                            '${worker.reviewCount} reviews',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Pricing
                  Row(
                    children: [
                      Text(
                        '₹${worker.hourlyRate.toInt()}',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'per hour',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Availability Tags
                  if (worker.availabilityTags.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      children: worker.availabilityTags
                          .map((tag) => Chip(
                                label: Text(tag),
                                backgroundColor: colorScheme.secondaryContainer
                                    .withValues(alpha: 0.3),
                                labelStyle:
                                    TextStyle(color: colorScheme.secondary),
                                side: BorderSide.none,
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Bio / About
                  Text(
                    'About this Professional',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    worker.bio,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Skills
                  Text(
                    'Skills & Expertise',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: worker.skills
                        .map((skill) => GlassContainer(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              opacity: 0.1,
                              child: Text(
                                skill,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ))
                        .toList(),
                  ),

                  const SizedBox(height: 100), // Space for bottom button
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Chat feature coming soon!')),
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Chat Now'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: worker.status == 'available'
                    ? () async {
                        if (isInstant) {
                          // Instant flow: Pick Location -> Presence Check
                          final location = await Navigator.push<PickedLocation>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const EventLocationPickerScreen(),
                            ),
                          );

                          if (location != null && context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PresenceCheckScreen(
                                  worker: worker,
                                  skill: worker.skills.isNotEmpty
                                      ? worker.skills.first
                                      : 'General Task',
                                  serviceLocation: location.address,
                                  lat: location.lat,
                                  lng: location.lng,
                                ),
                              ),
                            );
                          }
                        } else {
                          // Scheduled flow: Type/Package Selector
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BookingTypeSelector(worker: worker),
                            ),
                          );
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: worker.status == 'available'
                      ? colorScheme.primary
                      : Colors.grey,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  worker.status == 'available' ? 'Book Now' : 'Worker is Busy',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
