import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../repositories/rentals_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import 'rental_fulfillment_card.dart';

/// Customer's rental reservations: status timeline + cancel while
/// PENDING/CONFIRMED.
class MyRentalsScreen extends ConsumerStatefulWidget {
  const MyRentalsScreen({super.key});

  @override
  ConsumerState<MyRentalsScreen> createState() => _MyRentalsScreenState();
}

class _MyRentalsScreenState extends ConsumerState<MyRentalsScreen> {
  List<Map<String, dynamic>> _reservations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(rentalsRepositoryProvider).myReservations();
      if (mounted) {
        setState(() {
          _reservations = res;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Reservations load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(Map<String, dynamic> r) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Cancel reservation?'),
      content: const Text('This releases your reserved units. Any amount already paid must be refunded directly by the owner and acknowledged by both participants.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep rental')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel rental'))],
    ));
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(rentalsRepositoryProvider)
          .decide(r['id'].toString(), 'cancel');
      if (mounted) {
        showGxSnack(context, 'Reservation cancelled',
            type: GxSnackType.success);
        _load();
      }
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Could not cancel: $e', type: GxSnackType.error);
      }
    }
  }

  (Color, String) _statusStyle(String status) {
    switch (status) {
      case 'PENDING':
        return (GixbeeTheme.accentGold, 'Awaiting owner');
      case 'CONFIRMED':
        return (GixbeeTheme.accentTeal, 'Confirmed');
      case 'ACTIVE':
        return (GixbeeTheme.accentViolet, 'With you now');
      case 'COMPLETED':
        return (GixbeeTheme.accentGreen, 'Completed');
      case 'REJECTED':
        return (const Color(0xFFEF4444), 'Declined');
      default:
        return (Colors.white38, 'Cancelled');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM, h:mm a');
    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: context.gx.ink),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text('My rentals',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: context.gx.ink)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _reservations.isEmpty
                        ? Center(
                            child: Text('No reservations yet',
                                style: TextStyle(
                                    fontSize: 14,
                                    color:
                                        context.gx.ink.withValues(alpha: 0.5))),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 20),
                              itemCount: _reservations.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final r = _reservations[i];
                                final status = '${r['status'] ?? ''}';
                                final (color, label) = _statusStyle(status);
                                final item = r['item'] as Map? ?? {};
                                final canCancel = (status == 'PENDING' || status == 'CONFIRMED') &&
                                    r['ownerHandedOverAt'] == null && r['renterCollectedAt'] == null;
                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: context.gx.card,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: context.gx.border,
                                        width: 1.5),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text('${item['name'] ?? ''}',
                                                style: TextStyle(
                                                    fontSize: 14.5,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    color: context.gx.ink)),
                                          ),
                                          Container(
                                            padding: const EdgeInsets
                                                .symmetric(
                                                horizontal: 9, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: color.withValues(
                                                  alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(label,
                                                style: TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    color: color)),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${fmt.format(DateTime.parse('${r['startTime']}').toLocal())}  →  ${fmt.format(DateTime.parse('${r['endTime']}').toLocal())}',
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            color: context.gx.ink
                                                .withValues(alpha: 0.6)),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Text(
                                              '₹${num.tryParse('${r['totalPrice']}')?.round() ?? r['totalPrice']}',
                                              style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w900,
                                                  color:
                                                      GixbeeTheme.accentTeal)),
                                          const Spacer(),
                                          if (canCancel)
                                            TextButton(
                                              onPressed: () => _cancel(r),
                                              child: const Text('Cancel',
                                                  style: TextStyle(
                                                      fontSize: 12.5,
                                                      color: Color(
                                                          0xFFEF4444))),
                                            ),
                                        ],
                                      ),
                                      RentalFulfillmentCard(key: ValueKey(r['id']), reservation: r, isOwner: false, onChanged: _load),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
