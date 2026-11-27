import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/rentals_repository.dart';
import '../../repositories/events_repository.dart' show eventMoney, eventError;
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';

/// Both participants see the same saved terms and acknowledge only their side.
class RentalFulfillmentCard extends ConsumerStatefulWidget {
  const RentalFulfillmentCard({super.key, required this.reservation, required this.isOwner, required this.onChanged});
  final Map<String, dynamic> reservation;
  final bool isOwner;
  final Future<void> Function() onChanged;
  @override
  ConsumerState<RentalFulfillmentCard> createState() => _RentalFulfillmentCardState();
}

class _RentalFulfillmentCardState extends ConsumerState<RentalFulfillmentCard> {
  bool _busy = false;
  final _otpCtrl = TextEditingController();

  @override
  void dispose() {
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _ack(String action, String label, String message) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(label), content: Text(message), actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Go back')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
      ]));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(rentalsRepositoryProvider).acknowledge('${widget.reservation['id']}', action);
      await widget.onChanged();
    } catch (e) {
      if (mounted) showGxSnack(context, eventError(e));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Widget _button(String action, String label, String message) => Padding(
    padding: const EdgeInsets.only(top: 8), child: GxButton(label: label, filled: false,
      loading: _busy, onTap: () => _ack(action, label, message)));

  Future<void> _verifyOtp(String kind) async {
    final code = _otpCtrl.text.trim();
    if (code.length != 4) {
      showGxSnack(context, 'Enter the 4-digit OTP');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(rentalsRepositoryProvider).verifyOtp('${widget.reservation['id']}', kind, code);
      _otpCtrl.clear();
      await widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, eventError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reservation;
    final p = r['priceBreakdown'] as Map? ?? {};
    final owner = widget.isOwner;
    final status = '${r['status']}';
    final active = status == 'CONFIRMED' || status == 'ACTIVE' || status == 'RETURN_PENDING';
    final handed = r['ownerHandedOverAt'] != null || r['renterCollectedAt'] != null;
    final returned = r['ownerReturnedAt'] != null && r['renterReturnedAt'] != null;
    final paid = r['ownerPaidAt'] != null || r['renterPaidAt'] != null;
    final advanceRefund = switch (p['refundStatus']) {
      'REFUND_REQUIRED' => 'Advance refund queued',
      'REFUND_PENDING' => 'Advance refund is processing',
      'REFUNDED' => 'Advance refunded',
      'REFUND_FAILED' => 'Advance refund needs support review',
      _ => null,
    };
    final deposit = num.tryParse('${p['deposit'] ?? 0}') ?? 0;
    final refund = status == 'CANCELLED' && paid ? num.tryParse('${r['totalPrice']}') ?? 0 : returned && paid ? deposit : 0;
    final inWindow = !(DateTime.tryParse('${r['startTime']}')?.isAfter(DateTime.now()) ?? true) &&
      (DateTime.tryParse('${r['endTime']}')?.isAfter(DateTime.now()) ?? false);
    String state(String key) => r[key] == null ? 'pending' : 'confirmed';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Divider(height: 24),
      Text('${r['quantity'] ?? 1} unit(s) · ${r['fulfillment'] == 'DELIVERY' ? 'Delivery' : 'Pickup'}'),
      if ('${r['fulfillmentAddress'] ?? ''}'.isNotEmpty) Text('${r['fulfillmentAddress']}'),
      if (p.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Rental ${eventMoney(p['rent'])} · Delivery ${eventMoney(p['delivery'])}'),
        Text('Refundable deposit ${eventMoney(p['deposit'])}'),
        if (r['advanceAmount'] != null) Text('Advance ${eventMoney(r['advanceAmount'])}'),
        if (advanceRefund != null)
          Text(
            advanceRefund,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        Text('${p['depositTerms'] ?? ''}'),
      ],
      if (owner && (status == 'CONFIRMED' || status == 'ACTIVE')) ...[
        const SizedBox(height: 10),
        TextField(
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: InputDecoration(
            counterText: '',
            hintText: status == 'CONFIRMED' ? 'Customer pickup OTP' : 'Customer return OTP',
          ),
        ),
        GxButton(
          label: status == 'CONFIRMED' ? 'Verify pickup OTP' : 'Verify return OTP',
          filled: false,
          height: 40,
          loading: _busy,
          onTap: _busy
              ? null
              : () => _verifyOtp(status == 'CONFIRMED' ? 'handover' : 'return'),
        ),
      ],
      if (active || status == 'COMPLETED' || (status == 'CANCELLED' && paid)) ...[
        const SizedBox(height: 10),
        Text('Handover: owner ${state('ownerHandedOverAt')}, renter ${state('renterCollectedAt')}'),
        Text('Return: owner ${state('ownerReturnedAt')}, renter ${state('renterReturnedAt')}'),
        Text('Payment: owner ${state('ownerPaidAt')}, renter ${state('renterPaidAt')}'),
        if (returned && active) const Text('Item returned. Finish payment and deposit acknowledgements to close the rental.'),
      ],
      if (active) ...[
        if (!returned && inWindow && r[owner ? 'ownerHandedOverAt' : 'renterCollectedAt'] == null)
          _button('handover', owner ? 'I handed over the items' : 'I collected the items',
            'Confirm that ${r['quantity'] ?? 1} unit(s) have been handed over and the condition has been checked together.'),
        if (handed && r[owner ? 'ownerReturnedAt' : 'renterReturnedAt'] == null)
          _button('return', owner ? 'I received the returned items' : 'I returned the items',
            'Confirm all rented units were returned. Inspect the condition together. Both sides must acknowledge the return.'),
        if (r[owner ? 'ownerPaidAt' : 'renterPaidAt'] == null)
          _button('payment', owner ? 'I received full payment' : 'I paid the full amount',
            'Confirm only after ${owner ? 'receiving' : 'paying'} ${eventMoney(r['totalPrice'])} directly, including any refundable deposit. This records your acknowledgement; it does not transfer money.'),
      ],
      if (refund > 0) ...[
        const SizedBox(height: 8),
        Text('Refund ${eventMoney(refund)}: sent ${state('ownerRefundedAt')}, received ${state('renterRefundedAt')}'),
        if (r[owner ? 'ownerRefundedAt' : 'renterRefundedAt'] == null)
          _button('refund', owner ? 'I sent the refund' : 'I received the refund',
            'Confirm only after ${owner ? 'sending' : 'receiving'} ${eventMoney(refund)} directly. This does not transfer money.'),
      ],
    ]);
  }
}
