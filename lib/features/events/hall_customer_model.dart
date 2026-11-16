/// Hall search/slot price calculations mirror Rust halls/customer.rs.
/// Values are derived only from active verified hall package snapshots.
class HallCustomerModel {
  const HallCustomerModel._();

  static int? offer(Map raw, bool ac) {
    if (raw['enabled'] == false) return null;
    if (ac ? raw['offerAc'] != true : raw['offerNoAc'] == false) return null;
    final base = raw[ac ? 'priceAc' : 'priceNoAc'];
    final pct = raw[ac ? 'discountAcPct' : 'discountNoAcPct'] ?? 0;
    if (base is! int || base < 0 || base > 100000000 ||
        pct is! int || pct < 0 || pct > 99) return null;
    return (base * (100 - pct) + 50) ~/ 100;
  }

  static int? minimumPrice(Map<String,dynamic> hall, {
    String ac = 'any',
  }) {
    final prices = <int>[];
    for (final slot in (hall['slotOffers'] as List? ?? const [])) {
      if (slot is! Map) continue;
      if (ac != 'ac') {
        final p = offer(slot,false);
        if (p != null) prices.add(p);
      }
      if (ac != 'noac') {
        final p = offer(slot,true);
        if (p != null) prices.add(p);
      }
    }
    if (prices.isEmpty) return null;
    prices.sort();
    return prices.first;
  }

  static List<Map<String,dynamic>> matches(
    List<Map<String,dynamic>> halls, {
    required int guests,
    required String event,
    String ac = 'any',
    String venue = 'any',
    int maxPrice = 200000,
    String query = '',
    String sort = 'price',
  }) {
    if (guests < 1 || guests > 100000 || maxPrice < 0) return [];
    final needle = query.toLowerCase().trim();
    final list = halls.where((h) {
      if (venue != 'any' && h['spaceType'] != venue) return false;
      final capacity = (h['capacity'] as Map?)?['seat'];
      if (capacity is int && capacity > 0 && guests > capacity) return false;
      final events = (h['events'] as List? ?? const [])
          .whereType<String>().map((e)=>e.toLowerCase()).toList();
      if (event.trim().isNotEmpty && events.isNotEmpty &&
          !events.contains(event.trim().toLowerCase())) return false;
      if (needle.isNotEmpty &&
          !'${h['hallName']??''} ${h['businessName']??''} ${h['location']??''}'
              .toLowerCase().contains(needle)) return false;
      final price = minimumPrice(h,ac:ac);
      return price != null && price <= maxPrice;
    }).toList();
    list.sort((a,b) {
      if (sort == 'price') {
        final pa = minimumPrice(a,ac:ac) ?? 2147483647;
        final pb = minimumPrice(b,ac:ac) ?? 2147483647;
        final comparison=pa.compareTo(pb);
        if (comparison!=0)return comparison;
      }
      return '${a['hallName']??''}'.compareTo('${b['hallName']??''}');
    });
    return list;
  }

  static List<Map<String,dynamic>> availableSlots(
    Map<String,dynamic> detail, {String ac = 'any'}) {
    final slots = <Map<String,dynamic>>[];
    for (final raw in (detail['slots'] as List? ?? const [])) {
      if (raw is! Map || raw['available'] != true) continue;
      final offer = raw['offer'];
      if (offer is! Map) continue;
      for (final withAc in [false,true]) {
        if (ac == 'ac' && !withAc || ac == 'noac' && withAc) continue;
        final enabled = offer[withAc ? 'offerAc' : 'offerNoAc'] == true;
        final price = offer[withAc ? 'priceAc' : 'priceNoAc'];
        if (!enabled || price is! int || price < 0) continue;
        slots.add({
          'slotId':offer['id'], 'label':offer['label'],
          'start':raw['start'], 'end':raw['end'],
          'withAc':withAc, 'price':price,
          'basePrice':offer[withAc ? 'listPriceAc' : 'listPriceNoAc'] ?? price,
          'discountPercent':offer[withAc
            ? 'discountAcPct' : 'discountNoAcPct'] ?? 0,
        });
      }
    }
    return slots;
  }

  static Map<String,dynamic> request({
    required Map<String,dynamic> detail,
    required Map<String,dynamic> slot,
  }) {
    final hall=detail['hallId'], id=slot['slotId'];
    final price=slot['price'];
    if (hall is! String || id is! String ||
        price is! int || price < 0 ||
        slot['withAc'] is! bool ||
        DateTime.tryParse('${slot['start']}') == null ||
        DateTime.tryParse('${slot['end']}') == null) {
      throw const FormatException('Choose an available hall price and slot.');
    }
    return {
      'hallId':hall,
      'slotId':id,
      'withAc':slot['withAc'],
      'expectedEstimate':price,
    };
  }
}
