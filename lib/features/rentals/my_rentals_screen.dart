import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/config/app_config.dart';
import '../../repositories/rentals_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../theme.dart';
import 'rental_fulfillment_card.dart';

/// Customer's rental reservations: status timeline + cancel while
/// PENDING/CONFIRMED.
class MyRentalsScreen extends ConsumerStatefulWidget {
  const MyRentalsScreen({super.key, this.initialReservationId});

  /// When set (e.g. from Activity), scrolls to that reservation after load.
  final String? initialReservationId;

  @override
  ConsumerState<MyRentalsScreen> createState() => _MyRentalsScreenState();
}

class _MyRentalsScreenState extends ConsumerState<MyRentalsScreen> {
  List<Map<String, dynamic>> _reservations = [];
  bool _loading = true;
  bool _paying = false;
  bool _focusReservationPending = true;
  final _scrollController = ScrollController();
  Razorpay? _razorpay;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _razorpay?.clear();
    super.dispose();
  }

  void _openInitialReservation() {
    final id = widget.initialReservationId?.trim();
    if (id == null || id.isEmpty || !_focusReservationPending) return;
    Map<String, dynamic>? match;
    for (final r in _reservations) {
      if (r['id']?.toString() == id) {
        match = r;
        break;
      }
    }
    if (match == null) return;
    _focusReservationPending = false;
    final row = match;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showReservationDetailSheet(row);
    });
  }

  Future<void> _showReservationDetailSheet(Map<String, dynamic> r) {
    final fmt = DateFormat('d MMM, h:mm a');
    final item = r['item'] as Map? ?? {};
    return showGxSheet<void>(
      context,
      title: '${item['name'] ?? 'Reservation'}',
      child: SingleChildScrollView(
        child: _renterReservationBody(r, fmt),
      ),
    );
  }

  Widget _renterReservationBody(Map<String, dynamic> r, DateFormat fmt) {
    final status = '${r['status'] ?? ''}';
    final (color, label) = _statusStyle(status);
    final item = r['item'] as Map? ?? {};
    final canCancel = (status == 'PENDING' ||
            status == 'PENDING_OWNER_CONFIRMATION' ||
            status == 'TEMP_HOLD' ||
            status == 'PAYMENT_PENDING' ||
            status == 'CONFIRMED') &&
        r['ownerHandedOverAt'] == null &&
        r['renterCollectedAt'] == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${item['name'] ?? ''}',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: context.gx.ink)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: color)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${fmt.format(DateTime.parse('${r['startTime']}').toLocal())}  →  ${fmt.format(DateTime.parse('${r['endTime']}').toLocal())}',
          style: TextStyle(
              fontSize: 12.5, color: context.gx.ink.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
                '₹${num.tryParse('${r['totalPrice']}')?.round() ?? r['totalPrice']}',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: GixbeeTheme.accentTeal)),
            const Spacer(),
            if (canCancel)
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _cancel(r);
                },
                child: const Text('Cancel',
                    style: TextStyle(
                        fontSize: 12.5, color: Color(0xFFEF4444))),
              ),
          ],
        ),
        if (status == 'TEMP_HOLD' || status == 'PAYMENT_PENDING') ...[
          const SizedBox(height: 8),
          GxButton(
            label:
                'Pay advance ₹${num.tryParse('${r['advanceAmount']}')?.round() ?? r['advanceAmount']}',
            height: 40,
            radius: 10,
            fontSize: 12.5,
            loading: _paying,
            onTap: _paying ? null : () => _payAdvance(r),
          ),
        ],
        if ('${r['handoverOtp'] ?? ''}'.isNotEmpty && status == 'CONFIRMED') ...[
          const SizedBox(height: 8),
          Text(
            'Pickup OTP ${r['handoverOtp']} — show this at the store',
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: GixbeeTheme.accentTeal),
          ),
        ],
        if ('${r['returnOtp'] ?? ''}'.isNotEmpty &&
            (status == 'ACTIVE' || status == 'RETURN_PENDING')) ...[
          const SizedBox(height: 8),
          Text(
            'Return OTP ${r['returnOtp']}',
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: GixbeeTheme.accentTeal),
          ),
        ],
        RentalFulfillmentCard(
            key: ValueKey(r['id']),
            reservation: r,
            isOwner: false,
            onChanged: _load),
      ],
    );
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(rentalsRepositoryProvider).myReservations();
      if (mounted) {
        setState(() {
          _reservations = res;
          _loading = false;
        });
        _openInitialReservation();
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

  Future<void> _payAdvance(Map<String, dynamic> r) async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      final order = await ref
          .read(rentalsRepositoryProvider)
          .createAdvanceOrder(r['id'].toString());
      _razorpay ??= Razorpay()
        ..on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse _) {
          if (!mounted) return;
          showGxSnack(context, 'Advance received — waiting for the store',
              type: GxSnackType.success);
          _load();
        })
        ..on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
          if (!mounted) return;
          showGxSnack(context, response.message ?? 'Payment failed',
              type: GxSnackType.error);
        })
        ..on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});
      _razorpay!.open({
        'key': order['keyId'] ?? AppConfig.razorpayKey,
        'order_id': order['orderId'],
        'amount': order['amount'],
        'currency': order['currency'] ?? 'INR',
        'name': 'Gixbee Rentals',
      });
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Could not start advance payment: $e',
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  (Color, String) _statusStyle(String status) {
    switch (status) {
      case 'TEMP_HOLD':
      case 'PAYMENT_PENDING':
        return (GixbeeTheme.accentGold, 'Pay advance to hold');
      case 'PENDING':
      case 'PENDING_OWNER_CONFIRMATION':
        return (GixbeeTheme.accentGold, 'Awaiting store');
      case 'CONFIRMED':
        return (GixbeeTheme.accentTeal, 'Confirmed');
      case 'ACTIVE':
        return (GixbeeTheme.accentViolet, 'With you now');
      case 'RETURN_PENDING':
        return (GixbeeTheme.accentViolet, 'Returned — settling');
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
                              controller: _scrollController,
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 20),
                              itemCount: _reservations.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final r = _reservations[i];
                                return GxPressable(
                                  onTap: () => _showReservationDetailSheet(r),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: context.gx.card,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: context.gx.border,
                                          width: 1.5),
                                    ),
                                    child: _renterReservationBody(r, fmt),
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
