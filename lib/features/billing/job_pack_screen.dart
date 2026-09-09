import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../repositories/job_credits_repository.dart';
import '../../repositories/auth_repository.dart';
import '../../core/config/app_config.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_button.dart';
import '../../theme.dart';
import 'credit_history_screen.dart';

final jobPackDetailsProvider =
    FutureProvider<({int balance, Map<String, dynamic> pack})>((ref) async {
  final repo = ref.watch(jobCreditsRepositoryProvider);
  final balance = await repo.getBalanceInfo();
  final pack = await repo.getPackInfo();
  return (balance: balance.balance, pack: pack);
});

class JobPackScreen extends ConsumerStatefulWidget {
  const JobPackScreen({super.key});

  @override
  ConsumerState<JobPackScreen> createState() => _JobPackScreenState();
}

class _JobPackScreenState extends ConsumerState<JobPackScreen>
    with WidgetsBindingObserver {
  late final Razorpay _razorpay;
  bool _isPurchasing = false;
  ({String orderId, String paymentId, String signature})? _pendingVerification;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _razorpay = Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(jobPackDetailsProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _razorpay.clear();
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    if (!mounted) return;
    final orderId = response.orderId;
    final paymentId = response.paymentId;
    final signature = response.signature;
    if (orderId == null || paymentId == null || signature == null) {
      setState(() => _isPurchasing = false);
      ref.invalidate(jobPackDetailsProvider);
      showGxSnack(context,
          'Waiting for payment confirmation. Refresh credits before trying another purchase.');
      return;
    }
    _pendingVerification =
        (orderId: orderId, paymentId: paymentId, signature: signature);
    _verifyPendingPayment();
  }

  Future<void> _verifyPendingPayment() async {
    final pending = _pendingVerification;
    if (pending == null) return;
    setState(() => _isPurchasing = true);
    try {
      await ref.read(jobCreditsRepositoryProvider).verifyPayment(
            orderId: pending.orderId,
            paymentId: pending.paymentId,
            signature: pending.signature,
          );
      if (!mounted) return;
      setState(() {
        _pendingVerification = null;
        _isPurchasing = false;
      });
      ref.invalidate(jobPackDetailsProvider);
      showGxSnack(context, 'Payment confirmed. Your credits have been updated.',
          type: GxSnackType.success);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isPurchasing = false);
      ref.invalidate(jobPackDetailsProvider);
      showGxSnack(
          context,
          'Payment confirmation is pending. Use Check payment or refresh credits. '
          'If you were charged, avoid another purchase and contact support if it stays pending.');
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _isPurchasing = false);
    ref.invalidate(jobPackDetailsProvider);
    showGxSnack(context,
        'Checkout did not complete. Refresh credits if you were charged.',
        type: GxSnackType.error);
  }

  Future<void> _startPurchase(Map<String, dynamic> pack) async {
    if (_isPurchasing) return;
    final user = ref.read(currentUserProvider).asData?.value;
    if (user == null) {
      showGxSnack(context, 'Your profile is unavailable. Please try again.');
      return;
    }
    setState(() => _isPurchasing = true);
    try {
      final order = await ref.read(jobCreditsRepositoryProvider).createOrder();
      if (!mounted) return;
      if (order['amount'] != (pack['price'] as num) * 100 ||
          order['credits'] != pack['credits']) {
        setState(() => _isPurchasing = false);
        ref.invalidate(jobPackDetailsProvider);
        showGxSnack(context,
            'Pack details changed. Review the updated pack before purchasing.');
        return;
      }
      if (order['keyId'] is! String || order['orderId'] is! String) {
        throw StateError('Payment details unavailable');
      }
      _razorpay.open({
        'key': order['keyId'],
        'amount': order['amount'],
        'order_id': order['orderId'],
        'currency': order['currency'],
        'name': AppConfig.appName,
        'description': '${order['credits']} acceptance credits',
        'timeout': AppConfig.paymentTimeoutSeconds,
        'prefill': {'contact': user.phone, 'email': user.email ?? ''},
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPurchasing = false);
      final data = e is DioException ? e.response?.data : null;
      final message = data is Map && data['message'] is String
          ? data['message'] as String
          : 'Could not start checkout. Please try again.';
      showGxSnack(context, message, type: GxSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job credits'),
        actions: [
          IconButton(
            tooltip: 'Refresh credits',
            onPressed: () => ref.invalidate(jobPackDetailsProvider),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Credit history',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CreditHistoryScreen())),
          ),
        ],
      ),
      body: ref.watch(jobPackDetailsProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Credit balance and pack details are unavailable.'),
                  const SizedBox(height: 12),
                  TextButton(
                      onPressed: () => ref.invalidate(jobPackDetailsProvider),
                      child: const Text('Try again')),
                ]),
              ),
            ),
            data: (details) {
              final pack = details.pack;
              final credits = (pack['credits'] as num).toInt();
              final cost = (pack['creditsPerAccept'] as num).toInt();
              final price = pack['price'];
              final free = cost == 0;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${details.balance} credits',
                          style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: context.gx.accent)),
                      const SizedBox(height: 8),
                      Text(
                          free
                              ? 'Accepting jobs is currently free.'
                              : 'Enough for ${details.balance ~/ cost} job accepts at $cost credits each.',
                          style: TextStyle(color: context.gx.ink, height: 1.5)),
                      const SizedBox(height: 28),
                      if (!free) ...[
                        Text('$credits credits · ₹$price',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: context.gx.ink)),
                        const SizedBox(height: 8),
                        Text(
                            'Enough for ${credits ~/ cost} accepts at the current rate. '
                            'Credits are deducted when you accept a job.',
                            style:
                                TextStyle(color: context.gx.ink, height: 1.5)),
                        const SizedBox(height: 18),
                        GxButton(
                          label: _isPurchasing
                              ? 'Checking payment…'
                              : _pendingVerification != null
                                  ? 'Check payment'
                                  : 'Buy for ₹$price',
                          onTap: _isPurchasing
                              ? null
                              : _pendingVerification != null
                                  ? _verifyPendingPayment
                                  : () => _startPurchase(pack),
                        ),
                        const SizedBox(height: 20),
                      ],
                      Text(
                          'Credits pay for access to job requests. Customers pay your service bill '
                          'directly to you by cash or UPI. A separate Go Live period fee may be due; '
                          'check your Go Live dashboard before buying.',
                          style: TextStyle(
                              color: context.gx.ink.withValues(alpha: 0.7),
                              height: 1.5)),
                      const SizedBox(height: 16),
                      Text(
                          'Eligible customer cancellations and no-shows return the credits used '
                          'for that booking. View Credit history for purchases, usage and refunds.',
                          style: TextStyle(
                              color: context.gx.ink.withValues(alpha: 0.7),
                              height: 1.5)),
                    ]),
              );
            },
          ),
    );
  }
}
