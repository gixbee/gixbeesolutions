import 'package:flutter/material.dart';

class HallSlotOptions {
  bool offerNoAc = true;
  bool offerAc = true;
  bool discountNoAc = false;
  bool discountAc = false;
  String usage = 'full';
  String timing = 'flexible';
  final hours = TextEditingController(text: '1');
  final from = TextEditingController(text: '10:00');
  final to = TextEditingController(text: '11:00');

  void load(Map<String, dynamic> slot) {
    offerNoAc = slot['offerNoAc'] != false;
    offerAc = slot['offerAc'] == true;
    discountNoAc = slot['discountNoAcEnabled'] as bool? ??
        (slot['discountNoAcPct'] as num? ?? 0) > 0;
    discountAc = slot['discountAcEnabled'] as bool? ??
        (slot['discountAcPct'] as num? ?? 0) > 0;
    usage = slot['acUsage'] as String? ?? 'full';
    timing = slot['acTiming'] as String? ?? 'flexible';
    hours.text = '${slot['acHours'] ?? 1}';
    from.text = slot['acFrom'] as String? ?? '10:00';
    to.text = slot['acTo'] as String? ?? '11:00';
  }

  static int? minutes(String value) {
    if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(value.trim())) return null;
    final parts = value.trim().split(':').map(int.parse).toList();
    return parts[0] < 24 && parts[1] < 60 ? parts[0] * 60 + parts[1] : null;
  }

  String? validate(String start, String end, bool hasAc) {
    if (!offerNoAc && !(hasAc && offerAc)) return 'Select a pricing option';
    if (!hasAc || !offerAc) return null;
    final window = (minutes(end) ?? 0) - (minutes(start) ?? 0);
    final included =
        usage == 'full' ? window / 60 : double.tryParse(hours.text);
    if (included == null ||
        !included.isFinite ||
        included <= 0 ||
        included * 60 > window) {
      return 'AC hours must be positive and within the booking window';
    }
    if (timing == 'fixed') {
      final acStart = minutes(from.text);
      final acEnd = minutes(to.text);
      if (acStart == null ||
          acEnd == null ||
          acStart < (minutes(start) ?? 0) ||
          acEnd > (minutes(end) ?? 0) ||
          acEnd <= acStart ||
          ((acEnd - acStart) - included * 60).abs() > 0.000001) {
        return 'Fixed AC schedule must fit the booking window and match included hours';
      }
    }
    return null;
  }

  Map<String, dynamic> json(String start, String end) {
    final window = (minutes(end)! - minutes(start)!) / 60;
    final included = usage == 'full' ? window : double.parse(hours.text);
    return {
      'acUsage': included == window ? 'full' : usage,
      'acHours': included,
      'acTiming': timing,
      if (timing == 'fixed') 'acFrom': from.text.trim(),
      if (timing == 'fixed') 'acTo': to.text.trim(),
    };
  }

  void dispose() {
    hours.dispose();
    from.dispose();
    to.dispose();
  }
}
