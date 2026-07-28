import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme.dart';
import '../../../repositories/addresses_repository.dart';
import '../../../services/location_service.dart';
import '../../../services/location_bootstrap.dart';
import '../../../repositories/cities_repository.dart';
import '../../../repositories/worker_repository.dart'; // selectedLocationProvider
import '../../../shared/widgets/gx_snackbar.dart';
import '../../booking/location_pin_screen.dart';
import 'save_address_bottom_sheet.dart';

class AddressPickerBottomSheet extends ConsumerStatefulWidget {
  const AddressPickerBottomSheet({super.key});

  @override
  ConsumerState<AddressPickerBottomSheet> createState() =>
      _AddressPickerBottomSheetState();
}

class _AddressPickerBottomSheetState
    extends ConsumerState<AddressPickerBottomSheet> {
  bool _isDetecting = false;

  IconData _getIconForLabel(String? label) {
    if (label == null) return Icons.location_on_outlined;
    final lower = label.toLowerCase();
    if (lower == 'home') return Icons.home_outlined;
    if (lower == 'office' || lower == 'work') return Icons.work_outline;
    return Icons.location_on_outlined;
  }

  Future<void> _detectLocation() async {
    setState(() => _isDetecting = true);
    try {
      final pos = await ref
          .read(locationServiceProvider)
          .getCurrentPosition()
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (pos != null) {
        final address = await ref
            .read(locationServiceProvider)
            .getAddressFromLatLng(pos)
            .timeout(const Duration(seconds: 8));
        
        if (!mounted) return;

        final cities = ref.read(citiesProvider).value ?? const <CityEntry>[];
        await applyLocation(
          ref,
          address: address,
          lat: pos.latitude,
          lng: pos.longitude,
          city: nearestCity(cities, pos.latitude, pos.longitude),
        );
        if (mounted) Navigator.pop(context);
      } else {
        showGxSnack(context, 'Please enable Location Services and grant permissions.');
      }
    } catch (e) {
      debugPrint('Location detection failed: $e');
      if (mounted) {
        showGxSnack(context, 'Could not detect location. Please select from the list.');
      }
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  Future<void> _openMapPicker() async {
    // Open the map centred on the user's CURRENT context — their applied
    // location, else their selected city — not a hardcoded fallback. (Bug:
    // this previously always opened in Kochi, 200km from a Trivandrum user.)
    final applied = ref.read(selectedLocationProvider);
    final city = ref.read(currentCityProvider);
    final startLat = applied?.lat ?? city?.lat ?? 8.5241; // Trivandrum
    final startLng = applied?.lng ?? city?.lng ?? 76.9366;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPinScreen(
          initialLat: startLat,
          initialLng: startLng,
          // No placeholder text here — it would leak into the confirmed
          // address if reverse-geocoding fails. Reverse geocode fills it.
          initialAddress: null,
        ),
      ),
    );

    if (!mounted || result == null) return;
    
    // Result is a PinnedLocation or SavedAddress after they confirm and save
    if (result is PinnedLocation) {
      if (!mounted) return;
      final savedAddress = await showModalBottomSheet<SavedAddress?>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SaveAddressBottomSheet(pinnedLocation: result),
      );

      if (!mounted) return;
      if (savedAddress != null) {
        final cities = ref.read(citiesProvider).value ?? const <CityEntry>[];
        await applyLocation(
          ref,
          address: savedAddress.line,
          lat: savedAddress.lat!,
          lng: savedAddress.lng!,
          city: nearestCity(cities, savedAddress.lat!, savedAddress.lng!),
        );
        if (mounted) Navigator.pop(context);
      }
    } else if (result is SavedAddress) {
      final cities = ref.read(citiesProvider).value ?? const <CityEntry>[];
      if (result.hasPin) {
        await applyLocation(
          ref,
          address: result.line,
          lat: result.lat!,
          lng: result.lng!,
          city: nearestCity(cities, result.lat!, result.lng!),
        );
      } else {
        ref.read(currentAddressProvider.notifier).state = result.line;
      }
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final addressesAsync = ref.watch(myAddressesProvider);

    return Container(
      decoration: BoxDecoration(
        color: context.gx.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Select Delivery Address',
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.gx.ink,
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Current location shortcut
          InkWell(
            onTap: _isDetecting ? null : _detectLocation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.my_location, color: context.gx.accent, size: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Use current location',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: context.gx.accent,
                          ),
                        ),
                        if (_isDetecting)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Detecting...',
                              style: TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                          )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const Divider(height: 32, indent: 20, endIndent: 20),
          
          // Saved Addresses
          Flexible(
            child: addressesAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load saved addresses.',
                  style: TextStyle(color: context.gx.ink.withValues(alpha: 0.5)),
                  textAlign: TextAlign.center,
                ),
              ),
              data: (addresses) {
                if (addresses.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Text(
                      'No saved addresses found.',
                      style: TextStyle(color: context.gx.ink.withValues(alpha: 0.5)),
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: addresses.length,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final addr = addresses[index];
                    return InkWell(
                      onTap: () async {
                        if (addr.hasPin) {
                          final cities = ref.read(citiesProvider).value ?? const <CityEntry>[];
                          await applyLocation(
                            ref,
                            address: addr.line,
                            lat: addr.lat!,
                            lng: addr.lng!,
                            city: nearestCity(cities, addr.lat!, addr.lng!),
                          );
                        } else {
                          ref.read(currentAddressProvider.notifier).state = addr.line;
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _getIconForLabel(addr.label),
                            color: context.gx.ink.withValues(alpha: 0.7),
                            size: 24,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (addr.label != null && addr.label!.isNotEmpty)
                                  Text(
                                    addr.label!,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: context.gx.ink,
                                    ),
                                  ),
                                Text(
                                  addr.line,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: context.gx.ink.withValues(alpha: 0.6),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          const Divider(height: 32, indent: 20, endIndent: 20),
          
          // Add new address
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: InkWell(
              onTap: _openMapPicker,
              child: Row(
                children: [
                  Icon(Icons.add, color: context.gx.accent, size: 24),
                  const SizedBox(width: 16),
                  Text(
                    'Add new Address',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.gx.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
