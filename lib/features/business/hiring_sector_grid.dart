import 'package:flutter/material.dart';

import '../../theme.dart';

/// Keys match `hiring-catalogue.json` sector `icon` field.
const _sectorIcons = {
  'bolt': Icons.bolt,
  'pipe': Icons.plumbing,
  'broom': Icons.cleaning_services,
  'roller': Icons.format_paint,
  'hammer': Icons.handyman,
  'fan': Icons.ac_unit,
  'car': Icons.directions_car_outlined,
  'box': Icons.inventory_2_outlined,
  'chef': Icons.restaurant,
  'shield': Icons.shield_outlined,
  'store': Icons.storefront_outlined,
  'briefcase': Icons.work_outline,
  'laptop': Icons.laptop_mac_outlined,
  'book': Icons.menu_book_outlined,
  'health': Icons.favorite_outline,
  'cal': Icons.event_outlined,
  'dumbbell': Icons.fitness_center,
  'lotus': Icons.spa_outlined,
};

/// Fallback when API `icon` is missing or stale in DB.
const _sectorIconsById = {
  'electrical': Icons.bolt,
  'plumbing': Icons.plumbing,
  'cleaning': Icons.cleaning_services,
  'painting': Icons.format_paint,
  'construction': Icons.handyman,
  'hvac': Icons.ac_unit,
  'driving': Icons.directions_car_outlined,
  'delivery': Icons.inventory_2_outlined,
  'cooking': Icons.restaurant,
  'security': Icons.shield_outlined,
  'retail': Icons.storefront_outlined,
  'office': Icons.business_center_outlined,
  'tech': Icons.computer_outlined,
  'teaching': Icons.menu_book_outlined,
  'healthcare': Icons.favorite_outline,
  'events': Icons.event_outlined,
  'fitness': Icons.fitness_center,
  'beauty': Icons.spa_outlined,
};

IconData hiringSectorIcon(Map<String, dynamic> sector) {
  final key = '${sector['icon'] ?? ''}'.trim().toLowerCase();
  if (key.isNotEmpty && _sectorIcons.containsKey(key)) {
    return _sectorIcons[key]!;
  }
  final id = '${sector['id'] ?? ''}'.trim().toLowerCase();
  return _sectorIconsById[id] ?? Icons.work_outline;
}

class _SectorIconBadge extends StatelessWidget {
  const _SectorIconBadge({required this.tint, required this.icon});

  final Color tint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(icon, color: tint, size: 22),
        ),
      ),
    );
  }
}

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
        final cols = c.maxWidth >= 280 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: cols == 3 ? 0.82 : 0.88,
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
            final icon = hiringSectorIcon(s);
            const selectedFill = Color(0xFFF0FDF4);
            return Material(
              color: selected ? selectedFill : Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSelect(s),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? GixbeeTheme.accentGreen : gx.border,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (selected)
                        Positioned(
                          top: -6,
                          right: -4,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: GixbeeTheme.accentGreen,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, size: 12, color: Colors.white),
                          ),
                        ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _SectorIconBadge(tint: tint, icon: icon),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Text(
                                '${s['label']}',
                                textAlign: TextAlign.center,
                                maxLines: 4,
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                  color: selected
                                      ? GixbeeTheme.accentGreenDark
                                      : gx.ink,
                                ),
                              ),
                            ),
                          ),
                        ],
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
