import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../repositories/rentals_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../../theme.dart';
import 'my_rentals_screen.dart';
import 'owner_rentals_screen.dart';
import 'rental_item_detail_screen.dart';

/// Rentals catalog — its own module beside Plan an Event (per client:
/// "don't drop Plan an Event, I need new as rental"). Customers browse and
/// reserve; the header links to My Rentals (reservations) and Owner mode
/// (list your own items).
class RentalsCatalogScreen extends ConsumerWidget {
  const RentalsCatalogScreen({super.key});

  String _rateLabel(Map<String, dynamic> item) {
    final daily = item['dailyRate'];
    if (daily != null) {
      return '₹${num.tryParse('$daily')?.round() ?? daily}/day';
    }
    final hourly = item['hourlyRate'];
    return '₹${num.tryParse('$hourly')?.round() ?? hourly}/hr';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(rentalItemsProvider);

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
                child: Text('Tools, gear & event supplies near you',
                    style: TextStyle(
                        fontSize: 13,
                        color: context.gx.ink.withValues(alpha: 0.5))),
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
                    child: Text('Could not load rentals: $e',
                        style: TextStyle(color: context.gx.ink.withValues(alpha: 0.54))),
                  ),
                  data: (items) => items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inventory_2_outlined,
                                  size: 44,
                                  color: context.gx.ink.withValues(alpha: 0.25)),
                              const SizedBox(height: 12),
                              Text('No items listed yet',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: context.gx.ink
                                          .withValues(alpha: 0.5))),
                              const SizedBox(height: 4),
                              Text('Be the first — tap the shop icon above',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: context.gx.ink
                                          .withValues(alpha: 0.35))),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () async =>
                              ref.refresh(rentalItemsProvider.future),
                          child: GridView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding:
                                const EdgeInsets.fromLTRB(20, 4, 20, 20),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    childAspectRatio: 0.8),
                            itemCount: items.length,
                            itemBuilder: (context, i) =>
                                _itemCard(context, items[i]),
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

  Widget _itemCard(BuildContext context, Map<String, dynamic> item) {
    final imageUrl = item['imageUrl'] as String?;
    return GxPressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                RentalItemDetailScreen(itemId: item['id'].toString())),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: context.gx.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.gx.border, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: context.gx.card2,
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl.startsWith('http')
                            ? imageUrl
                            : '${AppConfig.baseUrl}$imageUrl',
                        fit: BoxFit.cover,
                        cacheWidth: 400,
                        errorBuilder: (_, __, ___) => Icon(
                            Icons.inventory_2_outlined,
                            color: context.gx.ink.withValues(alpha: 0.24),
                            size: 36),
                      )
                    : Icon(Icons.inventory_2_outlined,
                        color: context.gx.ink.withValues(alpha: 0.24), size: 36),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${item['name'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: context.gx.ink)),
                  const SizedBox(height: 3),
                  Text(_rateLabel(item),
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: GixbeeTheme.accentTeal)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
