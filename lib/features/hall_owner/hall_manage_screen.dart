import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/hall_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_snackbar.dart';
import 'hall_calendar_screen.dart';
import 'hall_enquiries_inbox_screen.dart';
import 'hall_operators_screen.dart';
import 'hall_package_wizard_screen.dart';
import 'hall_photos_screen.dart';

class HallManageScreen extends ConsumerStatefulWidget {
  const HallManageScreen({
    super.key,
    required this.business,
    required this.hallId,
  });
  final Business business;
  final String hallId;

  @override
  ConsumerState<HallManageScreen> createState() => _HallManageScreenState();
}

class _HallManageScreenState extends ConsumerState<HallManageScreen> {
  Map<String, dynamic>? _hall;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final h = await ref
          .read(hallRepositoryProvider)
          .getHall(widget.business.id, widget.hallId);
      if (!mounted) return;
      setState(() {
        _hall = h;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showGxSnack(context, '$e', type: GxSnackType.error);
    }
  }

  bool get _packageSaved => _hall?['packageSaved'] == true;

  Future<void> _openGuarded(Widget screen, {required bool needsPackage}) async {
    if (needsPackage && !_packageSaved) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Package required'),
          content: const Text(
            'Open Price & packages, complete all steps, and tap Save Package on Review. Then Calendar, Operators, and Booking requests unlock for this hall.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  Future<void> _archive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive hall?'),
        content: const Text(
          'This removes the hall from your active list. Existing bookings are kept. You cannot archive a hall with active holds or confirmations.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Archive')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(hallRepositoryProvider)
          .archiveHall(widget.business.id, widget.hallId);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, '$e', type: GxSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (_hall?['name'] as String?) ?? 'Hall';
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _tile(
                  Icons.currency_rupee,
                  'Price & packages',
                  'Slots, pricing, cancellation policy',
                  () => _openGuarded(
                    HallPackageWizardScreen(
                      business: widget.business,
                      hallId: widget.hallId,
                    ),
                    needsPackage: false,
                  ),
                ),
                _tile(
                  Icons.calendar_month,
                  'Calendar',
                  'Availability and blocked dates',
                  () => _openGuarded(
                    HallCalendarScreen(
                      business: widget.business,
                      hallId: widget.hallId,
                    ),
                    needsPackage: true,
                  ),
                ),
                _tile(
                  Icons.inbox_outlined,
                  'Booking requests',
                  'Assigned enquiries for this hall (read-only for operators)',
                  () => _openGuarded(
                    HallEnquiriesInboxScreen(
                      business: widget.business,
                      hallId: widget.hallId,
                    ),
                    needsPackage: true,
                  ),
                ),
                _tile(
                  Icons.groups_outlined,
                  'Operators',
                  'Who can manage this hall calendar',
                  () => _openGuarded(
                    HallOperatorsScreen(
                      business: widget.business,
                      hallId: widget.hallId,
                    ),
                    needsPackage: true,
                  ),
                ),
                _tile(
                  Icons.photo_library_outlined,
                  'Photos',
                  'Cover image and gallery',
                  () => _openGuarded(
                    HallPhotosScreen(
                      business: widget.business,
                      hallId: widget.hallId,
                    ),
                    needsPackage: false,
                  ),
                ),
                _tile(
                  Icons.archive_outlined,
                  'Archive hall',
                  'Remove from active list',
                  _archive,
                  danger: true,
                ),
              ],
            ),
    );
  }

  Widget _tile(
    IconData icon,
    String title,
    String sub,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: danger ? Colors.red : null),
      title: Text(title, style: TextStyle(color: danger ? Colors.red : null)),
      subtitle: Text(sub),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
