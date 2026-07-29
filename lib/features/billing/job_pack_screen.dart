import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:dio/dio.dart';
import '../../repositories/job_credits_repository.dart';
import '../../repositories/auth_repository.dart';
import '../../core/config/app_config.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_button.dart';
import '../../theme.dart';

class JobPackScreen extends ConsumerStatefulWidget {
  const JobPackScreen({super.key});

  @override
  ConsumerState<JobPackScreen> createState() => _JobPackScreenState();
}

class _JobPackScreenState extends ConsumerState<JobPackScreen> {
  late Razorpay _razorpay;
  int _balance = 0;
  bool _isLoading = true;
  bool _isPurchasing = false;
  Map<String, dynamic>? _packInfo;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final repo = ref.read(jobCreditsRepositoryProvider);
      final balance = await repo.getBalance();
      final packInfo = await repo.getPackInfo();
      if (mounted) {
        setState(() {
          _balance = balance;
          _packInfo = packInfo;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showGxSnack(context, 'Failed to load job credits', type: GxSnackType.error);
      }
    }
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    
    // Client-side verification
    final orderId = response.orderId;
    final paymentId = response.paymentId;
    final signature = response.signature;

    if (orderId == null || paymentId == null || signature == null) {
      setState(() => _isPurchasing = false);
      showGxSnack(context, 'Payment verification details missing.', type: GxSnackType.error);
      return;
    }

    try {
      final repo = ref.read(jobCreditsRepositoryProvider);
      final newBalance = await repo.verifyPayment(
        orderId: orderId,
        paymentId: paymentId,
        signature: signature,
      );
      if (mounted) {
        setState(() {
          _balance = newBalance;
          _isPurchasing = false;
        });
        showGxSnack(context, 'Success! You received ${_packInfo?['credits']} job credits.', type: GxSnackType.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPurchasing = false);
        showGxSnack(context, 'Failed to verify payment. If you were charged, please contact support.', type: GxSnackType.error);
      }
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (mounted) {
      setState(() => _isPurchasing = false);
      showGxSnack(context, 'Payment failed: ${response.message}', type: GxSnackType.error);
    }
  }

  Future<void> _startPurchase() async {
    final userState = ref.read(currentUserProvider);
    if (userState.isLoading) {
      showGxSnack(context, 'Loading profile, please wait...');
      return;
    }
    final user = userState.value;

    setState(() => _isPurchasing = true);

    Map<String, dynamic> order;
    try {
      order = await ref.read(jobCreditsRepositoryProvider).createOrder();
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response?.data['message']?.toString() ?? 'Could not start the payment')
          : 'Could not start the payment';
      if (mounted) {
        setState(() => _isPurchasing = false);
        showGxSnack(context, msg, type: GxSnackType.error);
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() => _isPurchasing = false);
        showGxSnack(context, 'Could not start the payment', type: GxSnackType.error);
      }
      return;
    }

    var options = {
      'key': order['keyId'] ?? AppConfig.razorpayKey,
      'amount': order['amount'],
      'order_id': order['orderId'],
      'currency': order['currency'] ?? 'INR',
      'name': AppConfig.appName,
      'description': 'Buy Job Pack',
      'timeout': AppConfig.paymentTimeoutSeconds,
      'prefill': {
        'contact': user?.phone ?? '',
        'email': user?.email ?? '',
      }
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      if (mounted) {
        setState(() => _isPurchasing = false);
        showGxSnack(context, 'Could not launch Razorpay', type: GxSnackType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final credits = _packInfo?['credits'] ?? 3;
    final price = _packInfo?['price'] ?? 49;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Credits', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: context.gx.card,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.gx.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.gx.accent.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Text(
                    '$_balance',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: context.gx.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Credits Remaining',
                    style: TextStyle(
                      fontSize: 16,
                      color: context.gx.ink.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Buy Job Pack',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.gx.ink),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.gx.card,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$credits Jobs',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: context.gx.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹$price',
                        style: TextStyle(fontSize: 16, color: context.gx.accent, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  _isPurchasing
                      ? const CircularProgressIndicator()
                      : GxButton(
                          label: 'Buy Now',
                          expand: false,
                          height: 40,
                          onTap: _startPurchase,
                        ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'One job credit is consumed automatically when you accept a booking. If the customer cancels, your credit is refunded.',
              style: TextStyle(
                fontSize: 14,
                color: context.gx.ink.withOpacity(0.6),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
