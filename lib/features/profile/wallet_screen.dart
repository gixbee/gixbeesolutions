import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../repositories/wallet_repository.dart';
import '../../repositories/auth_repository.dart';
import '../../core/config/app_config.dart';

/// User Wallet Screen.
/// Displays current balance, transaction history, and allows top-ups via Razorpay.
/// Also enforces/displays the Rs. 12 minimum balance requirement for booking.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  late Razorpay _razorpay;
  double _balance = 0.0;
  final double _minimumRequired = AppConfig.walletMinBalance;
  bool _isLoading = true;

  final _topUpAmountCtrl = TextEditingController(text: '100');
  List<dynamic> _transactions = [];

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    _fetchWalletData();
  }

  Future<void> _fetchWalletData() async {
    try {
      final repo = ref.read(walletRepositoryProvider);
      final balance = await repo.getBalance();
      final txs = await repo.getTransactions();
      if (mounted) {
        setState(() {
          _balance = balance;
          _transactions = txs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _razorpay.clear();
    _topUpAmountCtrl.dispose();
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    try {
      final repo = ref.read(walletRepositoryProvider);
      
      // 1. Notify backend to verify and credit
      await repo.verifyPayment(
        paymentId: response.paymentId!,
        orderId: response.orderId,
        signature: response.signature,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wallet credited successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // 2. Refresh local data
      _fetchWalletData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment verification failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${response.message}'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('External Wallet Selected: ${response.walletName}')),
    );
  }

  void _startTopUp() {
    final amount = double.tryParse(_topUpAmountCtrl.text);
    if (amount == null || amount < AppConfig.walletMinTopUp) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Minimum top-up is ₹${AppConfig.walletMinTopUp.toInt()}')),
      );
      return;
    }

    // Issue #19: Read real user data for Razorpay prefill
    final user = ref.read(currentUserProvider).value;

    var options = {
      'key': AppConfig.razorpayKey,
      'amount': (amount * 100).toInt(), // Razorpay expects amount in paise
      'name': AppConfig.appName,
      'description': AppConfig.walletTopUpDescription,
      'timeout': AppConfig.paymentTimeoutSeconds,
      'prefill': {
        'contact': user?.phone ?? '',
        'email': user?.email ?? '',
      }
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      debugPrint('Error starting Razorpay: $e');
    }
  }

  void _setAmount(String amount) {
    setState(() {
      _topUpAmountCtrl.text = amount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLowBalance = _balance < _minimumRequired;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('My Wallet', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: cs.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _fetchWalletData();
            },
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
        children: [
          // ── BALANCE CARD ──
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, cs.primary.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Available Balance',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Icon(Icons.account_balance_wallet, color: Colors.white, size: 20),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '₹${_balance.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),

                // Minimum gate status
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isLowBalance ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isLowBalance
                              ? 'Low balance! Add funds to book a service.'
                              : 'You have enough balance to book services.',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── MIN REQUIREMENT INFO ──
          if (isLowBalance)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: Text(
                'Note: A minimum balance of ₹${_minimumRequired.toInt()} is required to connect with workers.',
                style: const TextStyle(color: Colors.red, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),

          const SizedBox(height: 16),

          // ── QUICK ADD PANEL ──
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add Money',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),

                  // Input field
                  TextField(
                    controller: _topUpAmountCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      prefixIcon: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('₹', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                      filled: true,
                      fillColor: cs.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Quick amount chips
                  Row(
                    children: [
                      _QuickAmountChip(amount: '50', onTap: () => _setAmount('50')),
                      const SizedBox(width: 12),
                      _QuickAmountChip(amount: '100', onTap: () => _setAmount('100')),
                      const SizedBox(width: 12),
                      _QuickAmountChip(amount: '500', onTap: () => _setAmount('500')),
                    ],
                  ),

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: _startTopUp,
                      child: const Text('Proceed to Pay', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),

                  const SizedBox(height: 32),
                  const Text(
                    'Recent Transactions',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),

                  // Transaction list
                  Expanded(
                    child: _transactions.isEmpty 
                    ? const Center(child: Text('No transactions yet.', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                      itemCount: _transactions.length,
                      itemBuilder: (context, i) {
                        final t = _transactions[i];
                        final isCredit = t['type'] == 'CREDIT' || t['type'] == 'credit';
                        final createdAt = t['createdAt'] != null ? DateTime.parse(t['createdAt']) : DateTime.now();

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isCredit
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.red.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                              color: isCredit ? Colors.green : Colors.red,
                              size: 20,
                            ),
                          ),
                          title: Text(t['description'] ?? 'Transaction', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(DateFormat('MMM d, hh:mm a').format(createdAt), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                          trailing: Text(
                            '${isCredit ? '+' : '-'} ₹${(num.tryParse(t['amount'].toString()) ?? 0).toInt()}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isCredit ? Colors.green : Colors.red,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAmountChip extends StatelessWidget {
  final String amount;
  final VoidCallback onTap;

  const _QuickAmountChip({required this.amount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: Text(
              '+ ₹$amount',
              style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary),
            ),
          ),
        ),
      ),
    );
  }
}
