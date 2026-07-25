import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/booking_status_provider.dart';
import '../../shared/utils/booking_flags.dart';
import '../../shared/widgets/gx_dialog.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_pressable.dart';
import 'manual_payment_billing.dart';
import 'rate_customer_screen.dart';

/// Worker post-completion manual payment screen (cash / UPI outside the app).
/// Matches the Instant Help "Worker Flow · Payment" mockup.
class CollectPaymentScreen extends ConsumerStatefulWidget {
  final String bookingId;
  final double amount;
  final String customerName;
  final double? hourlyRate;
  final int? workedMinutes;
  final int? pausedMinutes;
  final double? platformFee;
  /// True when this worker already confirmed and is waiting on the customer.
  final bool initiallyWaiting;

  const CollectPaymentScreen({
    super.key,
    required this.bookingId,
    required this.amount,
    required this.customerName,
    this.hourlyRate,
    this.workedMinutes,
    this.pausedMinutes,
    this.platformFee,
    this.initiallyWaiting = false,
  });

  @override
  ConsumerState<CollectPaymentScreen> createState() =>
      _CollectPaymentScreenState();
}

enum _HonestyChoice { exact, tip, underpaid }

class _CollectPaymentScreenState extends ConsumerState<CollectPaymentScreen> {
  bool _isLoading = false;
  _HonestyChoice _honesty = _HonestyChoice.exact;
  ManualPaymentBilling? _billing;
  bool _loadingBilling = true;
  bool _waitingForOther = false;
  Timer? _waitPoll;
  bool _advancedToRate = false;

  @override
  void initState() {
    super.initState();
    _waitingForOther = widget.initiallyWaiting;
    _hydrate();
  }

  @override
  void dispose() {
    _waitPoll?.cancel();
    super.dispose();
  }

  void _refreshProviders() {
    ref.invalidate(myBookingsProvider);
    ref.invalidate(bookingStatusProvider(widget.bookingId));
  }

