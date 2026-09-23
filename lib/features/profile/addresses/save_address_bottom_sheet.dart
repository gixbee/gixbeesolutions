import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme.dart';
import '../../../repositories/addresses_repository.dart';
import '../../../repositories/cities_repository.dart';
import '../../../shared/widgets/gx_button.dart';
import '../../../shared/widgets/gx_city_field.dart';
import '../../../shared/widgets/gx_snackbar.dart';
import '../../booking/location_pin_screen.dart';
import 'address_line.dart';

class SaveAddressBottomSheet extends ConsumerStatefulWidget {
  final PinnedLocation pinnedLocation;

  const SaveAddressBottomSheet({super.key, required this.pinnedLocation});

  @override
  ConsumerState<SaveAddressBottomSheet> createState() =>
      _SaveAddressBottomSheetState();
}

class _SaveAddressBottomSheetState extends ConsumerState<SaveAddressBottomSheet> {
  final _doorNoCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  late final TextEditingController _areaCtrl;
  late final TextEditingController _pincodeCtrl;
  final _cityCtrl = TextEditingController();
  final _cityFocus = FocusNode();
  String _selectedLabel = 'Home';
  String? _cityId;
  String? _houseError;
  String? _cityError;
  bool _citySeeded = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _areaCtrl = TextEditingController(text: widget.pinnedLocation.address);
    _pincodeCtrl =
        TextEditingController(text: widget.pinnedLocation.postalCode ?? '');
  }

  @override
  void dispose() {
    _doorNoCtrl.dispose();
    _landmarkCtrl.dispose();
    _areaCtrl.dispose();
    _pincodeCtrl.dispose();
    _cityCtrl.dispose();
    _cityFocus.dispose();
    super.dispose();
  }

  void _seedCity(List<CityEntry> cities) {
    if (_citySeeded || cities.isEmpty) return;
    _citySeeded = true;
    String? id;
    final locality = widget.pinnedLocation.locality?.trim().toLowerCase();
    if (locality != null && locality.isNotEmpty) {
      for (final c in cities) {
        if (c.name.trim().toLowerCase() == locality) {
          id = c.id;
          break;
        }
      }
    }
    id ??= nearestCity(
      cities,
      widget.pinnedLocation.lat,
      widget.pinnedLocation.lng,
    )?.id;
    if (id == null || id == _cityId) return;
    CityEntry? city;
    for (final c in cities) {
      if (c.id == id) {
        city = c;
        break;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _cityId = id;
        if (city != null && _cityCtrl.text.trim().isEmpty) {
          _cityCtrl.text = city.displayName;
        }
      });
    });
  }

  Future<void> _saveAddress() async {
    final doorNo = _doorNoCtrl.text.trim();
    final cityText = _cityCtrl.text.trim();
    final houseError =
        doorNo.isEmpty ? 'Please enter Flat / House No.' : null;
    final cityError =
        cityText.isEmpty ? 'Type the city for this address' : null;
    if (houseError != null || cityError != null) {
      setState(() {
        _houseError = houseError;
        _cityError = cityError;
      });
      showGxSnack(context, houseError ?? cityError!, type: GxSnackType.error);
      return;
    }
    setState(() {
      _houseError = null;
      _cityError = null;
    });
    final cities = ref.read(citiesProvider).value ?? const <CityEntry>[];
    final matched = matchTypedCity(cities, cityText);
    final cityLabel = matched?.displayName ?? cityText;
    _cityId = matched?.id;

    setState(() => _isSaving = true);
    try {
      final fullLine = composeAddressLine(
        house: doorNo,
        landmark: _landmarkCtrl.text,
        area: _areaCtrl.text,
        city: cityLabel,
        pincode: _pincodeCtrl.text,
      );

      final repo = ref.read(addressesRepositoryProvider);
      final saved = await repo.add(
        fullLine,
        label: _selectedLabel,
        lat: widget.pinnedLocation.lat,
        lng: widget.pinnedLocation.lng,
      );

      ref.invalidate(myAddressesProvider);

      if (mounted) {
        Navigator.pop(context, saved);
      }
    } catch (e) {
      debugPrint('Error saving address: $e');
      if (mounted) {
        showGxSnack(context, 'Failed to save address. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  InputDecoration _dec(String label, {bool required = false, String? error}) {
    return InputDecoration(
      labelText: required ? '$label *' : label,
      labelStyle: TextStyle(color: context.gx.ink.withValues(alpha: 0.6)),
      errorText: error,
      border: const OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: context.gx.accent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cities = ref.watch(citiesProvider).value ?? const <CityEntry>[];
    _seedCity(cities);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: context.gx.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 20,
        right: 20,
        bottom: 24 + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Enter complete address',
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.gx.ink,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.gx.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.gx.ink.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: context.gx.accent, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.pinnedLocation.address.isEmpty
                          ? 'Pinned location'
                          : widget.pinnedLocation.address,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.gx.ink,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _doorNoCtrl,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_houseError != null) setState(() => _houseError = null);
              },
              decoration: _dec('Flat / House no / Floor / Building',
                  required: true, error: _houseError),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _landmarkCtrl,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: _dec('Nearby landmark (optional)'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _areaCtrl,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLines: 2,
              decoration: _dec('Area / street / locality'),
            ),
            const SizedBox(height: 16),
            GxCityField(
              cities: cities,
              controller: _cityCtrl,
              focusNode: _cityFocus,
              label: 'City *',
              enabled: !_isSaving,
              loading: ref.watch(citiesProvider).isLoading,
              decoration: _dec('City', required: true, error: _cityError),
              onSelected: (c) => setState(() {
                _cityId = c?.id;
                _cityError = null;
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pincodeCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: _dec('Pincode (optional)'),
            ),
            const SizedBox(height: 24),
            Text(
              'Save address as',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.gx.ink.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _LabelChip(
                  icon: Icons.home_outlined,
                  label: 'Home',
                  isSelected: _selectedLabel == 'Home',
                  onTap: () => setState(() => _selectedLabel = 'Home'),
                ),
                const SizedBox(width: 12),
                _LabelChip(
                  icon: Icons.work_outline,
                  label: 'Work',
                  isSelected: _selectedLabel == 'Work',
                  onTap: () => setState(() => _selectedLabel = 'Work'),
                ),
                const SizedBox(width: 12),
                _LabelChip(
                  icon: Icons.location_on_outlined,
                  label: 'Other',
                  isSelected: _selectedLabel == 'Other',
                  onTap: () => setState(() => _selectedLabel = 'Other'),
                ),
              ],
            ),
            const SizedBox(height: 32),
            GxButton(
              label: 'Save Address',
              loading: _isSaving,
              onTap: _saveAddress,
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _LabelChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? context.gx.accent.withValues(alpha: 0.1) : context.gx.card,
          border: Border.all(
            color: isSelected ? context.gx.accent : context.gx.ink.withValues(alpha: 0.2),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? context.gx.accent : context.gx.ink.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? context.gx.accent : context.gx.ink.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
