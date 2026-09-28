import 'package:flutter/material.dart';
import 'hall_owner_tokens.dart';

class HallLmbTopBar extends StatelessWidget {
  const HallLmbTopBar({
    super.key,
    this.leading,
    this.title = 'List My Business',
    this.trailingLabel = 'Manage & grow',
  });

  final Widget? leading;
  final String title;
  final String trailingLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: HallOwnerTokens.topBar,
        border: Border(bottom: BorderSide(color: HallOwnerTokens.line)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: HallOwnerTokens.navy,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: HallOwnerTokens.line),
            ),
            child: Text(
              trailingLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: HallOwnerTokens.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HallGreenPill extends StatelessWidget {
  const HallGreenPill({super.key, required this.label, this.onTap, this.icon});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HallOwnerTokens.green,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HallPrimaryButton extends StatelessWidget {
  const HallPrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.outline = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool outline;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final fill = destructive
        ? HallOwnerTokens.red
        : outline
            ? Colors.white
            : HallOwnerTokens.green;
    final fg = outline
        ? (destructive ? HallOwnerTokens.red : HallOwnerTokens.green)
        : Colors.white;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(HallOwnerTokens.radiusBtn),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(HallOwnerTokens.radiusBtn),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(HallOwnerTokens.radiusBtn),
              border: outline
                  ? Border.all(
                      color: destructive
                          ? HallOwnerTokens.red
                          : HallOwnerTokens.green,
                      width: 1.5,
                    )
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HallManageMenuRow extends StatelessWidget {
  const HallManageMenuRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    this.showDot = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(HallOwnerTokens.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HallOwnerTokens.radiusCard),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(HallOwnerTokens.radiusCard),
            border: Border.all(color: HallOwnerTokens.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: danger ? HallOwnerTokens.red : HallOwnerTokens.ink,
                      ),
                    ),
                  ),
                  if (showDot)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: HallOwnerTokens.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: HallOwnerTokens.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HallSectionLabel extends StatelessWidget {
  const HallSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: Color(0xFF9CA3AF),
        ),
      ),
    );
  }
}