  void _startWaitingPoll() {
    _waitPoll?.cancel();
    _waitPoll = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_checkPaidAndAdvance());
    });
    unawaited(_checkPaidAndAdvance());
  }

  Future<void> _checkPaidAndAdvance() async {
    try {
      final b = await ref
          .read(bookingRepositoryProvider)
          .getBookingById(widget.bookingId);
      if (!mounted || b == null) return;
      if (bookingFlagTrue(b['isPaid'])) {
        _waitPoll?.cancel();
        _refreshProviders();
        _goToRate();
      }
    } catch (_) {}
  }

  Future<void> _hydrate() async {
    ManualPaymentBilling billing = ManualPaymentBilling(
      amount: widget.amount,
      hourlyRate: widget.hourlyRate ?? widget.amount,
      workedMinutes: widget.workedMinutes ?? 60,
      pausedMinutes: widget.pausedMinutes ?? 0,
      platformFee: widget.platformFee ?? 12,
      counterpartName: widget.customerName,
    );
    var waiting = widget.initiallyWaiting;
    try {
      final b =
          await ref.read(bookingRepositoryProvider).getBookingById(widget.bookingId);
      if (b != null) {
        billing = ManualPaymentBilling.fromMaps(
          booking: b,
          completion: {
            if (widget.hourlyRate != null) 'hourlyRate': widget.hourlyRate,
            if (widget.workedMinutes != null) 'workedMinutes': widget.workedMinutes,
            if (widget.pausedMinutes != null) 'pausedMinutes': widget.pausedMinutes,
            if (widget.platformFee != null) 'platformFee': widget.platformFee,
            'totalAmount': widget.amount,
          },
          fallbackName: widget.customerName,
          counterpartIsCustomer: true,
        );
        if (bookingFlagTrue(b['isPaid'])) {
          if (!mounted) return;
          setState(() {
            _billing = billing;
            _loadingBilling = false;
          });
          _refreshProviders();
          _goToRate();
          return;
        }
        waiting = bookingFlagTrue(b['workerPaidConfirmed']);
      }
    } catch (_) {
      // Keep constructor-provided fallbacks.
    }
    if (!mounted) return;
    setState(() {
      _billing = billing;
      _loadingBilling = false;
      _waitingForOther = waiting;
    });
    if (waiting) _startWaitingPoll();
  }

  String get _honestyApi {
    switch (_honesty) {
      case _HonestyChoice.exact:
        return 'EXACT';
      case _HonestyChoice.tip:
        return 'TIP';
      case _HonestyChoice.underpaid:
        return 'UNDERPAID';
    }
  }

  Future<void> _markPaid() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref.read(bookingRepositoryProvider).markPaid(
            widget.bookingId,
            honestyCheck: _honestyApi,
          );
      _refreshProviders();
      if (!mounted) return;
      if (bookingFlagTrue(res['isPaid'])) {
        _showSuccessDialog();
      } else {
        setState(() => _waitingForOther = true);
        _startWaitingPoll();
        showGxSnack(
          context,
          'Waiting for the customer to confirm payment',
          type: GxSnackType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Failed to confirm payment: $e',
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToRate() {
    if (_advancedToRate || !mounted) return;
    _advancedToRate = true;
    final name = _billing?.counterpartName ?? widget.customerName;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RateCustomerScreen(
          bookingId: widget.bookingId,
          customerName: name,
        ),
      ),
    );
  }

  void _showSuccessDialog() {
    final name = _billing?.counterpartName ?? widget.customerName;
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
              color: GixbeeTheme.accentGreen.withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.check_circle,
                color: GixbeeTheme.accentGreen, size: 56),
          ),
          const SizedBox(height: 20),
          Text(
            'Payment confirmed',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: context.gx.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Thanks — next, rate $name.',
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.5,
              color: context.gx.ink.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
      actions: [
        GxDialogAction(
          'Continue',
          isPrimary: true,
          onTap: () {
            Navigator.pop(context);
            _goToRate();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final billing = _billing;
    final amount = billing?.amountInt ?? widget.amount.round();
    final name = billing?.counterpartName ?? widget.customerName;
    final fee = billing?.feeInt ?? 12;
    final green = GixbeeTheme.accentGreen;
    final purple = gx.accent;

    if (_waitingForOther && !_loadingBilling) {
      return Scaffold(
        backgroundColor: gx.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () {
                      _refreshProviders();
                      Navigator.pop(context);
                    },
                    icon: Icon(Icons.arrow_back, color: gx.ink),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: green.withValues(alpha: 0.12),
                  ),
                  child: Icon(Icons.hourglass_top_rounded,
                      color: green, size: 48),
                ),
                const SizedBox(height: 24),
                Text(
                  'Waiting for customer',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: gx.ink,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'You confirmed collecting ₹$amount from $name. '
                  'This job closes when they also confirm.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: gx.ink.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 28),
                const CircularProgressIndicator(),
                const Spacer(),
                GxPressable(
                  onTap: () {
                    _refreshProviders();
                    Navigator.pop(context);
                  },
                  child: Container(
                    height: 52,
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: gx.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: gx.border),
                    ),
                    child: Text(
                      'Back to home',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: gx.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: gx.bg,
      body: SafeArea(
        child: _loadingBilling || billing == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      children: [
                        Text(
                          'Collect ₹$amount',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: gx.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Collect from customer then confirm',
                          style: TextStyle(
                            fontSize: 14,
                            color: gx.ink.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _AmountCard(
                          green: green,
                          card: gx.card,
                          border: gx.border,
                          ink: gx.ink,
                          amount: amount,
                          subtitle: 'Collect this from $name now.',
                          rows: [
                            _BreakdownRow(
                              label:
                                  '${billing.compactDurationLabel} × ₹${billing.rateInt}/hr',
                              value: '₹$amount',
                              valueColor: green,
                            ),
                            _BreakdownRow(
                              label: 'Pause time (not charged)',
                              value: '₹0',
                              valueColor: gx.ink.withValues(alpha: 0.45),
                            ),
                            _BreakdownRow(
                              label: 'Gixbee fee (from your wallet)',
                              value: '-₹$fee',
                              valueColor: const Color(0xFFEF4444),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _NoteBox(
                          purple: purple,
                          text:
                              'Collect ₹$amount from $name in cash or any method. Gixbee fee ₹$fee is deducted from your wallet — not this payment.',
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Honesty check',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: gx.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Did you collect exactly ₹$amount?',
                          style: TextStyle(
                            fontSize: 13,
                            color: gx.ink.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _HonestyOption(
                          selected: _honesty == _HonestyChoice.exact,
                          title: 'Yes — collected exactly ₹$amount',
                          subtitle: 'Payment confirmed',
                          green: green,
                          onTap: () =>
                              setState(() => _honesty = _HonestyChoice.exact),
                        ),
                        const SizedBox(height: 10),
                        _HonestyOption(
                          selected: _honesty == _HonestyChoice.tip,
                          title: 'Customer gave extra as a tip',
                          subtitle: 'Voluntary — I did not ask',
                          green: green,
                          onTap: () =>
                              setState(() => _honesty = _HonestyChoice.tip),
                        ),
                        const SizedBox(height: 10),
                        _HonestyOption(
                          selected: _honesty == _HonestyChoice.underpaid,
                          title: 'Customer paid less than ₹$amount',
                          subtitle: 'Payment issue — I will report',
                          green: green,
                          onTap: () => setState(
                              () => _honesty = _HonestyChoice.underpaid),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      children: [
                        GxPressable(
                          onTap: _isLoading ? null : _markPaid,
                          child: Container(
                            height: 56,
                            width: double.infinity,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: green,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      valueColor: AlwaysStoppedAnimation(
                                          Color(0xFF0B1A12)),
                                    ),
                                  )
                                : const Text(
                                    'Payment received · Confirm',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0B1A12),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Gixbee fee ₹$fee deducted from your wallet after confirmation',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: gx.ink.withValues(alpha: 0.40),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  final Color green;
  final Color card;
  final Color border;
  final Color ink;
  final int amount;
  final String subtitle;
  final List<_BreakdownRow> rows;

  const _AmountCard({
    required this.green,
    required this.card,
    required this.border,
    required this.ink,
    required this.amount,
    required this.subtitle,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: green.withValues(alpha: 0.55), width: 1.2),
      ),
      child: Column(
        children: [
          Text(
            'Gixbee calculated for you',
            style: TextStyle(
              fontSize: 12,
              color: ink.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₹$amount',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w800,
              color: green,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: ink.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: border),
          const SizedBox(height: 10),
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: ink.withValues(alpha: 0.70),
                        ),
                      ),
                    ),
                    Text(
                      r.value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: r.valueColor,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _BreakdownRow {
  final String label;
  final String value;
  final Color valueColor;
  const _BreakdownRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });
}

class _NoteBox extends StatelessWidget {
  final Color purple;
  final String text;
  const _NoteBox({required this.purple, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: purple.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: purple.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.45,
          color: context.gx.ink.withValues(alpha: 0.78),
        ),
      ),
    );
  }
}

class _HonestyOption extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final Color green;
  final VoidCallback onTap;

  const _HonestyOption({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.green,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    return GxPressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: selected ? green.withValues(alpha: 0.10) : gx.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? green : gx.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? green : Colors.transparent,
                border: Border.all(
                  color: selected ? green : gx.ink.withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.circle, size: 8, color: Color(0xFF0B1A12))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected ? green : gx.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: gx.ink.withValues(alpha: 0.50),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
