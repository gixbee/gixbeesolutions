import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../repositories/auth_repository.dart';
import '../../repositories/events_repository.dart' show eventDate, eventError;
import '../../repositories/matching_repository.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../jobs/pending_payments_screen.dart';

class PlatformPlansScreen extends ConsumerStatefulWidget {
  const PlatformPlansScreen({super.key, required this.family});
  final String family;

  @override
  ConsumerState<PlatformPlansScreen> createState() =>
      _PlatformPlansScreenState();
}

class _PlatformPlansScreenState extends ConsumerState<PlatformPlansScreen> {
  Map<String, dynamic>? _catalogue;
  String? _error;
  bool _busy = false;
  Razorpay? _gateway;
  String? _orderId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _gateway?.clear();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response =
          await ref.read(dioProvider).get('/plans/${widget.family}');
      if (!mounted) return;
      setState(() {
        _catalogue = Map<String, dynamic>.from(response.data as Map);
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = eventError(error));
    }
  }

  Future<void> _trial() async {
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).post('/plans/career/trial');
      await _load();
    } catch (error) {
      if (mounted) showGxSnack(context, eventError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy(Map plan) async {
    setState(() => _busy = true);
    try {
      final response = await ref.read(dioProvider).post(
        '/plans/checkout/${plan['code']}',
        data: {
          'price': plan['price'],
          'days': plan['days'],
          'capacity': plan['capacity']
        },
      );
      if (!mounted) return;
      final order = response.data as Map;
      _orderId = order['orderId'] as String?;
      if (_orderId == null) throw StateError('Missing payment order');
      _gateway ??= Razorpay()
        ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _paid)
        ..on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
          if (!mounted) return;
          setState(() => _busy = false);
          showGxSnack(context,
              'Payment did not complete. You can resume it from Pending payments.');
        })
        ..on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {
          if (mounted) setState(() => _busy = false);
        });
      final user = ref.read(currentUserProvider).value;
      _gateway!.open({
        'key': order['keyId'],
        'order_id': _orderId,
        'amount': order['amount'],
        'currency': order['currency'],
        'name': 'Gixbee',
        'description': '${plan['name']} · ${plan['days']} days',
        'prefill': {'contact': user?.phone ?? '', 'email': user?.email ?? ''},
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showGxSnack(context, eventError(error));
      await _load();
    }
  }

  Future<void> _paid(PaymentSuccessResponse response) async {
    if (!mounted) return;
    try {
      final order = response.orderId;
      final payment = response.paymentId;
      if (order == null || order != _orderId || payment == null) {
        throw StateError('Missing payment reference');
      }
      await ref.read(matchingRepositoryProvider).verifyPayment(order, payment);
      await _load();
      if (mounted) {
        showGxSnack(context, 'Payment confirmed. Your plan is active.');
      }
    } catch (_) {
      if (mounted) {
        showGxSnack(context,
            'Payment confirmation is pending. Check Pending payments.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _unit => switch (widget.family) {
        'CAREER' => 'career profiles',
        'SERVICE' => 'service listings',
        'RENTAL' => 'rental items per business',
        'SHOP' => 'active offers per shop',
        _ => 'collecting hiring requests per business',
      };

  @override
  Widget build(BuildContext context) {
    final data = _catalogue;
    final plans = data?['plans'] as List? ?? [];
    final active = data?['active'] as List? ?? [];
    final trial = data?['trialDays'] as int? ?? 0;
    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.family == 'CAREER' ? 'Career plans' : 'Business plans'),
        actions: [
          IconButton(
            tooltip: 'Pending payments',
            onPressed: _busy
                ? null
                : () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const PendingPaymentsScreen(),
                        ));
                    if (mounted) await _load();
                  },
            icon: const Icon(Icons.receipt_long_outlined),
          ),
        ],
      ),
      body: data == null && _error == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_error != null) ...[
                  Text(_error!),
                  TextButton(
                      onPressed: _busy ? null : _load,
                      child: const Text('Try again')),
                ],
                if (data != null)
                  ListTile(
                      title: const Text('Basic · Free'),
                      subtitle: Text('Up to ${data['basicCapacity']} $_unit')),
                for (final grant in active)
                  ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(
                        '${grant['tier'] == 'PRO' ? 'Pro' : 'Standard'} active'),
                    subtitle:
                        Text('Valid until ${eventDate(grant['validUntil'])}'),
                  ),
                if (trial > 0)
                  OutlinedButton(
                    onPressed: _busy ? null : _trial,
                    child: Text('Try Pro free for $trial days'),
                  ),
                for (final plan in plans.cast<Map>())
                  Card(
                    child: ListTile(
                      title: Text('${plan['name']} · ₹${plan['price']}'),
                      subtitle: Text(
                        '${plan['days']} days · ${plan['capacity'] == 0 ? 'Unlimited' : 'Up to ${plan['capacity']}'} $_unit'
                        '${widget.family == 'CAREER' ? '\nPriority among eligible matches' : ''}'
                        '${widget.family == 'SERVICE' ? '\nPriority placement in event listings' : ''}',
                      ),
                      trailing: FilledButton(
                        onPressed: _busy ? null : () => _buy(plan),
                        child: const Text('Choose'),
                      ),
                    ),
                  ),
                if (plans.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                        'Pay once for the selected period. Renew whenever you need to.'),
                  ),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
    );
  }
}
