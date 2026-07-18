import 'package:flutter/material.dart';
import '../../theme.dart';
import 'gx_pressable.dart';
import 'gx_sheet.dart';

/// Gixbee 2026 design language — in-app time picker.
///
/// Replaces the off-brand Material `showTimePicker` with a violet glass
/// bottom sheet that matches the v106 look (and the companion
/// `showGxCalendar`). Dependency-free: two `ListWheelScrollView` columns
/// (hour 1–12, minute 0–59) plus an AM/PM segmented toggle.
///
/// Returns the picked [TimeOfDay] or null if dismissed.
Future<TimeOfDay?> showGxTimePicker(
  BuildContext context, {
  TimeOfDay? initialTime,
  String title = 'Select time',
  Color? accent,
  List<Color>? accentGradient,
}) {
  return showGxSheet<TimeOfDay>(
    context,
    title: title,
    child: _GxTimePickerBody(
      initialTime: initialTime ?? TimeOfDay.now(),
      accent: accent ?? context.gx.accent,
      accentGradient: accentGradient ?? context.gx.accentGradient,
    ),
  );
}

class _GxTimePickerBody extends StatefulWidget {
  final TimeOfDay initialTime;
  final Color accent;
  final List<Color> accentGradient;

  const _GxTimePickerBody({
    required this.initialTime,
    required this.accent,
    required this.accentGradient,
  });

  @override
  State<_GxTimePickerBody> createState() => _GxTimePickerBodyState();
}

class _GxTimePickerBodyState extends State<_GxTimePickerBody> {
  late int _hour12; // 1..12
  late int _minute; // 0..59
  late bool _isPm;

  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minuteCtrl;

  @override
  void initState() {
    super.initState();
    final h = widget.initialTime.hour;
    _isPm = h >= 12;
    final disp = h % 12;
    _hour12 = disp == 0 ? 12 : disp;
    _minute = widget.initialTime.minute;
    _hourCtrl = FixedExtentScrollController(initialItem: _hour12 - 1);
    _minuteCtrl = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  TimeOfDay get _result {
    int h24;
    if (_isPm) {
      h24 = _hour12 == 12 ? 12 : _hour12 + 12;
    } else {
      h24 = _hour12 == 12 ? 0 : _hour12;
    }
    return TimeOfDay(hour: h24, minute: _minute);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 168,
          child: Stack(
            children: [
              // Centre selection band.
              Center(
                child: Container(
                  height: 40,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: widget.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.accent.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _Wheel(
                      controller: _hourCtrl,
                      count: 12,
                      labelBuilder: (i) => '${i + 1}',
                      onChanged: (i) => setState(() => _hour12 = i + 1),
                    ),
                  ),
                  Text(
                    ':',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: context.gx.ink,
                    ),
                  ),
                  Expanded(
                    child: _Wheel(
                      controller: _minuteCtrl,
                      count: 60,
                      labelBuilder: (i) => i.toString().padLeft(2, '0'),
                      onChanged: (i) => setState(() => _minute = i),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // AM / PM toggle.
        Row(
          children: [
            _PeriodChip(
              label: 'AM',
              selected: !_isPm,
              accentGradient: widget.accentGradient,
              onTap: () => setState(() => _isPm = false),
            ),
            const SizedBox(width: 10),
            _PeriodChip(
              label: 'PM',
              selected: _isPm,
              accentGradient: widget.accentGradient,
              onTap: () => setState(() => _isPm = true),
            ),
          ],
        ),
        const SizedBox(height: 18),
        // Confirm CTA (the single gradient per sheet).
        GxPressable(
          onTap: () => Navigator.of(context).pop(_result),
          child: Container(
            width: double.infinity,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: widget.accentGradient),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Confirm time',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: context.gx.onAccent, // sits on the accent gradient
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Wheel extends StatelessWidget {
  final FixedExtentScrollController controller;
  final int count;
  final String Function(int) labelBuilder;
  final ValueChanged<int> onChanged;

  const _Wheel({
    required this.controller,
    required this.count,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 40,
      perspective: 0.004,
      diameterRatio: 1.6,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (context, index) {
          if (index < 0 || index >= count) return null;
          return Center(
            child: Text(
              labelBuilder(index),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: context.gx.ink,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final List<Color> accentGradient;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.accentGradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GxPressable(
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected ? LinearGradient(colors: accentGradient) : null,
            color: selected ? null : context.gx.ink.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: context.gx.ink.withValues(
                alpha: selected ? 0.0 : 0.10,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              // Selected sits on the accent gradient chip; unselected sits
              // on the sheet's card surface.
              color: selected
                  ? context.gx.onAccent
                  : context.gx.ink.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }
}
