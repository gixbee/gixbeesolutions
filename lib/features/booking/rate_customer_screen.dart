import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import '../../repositories/booking_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';

/// v126 Instant Help w10 — after payment is received the WORKER rates the
/// customer (both sides rate; the customer already rates the worker in the
/// completion flow). POSTs to /bookings/:id/rate-customer.
class RateCustomerScreen extends ConsumerStatefulWidget {
  final String bookingId;
  final String customerName;

  const RateCustomerScreen({
    super.key,
    required this.bookingId,
    required this.customerName,
  });

  @override
  ConsumerState<RateCustomerScreen> createState() => _RateCustomerScreenState();
}

class _RateCustomerScreenState extends ConsumerState<RateCustomerScreen> {
  int _stars = 0;
  bool _submitting = false;

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _submit() async {
    if (_stars == 0) {
      showGxSnack(context, 'Tap a star to rate', type: GxSnackType.error);
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(bookingRepositoryProvider)
          .rateCustomer(widget.bookingId, _stars);
      if (!mounted) return;
      showGxSnack(context, 'Thanks — rating submitted!',
          type: GxSnackType.success);
      _goHome();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showGxSnack(context, 'Could not submit rating: $e',
          type: GxSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green.withValues(alpha: 0.12),
                  ),
                  child: const Icon(Icons.check_circle,
                      color: Colors.green, size: 56),
                ),
                const SizedBox(height: 20),
                Text(
                  'Job complete & paid',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: context.gx.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  'How was working with ${widget.customerName}?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: context.gx.ink.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      IconButton(
                        onPressed: () => setState(() => _stars = i),
                        icon: Icon(
                          i <= _stars
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 40,
                          color: i <= _stars
                              ? GixbeeTheme.accentGold
                              : context.gx.ink.withValues(alpha: 0.3),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                GxButton(
                  label: _submitting ? 'Submitting…' : 'Submit rating',
                  onTap: _submitting ? null : _submit,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _goHome,
                  child: Text(
                    'Skip — back to Go Live',
                    style: TextStyle(
                        fontSize: 13,
                        color: context.gx.ink.withValues(alpha: 0.55)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
