import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme.dart';
import '../../../repositories/addresses_repository.dart';
import '../../../shared/widgets/gx_button.dart';
import '../../../shared/widgets/gx_snackbar.dart';
import '../../booking/location_pin_screen.dart';

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
  String _selectedLabel = 'Home';
  bool _isSaving = false;

  @override
  void dispose() {
    _doorNoCtrl.dispose();
    _landmarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAddress() async {
    final doorNo = _doorNoCtrl.text.trim();
    if (doorNo.isEmpty) {
      showGxSnack(context, 'Please enter Flat / House No.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final landmark = _landmarkCtrl.text.trim();
      final fullLine = [
        doorNo,
        if (landmark.isNotEmpty) landmark,
        widget.pinnedLocation.address
      ].join(', ');

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

  @override
  Widget build(BuildContext context) {
    // Handle keyboard padding so the bottom sheet pushes up
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
              border: Border.all(color: context.gx.ink.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on, color: context.gx.accent, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.pinnedLocation.address,
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
            decoration: InputDecoration(
              labelText: 'Flat / House no / Floor / Building *',
              labelStyle: TextStyle(color: context.gx.ink.withValues(alpha: 0.6)),
              border: const OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: context.gx.accent),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          TextField(
            controller: _landmarkCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Nearby landmark (optional)',
              labelStyle: TextStyle(color: context.gx.ink.withValues(alpha: 0.6)),
              border: const OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: context.gx.accent),
              ),
            ),
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
