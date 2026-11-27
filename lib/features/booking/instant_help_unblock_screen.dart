import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/config/app_config.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/payments_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

/// Shown when Instant Help is blocked after repeated late cancels.
/// Loads the travel-compensation quote and opens Razorpay checkout.
class InstantHelpUnblockScreen extends ConsumerStatefulWidget {
  const InstantHelpUnblockScreen({super.key});

  @override
  ConsumerState<InstantHelpUnblockScreen> createState() =>
      _InstantHelpUnblockScreenState();
}

class _InstantHelpUnblockScreenState
    extends ConsumerState<InstantHelpUnblockScreen> {
  bool _loading = true;
  bool _paying = false;
  Map<String, dynamic>? _quote;
  Razorpay? _razorpay;

  @override
  void initState() {
    super.initState();
    _loadQuote();
  }

  @override
  void dispose() {
    _razorpay?.clear();
    super.dispose();
  }

  Future<void> _loadQuote() async {
    try {
      final quote = await ref
          .read(bookingRepositoryProvider)
          .getLateCancelCompensationQuote();
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _loading = false;
      });
      if (quote['blocked'] != true) {
        ref.invalidate(currentUserProvider);
        if (mounted) Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        showGxSnack(context, 'Could not load compensation details.',
            type: GxSnackType.error);
      }
    }
  }

  Future<void> _pay() async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      final order = await ref
          .read(paymentsRepositoryProvider)
          .createLateCancelCompensationOrder();
      final user = ref.read(currentUserProvider).value;

      _razorpay ??= Razorpay()
        ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess)
        ..on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError)
        ..on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});

      _razorpay!.open({
        'key': order['keyId'] ?? AppConfig.razorpayKey,
        'amount': order['amount'],
        'order_id': order['orderId'],
        'currency': order['currency'] ?? 'INR',
        'name': AppConfig.appName,
        'description': 'Travel compensation — unlock Instant Help',
        'timeout': AppConfig.paymentTimeoutSeconds,
        'prefill': {'contact': user?.phone ?? '', 'email': user?.email ?? ''},
      });
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['message']?.toString() ?? '')
          : '';
      if (mounted) {
        showGxSnack(context, msg.isEmpty ? 'Could not start payment' : msg,
            type: GxSnackType.error);
        setState(() => _paying = false);
      }
    } catch (_) {
      if (mounted) {
        showGxSnack(context, 'Could not start payment',
            type: GxSnackType.error);
        setState(() => _paying = false);
      }
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    final confirmed = await ref.read(paymentsRepositoryProvider)
        .confirmCapturedPayment(response.orderId, response.paymentId);
    if (!mounted) return;
    setState(() => _paying = false);
    ref.invalidate(currentUserProvider);
    if (confirmed) {
      showGxSnack(context, 'Payment received. Instant Help is unlocked.',
          type: GxSnackType.success);
      Navigator.pop(context, true);
    } else {
      showGxSnack(context, 'Payment is being confirmed.');
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _paying = false);
    showGxSnack(context, 'Payment failed: ${response.message ?? 'try again'}',
        type: GxSnackType.error);
  }

  @override
  Widget build(BuildContext context) {
    final amount = (_quote?['amountInr'] as num?)?.toDouble() ?? 0;
    final distanceKm = (_quote?['distanceKm'] as num?)?.toDouble();
    final workerName = _quote?['workerName']?.toString();

    return Scaffold(
      backgroundColor: context.gx.bg,
      appBar: AppBar(
        title: const Text('Instant Help blocked'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: DribbbleBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: context.gx.card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: context.gx.border, width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.block_rounded,
                                  color: Theme.of(context).colorScheme.error),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Instant Help is temporarily blocked',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: context.gx.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'After repeated late cancellations, you need to '
                            'compensate your pro for travel before booking '
                            'Instant Help again.',
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              color: context.gx.ink.withValues(alpha: 0.65),
                            ),
                          ),
                          if (workerName != null && workerName.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text('Pro',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                    color: context.gx.ink
                                        .withValues(alpha: 0.45))),
                            const SizedBox(height: 4),
                            Text(workerName,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: context.gx.ink)),
                          ],
                          const SizedBox(height: 14),
                          Text('Travel compensation',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                  color:
                                      context.gx.ink.withValues(alpha: 0.45))),
                          const SizedBox(height: 4),
                          Text(
                            '₹${amount.toStringAsFixed(0)}'
                            '${distanceKm != null && distanceKm > 0 ? ' · ${distanceKm.toStringAsFixed(1)} km' : ''}',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: context.gx.accentSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    GxButton(
                      label: _paying ? 'Opening checkout…' : 'Pay & unlock',
                      icon: Icons.payment_rounded,
                      onTap: _paying || amount <= 0 ? null : _pay,
                      loading: _paying,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Returns true when [error] is the Instant Help blocked response.
bool isInstantHelpBlockedError(Object error) {
  if (error is! DioException) return false;
  final data = error.response?.data;
  final raw = data is Map ? data['message'] : null;
  final message = raw is String
      ? raw
      : raw is List && raw.isNotEmpty
          ? raw.first.toString()
          : '';
  return message.toLowerCase().contains('instant help is blocked');
}

/// Navigate to the unblock screen when Instant Help is blocked.
Future<bool?> openInstantHelpUnblockScreen(BuildContext context) {
  return Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => const InstantHelpUnblockScreen()),
  );
}
