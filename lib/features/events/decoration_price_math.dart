/// Pure integer-rupee offer calculation. Rust applies the same half-up rule.
/// Catalogue pricing remains server-authoritative at enquiry creation.
class DecorationPriceMath {
  const DecorationPriceMath._();

  static const int maxPrice = 10000000;

  static bool isValid(int listPrice, int discountPct) =>
      listPrice >= 1 &&
      listPrice <= maxPrice &&
      discountPct >= 0 &&
      discountPct <= 90;

  static int offerPrice(int listPrice, int discountPct) {
    if (!isValid(listPrice, discountPct)) {
      throw RangeError('Invalid decoration list price or discount');
    }
    return (listPrice * (100 - discountPct) + 50) ~/ 100;
  }
}
