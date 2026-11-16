/// Client-side cancel/reschedule policy validation (mirrors Rust halls/policy.rs).
class HallPolicyTier {
  HallPolicyTier({
    required this.minDaysBeforeEvent,
    required this.maxDaysBeforeEvent,
    required this.deductionPercent,
  });

  final int minDaysBeforeEvent;
  final int? maxDaysBeforeEvent;
  final int deductionPercent;

  Map<String, dynamic> toJson() => {
        'minDaysBeforeEvent': minDaysBeforeEvent,
        'maxDaysBeforeEvent': maxDaysBeforeEvent,
        'deductionPercent': deductionPercent,
      };

  factory HallPolicyTier.fromJson(Map<String, dynamic> j) => HallPolicyTier(
        minDaysBeforeEvent: (j['minDaysBeforeEvent'] as num?)?.toInt() ?? 0,
        maxDaysBeforeEvent: (j['maxDaysBeforeEvent'] as num?)?.toInt(),
        deductionPercent: (j['deductionPercent'] as num?)?.toInt() ?? 0,
      );
}

String? validatePolicyTiers(List<HallPolicyTier> tiers, String field) {
  if (tiers.isEmpty) return '$field must include at least one tier';
  final sorted = [...tiers]
    ..sort((a, b) => a.minDaysBeforeEvent.compareTo(b.minDaysBeforeEvent));
  if (sorted.first.minDaysBeforeEvent != 0) {
    return '$field: first tier must start at minDaysBeforeEvent = 0';
  }
  final nullCaps = sorted.where((t) => t.maxDaysBeforeEvent == null).length;
  if (nullCaps != 1) {
    return '$field: exactly one tier must have maxDaysBeforeEvent = null';
  }
  if (sorted.last.maxDaysBeforeEvent != null) {
    return '$field: the furthest tier must have maxDaysBeforeEvent = null';
  }
  for (var i = 0; i < sorted.length - 1; i++) {
    final cur = sorted[i];
    final next = sorted[i + 1];
    final max = cur.maxDaysBeforeEvent;
    if (max == null) {
      return '$field: only the last tier may omit maxDaysBeforeEvent';
    }
    if (next.minDaysBeforeEvent != max + 1) {
      return '$field: gap or overlap between tiers';
    }
    if (cur.deductionPercent < 0 || cur.deductionPercent > 100) {
      return '$field: deductionPercent must be 0–100';
    }
  }
  final lastPct = sorted.last.deductionPercent;
  if (lastPct < 0 || lastPct > 100) {
    return '$field: deductionPercent must be 0–100';
  }
  return null;
}

List<HallPolicyTier> defaultPolicyTiers() => [
      HallPolicyTier(
          minDaysBeforeEvent: 0, maxDaysBeforeEvent: 0, deductionPercent: 100),
      HallPolicyTier(
          minDaysBeforeEvent: 1, maxDaysBeforeEvent: 2, deductionPercent: 100),
      HallPolicyTier(
          minDaysBeforeEvent: 3, maxDaysBeforeEvent: 6, deductionPercent: 75),
      HallPolicyTier(
          minDaysBeforeEvent: 7, maxDaysBeforeEvent: 14, deductionPercent: 50),
      HallPolicyTier(
          minDaysBeforeEvent: 15, maxDaysBeforeEvent: 29, deductionPercent: 25),
      HallPolicyTier(
          minDaysBeforeEvent: 30,
          maxDaysBeforeEvent: null,
          deductionPercent: 10),
    ];
