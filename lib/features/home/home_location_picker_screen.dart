import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/location_service.dart';
import '../../repositories/cities_repository.dart';
import '../../repositories/addresses_repository.dart';
import '../../repositories/worker_repository.dart'; // selectedLocationProvider
import '../../shared/widgets/dribbble_background.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../booking/location_pin_screen.dart';
import '../profile/addresses/save_address_bottom_sheet.dart';

class HomePickedLocation {
  final String address;
  final double lat;
  final double lng;

  /// The serviceable city (from the admin cities master) this pick maps to —
  /// direct pick from the list, or nearest-city match for a GPS detect.
  /// Null when the location is outside every serviceable city.
  final CityEntry? city;

  const HomePickedLocation({
    required this.address,
    required this.lat,
    required this.lng,
    this.city,
  });
}

class HomeLocationPickerScreen extends ConsumerStatefulWidget {
  const HomeLocationPickerScreen({super.key});

  @override
  ConsumerState<HomeLocationPickerScreen> createState() =>
      _HomeLocationPickerScreenState();
}

class _HomeLocationPickerScreenState
    extends ConsumerState<HomeLocationPickerScreen> {
  final _searchController = TextEditingController();
  bool _isDetecting = false;

  // Offline fallback only — the real list comes from the cities master via
  // citiesProvider (GET /cities?isActive=true, managed in the admin portal).
  // Shown only when that fetch fails/returns empty, so the picker never
  // renders blank.
  static const List<HomePickedLocation> _fallbackCities = [
    HomePickedLocation(address: 'Kochi, Kerala', lat: 9.9312, lng: 76.2673),
    HomePickedLocation(address: 'Thiruvananthapuram, Kerala', lat: 8.5241, lng: 76.9366),
    HomePickedLocation(address: 'Kozhikode, Kerala', lat: 11.2588, lng: 75.7804),
    HomePickedLocation(address: 'Bangalore, Karnataka', lat: 12.9716, lng: 77.5946),
    HomePickedLocation(address: 'Chennai, Tamil Nadu', lat: 13.0827, lng: 80.2707),
    HomePickedLocation(address: 'Mumbai, Maharashtra', lat: 19.0760, lng: 72.8777),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

        // Map the GPS fix onto the nearest serviceable city (if any) so
        // city-scoped content follows a "use current location" pick too.
        final cities = ref.read(citiesProvider).value ?? const <CityEntry>[];

        Navigator.pop(
          context,
          HomePickedLocation(
            address: address,
            lat: pos.latitude,
            lng: pos.longitude,
            city: nearestCity(cities, pos.latitude, pos.longitude),
          ),
        );
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

  void _selectCity(HomePickedLocation city) {
    Navigator.pop(context, city);
  }

  IconData _iconForLabel(String? label) {
    final l = (label ?? '').toLowerCase();
    if (l == 'home') return Icons.home_outlined;
    if (l == 'work' || l == 'office') return Icons.work_outline;
    return Icons.location_on_outlined;
  }

  /// "Add new Address": pin on the map → save with label → apply as the
  /// current location. Map opens at the user's current context, never a
  /// hardcoded city.
  Future<void> _addNewAddress() async {
    final applied = ref.read(selectedLocationProvider);
    final cities = ref.read(citiesProvider).value ?? const <CityEntry>[];
    final startLat = applied?.lat ?? 8.5241; // Trivandrum fallback
    final startLng = applied?.lng ?? 76.9366;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPinScreen(
          initialLat: startLat,
          initialLng: startLng,
          initialAddress: null,
        ),
      ),
    );
    if (!mounted || result is! PinnedLocation) return;

    final saved = await showModalBottomSheet<SavedAddress?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SaveAddressBottomSheet(pinnedLocation: result),
    );
    if (!mounted || saved == null || !saved.hasPin) return;

    Navigator.pop(
      context,
      HomePickedLocation(
        address: saved.line,
        lat: saved.lat!,
        lng: saved.lng!,
        city: nearestCity(cities, saved.lat!, saved.lng!),
      ),
    );
  }

  /// Saved addresses (pinned ones) + "Add new Address" — the everyday entry
  /// point for the address book, Swiggy-style. Coord-less legacy addresses
  /// are hidden here: without a pin they can't scope the home location.
  Widget _savedAddressesSection() {
    final saved =
        ref.watch(myAddressesProvider).value ?? const <SavedAddress>[];
    final pinned = saved.where((a) => a.hasPin).take(4).toList();
    final cities = ref.watch(citiesProvider).value ?? const <CityEntry>[];

    return Column(
      children: [
        for (final a in pinned)
          InkWell(
            onTap: () => Navigator.pop(
              context,
              HomePickedLocation(
                address: a.line,
                lat: a.lat!,
                lng: a.lng!,
                city: nearestCity(cities, a.lat!, a.lng!),
              ),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Icon(_iconForLabel(a.label),
                      color: context.gx.ink.withValues(alpha: 0.7), size: 22),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (a.label != null && a.label!.isNotEmpty)
                          Text(a.label!,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: context.gx.ink)),
                        Text(a.line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                color:
                                    context.gx.ink.withValues(alpha: 0.55))),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: context.gx.ink.withValues(alpha: 0.38),
                      size: 20),
                ],
              ),
            ),
          ),
        InkWell(
          onTap: _addNewAddress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.add, color: context.gx.accentSoft, size: 22),
                const SizedBox(width: 16),
                Text(
                  'Add new Address',
                  style: TextStyle(
                    color: context.gx.accentSoft,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(color: context.gx.border, height: 1),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search Bar Area
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: context.gx.ink),
                      onPressed: () => Navigator.pop(context),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: context.gx.card2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.gx.border, width: 1.5),
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(color: context.gx.ink, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Search city, area or neighbourhood',
                            hintStyle: TextStyle(color: context.gx.ink.withValues(alpha: 0.55), fontSize: 14),
                            prefixIcon: Icon(Icons.search, color: context.gx.ink.withValues(alpha: 0.55), size: 20),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear, color: context.gx.ink.withValues(alpha: 0.7), size: 18),
                                    onPressed: () => setState(() {
                                      _searchController.clear();
                                    }),
                                  )
                                : null,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Divider(color: context.gx.border, height: 1),

              // Use Current Location
              InkWell(
                onTap: _isDetecting ? null : _detectLocation,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(Icons.my_location, color: context.gx.accentSoft, size: 24),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Use current location',
                              style: TextStyle(
                                color: context.gx.accentSoft,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Using GPS',
                              style: TextStyle(
                                color: context.gx.ink.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isDetecting)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: context.gx.accentSoft),
                        ),
                    ],
                  ),
                ),
              ),

              Divider(color: context.gx.border, height: 1),

              // Saved addresses + add-new (address book entry point)
              _savedAddressesSection(),

              // Serviceable cities (admin cities master; fallback when offline)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Text(
                  'AVAILABLE CITIES',
                  style: TextStyle(
                    color: context.gx.ink.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),

              Expanded(
                child: Builder(builder: (context) {
                  final citiesAsync = ref.watch(citiesProvider);
                  final fetched = citiesAsync.value ?? const <CityEntry>[];
                  // API cities carry their CityEntry (for content scoping);
                  // the hardcoded fallback has none.
                  var items = fetched.isNotEmpty
                      ? fetched
                          .map((c) => HomePickedLocation(
                                address: c.displayName,
                                lat: c.lat,
                                lng: c.lng,
                                city: c,
                              ))
                          .toList()
                      : _fallbackCities;

                  final query = _searchController.text.trim().toLowerCase();
                  if (query.isNotEmpty) {
                    items = items
                        .where((c) => c.address.toLowerCase().contains(query))
                        .toList();
                  }

                  if (citiesAsync.isLoading && fetched.isEmpty) {
                    return Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: context.gx.accentSoft),
                    );
                  }

                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        'No matching city',
                        style: TextStyle(
                            color: context.gx.ink.withValues(alpha: 0.5),
                            fontSize: 13),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        Divider(color: context.gx.border, height: 1),
                    itemBuilder: (context, index) {
                      final city = items[index];
                      return ListTile(
                        onTap: () => _selectCity(city),
                        leading: Icon(Icons.location_city,
                            color: context.gx.ink.withValues(alpha: 0.7), size: 20),
                        title: Text(
                          city.address,
                          style: TextStyle(
                              color: context.gx.ink, fontSize: 14),
                        ),
                        trailing: Icon(Icons.chevron_right,
                            color: context.gx.ink.withValues(alpha: 0.38), size: 20),
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
