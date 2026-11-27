import 'package:flutter/material.dart';

import '../../theme.dart';

const _descriptions = {
  'FT': 'Regular, full-day work',
  'PT': 'Work for a few hours daily',
  'INTERN': 'For training and learning',
  'CONTRACT': 'For a fixed period',
  'GIG': 'A single job or short-term task',
};

const _icons = {
  'FT': Icons.work_outline,
  'PT': Icons.schedule,
  'INTERN': Icons.school_outlined,
  'CONTRACT': Icons.description_outlined,
  'GIG': Icons.flash_on_outlined,
};

/// Employment type cards for Hire Employee step 1 (catalogue-driven codes).
class HiringEmploymentCards extends StatelessWidget {
  const HiringEmploymentCards({
    super.key,
    required this.types,
    required this.selectedCode,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> types;
  final String? selectedCode;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final active = types.where((t) => t['isActive'] != false).toList();
    if (active.isEmpty) {
      return Text(
        'No employment types available.',
        style: TextStyle(color: context.gx.ink.withValues(alpha: 0.55)),
      );
    }

    Widget card(Map<String, dynamic> type) {
      final code = '${type['code']}';
      final selected = selectedCode == code;
      final label = '${type['label']}';
      final desc = _descriptions[code];
      final icon = _icons[code] ?? Icons.badge_outlined;
      return _EmploymentCard(
        label: label,
        description: desc,
        icon: icon,
        selected: selected,
        onTap: () => onSelect(code),
      );
    }

    if (active.length <= 3) {
      return Row(
        children: [
          for (var i = 0; i < active.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: card(active[i])),
          ],
        ],
      );
    }

    final firstRow = active.take(3).toList();
    final secondRow = active.skip(3).toList();

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < firstRow.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: card(firstRow[i])),
            ],
          ],
        ),
        if (secondRow.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < secondRow.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: card(secondRow[i])),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _EmploymentCard extends StatelessWidget {
  const _EmploymentCard({
    required this.label,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = selected ? context.gxSuccessInk : context.gx.border;
    return Material(
      color: selected ? context.gxSuccessSurface : context.gx.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: selected ? 2 : 1),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (selected)
                Positioned(
                  top: -6,
                  right: -4,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: GixbeeTheme.greenAction,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, size: 14, color: Colors.white),
                  ),
                ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.gxSuccessInk.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(icon, color: context.gxSuccessInk, size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      color: selected ? context.gxSuccessInk : context.gx.ink,
                    ),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      description!,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.25,
                        color: context.gxMutedInk,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
