/// Shared billing helpers for post-completion manual payment screens.
class ManualPaymentBilling {
  final double amount;
  final double serviceAmount;
  final double petrolAmount;
  final double petrolDistanceKm;
  final double petrolRatePerKm;
  final double hourlyRate;
  final int workedMinutes;
  final int pausedMinutes;
  final double platformFee;
  final String counterpartName;

  const ManualPaymentBilling({
    required this.amount,
    this.serviceAmount = 0,
    this.petrolAmount = 0,
    this.petrolDistanceKm = 0,
    this.petrolRatePerKm = 0,
    required this.hourlyRate,
    required this.workedMinutes,
    required this.pausedMinutes,
    required this.platformFee,
    required this.counterpartName,
  });

  int get amountInt => amount.round();
  int get serviceAmountInt =>
      (serviceAmount > 0 ? serviceAmount : amount - petrolAmount).round();
  int get petrolAmountInt => petrolAmount.round();
  int get petrolRateInt => petrolRatePerKm.round();
  int get rateInt => hourlyRate.round();
  int get feeInt => platformFee.round();
  bool get hasPetrol => petrolAmount > 0;

  String get petrolDistanceLabel {
    if (petrolDistanceKm <= 0) return '0 km';
    final rounded = petrolDistanceKm.roundToDouble();
    return petrolDistanceKm == rounded
        ? '${rounded.toInt()} km'
        : '${petrolDistanceKm.toStringAsFixed(1)} km';
  }

  String get durationLabel => formatDuration(workedMinutes);

  String get pauseLabel {
    if (pausedMinutes <= 0) return '₹0';
    return '${formatDuration(pausedMinutes)} · ₹0';
  }

  /// `1hr 12min` style used on the worker breakdown row.
  String get compactDurationLabel {
    final h = workedMinutes ~/ 60;
    final m = workedMinutes % 60;
    if (h <= 0) return '${m}min';
    if (m <= 0) return '${h}hr';
    return '${h}hr ${m}min';
  }

  static String formatDuration(int totalMinutes) {
    final m = totalMinutes < 0 ? 0 : totalMinutes;
    final h = m ~/ 60;
    final rem = m % 60;
    if (h <= 0) return '$rem min';
    if (rem == 0) return '$h hr';
    return '$h hr $rem min';
  }

  static ManualPaymentBilling fromMaps({
    required Map<String, dynamic>? booking,
    Map<String, dynamic>? completion,
    required String fallbackName,
    bool counterpartIsCustomer = true,
  }) {
    final src = <String, dynamic>{
      ...?booking,
      ...?completion,
    };
    final amount = _num(src['totalAmount'] ?? src['amount'] ?? 0);
    final petrolAmount = _num(src['petrolAmount'] ?? 0);
    final calculatedService = amount - petrolAmount;
    final serviceAmount = src['serviceAmount'] != null
        ? _num(src['serviceAmount'])
        : (calculatedService > 0 ? calculatedService : 0.0);
    final rate = _num(
      src['hourlyRate'] ??
          (src['type']?.toString().toUpperCase() == 'INSTANT'
              ? src['amount']
              : src['hourlyRate']) ??
          amount,
    );
    final worked = _int(
      src['workedMinutes'] ??
          ((src['billingHours'] != null)
              ? (_num(src['billingHours']) * 60).round()
              : 60),
    );
    final paused = _int(src['pausedMinutes'] ?? 0);
    final fee = _num(src['platformFee'] ?? 12);
    String name = fallbackName;
    if (counterpartIsCustomer) {
      name = src['customerName']?.toString() ??
          booking?['customer']?['name']?.toString() ??
          fallbackName;
    } else {
      name = src['workerName']?.toString() ??
          booking?['operator']?['name']?.toString() ??
          fallbackName;
    }
    return ManualPaymentBilling(
      amount: amount,
      serviceAmount: serviceAmount,
      petrolAmount: petrolAmount,
      petrolDistanceKm: _num(src['petrolDistanceKm'] ?? 0),
      petrolRatePerKm: _num(src['petrolRatePerKm'] ?? 0),
      hourlyRate: rate > 0 ? rate : amount,
      workedMinutes: worked > 0 ? worked : 1,
      pausedMinutes: paused,
      platformFee: fee,
      counterpartName: name,
    );
  }

  static double _num(dynamic v) => (num.tryParse('$v') ?? 0).toDouble();
  static int _int(dynamic v) => (num.tryParse('$v') ?? 0).round();
}
