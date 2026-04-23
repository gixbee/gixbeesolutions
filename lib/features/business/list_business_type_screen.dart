import 'package:flutter/material.dart';
import 'list_business_details_screen.dart';

/// Entry point for the "List My Business" intent.
/// Allows the user to pick the type of business they want to register.
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFF9F43).withValues(alpha: 0.15),
              cs.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── TOP BAR ──
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // ── HEADER ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9F43).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        color: Color(0xFFFECA57),
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Grow your business\nwith Gixbee',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'What kind of business are you listing?',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── BUSINESS TYPES ──
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _TypeCard(
                      type: BusinessType.service,
                      icon: Icons.plumbing_rounded,
                      title: 'Service Business',
                      subtitle: 'Agencies, Salons, Workshops, Clinics',
                      isSelected: _selectedType == BusinessType.service,
                      onTap: () => setState(() => _selectedType = BusinessType.service),
                    ),
                    _TypeCard(
                      type: BusinessType.hiring,
                      icon: Icons.work_outline_rounded,
                      title: 'Hiring Agency',
                      subtitle: 'Recruiters, Staffing, Event Organisers',
                      isSelected: _selectedType == BusinessType.hiring,
                      onTap: () => setState(() => _selectedType = BusinessType.hiring),
                    ),
                    _TypeCard(
                      type: BusinessType.rental,
                      icon: Icons.car_rental_rounded,
                      title: 'Rental Business',
                      subtitle: 'Vehicles, Equipment, Properties, Costumes',
                      isSelected: _selectedType == BusinessType.rental,
                      onTap: () => setState(() => _selectedType = BusinessType.rental),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      // ── BOTTOM BUTTON ──
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.1)),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _selectedType != null ? _proceed : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF9F43),
                disabledBackgroundColor: cs.surfaceContainerHighest,
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 20, color: Colors.white),
              label: const Text(
                'Continue',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────
// MODELS & WIDGETS
// ─────────────────────────────────────
enum BusinessType { service, hiring, rental }

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
    const primaryOrange = Color(0xFFFF9F43);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: isSelected
                ? primaryOrange.withValues(alpha: 0.1)
                : cs.surfaceContainerHighest.withValues(alpha: 0.3),
            border: Border.all(
              color: isSelected ? primaryOrange : cs.outlineVariant.withValues(alpha: 0.2),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? primaryOrange.withValues(alpha: 0.2)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: isSelected ? primaryOrange : cs.onSurfaceVariant,
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
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isSelected ? primaryOrange : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? primaryOrange : cs.outlineVariant.withValues(alpha: 0.5),
                    width: isSelected ? 6 : 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
