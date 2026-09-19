/// Shared billing helpers for post-completion manual payment screens.
class ManualPaymentBilling {
  final double amount;
  final double serviceAmount;
  final double petrolAmount;
  final double petrolDistanceKm;
  final double petrolRatePerKm;
  final double hourlyRate;
  final int workedMinutes;
  final int billingHours;
  final double platformFee;
  final String counterpartName;
  final String bookingType;

  const ManualPaymentBilling({
    required this.amount,
    this.serviceAmount = 0,
    this.petrolAmount = 0,
    this.petrolDistanceKm = 0,
    this.petrolRatePerKm = 0,
    required this.hourlyRate,
    required this.workedMinutes,
    this.billingHours = 1,
    required this.platformFee,
    required this.counterpartName,
    this.bookingType = 'INSTANT',
  });

  int get amountInt => amount.round();
  int get serviceAmountInt =>
      (serviceAmount > 0 ? serviceAmount : amount - petrolAmount).round();
  int get petrolAmountInt => petrolAmount.round();
  int get petrolRateInt => petrolRatePerKm.round();
  int get rateInt => hourlyRate.round();
  int get feeInt => platformFee.round();
  bool get isInstant => bookingType.toUpperCase() == 'INSTANT';
  // Petrol is an INSTANT-only line; show it there even at ₹0 for transparency.
  bool get showPetrol => isInstant || petrolAmount > 0;
  bool get hasPetrol => petrolAmount > 0;

  /// Whole hours actually charged (minimum 1). INSTANT bills per elapsed hour;
  /// scheduled jobs are a fixed quote.
  int get billedHours => billingHours > 0 ? billingHours : 1;

  /// `1 hr` / `2 hr` — ceil hours (legacy). Prefer [serviceRateLabel] on receipts.
  String get billedHoursLabel => billedHours == 1 ? '1 hr' : '$billedHours hr';

  /// Charge line for INSTANT jobs: 1-hour minimum, then actual worked time.
  String get serviceRateLabel {
    if (!isInstant) return 'Service charge (fixed)';
    if (workedMinutes <= 60) return '1 hr × ₹$rateInt/hr';
    return '$durationLabel × ₹$rateInt/hr';
  }

  String get petrolDistanceLabel {
    if (petrolDistanceKm <= 0) return '0 km';
    final rounded = petrolDistanceKm.roundToDouble();
    return petrolDistanceKm == rounded
        ? '${rounded.toInt()} km'
        : '${petrolDistanceKm.toStringAsFixed(1)} km';
  }

  String get durationLabel => formatDuration(workedMinutes);

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
    final billingHours = _int(
      src['billingHours'] ?? ((worked > 0 ? worked : 1) / 60).ceil(),
    );
    final bookingType = (src['type'] ?? src['bookingType'] ?? 'INSTANT')
        .toString()
        .toUpperCase();
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
      billingHours: billingHours > 0 ? billingHours : 1,
      platformFee: fee,
      counterpartName: name,
      bookingType: bookingType,
    );
  }

  static double _num(dynamic v) => (num.tryParse('$v') ?? 0).toDouble();
  static int _int(dynamic v) => (num.tryParse('$v') ?? 0).round();
}
