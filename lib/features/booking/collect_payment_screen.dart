import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import '../../repositories/booking_repository.dart';
import '../../shared/widgets/gx_dialog.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_button.dart';
import 'rate_customer_screen.dart';

class CollectPaymentScreen extends ConsumerStatefulWidget {
  final String bookingId;
  final double amount;
  final String customerName;

  const CollectPaymentScreen({
    super.key,
    required this.bookingId,
    required this.amount,
    required this.customerName,
  });

  @override
  ConsumerState<CollectPaymentScreen> createState() => _CollectPaymentScreenState();
}

class _CollectPaymentScreenState extends ConsumerState<CollectPaymentScreen> {
  bool _isLoading = false;

  Future<void> _markPaid() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(bookingRepositoryProvider).markPaid(widget.bookingId);
      ref.invalidate(myBookingsProvider);
      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Failed to mark as paid: $e',
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSuccessDialog() {
    showGxDialog(
      context,
      barrierDismissible: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.check_circle, color: Colors.green, size: 56),
          ),
          const SizedBox(height: 20),
          Text(
            'Payment Received!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: context.gx.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The job has been fully completed and paid.',
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.5,
              color: context.gx.ink.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
      actions: [
        // v126 w10: after payment, the worker rates the customer.
        GxDialogAction(
          'Continue',
          isPrimary: true,
          onTap: () {
            Navigator.pop(context); // close dialog
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => RateCustomerScreen(
                  bookingId: widget.bookingId,
                  customerName: widget.customerName,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Collect Payment'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.currency_rupee, size: 80, color: context.gx.accent),
              const SizedBox(height: 24),
              Text(
                'Collect Payment',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please collect cash or an external UPI transfer from ${widget.customerName}.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 48),
              Text(
                'Amount Due',
                style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Text(
                '₹${widget.amount.toInt()}',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: context.gx.accent,
                ),
              ),
              const SizedBox(height: 64),
              GxButton(
                label: 'Mark as Paid',
                onTap: _markPaid,
                loading: _isLoading,
                height: 56,
                radius: 16,
                fontSize: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
