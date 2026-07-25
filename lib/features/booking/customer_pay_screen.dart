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
import 'rate_worker_screen.dart';

/// Customer post-completion manual payment screen — pay the worker directly
/// (cash / GPay / other). Matches the Instant Help "Customer Flow · Payment" mock.
class CustomerPayScreen extends ConsumerStatefulWidget {
  final String bookingId;
  final double amount;
  final String workerName;
  final double? hourlyRate;
  final int? workedMinutes;
  final int? pausedMinutes;
  final double? platformFee;
  /// True when this customer already confirmed and is waiting on the worker.
  final bool initiallyWaiting;

  const CustomerPayScreen({
    super.key,
    required this.bookingId,
    required this.amount,
    required this.workerName,
    this.hourlyRate,
    this.workedMinutes,
    this.pausedMinutes,
    this.platformFee,
    this.initiallyWaiting = false,
  });

  @override
  ConsumerState<CustomerPayScreen> createState() => _CustomerPayScreenState();
}

enum _PayMethod { cash, upi, other }

enum _SafetyChoice { ok, askedMore, tip }

class _CustomerPayScreenState extends ConsumerState<CustomerPayScreen> {
  bool _isLoading = false;
  _PayMethod _method = _PayMethod.upi;
  _SafetyChoice _safety = _SafetyChoice.ok;
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
    _waitPoll = Timer.periodic(const Duration(seconds: 30), (_) {
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
      counterpartName: widget.workerName,
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
          fallbackName: widget.workerName,
          counterpartIsCustomer: false,
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
        waiting = bookingFlagTrue(b['customerPaidConfirmed']);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _billing = billing;
      _loadingBilling = false;
      _waitingForOther = waiting;
    });
    if (waiting) _startWaitingPoll();
  }

  String get _methodApi {
    switch (_method) {
      case _PayMethod.cash:
        return 'CASH';
      case _PayMethod.upi:
        return 'UPI';
      case _PayMethod.other:
        return 'OTHER';
    }
  }

  String get _safetyApi {
    switch (_safety) {
      case _SafetyChoice.ok:
        return 'OK';
      case _SafetyChoice.askedMore:
        return 'ASKED_MORE';
      case _SafetyChoice.tip:
        return 'TIP';
    }
  }

  Future<void> _confirm() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref.read(bookingRepositoryProvider).markPaid(
            widget.bookingId,
            collectionMethod: _methodApi,
            safetyCheck: _safetyApi,
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
          'Waiting for the worker to confirm payment',
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
    final name = _billing?.counterpartName ?? widget.workerName;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RateWorkerScreen(
          bookingId: widget.bookingId,
          workerName: name,
        ),
      ),
    );
  }

  void _showSuccessDialog() {
    final name = _billing?.counterpartName ?? widget.workerName;
    showGxDialog(
      context,
      barrierDismissible: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
            'Payment noted',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: context.gx.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Next — rate $name.',
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
    ref.listen(bookingStatusProvider(widget.bookingId), (prev, next) {
      final data = next.value;
      if (data != null && bookingFlagTrue(data['isPaid'])) {
        _waitPoll?.cancel();
        _refreshProviders();
        _goToRate();
      }
    });

    final gx = context.gx;
    final billing = _billing;
    final amount = billing?.amountInt ?? widget.amount.round();
    final name = billing?.counterpartName ?? widget.workerName;
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
                  'Waiting for worker',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: gx.ink,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'You confirmed paying ₹$amount to $name. '
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
                          'Pay $name',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: gx.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Job complete · Pay directly',
                          style: TextStyle(
                            fontSize: 14,
                            color: gx.ink.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                          decoration: BoxDecoration(
                            color: gx.card,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: green.withValues(alpha: 0.55),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Gixbee calculated for you',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: gx.ink.withValues(alpha: 0.45),
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
                                'Pay this to $name directly',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: gx.ink.withValues(alpha: 0.55),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Divider(height: 1, color: gx.border),
                              const SizedBox(height: 10),
                              _row('Active work time', billing.durationLabel,
                                  green, gx),
                              _row(
                                'Pause time (not charged)',
                                billing.pauseLabel,
                                gx.ink.withValues(alpha: 0.45),
                                gx,
                              ),
                              _row('Rate', '₹${billing.rateInt}/hr', gx.ink, gx),
                              _row('Total', '₹$amount', green, gx, bold: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: purple.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: purple.withValues(alpha: 0.45)),
                          ),
                          child: Text(
                            'Pay $name directly — cash, GPay, or any method. Gixbee does not handle payments.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: gx.ink.withValues(alpha: 0.78),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'PAY ${name.toUpperCase()} USING',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: gx.ink.withValues(alpha: 0.45),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _MethodChip(
                                label: 'Cash',
                                selected: _method == _PayMethod.cash,
                                green: green,
                                onTap: () =>
                                    setState(() => _method = _PayMethod.cash),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MethodChip(
                                label: 'GPay / UPI',
                                selected: _method == _PayMethod.upi,
                                green: green,
                                onTap: () =>
                                    setState(() => _method = _PayMethod.upi),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MethodChip(
                                label: 'Other',
                                selected: _method == _PayMethod.other,
                                green: green,
                                onTap: () =>
                                    setState(() => _method = _PayMethod.other),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Quick safety check',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: gx.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Did $name ask for any amount more than ₹$amount?',
                          style: TextStyle(
                            fontSize: 13,
                            color: gx.ink.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SafetyOption(
                          selected: _safety == _SafetyChoice.ok,
                          title: 'No — he only asked for ₹$amount',
                          subtitle: 'Everything was fine',
                          green: green,
                          onTap: () =>
                              setState(() => _safety = _SafetyChoice.ok),
                        ),
                        const SizedBox(height: 10),
                        _SafetyOption(
                          selected: _safety == _SafetyChoice.askedMore,
                          title: 'Yes — he asked for more money',
                          subtitle: 'I felt pressured to pay extra',
                          green: green,
                          onTap: () => setState(
                              () => _safety = _SafetyChoice.askedMore),
                        ),
                        const SizedBox(height: 10),
                        _SafetyOption(
                          selected: _safety == _SafetyChoice.tip,
                          title: 'I gave extra as a tip voluntarily',
                          subtitle: '$name did not ask',
                          green: green,
                          onTap: () =>
                              setState(() => _safety = _SafetyChoice.tip),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      children: [
                        GxPressable(
                          onTap: _isLoading ? null : _confirm,
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
                                : Text(
                                    'I paid ₹$amount · Confirm',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0B1A12),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Gixbee deducts ₹$fee from $name\'s wallet, not from your payment',
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

  Widget _row(String label, String value, Color valueColor, GxColors gx,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: gx.ink.withValues(alpha: 0.70),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color green;
  final VoidCallback onTap;

  const _MethodChip({
    required this.label,
    required this.selected,
    required this.green,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    return GxPressable(
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? green.withValues(alpha: 0.10) : gx.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? green : gx.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? green : gx.ink.withValues(alpha: 0.70),
          ),
        ),
      ),
    );
  }
}

class _SafetyOption extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final Color green;
  final VoidCallback onTap;

  const _SafetyOption({
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
