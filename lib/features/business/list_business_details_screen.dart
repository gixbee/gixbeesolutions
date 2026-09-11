import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'list_business_type_screen.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_glass_card.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_text_field.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import '../../repositories/business_repository.dart';
import '../../repositories/cities_repository.dart'; // currentCityProvider

/// Step 2 of the Business Listing flow.
/// Adapts its form fields based on the selected business type.
/// Gixbee 2026 / v106 reskin: neutral header, form grouped into glass
/// sections, success confirmation via glass bottom sheet, surgical accent —
/// the "Gixbee for Business" colour is blue (accentBlue); the single gradient
/// on this screen is the Submit CTA.
class ListBusinessDetailsScreen extends ConsumerStatefulWidget {
  final BusinessType type;

  const ListBusinessDetailsScreen({super.key, required this.type});

  @override
  ConsumerState<ListBusinessDetailsScreen> createState() =>
      _ListBusinessDetailsScreenState();
}

class _ListBusinessDetailsScreenState
    extends ConsumerState<ListBusinessDetailsScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // Dynamic field for specific type requirements
  final _specialtyCtrl = TextEditingController();

  /// SERVICE subtype — maps to backend Business.serviceType enum.
  static const _serviceTypes = [
    ('HALL', 'Hall'),
    ('CATERING', 'Catering'),
    ('DECORATION', 'Decoration'),
    ('PHOTOGRAPHY', 'Photography'),
    ('DJ', 'Music / DJ'),
    ('MAKEUP', 'Makeup'),
    ('MEHENDI', 'Mehendi'),
    ('INVITATIONS', 'Invitations'),
  ];
  String? _serviceType;

  bool _isSubmitting = false;

  // ── Optional registration/tax-ID document upload (image_picker → /uploads/image) ──
  bool _uploadingDoc = false;
  String? _docUrl;

  Future<void> _pickDocument() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (x == null) return;
      setState(() => _uploadingDoc = true);
      final bytes = await x.readAsBytes();
      final url =
          await ref.read(businessRepositoryProvider).uploadImage(bytes, x.name);
      if (!mounted) return;
      setState(() {
        _docUrl = url;
        _uploadingDoc = false;
      });
      messenger.showSnackBar(
          gxSnackBar('Document uploaded', type: GxSnackType.success));
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingDoc = false);
      messenger.showSnackBar(
          gxSnackBar('Document upload failed: $e', type: GxSnackType.error));
    }
  }

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

  String get _typePill {
    switch (widget.type) {
      case BusinessType.service:
        return 'SERVICE';
      case BusinessType.hiring:
        return 'HIRING';
      case BusinessType.rental:
        return 'RENTAL';
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
    if (_nameCtrl.text.isEmpty ||
        _phoneCtrl.text.isEmpty ||
        _addressCtrl.text.trim().isEmpty) {
      showGxSnack(context, 'Please fill all required fields');
      return;
    }
    if (widget.type == BusinessType.service && _serviceType == null) {
      showGxSnack(context, 'Select a service category (Hall, Catering, …)');
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
        documentUrl: _docUrl,
        serviceType:
            widget.type == BusinessType.service && ['HALL', 'CATERING', 'DECORATION', 'PHOTOGRAPHY'].contains(_serviceType) ? _serviceType : null,
        eventServices: widget.type == BusinessType.service && _serviceType != null ? [_serviceType!] : const [],
        // Structured city scope from the home-selected serviceable city
        // (nullable — legacy behaviour when no city is selected).
        cityId: ref.read(currentCityProvider)?.id,
        ownerId: '', // Backend extracts this from JWT
        status: 'PENDING',
      );

      await ref.read(businessRepositoryProvider).registerBusiness(business);

      if (!mounted) return;
      await _showSuccessSheet();
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, 'Error: ${e.toString()}', type: GxSnackType.error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Glass success sheet (replaces the old AlertDialog). Whether dismissed
  /// via the CTA or a drag-down, we always return to the home tab — the
  /// application has already been submitted at this point.
  Future<void> _showSuccessSheet() async {
    final cs = Theme.of(context).colorScheme;
    await showGxSheet<void>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withValues(alpha: 0.12),
            ),
            child:
                const Icon(Icons.check_circle, color: Colors.green, size: 52),
          ),
          const SizedBox(height: 18),
          Text(
            'Application Submitted',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                color: context.gx.ink),
          ),
          const SizedBox(height: 8),
          Text(
            'Your business profile is under review. Our team will contact you within 24 hours to verify your details.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              height: 1.5,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 22),
          GxButton(
            label: 'Back to Home',
            // Pops the sheet (topmost route); navigation home happens below.
            onTap: () => Navigator.of(context).pop(),
            gradient: const [GixbeeTheme.accentBlue, Color(0xFF1D4ED8)],
            accent: GixbeeTheme.accentBlue,
            height: 52,
          ),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    // ── INFO BANNER (neutral bento, primary-tint icon) ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color:
                            cs.surfaceContainerHighest.withValues(alpha: 0.3),
                        border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: GixbeeTheme.accentBlue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child:
                                Icon(_heroIcon, color: GixbeeTheme.accentBlue, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Registering as a $_title',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
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

                    const SizedBox(height: 22),

                    // ── GLASS SECTION: BUSINESS INFO ──
                    _sectionLabel(context, 'BUSINESS INFO'),
                    GxGlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTextField(
                            controller: _nameCtrl,
                            label: 'Business / Company Name *',
                            icon: Icons.business_rounded,
                          ),
                          if (widget.type == BusinessType.service) ...[
                            const SizedBox(height: 14),
                            Text(
                              'SERVICE CATEGORY *',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final (value, label) in _serviceTypes)
                                  ChoiceChip(
                                    label: Text(label),
                                    selected: _serviceType == value,
                                    onSelected: (_) =>
                                        setState(() => _serviceType = value),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),
                          _buildTextField(
                            controller: _descCtrl,
                            label: 'Brief Description',
                            icon: Icons.info_outline,
                            maxLines: 3,
                          ),
                          const SizedBox(height: 14),
                          _buildTextField(
                            controller: _specialtyCtrl,
                            label: _specialtyLabel,
                            icon: Icons.category_outlined,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    // ── GLASS SECTION: CONTACT ──
                    _sectionLabel(context, 'CONTACT'),
                    GxGlassCard(
                      child: Column(
                        children: [
                          _buildTextField(
                            controller: _phoneCtrl,
                            label: 'Business Phone Number *',
                            icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 14),
                          _buildTextField(
                            controller: _addressCtrl,
                            label: 'Headquarters / Main Address',
                            icon: Icons.location_city_outlined,
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    // ── GLASS SECTION: DOCUMENTS ──
                    _sectionLabel(context, 'DOCUMENTS'),
                    GxGlassCard(
                      padding: EdgeInsets.zero,
                      child: GxPressable(
                        onTap: _uploadingDoc ? null : _pickDocument,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          child: Center(
                            child: Column(
                              children: [
                                if (_uploadingDoc)
                                  const SizedBox(
                                    width: 30,
                                    height: 30,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation(
                                            GixbeeTheme.accentBlue)),
                                  )
                                else
                                  Icon(
                                      _docUrl != null
                                          ? Icons.check_circle_rounded
                                          : Icons.upload_file_rounded,
                                      size: 30,
                                      color: _docUrl != null
                                          ? GixbeeTheme.accentGreen
                                          : GixbeeTheme.accentBlue),
                                const SizedBox(height: 8),
                                Text(
                                  _uploadingDoc
                                      ? 'Uploading…'
                                      : _docUrl != null
                                          ? 'Document uploaded — tap to replace'
                                          : 'Upload Registration or Tax ID (Optional)',
                                  style: TextStyle(
                                      color: _docUrl != null
                                          ? GixbeeTheme.accentGreen
                                          : GixbeeTheme.accentBlue,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'JPG or PNG up to 5MB',
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
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
            label: 'Submit Application',
            onTap: _isSubmitting ? null : _submit,
            loading: _isSubmitting,
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
                Text('Business Details',
                    style: TextStyle(
                        color: context.gx.ink,
                        fontSize: 19,
                        fontWeight: FontWeight.w900)),
                Text('Step 2 of 2 — almost there',
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: GixbeeTheme.accentBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: GixbeeTheme.accentBlue.withValues(alpha: 0.3)),
            ),
            child: Text(_typePill,
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

  Widget _sectionLabel(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: cs.onSurfaceVariant,
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
    return GxTextField(
      controller: controller,
      label: label,
      prefixIcon: icon,
      maxLines: maxLines,
      keyboardType: keyboardType,
      accent: GixbeeTheme.accentBlue,
    );
  }
}
