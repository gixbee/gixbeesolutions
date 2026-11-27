import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/matching_repository.dart';
import '../../repositories/events_repository.dart' show eventMoney, eventError, eventDate;
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';

class PendingPaymentsScreen extends ConsumerStatefulWidget {
  const PendingPaymentsScreen({super.key});
  @override
  ConsumerState<PendingPaymentsScreen> createState() => _PendingPaymentsScreenState();
}

class _PendingPaymentsScreenState extends ConsumerState<PendingPaymentsScreen> {
  List<Map<String, dynamic>>? _orders;
  String? _error;
  bool _busy = false;
  Razorpay? _razorpay;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _razorpay?.clear(); super.dispose(); }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final orders = await ref.read(matchingRepositoryProvider).pendingPayments();
      if (mounted) setState(() { _orders = orders; _error = null; });
    } catch (e) { if (mounted) setState(() => _error = eventError(e)); }
  }

  Future<void> _resume(Map<String, dynamic> order) async {
    if (_busy) return;
    final meta = order['meta'] as Map? ?? {};
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Resume saved payment?'), content: SingleChildScrollView(child: Text(
        '${meta['jobType'] ?? meta['planName'] ?? ''}\nPay ${eventMoney((num.tryParse('${order['amount']}') ?? 0) / 100)}\n\n'
        '${order['purpose'] == 'HIRING_MATCH_FEE' ? '${meta['vacancies']} vacancies · ${meta['location'] ?? ''}\nMonthly salary: ${eventMoney(meta['salaryMax'])}\nHiring Coins reserved: ${num.tryParse('${meta['creditApplied']}')?.toInt() ?? 0}' : order['purpose'] == 'PLATFORM_PLAN' ? '${meta['days']} days of plan access' : 'Career profile: ${meta['durationDays'] ?? 30} days of matching access'}\n\n'
        'This uses the saved order and its original details. If you have already paid, check confirmation first.')),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Go back')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Resume'))],
    ));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      if (await ref.read(matchingRepositoryProvider).paymentStatus('${order['orderId']}') == 'CREDITED') {
        await _load(); if (mounted) showGxSnack(context, 'Payment confirmed. Your purchase is ready.');
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (!mounted) return;
      final user = ref.read(currentUserProvider).value;
      _razorpay ??= Razorpay()
        ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _paid)
        ..on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
          if (mounted) { setState(() => _busy = false); showGxSnack(context, 'Payment was not completed. The order is saved.'); }
        })
        ..on(Razorpay.EVENT_EXTERNAL_WALLET, (_) { if (mounted) setState(() => _busy = false); });
      _razorpay!.open({'key': order['keyId'], 'order_id': order['orderId'], 'amount': order['amount'],
        'currency': 'INR', 'name': 'Gixbee', 'description': '${meta['jobType'] ?? meta['planName'] ?? 'Saved payment'}',
        'prefill': {'contact': user?.phone ?? '', 'email': user?.email ?? ''}});
    } catch (e) {
      if (mounted) { setState(() => _busy = false); showGxSnack(context, eventError(e)); }
    }
  }

  Future<void> _paid(PaymentSuccessResponse response) async {
    if (!mounted) return;
    try {
      final order = response.orderId; final payment = response.paymentId;
      if (order == null || payment == null) throw StateError('Missing payment reference');
      final status = await ref.read(matchingRepositoryProvider).verifyPayment(order, payment);
      if (mounted) {
        showGxSnack(context, switch (status) {
          'CREDITED' => 'Payment confirmed. Your purchase is ready.',
          'REFUND_REQUIRED' || 'REFUND_PENDING' => 'This checkout expired. Your refund is being processed.',
          'REFUNDED' => 'This checkout expired and your payment was refunded.',
          _ => 'Payment confirmation is pending.',
        });
      }
    } catch (_) {
      if (mounted) showGxSnack(context, 'Payment confirmation is still pending. Your order is saved; check again shortly.');
    } finally {
      await _load(); if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pending payments'), actions: [IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh))]),
    body: _orders == null ? Center(child: _error == null ? const CircularProgressIndicator()
      : Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!), TextButton(onPressed: _load, child: const Text('Try again'))]))
      : RefreshIndicator(onRefresh: _load, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(20), children: [
        if (_error != null) Text(_error!),
        const Text('Resume checkout or check an unconfirmed payment. Hiring Coins are released when an expired checkout is verified as unpaid.'),
        const SizedBox(height: 16),
        if (_orders!.isEmpty) const Text('No pending payments.'),
        for (final order in _orders!) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${order['meta']?['jobType'] ?? order['meta']?['planName'] ?? 'Saved purchase'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(order['purpose'] == 'HIRING_MATCH_FEE' ? 'Hiring match fee' : order['purpose'] == 'PLATFORM_PLAN' ? 'Plan purchase' : 'Career profile access'),
          Text(eventMoney((num.tryParse('${order['amount']}') ?? 0) / 100)),
          Text(eventDate(order['createdAt'])), const SizedBox(height: 12),
          GxButton(label: 'Resume payment', onTap: _busy ? null : () => _resume(order)),
          TextButton(onPressed: _busy ? null : () async {
            try {
              final status = await ref.read(matchingRepositoryProvider).paymentStatus('${order['orderId']}');
              if (context.mounted) showGxSnack(context, status == 'CREDITED' ? 'Payment confirmed. Your purchase is ready.' : 'Awaiting payment confirmation.');
              await _load();
            } catch (e) { if (context.mounted) showGxSnack(context, eventError(e)); }
          }, child: const Text('Check confirmation')),
        ]))),
      ])),
  );
}
