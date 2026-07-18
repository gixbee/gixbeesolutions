import 'package:flutter/material.dart';
import '../../shared/widgets/gx_button.dart';

// ⚠️ ORPHANED — no call sites (verified Pass 8, 2026-06-12).
// Superseded by the gateway-status payment picker built directly into
// `booking_screen.dart` (Pass 7). Kept because (a) this file is NOT tracked
// by git yet, so deleting it loses the code permanently, and (b) its
// advance/full-split UI is the natural starting point IF partial payments
// for event bookings are ever added (backend currently has no partial-payment
// fields — only `totalAmount` + `isPaid`). Safe to delete once committed to
// git or once a product decision rules out advance payments.

/// Result returned by [PaymentMethodScreen] when the user confirms.
class PaymentSelection {
  /// Backend `paymentMethod` value (WALLET / UPI / BANK / CASH).
  final String method;

  /// Whether the user chose to pay the full amount now (vs. an advance).
  final bool payFull;

  /// Amount payable now (full total, or the advance portion).
  final double amountPayable;

  /// Full grand total including the service charge.
  final double total;

  const PaymentSelection({
    required this.method,
    required this.payFull,
    required this.amountPayable,
    required this.total,
  });
}

/// Customer payment screen: amount breakdown, advance/full split, and a
/// payment-method picker (Wallet / UPI·PhonePe / Bank / Cash). Mirrors the
/// mockup's payment sub-screen. Returns a [PaymentSelection] via `Navigator.pop`.
class PaymentMethodScreen extends StatefulWidget {
  /// Service subtotal before the platform service charge.
  final double baseAmount;

  /// Service-charge rate applied to the subtotal (default 2%).
  final double serviceChargeRate;

  /// Advance fraction when paying a deposit (default 20%).
  final double advanceFraction;

  const PaymentMethodScreen({
    super.key,
    required this.baseAmount,
    this.serviceChargeRate = 0.02,
    this.advanceFraction = 0.20,
  });

  @override
  State<PaymentMethodScreen> createState() => _PaymentMethodScreenState();
}

class _PaymentMethodScreenState extends State<PaymentMethodScreen> {
  static const _methods = [
    (id: 'WALLET', label: 'Gixbee Wallet', icon: Icons.account_balance_wallet, hint: 'Instant'),
    (id: 'UPI', label: 'UPI / PhonePe', icon: Icons.qr_code_2, hint: 'PhonePe, GPay, Paytm'),
    (id: 'BANK', label: 'Bank Transfer', icon: Icons.account_balance, hint: 'NEFT / IMPS'),
    (id: 'CASH', label: 'Cash on service', icon: Icons.payments, hint: 'Pay the pro directly'),
  ];

  String _method = 'WALLET';
  bool _payFull = true;

  double get _serviceCharge =>
      double.parse((widget.baseAmount * widget.serviceChargeRate).toStringAsFixed(0));
  double get _total => widget.baseAmount + _serviceCharge;
  double get _advance =>
      double.parse((_total * widget.advanceFraction).toStringAsFixed(0));
  double get _payable => _payFull ? _total : _advance;

  void _confirm() {
    Navigator.pop(
      context,
      PaymentSelection(
        method: _method,
        payFull: _payFull,
        amountPayable: _payable,
        total: _total,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Breakdown ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _line(scheme, 'Service total', widget.baseAmount),
                const SizedBox(height: 8),
                _line(scheme, 'Service charge', _serviceCharge),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, color: scheme.outlineVariant),
                ),
                _line(scheme, 'Grand total', _total, bold: true),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Advance / full ──
          Text('When to pay',
              style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onSurface)),
          const SizedBox(height: 8),
          _payTile(scheme, full: true, label: 'Pay full now', amount: _total),
          _payTile(
            scheme,
            full: false,
            label: 'Pay ${(widget.advanceFraction * 100).toStringAsFixed(0)}% advance',
            amount: _advance,
          ),
          const SizedBox(height: 20),

          // ── Method ──
          Text('Payment method',
              style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onSurface)),
          const SizedBox(height: 8),
          ..._methods.map((m) {
            final selected = _method == m.id;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: selected
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              child: ListTile(
                onTap: () => setState(() => _method = m.id),
                leading: Icon(m.icon, color: scheme.primary),
                title: Text(m.label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(m.hint),
                trailing: Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? scheme.primary : scheme.outline,
                ),
              ),
            );
          }),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GxButton(
            label: 'Pay ₹${_payable.toStringAsFixed(0)}',
            onTap: _confirm,
          ),
        ),
      ),
    );
  }

  Widget _line(ColorScheme scheme, String label, double amount, {bool bold = false}) {
    final style = TextStyle(
      fontSize: bold ? 16 : 14,
      fontWeight: bold ? FontWeight.w900 : FontWeight.w500,
      color: bold ? scheme.onSurface : scheme.onSurfaceVariant,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text('₹${amount.toStringAsFixed(0)}', style: style),
      ],
    );
  }

  Widget _payTile(ColorScheme scheme,
      {required bool full, required String label, required double amount}) {
    final selected = _payFull == full;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: ListTile(
        onTap: () => setState(() => _payFull = full),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: Text('₹${amount.toStringAsFixed(0)}',
            style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary)),
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? scheme.primary : scheme.outline,
        ),
      ),
    );
  }
}
