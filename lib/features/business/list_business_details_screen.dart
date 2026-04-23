import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'list_business_type_screen.dart';
import '../../shared/models/business.dart';
import '../../repositories/business_repository.dart';

/// Step 2 of the Business Listing flow.
/// Adapts its form fields based on the selected business type.
class ListBusinessDetailsScreen extends ConsumerStatefulWidget {
  final BusinessType type;

  const ListBusinessDetailsScreen({super.key, required this.type});

  @override
  ConsumerState<ListBusinessDetailsScreen> createState() =>
      _ListBusinessDetailsScreenState();
}

class _ListBusinessDetailsScreenState extends ConsumerState<ListBusinessDetailsScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // Dynamic field for specific type requirements
  final _specialtyCtrl = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _specialtyCtrl.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.type) {
      case BusinessType.service:
        return 'Service Business';
      case BusinessType.hiring:
        return 'Hiring Agency';
      case BusinessType.rental:
        return 'Rental Business';
    }
  }

  String get _specialtyLabel {
    switch (widget.type) {
      case BusinessType.service:
        return 'Service Categories (e.g. Plumbing, IT)';
      case BusinessType.hiring:
        return 'Industries you hire for';
      case BusinessType.rental:
        return 'Types of assets you rent out';
    }
  }

  IconData get _heroIcon {
    switch (widget.type) {
      case BusinessType.service:
        return Icons.plumbing_rounded;
      case BusinessType.hiring:
        return Icons.work_outline_rounded;
      case BusinessType.rental:
        return Icons.car_rental_rounded;
    }
  }

  void _submit() async {
    if (_nameCtrl.text.isEmpty || _phoneCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final business = Business(
        id: '', // Backend generates this
        name: _nameCtrl.text,
        type: widget.type.name.toUpperCase(),
        description: _descCtrl.text,
        specialty: _specialtyCtrl.text,
        phone: _phoneCtrl.text,
        address: _addressCtrl.text,
        ownerId: '', // Backend extracts this from JWT
        status: 'PENDING',
      );

      await ref.read(businessRepositoryProvider).registerBusiness(business);

      if (!mounted) return;
      _showSuccessDialog();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.check_circle, color: Colors.green, size: 56),
            ),
            const SizedBox(height: 20),
            const Text(
              'Application Submitted',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              'Your business profile is under review. Our team will contact you within 24 hours to verify your details.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                height: 1.5,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).popUntil((r) => r.isFirst),
                child: const Text('Back to Home'),
              ),
            ),
          ],
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
              cs.surface,
              cs.surfaceContainerHighest.withValues(alpha: 0.2),
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
                    Text(
                      'Business Details',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),

                      // ── INFO BANNER ──
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: const Color(0xFFFF9F43).withValues(alpha: 0.1),
                          border: Border.all(
                            color: const Color(0xFFFF9F43).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(_heroIcon, color: const Color(0xFFFF9F43), size: 28),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Registering as a $_title',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tell us about your organization so we can verify and list you.',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // ── FORM FIELDS ──
                      _buildTextField(
                        controller: _nameCtrl,
                        label: 'Business / Company Name *',
                        icon: Icons.business_rounded,
                      ),
                      const SizedBox(height: 16),

                      _buildTextField(
                        controller: _descCtrl,
                        label: 'Brief Description',
                        icon: Icons.info_outline,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),

                      _buildTextField(
                        controller: _specialtyCtrl,
                        label: _specialtyLabel,
                        icon: Icons.category_outlined,
                      ),
                      const SizedBox(height: 16),

                      _buildTextField(
                        controller: _phoneCtrl,
                        label: 'Business Phone Number *',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),

                      _buildTextField(
                        controller: _addressCtrl,
                        label: 'Headquarters / Main Address',
                        icon: Icons.location_city_outlined,
                        maxLines: 2,
                      ),

                      const SizedBox(height: 24),

                      // ── DOCUMENT UPLOAD PLACEHOLDER ──
                      Text(
                        'Business Documents',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () {},
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: cs.outlineVariant,
                              style: BorderStyle.solid,
                            ),
                            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                          ),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.upload_file_rounded, size: 32, color: cs.primary),
                                const SizedBox(height: 8),
                                Text(
                                  'Upload Registration or Tax ID (Optional)',
                                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'PDF, JPG, or PNG up to 5MB',
                                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),

              // ── BOTTOM BUTTON ──
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(
                    top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.1)),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF9F43),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'Submit Application',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        alignLabelWithHint: maxLines > 1,
        prefixIcon: Padding(
          padding: EdgeInsets.only(bottom: maxLines > 1 ? (maxLines * 12.0) : 0),
          child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
        ),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF9F43), width: 2),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }
}

