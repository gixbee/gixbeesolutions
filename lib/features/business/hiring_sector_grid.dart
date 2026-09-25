import 'package:flutter/material.dart';

import '../../theme.dart';

const _sectorIcons = {
  'electrical': Icons.bolt,
  'plumbing': Icons.plumbing,
  'cleaning': Icons.cleaning_services,
  'painting': Icons.format_paint,
  'construction': Icons.handyman,
  'mechanical': Icons.ac_unit,
  'driving': Icons.local_taxi,
  'logistics': Icons.inventory_2,
  'hospitality': Icons.restaurant,
  'security': Icons.shield,
  'retail': Icons.storefront,
  'office': Icons.business_center,
  'tech': Icons.computer,
  'teaching': Icons.menu_book,
  'healthcare': Icons.favorite,
  'events': Icons.event,
  'fitness': Icons.fitness_center,
  'beauty': Icons.spa,
};

class HiringSectorGrid extends StatelessWidget {
  const HiringSectorGrid({
    super.key,
    required this.sectors,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> sectors;
  final String? selectedId;
  final ValueChanged<Map<String, dynamic>> onSelect;

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 520 ? 4 : 3;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.82,
          ),
          itemCount: sectors.length,
          itemBuilder: (_, i) {
            final s = sectors[i];
            final id = '${s['id']}';
            final selected = selectedId == id;
            final colorHex = '${s['color'] ?? '#12B76A'}';
            Color tint;
            try {
              tint = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
            } catch (_) {
              tint = gx.accent;
            }
            final iconKey = '${s['icon'] ?? ''}';
            final icon = _sectorIcons[iconKey] ?? Icons.work_outline;
            return Material(
              color: selected ? const Color(0xFFF0FDF4) : gx.card,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSelect(s),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? gx.accent : gx.border,
                      width: selected ? 2 : 1,
                    ),
                    boxShadow: selected
                        ? [BoxShadow(color: gx.accent.withValues(alpha: 0.15), blurRadius: 0, spreadRadius: 2)]
                        : null,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        backgroundColor: tint.withValues(alpha: 0.15),
                        child: Icon(icon, color: tint, size: 22),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${s['label']}',
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          color: gx.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
