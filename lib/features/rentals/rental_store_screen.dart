import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/rentals_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_skeleton.dart';
import '../../theme.dart';
import 'rental_images.dart';
import 'rental_item_card.dart';
import 'rental_listing_options.dart';

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
                  data: (items) => _StoreCatalog(storeId: storeId, items: items),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoreCatalog extends ConsumerStatefulWidget {
  const _StoreCatalog({required this.storeId, required this.items});
  final String storeId;
  final List<Map<String, dynamic>> items;

  @override
  ConsumerState<_StoreCatalog> createState() => _StoreCatalogState();
}

class _StoreCatalogState extends ConsumerState<_StoreCatalog> {
  String? _category;

  @override
  Widget build(BuildContext context) {
    final present = <String>{
      for (final item in widget.items) '${item['category'] ?? 'OTHER'}',
    };
    final chips = kRentalCategories.where((c) => present.contains(c.$1)).toList();
    final items = _category == null
        ? widget.items
        : widget.items.where((i) => '${i['category']}' == _category).toList();
    if (widget.items.isEmpty) {
      return Center(
        child: Text('No items listed yet',
            style: TextStyle(
                fontSize: 14, color: context.gx.ink.withValues(alpha: 0.5))),
      );
    }
    return Column(
      children: [
        if (chips.length > 1)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _category == null,
                    onSelected: (_) => setState(() => _category = null),
                  ),
                ),
                for (final c in chips)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c.$2),
                      selected: _category == c.$1,
                      onSelected: (_) => setState(() => _category = c.$1),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async =>
                ref.refresh(rentalStoreItemsProvider(widget.storeId).future),
            child: items.isEmpty
                ? ListView(children: [
                    const SizedBox(height: 80),
                    Center(
                      child: Text('No ${rentalCategoryLabel(_category).toLowerCase()} items',
                          style: TextStyle(
                              fontSize: 14,
                              color: context.gx.ink.withValues(alpha: 0.5))),
                    ),
                  ])
                : GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.68),
                    itemCount: items.length,
                    itemBuilder: (context, i) =>
                        RentalItemCard(item: items[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

