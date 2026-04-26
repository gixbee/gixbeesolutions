import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/worker.dart';
import '../../repositories/booking_repository.dart';
import 'waiting_for_worker_screen.dart';

class OnSiteContact {
  final String name;
  final String relation;
  final String phone;

  const OnSiteContact({
    required this.name,
    required this.relation,
    required this.phone,
  });

  Map<String, String> toMap() => {
        'name': name,
        'relation': relation,
        'phone': phone,
      };
}

class PresenceCheckScreen extends ConsumerStatefulWidget {
  final Worker worker;
  final String skill;
  final String serviceLocation;
  final double lat;
  final double lng;

  const PresenceCheckScreen({
    super.key,
    required this.worker,
    required this.skill,
    required this.serviceLocation,
    required this.lat,
    required this.lng,
  });

  @override
  ConsumerState<PresenceCheckScreen> createState() =>
      _PresenceCheckScreenState();
}

class _PresenceCheckScreenState extends ConsumerState<PresenceCheckScreen> {
  bool _selfPresent = true;
  bool _isLoading = false;
  final _nameController = TextEditingController();
  final _relationController = TextEditingController();
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _relationController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _proceed() async {
    OnSiteContact? contact;
    if (!_selfPresent) {
      if (!_formKey.currentState!.validate()) return;
      contact = OnSiteContact(
        name: _nameController.text.trim(),
        relation: _relationController.text.trim(),
        phone: _phoneController.text.trim(),
      );
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(bookingRepositoryProvider);
      final bookingResponse = await repo.sendInstantRequest(
        workerId: widget.worker.id,
        skill: widget.skill,
        serviceLocation: widget.serviceLocation,
        lat: widget.lat,
        lng: widget.lng,
        amount: widget.worker.hourlyRate,
        onSiteContact: contact?.toMap(),
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => WaitingForWorkerScreen(
              bookingId: bookingResponse['id'],
              worker: widget.worker,
              skill: widget.skill,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send request: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Who will be present?'),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Service summary
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.skill,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text(widget.serviceLocation,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            Text('Who will be present at the service location?',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'The arrival OTP will be sent to this person.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
            ),

            const SizedBox(height: 20),

            // Option cards
            _PresenceOptionCard(
              selected: _selfPresent,
              icon: Icons.person,
              title: 'I will be present',
              subtitle: 'OTP sent to my phone',
              onTap: () => setState(() => _selfPresent = true),
            ),
            const SizedBox(height: 12),
            _PresenceOptionCard(
              selected: !_selfPresent,
              icon: Icons.people,
              title: 'Someone else will be present',
              subtitle: 'OTP sent to their phone',
              onTap: () => setState(() => _selfPresent = false),
            ),

            // On-site contact form
            if (!_selfPresent) ...[
              const SizedBox(height: 28),
              Text('On-Site Contact Details',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _relationController,
                      decoration: InputDecoration(
                        labelText: 'Relation (e.g. Mother, Friend)',
                        prefixIcon: const Icon(Icons.group_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Relation is required' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().length < 10)
                              ? 'Enter a valid phone number'
                              : null,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _proceed,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Find Workers',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _PresenceOptionCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PresenceOptionCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.4)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 2 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.primary.withValues(alpha: 0.15)
                    : colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  color: selected ? colorScheme.primary : colorScheme.onSurface,
                  size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: selected ? colorScheme.primary : null)),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.6))),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: colorScheme.primary, size: 22),
          ],
        ),
      ),
    );
  }
}

