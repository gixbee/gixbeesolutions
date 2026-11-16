/// Shared, deterministic catering pricing calculations used by both food
/// items and packages. Server-side validation uses the same integer
/// half-up rupee rounding, so the customer quote matches the owner preview.
class CateringPriceMath {
  const CateringPriceMath._();

  static const maxGuests = 100000;
  static const maxPlatePrice = 10000000;

  static const referenceSlabs = <Map<String, int>>[
    {'minGuests': 1, 'maxGuests': 25, 'price': 500},
    {'minGuests': 26, 'maxGuests': 50, 'price': 450},
    {'minGuests': 51, 'maxGuests': 100, 'price': 400},
    {'minGuests': 101, 'maxGuests': 200, 'price': 350},
    {'minGuests': 201, 'maxGuests': 500, 'price': 300},
  ];

  static int discountedPrice(int price, int discountPct) {
    if (price < 1 || price > maxPlatePrice ||
        discountPct < 0 || discountPct > 90) {
      throw const FormatException('Invalid plate price or offer percentage');
    }
    return ((price * (100 - discountPct) + 50) ~/ 100)
        .clamp(1, maxPlatePrice)
        .toInt();
  }

  static List<Map<String, int>> validateBaseTiers(
      Iterable<Map<String, int>> tiers) {
    final rows = tiers.map((tier) => Map<String, int>.from(tier)).toList()
      ..sort((a, b) =>
          (a['minGuests'] ?? 0).compareTo(b['minGuests'] ?? 0));
    if (rows.isEmpty || rows.length > 20) {
      throw const FormatException('Set 1–20 guest-count pricing slabs');
    }
    var previous = 0;
    for (final row in rows) {
      final min = row['minGuests'];
      final max = row['maxGuests'];
      final price = row['price'];
      if (min == null || max == null || price == null ||
          min < 1 || min <= previous || max < min || max > maxGuests ||
          price < 1 || price > maxPlatePrice) {
        throw const FormatException(
          'Guest ranges must be valid, ordered and non-overlapping',
        );
      }
      previous = max;
    }
    return rows;
  }

  static List<Map<String, int>> offerTiers(
      Iterable<Map<String, int>> baseTiers, int discountPct) {
    if (discountPct < 0 || discountPct > 90) {
      throw const FormatException('Discount must be 0–90%');
    }
    return [
      for (final row in validateBaseTiers(baseTiers))
        {...row, 'price': discountedPrice(row['price']!, discountPct)},
    ];
  }

  /// Price selected by the Rust catalogue API for a guest count.
  /// Returns null when no slab covers the requested number of guests.
  static int? platePriceForGuests(
      List<Map<String, int>> displayedTiers, int guests) {
    if (guests < 1 || guests > maxGuests) return null;
    for (final tier in displayedTiers) {
      if ((tier['minGuests'] ?? maxGuests + 1) <= guests &&
          (tier['maxGuests'] ?? 0) >= guests) {
        return tier['price'];
      }
    }
    return null;
  }

  static int? estimateForGuests(
      List<Map<String, int>> displayedTiers, int guests) {
    final plate = platePriceForGuests(displayedTiers, guests);
    return plate == null ? null : plate * guests;
  }
}
