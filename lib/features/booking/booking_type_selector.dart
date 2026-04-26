import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/worker_repository.dart';
import 'event_location_picker_screen.dart';
import 'booking_screen.dart';
import '../../shared/models/worker.dart';

/// After the user selects a worker, they choose between a pre-defined
/// package or a custom/bespoke request before proceeding to checkout.
class BookingTypeSelector extends ConsumerStatefulWidget {
  final Worker worker;

  const BookingTypeSelector({super.key, required this.worker});

  @override
  ConsumerState<BookingTypeSelector> createState() => _BookingTypeSelectorState();
}

class _BookingTypeSelectorState extends ConsumerState<BookingTypeSelector> {
  _BookingType? _selectedType;

  // Package states
  List<_ServicePackage>? _packages;
  bool _isLoadingPackages = true;

  // Custom request fields
  final _customDescCtrl = TextEditingController();
  String _customEventType = 'General';
  int _guestCount = 1;

  final _eventTypes = [
    'General',
    'Home Repair',
    'Event Setup',
    'Deep Cleaning',
    'Office Maintenance',
    'Other',
  ];

  _ServicePackage? _selectedPackage;
  PickedLocation? _selectedLocation;

  @override
  void initState() {
    super.initState();
    _fetchPackages();
  }

  Future<void> _fetchPackages() async {
    try {
      final rawPackages = await ref.read(workerRepositoryProvider).getWorkerPackages(widget.worker.id);
      
      final packages = rawPackages.map((p) => _ServicePackage(
        name: p['name'] as String,
        description: p['description'] as String,
        duration: p['duration'] as String,
        price: (p['price'] as num).toDouble(),
        includes: p['includes'] != null ? List<String>.from(p['includes']) : ['1 task', 'Basic tools'],
        isBestValue: p['isPopular'] as bool? ?? false,
      )).toList();

      if (mounted) {
        setState(() {
          _packages = packages;
          if (packages.isNotEmpty) _selectedPackage = packages.first;
          _isLoadingPackages = false;
        });
      }
    } catch (e) {
      if (mounted) {
        // Fallback to local 
        setState(() {
          final fallback = _generateFallbackPackages(widget.worker);
          _packages = fallback;
          _selectedPackage = fallback.first;
          _isLoadingPackages = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _customDescCtrl.dispose();
    super.dispose();
  }

  List<_ServicePackage> _generateFallbackPackages(Worker worker) {
    final rate = worker.hourlyRate;
    return [
      _ServicePackage(
        name: 'Quick Fix',
        description: '1 hour of focused work on a single task',
        duration: '1 hr',
        price: rate,
        includes: ['1 task', 'Basic tools', 'Arrival OTP verified'],
      ),
      _ServicePackage(
        name: 'Half Day',
        description: 'Extended session for multiple tasks or bigger jobs',
        duration: '4 hrs',
        price: rate * 3.5,
        includes: ['Up to 3 tasks', 'All tools included', 'Report on completion'],
        isBestValue: true,
      ),
      _ServicePackage(
        name: 'Full Day',
        description: 'Full day engagement for large-scale work',
        duration: '8 hrs',
        price: rate * 6,
        includes: ['Unlimited tasks', 'Materials advice', 'Priority rebooking'],
      ),
    ];
  }

  void _proceed() {
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a booking type')),
      );
      return;
    }

    if (_selectedType == _BookingType.custom && _customDescCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe your requirements')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingScreen(
          worker: widget.worker,
          baseAmount: _selectedType == _BookingType.package 
              ? _selectedPackage?.price 
              : widget.worker.hourlyRate,
          bookingDescription: _selectedType == _BookingType.package
              ? 'Package: ${_selectedPackage?.name} (${_selectedPackage?.duration})'
              : 'Custom Request: $_customEventType - ${_customDescCtrl.text}',
          initialLocation: _selectedLocation,
        ),
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
              cs.primaryContainer.withValues(alpha: 0.25),
              cs.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── TOP BAR ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Booking Type',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            widget.worker.name,
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Worker avatar
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: NetworkImage(widget.worker.imageUrl),
                    ),
                  ],
                ),
              ),

              // ── TABS ──
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _TypeTab(
                      icon: Icons.inventory_2_rounded,
                      label: 'Package',
                      subtitle: 'Fixed price & scope',
                      isSelected: _selectedType == _BookingType.package,
                      color: const Color(0xFF6C63FF),
                      onTap: () =>
                          setState(() => _selectedType = _BookingType.package),
                    ),
                    const SizedBox(width: 12),
                    _TypeTab(
                      icon: Icons.edit_note_rounded,
                      label: 'Custom',
                      subtitle: 'Describe & get quote',
                      isSelected: _selectedType == _BookingType.custom,
                      color: const Color(0xFFFF6B6B),
                      onTap: () =>
                          setState(() => _selectedType = _BookingType.custom),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── CONTENT ──
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _selectedType == _BookingType.custom
                        ? _buildCustomForm(cs)
                        : _buildPackageList(cs),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      // ── BOTTOM BAR ──
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2)),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed: _selectedType != null ? _proceed : null,
              icon: Icon(
                _selectedType == _BookingType.custom
                    ? Icons.send_rounded
                    : Icons.shopping_cart_checkout_rounded,
                size: 20,
              ),
              label: Text(
                _selectedType == _BookingType.custom
                    ? 'Send Custom Request'
                    : 'Continue to Checkout',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────
  // PACKAGE LIST
  // ────────────────────────────────────
  Widget _buildPackageList(ColorScheme cs) {
    return Column(
      key: const ValueKey('packages'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose a Package',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Pre-defined scope with transparent pricing',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (_isLoadingPackages)
          const Center(child: CircularProgressIndicator())
        else if (_packages != null)
          ..._packages!.map((pkg) => _PackageCard(
              package: pkg,
              isSelected: _selectedPackage == pkg,
              onTap: () {
                setState(() => _selectedPackage = pkg);
              },
            )),
        const SizedBox(height: 24),
      ],
    );
  }

  // ────────────────────────────────────
  // CUSTOM FORM
  // ────────────────────────────────────
  Widget _buildCustomForm(ColorScheme cs) {
    return Column(
      key: const ValueKey('custom'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Describe Your Need',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'The worker will review and send you a quote',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 20),

        // Event type dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.2)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _customEventType,
              icon: Icon(Icons.keyboard_arrow_down,
                  color: cs.onSurfaceVariant),
              items: _eventTypes.map((t) {
                return DropdownMenuItem(value: t, child: Text(t));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _customEventType = val);
              },
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Description
        TextField(
          controller: _customDescCtrl,
          maxLines: 4,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText:
                'e.g. "Need to fix 3 leaking taps in kitchen and bathroom. \nAlso check the water heater connection."',
            hintStyle:
                TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 13),
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Guest / people count
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.people_outline, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'People / Guests',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
              // Stepper
              IconButton(
                onPressed: _guestCount > 1
                    ? () => setState(() => _guestCount--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline, size: 22),
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '$_guestCount',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _guestCount++),
                icon: Icon(Icons.add_circle_outline,
                    size: 22, color: cs.primary),
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Location picker shortcut
        InkWell(
          onTap: () async {
            final location = await Navigator.push<PickedLocation>(
              context,
              MaterialPageRoute(
                  builder: (_) => const EventLocationPickerScreen()),
            );
            if (location != null && mounted) {
              setState(() => _selectedLocation = location);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text('Location set: ${location.address}')),
              );
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on_outlined,
                    size: 20, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Set Service Location',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Text(
                        'With on-site contact & map pin',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    size: 14, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Info box
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.amber.withValues(alpha: 0.08),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 18, color: Colors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'The worker will review your request and send a quote within 30 minutes. '
                  'No payment until you accept.',
                  style:
                      TextStyle(color: cs.onSurfaceVariant, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),
      ],
    );
  }
}

// ─────────────────────────────────────
// ENUMS & MODELS
// ─────────────────────────────────────
enum _BookingType { package, custom }

class _ServicePackage {
  final String name;
  final String description;
  final String duration;
  final double price;
  final List<String> includes;
  final bool isBestValue;

  const _ServicePackage({
    required this.name,
    required this.description,
    required this.duration,
    required this.price,
    required this.includes,
    this.isBestValue = false,
  });
}

// ─────────────────────────────────────
// TYPE TAB WIDGET
// ─────────────────────────────────────
class _TypeTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _TypeTab({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isSelected
                ? color.withValues(alpha: 0.1)
                : cs.surfaceContainerHighest.withValues(alpha: 0.3),
            border: Border.all(
              color: isSelected
                  ? color
                  : cs.outlineVariant.withValues(alpha: 0.2),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? color.withValues(alpha: 0.15)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? color : cs.onSurfaceVariant,
                  size: 24,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isSelected ? color : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────
// PACKAGE CARD WIDGET
// ─────────────────────────────────────
class _PackageCard extends StatelessWidget {
  final _ServicePackage package;
  final bool isSelected;
  final VoidCallback onTap;

  const _PackageCard({
    required this.package,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            border: Border.all(
              color: package.isBestValue
                  ? const Color(0xFF6C63FF).withValues(alpha: 0.5)
                  : cs.outlineVariant.withValues(alpha: 0.2),
              width: package.isBestValue ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              package.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (package.isBestValue) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6C63FF)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'BEST VALUE',
                                  style: TextStyle(
                                    color: Color(0xFF6C63FF),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          package.description,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Price + duration
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${package.price.toInt()}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: cs.primary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          package.duration,
                          style: TextStyle(
                            color: cs.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Includes
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: package.includes
                    .map((item) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle,
                                size: 14,
                                color: Colors.green.shade400),
                            const SizedBox(width: 4),
                            Text(
                              item,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
