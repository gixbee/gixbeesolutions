import 'package:flutter/material.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../theme.dart';
import 'list_business_details_screen.dart';

/// "List My Business" module (mockup `lmb`).
/// Step 1: pick the type of business to register
/// (service / hiring agency / rental), then continue to details.
/// Gixbee 2026 / v106 reskin: neutral header, bento type trio, surgical
/// accent — the "Gixbee for Business" colour is blue (accentBlue); the single
/// gradient on this screen is the Continue CTA.
class ListBusinessTypeScreen extends StatefulWidget {
  const ListBusinessTypeScreen({super.key});

  @override
  State<ListBusinessTypeScreen> createState() => _ListBusinessTypeScreenState();
}

class _ListBusinessTypeScreenState extends State<ListBusinessTypeScreen> {
  BusinessType? _selectedType;

  void _proceed() {
    if (_selectedType == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListBusinessDetailsScreen(type: _selectedType!),
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
            slivers: [
              SliverToBoxAdapter(child: _header(context)),
              SliverToBoxAdapter(child: _heroCard(context)),
              SliverToBoxAdapter(child: _trustStrip(context)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                  child: Text(
                    'BUSINESS TYPE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _TypeCard(
                      type: BusinessType.service,
                      icon: Icons.plumbing_rounded,
                      title: 'Service Business',
                      subtitle: 'Agencies, Salons, Workshops, Clinics',
                      isSelected: _selectedType == BusinessType.service,
                      onTap: () => setState(
                          () => _selectedType = BusinessType.service),
                    ),
                    _TypeCard(
                      type: BusinessType.hiring,
                      icon: Icons.work_outline_rounded,
                      title: 'Hiring Agency',
                      subtitle: 'Recruiters, Staffing, Event Organisers',
                      isSelected: _selectedType == BusinessType.hiring,
                      onTap: () =>
                          setState(() => _selectedType = BusinessType.hiring),
                    ),
                    _TypeCard(
                      type: BusinessType.rental,
                      icon: Icons.car_rental_rounded,
                      title: 'Rental Business',
                      subtitle: 'Vehicles, Equipment, Properties, Costumes',
                      isSelected: _selectedType == BusinessType.rental,
                      onTap: () =>
                          setState(() => _selectedType = BusinessType.rental),
                    ),
                  ]),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
      ),

      // ── STICKY BOTTOM CTA (single gradient on this screen) ──
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
            onTap: _selectedType != null ? _proceed : null,
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

  // ── Neutral header (no gradient — surgical orange) ──────────────────────
  Widget _header(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
            child: Text('List My Business',
                style: TextStyle(
                    color: context.gx.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w900)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: GixbeeTheme.accentBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: GixbeeTheme.accentBlue.withValues(alpha: 0.3)),
            ),
            child: Text('FOR BUSINESSES',
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

  // ── Neutral bento hero (was a full gradient banner) ─────────────────────
  Widget _heroCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: GixbeeTheme.accentBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.storefront_rounded,
                color: GixbeeTheme.accentBlue, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Grow with Gixbee',
                    style: TextStyle(
                        color: context.gx.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  'Get discovered by thousands of customers near you',
                  style: TextStyle(
                      color: cs.onSurfaceVariant, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Trust strip ──────────────────────────────────────────────────────────
  Widget _trustStrip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const items = [
      (Icons.currency_rupee_rounded, 'Free listing'),
      (Icons.verified_rounded, 'Verified badge'),
      (Icons.groups_rounded, '1.2L+ customers'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final item in items)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.$1, color: GixbeeTheme.accentBlue, size: 20),
                  const SizedBox(height: 4),
                  Text(item.$2,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────
// MODELS & WIDGETS
// ─────────────────────────────────────
enum BusinessType { service, hiring, rental }

/// Bento-style selectable type card (Gixbee 2026): squircle icon block in
/// primary tint when selected, neutral otherwise; check ring on the right.
class _TypeCard extends StatelessWidget {
  final BusinessType type;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeCard({
    required this.type,
    required this.icon,
    required this.title,
    required this.subtitle,
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
              // Squircle icon block (primary tint when selected — no gradient)
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
                      title,
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
                      subtitle,
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
