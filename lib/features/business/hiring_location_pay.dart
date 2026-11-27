import 'package:flutter/material.dart';

import '../../theme.dart';

/// ₹ label suffix for catalogue salary-period codes.
String hiringSalaryUnitLabel(String code) {
  switch (code) {
    case 'HOURLY':
      return 'hour';
    case 'DAILY':
      return 'day';
    case 'WEEKLY':
      return 'week';
    case 'MONTHLY':
      return 'month';
    case 'PER_JOB':
      return 'job';
    default:
      return code.toLowerCase();
  }
}

const _workModes = {
  'ONSITE': (
    'Work at location',
    Icons.home_outlined,
    Color(0xFF12B76A),
  ),
  'HYBRID': (
    'Office + remote',
    Icons.apartment_outlined,
    GixbeeTheme.accentBlue,
  ),
  'REMOTE': (
    'Work remotely',
    Icons.laptop_mac_outlined,
    Color(0xFF7A5AF8),
  ),
};

const _periodIcons = {
  'HOURLY': Icons.schedule,
  'DAILY': Icons.calendar_today_outlined,
  'WEEKLY': Icons.date_range_outlined,
  'MONTHLY': Icons.calendar_month_outlined,
  'PER_JOB': Icons.work_outline,
};

String hiringWorkModeLabel(String code) {
  switch (code) {
    case 'ONSITE':
      return 'Onsite';
    case 'HYBRID':
      return 'Hybrid';
    case 'REMOTE':
      return 'Remote';
    default:
      return code;
  }
}

class HiringWorkModeCards extends StatelessWidget {
  const HiringWorkModeCards({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final String selected;
  final ValueChanged<String> onSelect;

  static void showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Work mode'),
        content: const Text(
          'Onsite and hybrid roles use your chosen job location for geography matching. '
          'Remote still uses a reference location for regional filters where applicable. '
          'Pick the location from search results so matching uses the correct master record.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const modes = ['ONSITE', 'HYBRID', 'REMOTE'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Work mode',
              style: TextStyle(fontWeight: FontWeight.w800, color: context.gx.ink),
            ),
            IconButton(
              tooltip: 'About work mode',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => showInfo(context),
              icon: Icon(Icons.info_outline, size: 20, color: context.gx.ink.withValues(alpha: 0.45)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < modes.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _WorkModeCard(
                      title: hiringWorkModeLabel(modes[i]),
                      subtitle: _workModes[modes[i]]!.$1,
                      icon: _workModes[modes[i]]!.$2,
                      tint: _workModes[modes[i]]!.$3,
                      selected: selected == modes[i],
                      onTap: () => onSelect(modes[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WorkModeCard extends StatelessWidget {
  const _WorkModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = selected ? context.gxSuccessInk : context.gx.border;
    return Material(
      color: selected ? context.gxSuccessSurface : context.gx.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: selected ? 2 : 1),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (selected)
                Positioned(
                  top: -4,
                  right: -2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: GixbeeTheme.greenAction,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, size: 11, color: Colors.white),
                  ),
                ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Center(child: Icon(icon, color: tint, size: 17)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      color: selected ? context.gxSuccessInk : context.gx.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1.15,
                      color: context.gxMutedInk,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HiringSalaryPeriodChips extends StatelessWidget {
  const HiringSalaryPeriodChips({
    super.key,
    required this.periods,
    required this.selectedCode,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> periods;
  final String selectedCode;
  final ValueChanged<String> onSelect;

  static void showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pay frequency'),
        content: const Text(
          'Choose how you quote salary. Changing frequency updates the ₹ labels only — '
          'amounts are not converted automatically. Enter values in the selected period.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = periods.where((p) => p['isActive'] != false).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Pay frequency',
              style: TextStyle(fontWeight: FontWeight.w800, color: context.gx.ink),
            ),
            IconButton(
              tooltip: 'About pay frequency',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => showInfo(context),
              icon: Icon(Icons.info_outline, size: 20, color: context.gx.ink.withValues(alpha: 0.45)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.start,
            children: [
              for (final p in active)
                _PeriodChip(
                  code: '${p['code']}',
                  label: '${p['label']}',
                  selected: selectedCode == '${p['code']}',
                  onTap: () => onSelect('${p['code']}'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.code,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = _periodIcons[code] ?? Icons.payments_outlined;
    return Material(
      color: selected ? GixbeeTheme.greenAction : context.gx.card,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? context.gxSuccessInk : context.gx.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : context.gxMutedInk,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : context.gx.ink,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 4),
                const Icon(Icons.check, size: 14, color: Colors.white),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class HiringMatchEstimateCard extends StatelessWidget {
  const HiringMatchEstimateCard({
    super.key,
    required this.estimating,
    required this.error,
    required this.estimated,
    required this.onRetry,
  });

  final bool estimating;
  final String? error;
  final int? estimated;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.gxSuccessSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.gxSuccessInk.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: GixbeeTheme.accentBlue.withValues(alpha: 0.12),
            child: estimating
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.people_alt_outlined, color: context.gxInfoInk),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (estimating)
                  Text(
                    'Updating estimate…',
                    style: TextStyle(fontWeight: FontWeight.w700, color: context.gx.ink),
                  )
                else if (error != null) ...[
                  Text(
                    error!,
                    style: TextStyle(fontWeight: FontWeight.w700, color: context.gx.ink),
                  ),
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
                ] else if (estimated == null)
                  Text(
                    'Set location and salary to see an estimate',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: context.gxMutedInk,
                    ),
                  )
                else ...[
                  Text(
                    '$estimated',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      color: context.gxSuccessInk,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    estimated == 0
                        ? 'No candidates match these requirements yet'
                        : 'candidates match your requirement',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.gx.ink.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
