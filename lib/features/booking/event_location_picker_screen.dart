import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/location_service.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/glass_container.dart';

/// Simple LatLng replacement to avoid Google Maps dependency
class SimpleLatLng {
  final double latitude;
  final double longitude;
  const SimpleLatLng(this.latitude, this.longitude);
}

/// Result returned when the user picks a location.
class PickedLocation {
  final String address;
  final double lat;
  final double lng;
  final String? contactName;
  final String? contactRelation;
  final String? contactPhone;

  const PickedLocation({
    required this.address,
    required this.lat,
    required this.lng,
    this.contactName,
    this.contactRelation,
    this.contactPhone,
  });
}

class EventLocationPickerScreen extends ConsumerStatefulWidget {
  const EventLocationPickerScreen({super.key});

  @override
  ConsumerState<EventLocationPickerScreen> createState() =>
      _EventLocationPickerScreenState();
}

class _EventLocationPickerScreenState
    extends ConsumerState<EventLocationPickerScreen> {
  final _addressController = TextEditingController();
  final _contactNameCtrl = TextEditingController();
  final _contactRelationCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();

  // Default to Kochi, Kerala
  SimpleLatLng _selectedPoint = const SimpleLatLng(9.9312, 76.2673);
  bool _isDetecting = false;
  bool _showContactFields = false;

  final List<_SavedLocation> _savedAddresses = [
    const _SavedLocation(
      label: 'Home',
      icon: Icons.home_rounded,
      address: 'Flat 4B, Prestige Tower, MG Road, Kochi',
      point: SimpleLatLng(9.9312, 76.2673),
    ),
    const _SavedLocation(
      label: 'Office',
      icon: Icons.work_rounded,
      address: 'TechPark Phase 2, InfoPark, Kakkanad',
      point: SimpleLatLng(10.0159, 76.3419),
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _detectLocation());
  }

  Future<void> _detectLocation() async {
    setState(() => _isDetecting = true);
    try {
      final pos = await ref
          .read(locationServiceProvider)
          .getCurrentPosition()
          .timeout(const Duration(seconds: 15));
      if (pos != null && mounted) {
        final address = await ref
            .read(locationServiceProvider)
            .getAddressFromLatLng(pos)
            .timeout(const Duration(seconds: 8));
        setState(() {
          _selectedPoint = SimpleLatLng(pos.latitude, pos.longitude);
          _addressController.text = address;
        });
      }
    } catch (e) {
      debugPrint('Location detection failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not detect location. Please type an address manually.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  void _selectSavedAddress(_SavedLocation addr) {
    setState(() {
      _addressController.text = addr.address;
      _selectedPoint = addr.point;
    });
  }

  void _confirmLocation() {
    if (_addressController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a location')),
      );
      return;
    }

    Navigator.pop(
      context,
      PickedLocation(
        address: _addressController.text,
        lat: _selectedPoint.latitude,
        lng: _selectedPoint.longitude,
        contactName:
            _contactNameCtrl.text.isNotEmpty ? _contactNameCtrl.text : null,
        contactRelation: _contactRelationCtrl.text.isNotEmpty
            ? _contactRelationCtrl.text
            : null,
        contactPhone:
            _contactPhoneCtrl.text.isNotEmpty ? _contactPhoneCtrl.text : null,
      ),
    );
  }

  @override
  void dispose() {
    _addressController.dispose();
    _contactNameCtrl.dispose();
    _contactRelationCtrl.dispose();
    _contactPhoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: DribbbleBackground(
        child: Column(
          children: [
            // ── TOP SECTION (Safe Area + Glass Search) ──
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Text(
                          'Service Location',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: _isDetecting ? null : _detectLocation,
                          icon: _isDetecting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.my_location_rounded, color: Colors.white),
                          tooltip: 'Use current location',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    GlassContainer(
                      padding: EdgeInsets.zero,
                      borderRadius: BorderRadius.circular(16),
                      child: TextField(
                        controller: _addressController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Search area, street, landmark...',
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
                          prefixIcon: const Icon(Icons.search, color: Colors.white70, size: 22),
                          suffixIcon: _addressController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.white70, size: 18),
                                  onPressed: () => setState(() {
                                    _addressController.clear();
                                  }),
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── MAIN CONTENT ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dynamic Map Placeholder / Visual
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.1),
                              Colors.white.withValues(alpha: 0.05),
                            ],
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(Icons.map_outlined, 
                              size: 80, 
                              color: Colors.white.withValues(alpha: 0.1)
                            ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.location_on, color: cs.primary, size: 32),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Precise Location Detected',
                                  style: TextStyle(
                                    color: Colors.white70, 
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Saved Addresses
                    Text(
                      'Saved Addresses',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    ..._savedAddresses.map((addr) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () => _selectSavedAddress(addr),
                        borderRadius: BorderRadius.circular(16),
                        child: GlassContainer(
                          padding: const EdgeInsets.all(16),
                          borderRadius: BorderRadius.circular(16),
                          border: _addressController.text == addr.address
                              ? Border.all(color: cs.primary, width: 2)
                              : null,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(addr.icon, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      addr.label,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      addr.address,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (_addressController.text == addr.address)
                                Icon(Icons.check_circle, color: cs.primary, size: 20),
                            ],
                          ),
                        ),
                      ),
                    )),

                    const SizedBox(height: 24),

                    // On-site Contact
                    InkWell(
                      onTap: () => setState(() => _showContactFields = !_showContactFields),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.person_pin_circle_rounded, color: Colors.white70, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Add On-Site Contact',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Icon(
                              _showContactFields ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (_showContactFields) ...[
                      const SizedBox(height: 12),
                      _buildGlassField(_contactNameCtrl, Icons.person_outline, 'Contact Name'),
                      const SizedBox(height: 12),
                      _buildGlassField(_contactRelationCtrl, Icons.people_outline, 'Relation'),
                      const SizedBox(height: 12),
                      _buildGlassField(_contactPhoneCtrl, Icons.phone_outlined, 'Phone Number', keyboardType: TextInputType.phone),
                    ],

                    const SizedBox(height: 48),

                    // Confirm Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _addressController.text.isNotEmpty ? _confirmLocation : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Confirm Location',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
    );
  }

  Widget _buildGlassField(TextEditingController ctrl, IconData icon, String label, {TextInputType? keyboardType}) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      borderRadius: BorderRadius.circular(12),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          icon: Icon(icon, color: Colors.white70, size: 20),
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _SavedLocation {
  final String label;
  final IconData icon;
  final String address;
  final SimpleLatLng point;

  const _SavedLocation({
    required this.label,
    required this.icon,
    required this.address,
    required this.point,
  });
}

