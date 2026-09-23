import 'package:flutter/material.dart';
import '../../shared/media/profile_photo.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../theme.dart';
import 'rental_images.dart';
import 'rental_item_detail_screen.dart';
import 'rental_listing_options.dart';

class RentalItemCard extends StatelessWidget {
  const RentalItemCard({super.key, required this.item});

  final Map<String, dynamic> item;

  String get _rateLabel {
    final daily = item['dailyRate'];
    if (daily != null) {
      return '₹${num.tryParse('$daily')?.round() ?? daily}/day';
    }
    final hourly = item['hourlyRate'];
    return '₹${num.tryParse('$hourly')?.round() ?? hourly}/hr';
  }

  @override
  Widget build(BuildContext context) {
    final photos = rentalImageUrls(item);
    final imageUrl = photos.isEmpty ? null : resolveProfileImageUrl(photos.first);
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
                        imageUrl,
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
                  Text(
                      '${rentalCategoryLabel('${item['category']}')} · ${rentalConditionLabel('${item['condition']}')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: context.gx.ink.withValues(alpha: 0.45))),
                  const SizedBox(height: 3),
                  Text(_rateLabel,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: GixbeeTheme.accentTeal)),
                  if (rentalDistanceLabel(item) != null) ...[
                    const SizedBox(height: 2),
                    Text(rentalDistanceLabel(item)!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: context.gx.ink.withValues(alpha: 0.45))),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
