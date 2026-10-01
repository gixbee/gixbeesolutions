import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/hall_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_text_field.dart';
import 'hall_business_home_screen.dart';

class HallSetupScreen extends ConsumerStatefulWidget {
  const HallSetupScreen({super.key, required this.business});
  final Business business;

  @override
  ConsumerState<HallSetupScreen> createState() => _HallSetupScreenState();
}

class _HallSetupScreenState extends ConsumerState<HallSetupScreen> {
  final _countCtrl = TextEditingController(text: '1');
  final _carCtrl = TextEditingController(text: '0');
  final _bikeCtrl = TextEditingController(text: '0');
  bool _saving = false;
  bool _showParking = false;

  @override
  void dispose() {
    _countCtrl.dispose();
    _carCtrl.dispose();
    _bikeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final count = int.tryParse(_countCtrl.text.trim()) ?? 0;
    if (count < 1 || count > 50) {
      showGxSnack(context, 'Enter a hall count between 1 and 50',
          type: GxSnackType.error);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(hallRepositoryProvider).patchVenue(widget.business.id, {
        'plannedHallCount': count,
        'commonParking': {
          'car': int.tryParse(_carCtrl.text.trim()) ?? 0,
          'bike': int.tryParse(_bikeCtrl.text.trim()) ?? 0,
        },
        'hallSetupComplete': true,
        'timezone': 'Asia/Kolkata',
      });
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HallBusinessHomeScreen(business: widget.business),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, 'Save failed: $e', type: GxSnackType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hall venue setup')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.business.name,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'How many halls or spaces do you want to list?',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          GxTextField(
            controller: _countCtrl,
            label: 'Number of halls',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          if (!_showParking)
            GxButton(
              label: 'Next — parking',
              onTap: () => setState(() => _showParking = true),
            )
          else ...[
            GxTextField(
              controller: _carCtrl,
              label: 'Car parking spots (shared)',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            GxTextField(
              controller: _bikeCtrl,
              label: 'Bike parking spots (shared)',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            GxButton(
              label: _saving ? 'Saving…' : 'Save and continue',
              onTap: _saving ? null : _save,
            ),
          ],
        ],
      ),
    );
  }
}
