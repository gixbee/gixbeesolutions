import 'package:flutter/material.dart';
import '../../theme.dart';

class MatchExplanationBlock extends StatelessWidget {
  final int? score;
  final List<String> reasons;
  final List<String> warnings;
  final bool verified;

  const MatchExplanationBlock({
    super.key,
    required this.score,
    required this.reasons,
    this.warnings = const [],
    this.verified = false,
  });

  @override
  Widget build(BuildContext context) {
    if (score == null && reasons.isEmpty && !verified) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (score != null)
          Text(
            '$score% Match',
            style: const TextStyle(
              color: GixbeeTheme.accentGreen,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        for (final reason in reasons.take(4))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.check_rounded,
                    size: 14, color: GixbeeTheme.accentGreen),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(reason,
                      style: TextStyle(fontSize: 12, color: cs.onSurface)),
                ),
              ],
            ),
          ),
        for (final warning in warnings.take(2))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.change_history_rounded,
                    size: 14, color: Color(0xFFB45309)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(warning,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
