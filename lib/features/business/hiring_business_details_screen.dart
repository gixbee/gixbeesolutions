import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/config/app_config.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/business_repository.dart';
import '../../repositories/cities_repository.dart';
import '../../repositories/worker_repository.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_city_field.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_text_field.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import '../booking/location_pin_screen.dart';
import '../profile/addresses/address_line.dart';
import 'hiring_business_verification_screen.dart';
import 'hiring_listing.dart';

/// Hiring Business Details — same chrome as service/rental listing, hiring fields only.
class HiringBusinessDetailsScreen extends ConsumerStatefulWidget {
  final HiringEmployerKind employerKind;

  const HiringBusinessDetailsScreen({super.key, required this.employerKind});

  @override
  ConsumerState<HiringBusinessDetailsScreen> createState() =>
      _HiringBusinessDetailsScreenState();
}

class _HiringBusinessDetailsScreenState
    extends ConsumerState<HiringBusinessDetailsScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  late final _employerTypeCtrl =
      TextEditingController(text: widget.employerKind.label);
  final _cityFocus = FocusNode();

  final Set<String> _industries = {};
  String? _companySize;
  String? _cityId;
  bool _citySeeded = false;
  double? _pinLat;
  double? _pinLng;
  String? _pinLabel;
  String? _pinSub;
  String? _logoUrl;
  bool _uploadingLogo = false;
  bool _phoneVerified = false;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(currentUserProvider).value?.phone;
    if (existing != null && existing.isNotEmpty) {
      _phoneCtrl.text = existing;
      _phoneVerified = true;
    }
    _phoneCtrl.addListener(_syncPhoneVerified);
  }

  void _syncPhoneVerified() {
    final userPhone = ref.read(currentUserProvider).value?.phone ?? '';
    final match = sameHiringPhone(_phoneCtrl.text, userPhone);
    if (match != _phoneVerified && match) {
      setState(() => _phoneVerified = true);
    } else if (!match && _phoneVerified) {
      setState(() => _phoneVerified = false);
    }
  }

  @override
  void dispose() {
    _phoneCtrl.removeListener(_syncPhoneVerified);
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _employerTypeCtrl.dispose();
    _cityFocus.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (x == null) return;
      setState(() => _uploadingLogo = true);
      final bytes = await x.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        if (!mounted) return;
        setState(() => _uploadingLogo = false);
        showGxSnack(context, 'Logo must be 5MB or smaller',
            type: GxSnackType.error);
        return;
      }
      final url =
          await ref.read(businessRepositoryProvider).uploadImage(bytes, x.name);
      if (!mounted) return;
      setState(() {
        _logoUrl = url;
        _uploadingLogo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingLogo = false);
      showGxSnack(context, 'Logo upload failed: $e', type: GxSnackType.error);
    }
  }

  Future<void> _verifyPhone() async {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      showGxSnack(context, 'Enter a valid 10-digit business phone number');
      return;
    }
    final phone = hiringOtpPhone(_phoneCtrl.text);
    final otpCtrl = TextEditingController();
    try {
      final devOtp =
          await ref.read(authRepositoryProvider).signInWithPhone(phone);
      if (!mounted) return;
      if (devOtp != null) {
        otpCtrl.text = devOtp;
        showGxSnack(context, 'Dev OTP: $devOtp',
            type: GxSnackType.success, duration: const Duration(seconds: 6));
      }
      final ok = await showGxSheet<bool>(
        context,
        title: 'Verify Number',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter the 6-digit code sent to $phone',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            GxTextField(
              controller: otpCtrl,
              label: 'OTP',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(AppConfig.otpLength),
              ],
              accent: GixbeeTheme.accentBlue,
            ),
            const SizedBox(height: 16),
            GxButton(
              label: 'Verify',
              onTap: () => Navigator.pop(context, true),
              gradient: const [GixbeeTheme.accentBlue, Color(0xFF1D4ED8)],
              accent: GixbeeTheme.accentBlue,
              height: 48,
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      await ref.read(authRepositoryProvider).confirmOtp(
            phoneNumber: phone,
            token: otpCtrl.text.trim(),
          );
      if (!mounted) return;
      setState(() => _phoneVerified = true);
      showGxSnack(context, 'Phone verified', type: GxSnackType.success);
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, 'Could not verify number. Try again.',
          type: GxSnackType.error);
    } finally {
      otpCtrl.dispose();
    }
  }

  void _continue() {
    final phoneDigits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (_nameCtrl.text.trim().isEmpty ||
        _addressCtrl.text.trim().isEmpty ||
        _cityCtrl.text.trim().isEmpty) {
      showGxSnack(context, 'Please fill all required fields');
      return;
    }
    if (_industries.isEmpty) {
      showGxSnack(context, 'Select at least one industry');
      return;
    }
    if (phoneDigits.length < 10 || phoneDigits.length > 15) {
      showGxSnack(context, 'Enter a valid 10-digit business phone number');
      return;
    }
    if (!_phoneVerified) {
      showGxSnack(context, 'Verify your business phone number');
      return;
    }
    if (_pinLat == null || _pinLng == null) {
      showGxSnack(context, 'Pin the exact business location on the map');
      return;
    }
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty && !email.contains('@')) {
      showGxSnack(context, 'Enter a valid business email, or leave it blank');
      return;
    }

    final draft = HiringListingDraft(
      employerKind: widget.employerKind,
      name: _nameCtrl.text.trim(),
      industries: _industries.toList(),
      companySize: _companySize,
      description: _descCtrl.text.trim(),
      logoUrl: _logoUrl,
      phone: phoneDigits.length == 10 ? phoneDigits : '+$phoneDigits',
      phoneVerified: _phoneVerified,
      email: email,
      address: _addressCtrl.text.trim(),
      city: _cityCtrl.text.trim(),
      cityId: _cityId,
      lat: _pinLat,
      lng: _pinLng,
      pinLabel: _pinLabel,
      pinSub: _pinSub,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HiringBusinessVerificationScreen(draft: draft),
      ),
    );
  }

  Future<void> _pickOnMap() async {
    final loc = ref.read(selectedLocationProvider);
    final current = ref.read(currentCityProvider);
    CityEntry? selected;
    if (_cityId != null) {
      for (final c in ref.read(citiesProvider).value ?? const <CityEntry>[]) {
        if (c.id == _cityId) {
          selected = c;
          break;
        }
      }
    }
    final result = await Navigator.push<PinnedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPinScreen(
          initialLat:
              _pinLat ?? loc?.lat ?? selected?.lat ?? current?.lat ?? 8.5241,
          initialLng:
              _pinLng ?? loc?.lng ?? selected?.lng ?? current?.lng ?? 76.9366,
          initialAddress: _addressCtrl.text.trim().isEmpty
              ? null
              : _addressCtrl.text.trim(),
        ),
      ),
    );
    if (result == null || !mounted) return;
    final live = ref.read(citiesProvider).value ?? const <CityEntry>[];
    final matched = matchTypedCity(live, result.locality ?? '') ??
        nearestCity(live, result.lat, result.lng);
    final parts = result.address
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    setState(() {
      _pinLat = result.lat;
      _pinLng = result.lng;
      _cityId = matched?.id;
      if (matched != null) {
        _cityCtrl.text = matched.displayName;
      } else if ((result.locality ?? '').trim().isNotEmpty) {
        _cityCtrl.text = result.locality!.trim();
      }
      _pinLabel = parts.isNotEmpty ? parts.first : (result.locality ?? 'Pinned location');
      _pinSub = parts.length > 1
          ? parts.skip(1).join(', ')
          : (matched?.displayName ?? result.locality ?? _cityCtrl.text);
      final line = result.address.trim().isNotEmpty
          ? result.address.trim()
          : _addressCtrl.text.trim();
      _addressCtrl.text = ensureCityInAddress(
        line,
        matched?.displayName ?? result.locality ?? _cityCtrl.text,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kind = widget.employerKind;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: SingleChildScrollView(
                primary: true,
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
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
                              color: GixbeeTheme.accentBlue
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(Icons.work_outline_rounded,
                                color: GixbeeTheme.accentBlue, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  kind.detailsTitle,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  kind.detailsSubtitle,
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
                    _sectionLabel(context, 'BUSINESS INFO'),
                    _sectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _field(
                            controller: _nameCtrl,
                            label: 'Business / Company Name *',
                            icon: Icons.business_rounded,
                          ),
                          const SizedBox(height: 14),
                          GxTextField(
                            controller: _employerTypeCtrl,
                            label: 'Employer Type *',
                            prefixIcon: Icons.badge_outlined,
                            readOnly: true,
                            enabled: false,
                            accent: GixbeeTheme.accentBlue,
                            blur: false,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            kind.industryLabel.toUpperCase(),
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
                              for (final industry in hiringIndustryOptions)
                                FilterChip(
                                  label: Text(industry),
                                  selected: _industries.contains(industry),
                                  onSelected: (on) => setState(() {
                                    if (on) {
                                      _industries.add(industry);
                                    } else {
                                      _industries.remove(industry);
                                    }
                                  }),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'COMPANY SIZE',
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
                              for (final size in hiringCompanySizes)
                                ChoiceChip(
                                  label: Text(size),
                                  selected: _companySize == size,
                                  onSelected: (_) =>
                                      setState(() => _companySize = size),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _field(
                            controller: _descCtrl,
                            label: 'Brief Description',
                            icon: Icons.info_outline,
                            maxLines: 3,
                          ),
                          const SizedBox(height: 14),
                          GxPressable(
                            onTap: _uploadingLogo ? null : _pickLogo,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: cs.outlineVariant
                                        .withValues(alpha: 0.4)),
                              ),
                              child: Column(
                                children: [
                                  if (_uploadingLogo)
                                    const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor: AlwaysStoppedAnimation(
                                              GixbeeTheme.accentBlue)),
                                    )
                                  else
                                    Icon(
                                      _logoUrl != null
                                          ? Icons.check_circle_rounded
                                          : Icons.add_photo_alternate_outlined,
                                      color: _logoUrl != null
                                          ? GixbeeTheme.accentGreen
                                          : GixbeeTheme.accentBlue,
                                    ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _logoUrl != null
                                        ? 'Logo uploaded — tap to replace'
                                        : 'Company Logo (optional)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: _logoUrl != null
                                          ? GixbeeTheme.accentGreen
                                          : GixbeeTheme.accentBlue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _sectionLabel(context, 'CONTACT'),
                    _sectionCard(
                      child: Column(
                        children: [
                          GxTextField(
                            controller: _phoneCtrl,
                            label: 'Business Phone Number *',
                            prefixIcon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9+\s\-()]')),
                              LengthLimitingTextInputFormatter(18),
                            ],
                            accent: GixbeeTheme.accentBlue,
                            blur: false,
                            suffix: _phoneVerified
                                ? const Text(
                                    'OTP Verified ✓',
                                    style: TextStyle(
                                      color: GixbeeTheme.accentGreen,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  )
                                : GxPressable(
                                    onTap: _verifyPhone,
                                    child: const Text(
                                      'Verify Number',
                                      style: TextStyle(
                                        color: GixbeeTheme.accentBlue,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 14),
                          _field(
                            controller: _emailCtrl,
                            label: 'Business Email',
                            icon: Icons.mail_outline_rounded,
                            keyboardType: TextInputType.emailAddress,
                            hint: 'e.g. hr@company.com',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _sectionLabel(context, 'LOCATION'),
                    _sectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _field(
                            controller: _addressCtrl,
                            label: 'Headquarters / Main Address *',
                            icon: Icons.location_on_outlined,
                            maxLines: 2,
                          ),
                          const SizedBox(height: 14),
                          _cityField(context),
                          if (_pinLat != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: GixbeeTheme.accentBlue
                                    .withValues(alpha: 0.06),
                                border: Border.all(
                                    color: GixbeeTheme.accentBlue
                                        .withValues(alpha: 0.22)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '📍 ${_pinLabel ?? 'Pinned location'}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: context.gx.ink,
                                    ),
                                  ),
                                  if ((_pinSub ?? '').isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      _pinSub!,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  GxPressable(
                                    onTap: _pickOnMap,
                                    child: const Text(
                                      'Change location',
                                      style: TextStyle(
                                        color: GixbeeTheme.accentBlue,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
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
            label: 'Continue to Verification',
            icon: Icons.arrow_forward_rounded,
            onTap: _continue,
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
                Text('Step 2 of 3',
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

  Widget _sectionCard({required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: child,
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

  Widget _cityField(BuildContext context) {
    final citiesAsync = ref.watch(citiesProvider);
    final cities = citiesAsync.value ?? const <CityEntry>[];
    if (!_citySeeded && cities.isNotEmpty) {
      _citySeeded = true;
      final loc = ref.read(selectedLocationProvider);
      final city = resolveLiveCity(
        cities,
        ref.read(currentCityProvider),
        lat: loc?.lat,
        lng: loc?.lng,
      );
      if (city != null && city.id != _cityId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _cityId = city.id;
            if (_cityCtrl.text.trim().isEmpty) {
              _cityCtrl.text = city.displayName;
            }
          });
        });
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GxCityField(
          cities: cities,
          controller: _cityCtrl,
          focusNode: _cityFocus,
          label: 'City *',
          hint: 'Search any city — Trivandrum or Thiruvananthapuram',
          onSelected: (c) => setState(() => _cityId = c?.id),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _pickOnMap,
          icon: Icon(
            _pinLat == null
                ? Icons.add_location_alt_outlined
                : Icons.edit_location_alt_outlined,
            size: 18,
          ),
          label: Text(
            _pinLat == null ? 'Pin business location' : 'Adjust pin on map',
          ),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? hint,
  }) {
    return GxTextField(
      controller: controller,
      label: label,
      hint: hint,
      prefixIcon: icon,
      maxLines: maxLines,
      keyboardType: keyboardType,
      accent: GixbeeTheme.accentBlue,
      blur: false,
    );
  }
}
