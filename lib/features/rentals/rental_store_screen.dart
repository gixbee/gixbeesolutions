import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/rentals_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../../theme.dart';
import 'rental_images.dart';
import 'rental_item_card.dart';

/// Items belonging to one nearby verified rental store.
class RentalStoreScreen extends ConsumerWidget {
  const RentalStoreScreen({super.key, required this.store});

  final Map<String, dynamic> store;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeId = '${store['id'] ?? ''}';
    final itemsAsync = ref.watch(rentalStoreItemsProvider(storeId));
    final name = '${store['name'] ?? 'Rental store'}';
    final location = '${store['location'] ?? ''}'.trim();
    final count = int.tryParse('${store['itemCount'] ?? ''}') ?? 0;
    final distance = rentalDistanceLabel(store);

    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: context.gx.ink),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: context.gx.ink)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                child: Text(
                  [
                    if (location.isNotEmpty) location,
                    if (distance != null) distance,
                    if (count > 0) '$count item${count == 1 ? '' : 's'}',
                  ].join(' · '),
                  style: TextStyle(
                      fontSize: 13,
                      color: context.gx.ink.withValues(alpha: 0.5)),
                ),
              ),
              Expanded(
                child: itemsAsync.when(
                  loading: () => GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.8),
                    itemCount: 6,
                    itemBuilder: (_, __) => const GxSkeleton(
                        width: double.infinity,
                        height: double.infinity,
                        radius: 18),
                  ),
                  error: (e, _) => Center(
                    child: Text('Could not load this store: $e',
                        style: TextStyle(
                            color: context.gx.ink.withValues(alpha: 0.54))),
                  ),
                  data: (items) => items.isEmpty
                      ? Center(
                          child: Text('No items listed yet',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: context.gx.ink
                                      .withValues(alpha: 0.5))),
                        )
                      : RefreshIndicator(
                          onRefresh: () async => ref
                              .refresh(rentalStoreItemsProvider(storeId).future),
                          child: GridView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding:
                                const EdgeInsets.fromLTRB(20, 4, 20, 20),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    childAspectRatio: 0.72),
                            itemCount: items.length,
                            itemBuilder: (context, i) =>
                                RentalItemCard(item: items[i]),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
