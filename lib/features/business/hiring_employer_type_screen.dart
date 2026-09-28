import 'package:flutter/material.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../theme.dart';
import 'hiring_business_details_screen.dart';
import 'hiring_listing.dart';

/// Step between List My Business and Business Details for hiring units.
class HiringEmployerTypeScreen extends StatefulWidget {
  const HiringEmployerTypeScreen({super.key});

  @override
  State<HiringEmployerTypeScreen> createState() =>
      _HiringEmployerTypeScreenState();
}

class _HiringEmployerTypeScreenState extends State<HiringEmployerTypeScreen> {
  HiringEmployerKind? _kind;

  void _proceed() {
    final kind = _kind;
    if (kind == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HiringBusinessDetailsScreen(employerKind: kind),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: DribbbleBackground(
        child: SafeArea(
          child: CustomScrollView(
            primary: true,
            slivers: [
              SliverToBoxAdapter(child: _header(context)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How do you hire?',
                        style: TextStyle(
                          color: context.gx.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose the option that best describes your business.',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _KindCard(
                      kind: HiringEmployerKind.direct,
                      icon: Icons.apartment_rounded,
                      isSelected: _kind == HiringEmployerKind.direct,
                      onTap: () => setState(
                          () => _kind = HiringEmployerKind.direct),
                    ),
                    _KindCard(
                      kind: HiringEmployerKind.staffing,
                      icon: Icons.groups_outlined,
                      isSelected: _kind == HiringEmployerKind.staffing,
                      onTap: () => setState(
                          () => _kind = HiringEmployerKind.staffing),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.1)),
          ),
        ),
        child: SafeArea(
          child: GxButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            onTap: _kind != null ? _proceed : null,
            gradient: const [GixbeeTheme.accentBlue, Color(0xFF1D4ED8)],
            accent: GixbeeTheme.accentBlue,
            height: 56,
            radius: 16,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          GxPressable(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: context.gx.ink.withValues(alpha: 0.06),
                shape: BoxShape.circle,
                border:
                    Border.all(color: context.gx.ink.withValues(alpha: 0.10)),
              ),
              child: Icon(Icons.arrow_back_rounded,
                  color: context.gx.ink, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How do you hire?',
                    style: TextStyle(
                        color: context.gx.ink,
                        fontSize: 19,
                        fontWeight: FontWeight.w900)),
                Text('Step 1 of 3',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: GixbeeTheme.accentBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: GixbeeTheme.accentBlue.withValues(alpha: 0.3)),
            ),
            child: const Text('HIRING',
                style: TextStyle(
                    color: GixbeeTheme.accentBlue,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
          ),
        ],
      ),
    );
  }
}

class _KindCard extends StatelessWidget {
  final HiringEmployerKind kind;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _KindCard({
    required this.kind,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GxPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: isSelected
                ? GixbeeTheme.accentBlue.withValues(alpha: 0.08)
                : cs.surfaceContainerHighest.withValues(alpha: 0.3),
            border: Border.all(
              color: isSelected
                  ? GixbeeTheme.accentBlue
                  : cs.outlineVariant.withValues(alpha: 0.2),
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: isSelected
                      ? GixbeeTheme.accentBlue.withValues(alpha: 0.16)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  icon,
                  size: 26,
                  color: isSelected
                      ? GixbeeTheme.accentBlue
                      : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kind.cardTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                        color: isSelected
                            ? GixbeeTheme.accentBlue
                            : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      kind.cardSubtitle,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? GixbeeTheme.accentBlue
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? GixbeeTheme.accentBlue
                        : cs.outlineVariant.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Icon(Icons.check_rounded,
                        size: 16, color: context.gx.onAccent)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
