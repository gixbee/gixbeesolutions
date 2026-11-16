/// Read-only pricing for the catering customer UI. The Rust catalogue
/// selection endpoint independently recalculates and validates all amounts.
class CateringCustomerPrice {
  const CateringCustomerPrice({
    required this.basePerPlate,
    required this.offerPerPlate,
    required this.guests,
    required this.minGuests,
    required this.maxGuests,
    required this.discountPercent,
  });

  final int basePerPlate;
  final int offerPerPlate;
  final int guests;
  final int minGuests;
  final int maxGuests;
  final int discountPercent;

  int get total => offerPerPlate * guests;
  int get originalTotal => basePerPlate * guests;
  int get saving => originalTotal - total;

  static CateringCustomerPrice? forItem(Map item, int guests) {
    if (item['active'] == false || guests < 1 || guests > 100000) return null;
    final tiers = (item['tiers'] as List? ?? const []).whereType<Map>();
    Map? matching;
    for (final tier in tiers) {
      final low = (tier['minGuests'] as num?)?.toInt();
      final high = (tier['maxGuests'] as num?)?.toInt();
      if (low != null && high != null && guests >= low && guests <= high) {
        matching = tier;
        break;
      }
    }
    if (matching == null) return null;
    final price = (matching['price'] as num?)?.toInt();
    if (price == null || price < 1) return null;
    final min = (matching['minGuests'] as num).toInt();
    final max = (matching['maxGuests'] as num).toInt();
    final base = (item['baseTiers'] as List? ?? const [])
        .whereType<Map>()
        .where((tier) => tier['minGuests'] == min && tier['maxGuests'] == max)
        .firstOrNull;
    final rawBase = (base?['price'] as num?)?.toInt();
    final basePrice = rawBase != null && rawBase >= price ? rawBase : price;
    final percent = (item['discountPct'] as num?)?.toInt() ?? 0;
    return CateringCustomerPrice(
      basePerPlate: basePrice,
      offerPerPlate: price,
      guests: guests,
      minGuests: min,
      maxGuests: max,
      discountPercent: percent >= 1 && percent <= 90 ? percent : 0,
    );
  }

  static int? estimate(List<Map<String, dynamic>> selection, int guests) {
    if (selection.isEmpty || selection.length > 20) return null;
    if (selection.length > 1 && selection.any((i) => i['kind'] != 'ITEM')) {
      return null;
    }
    final ids = <String>{};
    var total = 0;
    for (final item in selection) {
      final id = item['id'];
      if (id is! String || !ids.add(id)) return null;
      final price = forItem(item, guests);
      if (price == null) return null;
      total += price.total;
      if (total > 999999999) return null;
    }
    return total;
  }

  static List<Map<String, dynamic>> activeItems(Map catalogue) {
    return (catalogue['items'] as List? ?? const [])
        .whereType<Map>()
        .where((item) => item['active'] != false)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static List<Map<String, dynamic>> filterPackages(
    List<Map<String, dynamic>> items,
    int guests, {
    String eventCategory = 'all',
    String diet = 'all',
    String serving = 'all',
    int minPlate = 0,
    int maxPlate = 10000000,
  }) {
    return items.where((item) {
      if (item['kind'] != 'PACKAGE') return false;
      final quote = forItem(item, guests);
      if (quote == null || quote.offerPerPlate < minPlate ||
          quote.offerPerPlate > maxPlate) return false;
      if (eventCategory != 'all' && item['category'] != eventCategory) {
        return false;
      }
      if (diet != 'all' && item['diet'] != diet) return false;
      if (serving != 'all' && item['serveStyle'] != serving &&
          item['serveStyle'] != 'both') return false;
      return true;
    }).toList();
  }

  static List<Map<String, dynamic>> filterDishes(
    List<Map<String, dynamic>> items, int guests, {String diet = 'all'}) {
    return items.where((item) => item['kind'] == 'ITEM' &&
        (diet == 'all' || item['diet'] == diet) &&
        forItem(item, guests) != null).toList();
  }
}
