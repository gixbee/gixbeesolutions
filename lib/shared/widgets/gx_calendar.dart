import 'package:flutter/material.dart';
import '../../theme.dart';
import 'gx_pressable.dart';
import 'gx_sheet.dart';

/// Gixbee 2026 design language — in-app month-grid date picker.
///
/// Replaces the off-brand Material `showDatePicker` with a violet glass
/// bottom sheet that matches the v106 look. Pass [blockedDays] (date-only
/// DateTimes) to render an *availability* calendar — those days are shown in
/// red and are not selectable — which is the building block the per-vendor
/// hall/rental booking flow needs (see PENDING_WORK 1.2). When [blockedDays]
/// is empty it behaves as a plain branded picker.
///
/// Returns the picked [DateTime] (date-only, local) or null if dismissed.
Future<DateTime?> showGxCalendar(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  Set<DateTime> blockedDays = const {},
  String title = 'Select date',
  Color? accent,
  List<Color>? accentGradient,
}) {
  final now = DateTime.now();
  final first = _dateOnly(firstDate ?? now);
  final last = _dateOnly(lastDate ?? now.add(const Duration(days: 365)));
  return showGxSheet<DateTime>(
    context,
    title: title,
    child: _GxCalendarBody(
      initialDate: _dateOnly(initialDate ?? first),
      firstDate: first,
      lastDate: last,
      blockedDays: blockedDays.map(_dateOnly).toSet(),
      accent: accent ?? context.gx.accent,
      accentGradient: accentGradient ?? context.gx.accentGradient,
    ),
  );
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _GxCalendarBody extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Set<DateTime> blockedDays;
  final Color accent;
  final List<Color> accentGradient;

  const _GxCalendarBody({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.blockedDays,
    required this.accent,
    required this.accentGradient,
  });

  @override
  State<_GxCalendarBody> createState() => _GxCalendarBodyState();
}

class _GxCalendarBodyState extends State<_GxCalendarBody> {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  late DateTime _visibleMonth; // first day of the displayed month
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    final init = widget.initialDate;
    _visibleMonth = DateTime(init.year, init.month, 1);
    if (!_isBlocked(init) && !_isBeforeFirst(init) && !_isAfterLast(init)) {
      _selected = init;
    }
  }

  bool _isBlocked(DateTime d) =>
      widget.blockedDays.any((b) => _sameDay(b, d));
  bool _isBeforeFirst(DateTime d) => d.isBefore(widget.firstDate);
  bool _isAfterLast(DateTime d) => d.isAfter(widget.lastDate);

  bool get _canGoPrev {
    final prev = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
    final lastOfPrev = DateTime(prev.year, prev.month + 1, 0);
    return !lastOfPrev.isBefore(widget.firstDate);
  }

  bool get _canGoNext {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    return !next.isAfter(widget.lastDate);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _visibleMonth =
          DateTime(_visibleMonth.year, _visibleMonth.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final daysInMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    // weekday() returns 1 (Mon) .. 7 (Sun); we want Sunday-first columns.
    final leadBlanks = _visibleMonth.weekday % 7;
    final hasBlocked = widget.blockedDays.isNotEmpty;

    final cells = <Widget>[];
    for (var i = 0; i < leadBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
      final disabled =
          _isBeforeFirst(date) || _isAfterLast(date) || _isBlocked(date);
      final blocked = _isBlocked(date);
      final selected = _selected != null && _sameDay(_selected!, date);
      final isToday = _sameDay(today, date);
      cells.add(_DayCell(
        day: day,
        disabled: disabled,
        blocked: blocked,
        selected: selected,
        isToday: isToday,
        accent: widget.accent,
        accentGradient: widget.accentGradient,
        onTap: disabled ? null : () => setState(() => _selected = date),
      ));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Month nav header.
        Row(
          children: [
            Text(
              '${_months[_visibleMonth.month - 1]} ${_visibleMonth.year}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: context.gx.ink,
              ),
            ),
            const Spacer(),
            _NavChevron(
              icon: Icons.chevron_left_rounded,
              enabled: _canGoPrev,
              onTap: _canGoPrev ? () => _shiftMonth(-1) : null,
            ),
            const SizedBox(width: 6),
            _NavChevron(
              icon: Icons.chevron_right_rounded,
              enabled: _canGoNext,
              onTap: _canGoNext ? () => _shiftMonth(1) : null,
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Weekday labels.
        Row(
          children: _weekdays
              .map((w) => Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: context.gx.ink.withValues(alpha: 0.40),
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        // Day grid.
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: cells,
        ),
        if (hasBlocked) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              _LegendDot(color: widget.accent, label: 'Selected'),
              const SizedBox(width: 16),
              _LegendDot(
                  color: const Color(0xFFE8173A), label: 'Unavailable'),
            ],
          ),
        ],
        const SizedBox(height: 18),
        // Confirm CTA (the single gradient per sheet).
        GxPressable(
          onTap: _selected == null
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: Opacity(
            opacity: _selected == null ? 0.45 : 1.0,
            child: Container(
              width: double.infinity,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: widget.accentGradient),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'Confirm date',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: context.gx.onAccent, // sits on the accent gradient
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool disabled;
  final bool blocked;
  final bool selected;
  final bool isToday;
  final Color accent;
  final List<Color> accentGradient;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.disabled,
    required this.blocked,
    required this.selected,
    required this.isToday,
    required this.accent,
    required this.accentGradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color textColor;
    if (selected) {
      textColor = context.gx.onAccent; // sits on the accent gradient dot
    } else if (blocked) {
      textColor = const Color(0xFFE8173A).withValues(alpha: 0.85);
    } else if (disabled) {
      textColor = context.gx.ink.withValues(alpha: 0.20);
    } else {
      textColor = context.gx.ink.withValues(alpha: 0.90);
    }

    return GxPressable(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected ? LinearGradient(colors: accentGradient) : null,
          color: !selected && blocked
              ? const Color(0xFFE8173A).withValues(alpha: 0.10)
              : null,
          shape: BoxShape.circle,
          border: isToday && !selected
              ? Border.all(
                  color: accent.withValues(alpha: 0.70), width: 1.5)
              : null,
        ),
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: textColor,
            decoration: blocked ? TextDecoration.lineThrough : null,
            decorationColor: const Color(0xFFE8173A).withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

class _NavChevron extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _NavChevron({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GxPressable(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.gx.ink.withValues(alpha: 0.06),
          shape: BoxShape.circle,
          border: Border.all(color: context.gx.ink.withValues(alpha: 0.10)),
        ),
        child: Icon(
          icon,
          size: 22,
          color: context.gx.ink.withValues(alpha: enabled ? 0.90 : 0.25),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.gx.ink.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
