import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/rentals_repository.dart';
import '../../repositories/cities_repository.dart';
import '../../repositories/worker_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../../theme.dart';
import 'my_rentals_screen.dart';
import 'owner_rentals_screen.dart';
import 'rental_images.dart';
import 'rental_store_screen.dart';

/// Nearby verified rental stores (city or GPS radius), then items inside a store.
class RentalsCatalogScreen extends ConsumerWidget {
  const RentalsCatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storesAsync = ref.watch(rentalStoresProvider);
    final hasFix = ref.watch(selectedLocationProvider) != null ||
        ref.watch(currentCityProvider) != null;

    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 12, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: context.gx.ink),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text('Rentals',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: context.gx.ink)),
                    ),
                    IconButton(
                      tooltip: 'My rentals',
                      icon: Icon(Icons.receipt_long_rounded,
                          color: context.gx.ink.withValues(alpha: 0.7), size: 21),
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MyRentalsScreen())),
                    ),
                    IconButton(
                      tooltip: 'Rent out my items',
                      icon: Icon(Icons.storefront_rounded,
                          color: context.gx.ink.withValues(alpha: 0.7), size: 21),
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const OwnerRentalsScreen())),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                child: Text('Rental stores near you — city or 25 km',
                    style: TextStyle(
                        fontSize: 13,
                        color: context.gx.ink.withValues(alpha: 0.5))),
              ),
              Expanded(
                child: storesAsync.when(
                  loading: () => ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    itemCount: 6,
                    itemBuilder: (_, __) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: GxSkeleton(
                          width: double.infinity, height: 88, radius: 18),
                    ),
                  ),
                  error: (e, _) => Center(
                    child: Text('Could not load rental stores: $e',
                        style: TextStyle(
                            color: context.gx.ink.withValues(alpha: 0.54))),
                  ),
                  data: (stores) => stores.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.storefront_outlined,
                                  size: 44,
                                  color: context.gx.ink.withValues(alpha: 0.25)),
                              const SizedBox(height: 12),
                              Text(
                                  hasFix
                                      ? 'No rental stores near you yet'
                                      : 'Turn on location to see stores near you',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: context.gx.ink
                                          .withValues(alpha: 0.5))),
                              const SizedBox(height: 4),
                              Text(
                                  hasFix
                                      ? 'Stores in your city or within 25 km will show here'
                                      : 'Rentals are shown around your current city',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: context.gx.ink
                                          .withValues(alpha: 0.35))),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () async =>
                              ref.refresh(rentalStoresProvider.future),
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding:
                                const EdgeInsets.fromLTRB(20, 4, 20, 20),
                            itemCount: stores.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) =>
                                _storeCard(context, stores[i]),
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

  Widget _storeCard(BuildContext context, Map<String, dynamic> store) {
    final count = int.tryParse('${store['itemCount'] ?? 0}') ?? 0;
    final location = '${store['location'] ?? ''}'.trim();
    final distance = rentalDistanceLabel(store);
    return GxPressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RentalStoreScreen(store: store)),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.gx.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.gx.border, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.gx.card2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.storefront_rounded,
                  color: GixbeeTheme.accentTeal, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${store['name'] ?? 'Rental store'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: context.gx.ink)),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (location.isNotEmpty) location,
                      if (distance != null) distance,
                      '$count item${count == 1 ? '' : 's'}',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: context.gx.ink.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: context.gx.ink.withValues(alpha: 0.35)),
          ],
        ),
      ),
    );
  }
}
