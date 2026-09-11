import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/config/app_config.dart';
import '../../repositories/rentals_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_calendar.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_time_picker.dart';
import '../../shared/widgets/gx_text_field.dart';
import '../../theme.dart';
import 'my_rentals_screen.dart';

/// Rental item detail: photo, rates, description, already-booked windows,
/// and a start/end picker → reserve (owner then confirms; both get pushes).
class RentalItemDetailScreen extends ConsumerStatefulWidget {
  final String itemId;

  const RentalItemDetailScreen({super.key, required this.itemId});

  @override
  ConsumerState<RentalItemDetailScreen> createState() =>
      _RentalItemDetailScreenState();
}

class _RentalItemDetailScreenState
    extends ConsumerState<RentalItemDetailScreen> {
  Map<String, dynamic>? _item;
  bool _loading = true;
  DateTime? _start;
  DateTime? _end;
  bool _submitting = false;
  int _quantity = 1;
  bool _delivery = false;
  final _deliveryAddress = TextEditingController();

  @override
  void dispose() { _deliveryAddress.dispose(); super.dispose(); }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final item =
          await ref.read(rentalsRepositoryProvider).getItemDetail(widget.itemId);
      if (mounted) {
        setState(() {
          _item = item;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Item load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showGxCalendar(
      context,
      title: 'Rental date',
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      accent: GixbeeTheme.accentTeal,
      accentGradient: const [GixbeeTheme.accentTeal, Color(0xFF0F766E)],
    );
    if (date == null || !mounted) return null;
    final time = await showGxTimePicker(
      context,
      title: 'Rental time',
      initialTime: TimeOfDay.fromDateTime(initial),
      accent: GixbeeTheme.accentTeal,
      accentGradient: const [GixbeeTheme.accentTeal, Color(0xFF0F766E)],
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  double? get _estimatedPrice {
    if (_item == null || _start == null || _end == null) return null;
    final hours = _end!.difference(_start!).inMinutes / 60.0;
    if (hours <= 0) return null;
    final daily = num.tryParse('${_item!['dailyRate'] ?? ''}');
    final hourly = num.tryParse('${_item!['hourlyRate'] ?? 0}') ?? 0;
    final rent = daily != null && hours >= 24 ? (hours / 24).ceil() * daily.toDouble() : hours * hourly.toDouble();
    final deposit = num.tryParse('${_item!['depositPerUnit'] ?? 0}') ?? 0;
    final delivery = _delivery ? num.tryParse('${_item!['deliveryFee'] ?? 0}') ?? 0 : 0;
    return (rent + deposit) * _quantity + delivery;
  }

  Future<void> _reserve() async {
    if (_submitting) return;
    if (_start == null || _end == null) {
      showGxSnack(context, 'Pick a start and end time',
          type: GxSnackType.error);
      return;
    }
    if (!_end!.isAfter(_start!)) {
      showGxSnack(context, 'End must be after start', type: GxSnackType.error);
      return;
    }
    final minimum = int.tryParse('${_item?['minHoursToRent'] ?? 1}') ?? 1;
    if (_end!.difference(_start!).inMinutes < minimum * 60) {
      showGxSnack(context, 'Minimum rental period is $minimum hours'); return;
    }
    if (_delivery && _deliveryAddress.text.trim().isEmpty) {
      showGxSnack(context, 'Enter your delivery address'); return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(rentalsRepositoryProvider).reserve(
            itemId: widget.itemId,
            start: _start!,
            end: _end!,
            quantity: _quantity, fulfillment: _delivery ? 'DELIVERY' : 'PICKUP',
            deliveryAddress: _deliveryAddress.text.trim(),
          );
      if (!mounted) return;
      showGxSnack(context, 'Request sent — the owner will confirm.',
          type: GxSnackType.success);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MyRentalsScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showGxSnack(context, 'Could not reserve: $e', type: GxSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE, d MMM · h:mm a');
    final imageUrl = _item?['imageUrl'] as String?;
    final booked = (_item?['bookedRanges'] as List? ?? []);

    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _item == null
                  ? Center(
                      child: Text('Item not found',
                          style: TextStyle(color: context.gx.ink.withValues(alpha: 0.54))))
                  : Column(
                      children: [
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.zero,
                            children: [
                              // Image header + back
                              Stack(
                                children: [
                                  Container(
                                    height: 220,
                                    width: double.infinity,
                                    color: context.gx.card2,
                                    child: imageUrl != null &&
                                            imageUrl.isNotEmpty
                                        ? Image.network(
                                            imageUrl.startsWith('http')
                                                ? imageUrl
                                                : '${AppConfig.baseUrl}$imageUrl',
                                            fit: BoxFit.cover,
                                            cacheWidth: 800,
                                            errorBuilder: (_, __, ___) =>
                                                Icon(
                                                    Icons
                                                        .inventory_2_outlined,
                                                    color: context.gx.ink.withValues(alpha: 0.24),
                                                    size: 48),
                                          )
                                        : Icon(
                                            Icons.inventory_2_outlined,
                                            color: context.gx.ink.withValues(alpha: 0.24),
                                            size: 48),
                                  ),
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: CircleAvatar(
                                      backgroundColor: Colors.black54,
                                      child: IconButton(
                                        icon: const Icon(Icons.arrow_back,
                                            color: Colors.white, size: 20),
                                        onPressed: () =>
                                            Navigator.pop(context),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 16, 20, 0),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('${_item!['name'] ?? ''}',
                                        style: TextStyle(
                                            fontSize: 21,
                                            fontWeight: FontWeight.w900,
                                            color: context.gx.ink)),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Text(
                                            '₹${num.tryParse('${_item!['hourlyRate']}')?.round()}/hr',
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color:
                                                    GixbeeTheme.accentTeal)),
                                        if (_item!['dailyRate'] != null) ...[
                                          const SizedBox(width: 10),
                                          Text(
                                              '₹${num.tryParse('${_item!['dailyRate']}')?.round()}/day',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color: context.gx.ink
                                                      .withValues(
                                                          alpha: 0.6))),
                                        ],
                                        const Spacer(),
                                        Text(
                                            'Min ${_item!['minHoursToRent'] ?? 1}h',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: context.gx.ink
                                                    .withValues(alpha: 0.45))),
                                      ],
                                    ),
                                    if ((_item!['description'] as String?)
                                            ?.isNotEmpty ??
                                        false) ...[
                                      const SizedBox(height: 12),
                                      Text('${_item!['description']}',
                                          style: TextStyle(
                                              fontSize: 13.5,
                                              height: 1.55,
                                              color: context.gx.ink
                                                  .withValues(alpha: 0.65))),
                                    ],
                                    if (booked.isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      Text('ALREADY BOOKED',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.2,
                                              color: context.gx.ink
                                                  .withValues(alpha: 0.45))),
                                      const SizedBox(height: 8),
                                      for (final r in booked)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 4),
                                          child: Text(
                                            '${fmt.format(DateTime.parse('${r['start']}').toLocal())}  →  ${fmt.format(DateTime.parse('${r['end']}').toLocal())}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: GixbeeTheme.accentGold),
                                          ),
                                        ),
                                    ],
                                    const SizedBox(height: 20),
                                    Row(children: [
                                      const Expanded(child: Text('Quantity')),
                                      IconButton(onPressed: _quantity <= 1 ? null : () => setState(() => _quantity--), icon: const Icon(Icons.remove)),
                                      Text('$_quantity'),
                                      IconButton(onPressed: _quantity >= (int.tryParse('${_item!['quantity'] ?? 1}') ?? 1) ? null : () => setState(() => _quantity++), icon: const Icon(Icons.add)),
                                    ]),
                                    Text('Pickup: ${_item!['pickupAddress'] ?? 'Coordinate with the owner'}'),
                                    if (_item!['deliveryAvailable'] == true)
                                      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Request delivery'),
                                        subtitle: Text('₹${_item!['deliveryFee'] ?? 0} per reservation'), value: _delivery,
                                        onChanged: (value) => setState(() => _delivery = value)),
                                    if (_delivery) GxTextField(controller: _deliveryAddress, label: 'Delivery address', maxLines: 2, maxLength: 2000),
                                    const SizedBox(height: 12),
                                    Text('Refundable deposit: ₹${_item!['depositPerUnit'] ?? 0} per unit. Included in the total. Fully refundable after return; cancel before handover for a refund of amounts paid.'),
                                    const SizedBox(height: 20),
                                    Text('WHEN DO YOU NEED IT?',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 1.2,
                                            color: context.gx.ink
                                                .withValues(alpha: 0.45))),
                                    const SizedBox(height: 10),
                                    _timeRow(
                                        'From',
                                        _start == null
                                            ? 'Pick start'
                                            : fmt.format(_start!), () async {
                                      final picked = await _pickDateTime(
                                          _start ??
                                              DateTime.now().add(
                                                  const Duration(hours: 1)));
                                      if (picked != null) {
                                        setState(() => _start = picked);
                                      }
                                    }),
                                    const SizedBox(height: 8),
                                    _timeRow(
                                        'Until',
                                        _end == null
                                            ? 'Pick end'
                                            : fmt.format(_end!), () async {
                                      final picked = await _pickDateTime(_end ??
                                          (_start ?? DateTime.now())
                                              .add(const Duration(hours: 4)));
                                      if (picked != null) {
                                        setState(() => _end = picked);
                                      }
                                    }),
                                    if (_estimatedPrice != null) ...[
                                      const SizedBox(height: 14),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Estimated total',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color: context.gx.ink
                                                      .withValues(
                                                          alpha: 0.6))),
                                          Text(
                                              '₹${_estimatedPrice!.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w900,
                                                  color: GixbeeTheme
                                                      .accentTeal)),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 20),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          child: GxButton(
                            label: _submitting
                                ? 'Sending request…'
                                : 'Request to rent',
                            icon: Icons.event_available_rounded,
                            onTap: _submitting ? null : _reserve,
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _timeRow(String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: context.gx.card2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.gx.border, width: 1.5),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: context.gx.ink.withValues(alpha: 0.5))),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: context.gx.ink)),
            ),
            const Icon(Icons.calendar_month_rounded,
                size: 17, color: GixbeeTheme.accentTeal),
          ],
        ),
      ),
    );
  }
}
