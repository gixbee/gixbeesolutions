import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/catering_customer_pricing.dart';

void main() {
  final package = <String, dynamic>{
    'id': 'p1',
    'kind': 'PACKAGE',
    'name': 'Wedding Package',
    'category': 'Wedding & Related Functions',
    'serveStyle': 'both',
    'diet': 'mixed',
    'active': true,
    'discountPct': 10,
    'baseTiers': [
      {'minGuests': 1, 'maxGuests': 25, 'price': 500},
      {'minGuests': 26, 'maxGuests': 50, 'price': 450},
      {'minGuests': 51, 'maxGuests': 100, 'price': 400},
    ],
    'tiers': [
      {'minGuests': 1, 'maxGuests': 25, 'price': 450},
      {'minGuests': 26, 'maxGuests': 50, 'price': 405},
      {'minGuests': 51, 'maxGuests': 100, 'price': 360},
    ],
  };

  test('selects the exact current guest slab and exposes base/offer', () {
    final at25 = CateringCustomerPrice.forItem(package, 25)!;
    final at26 = CateringCustomerPrice.forItem(package, 26)!;
    expect(at25.basePerPlate, 500);
    expect(at25.offerPerPlate, 450);
    expect(at25.saving, 1250);
    expect(at25.total, 11250);
    expect(at26.basePerPlate, 450);
    expect(at26.offerPerPlate, 405);
    expect(at26.total, 10530);
    expect(CateringCustomerPrice.forItem(package, 101), isNull);
  });

  test('hides drafts and does not fabricate prices outside ranges', () {
    expect(CateringCustomerPrice.forItem({...package, 'active': false}, 30),
      isNull);
    expect(CateringCustomerPrice.forItem(package, 0), isNull);
    expect(CateringCustomerPrice.forItem(package, 100001), isNull);
  });

  test('package is exclusive; individual dishes can be combined', () {
    final dish = {
      'id': 'd1', 'kind': 'ITEM', 'active': true,
      'tiers': [
        {'minGuests': 1, 'maxGuests': 100, 'price': 100}
      ]
    };
    final other = {...dish, 'id': 'd2', 'tiers': [
      {'minGuests': 1, 'maxGuests': 100, 'price': 200}
    ]};
    expect(CateringCustomerPrice.estimate([package], 30), 12150);
    expect(CateringCustomerPrice.estimate([dish, other], 30), 9000);
    expect(CateringCustomerPrice.estimate([package, dish], 30), isNull);
    expect(CateringCustomerPrice.estimate([dish, dish], 30), isNull);
    expect(CateringCustomerPrice.estimate([], 30), isNull);
  });

  test('filters live wedding packages by diet, serving and guest price', () {
    final rows = <Map<String, dynamic>>[
      package,
      {...package, 'id': 'draft', 'active': false},
      {...package, 'id': 'other', 'category': 'Other Functions'}
    ];
    final visible = CateringCustomerPrice.filterPackages(
      CateringCustomerPrice.activeItems({'items': rows}), 50,
      eventCategory: 'Wedding & Related Functions',
      diet: 'mixed', serving: 'table', minPlate: 400,
      maxPlate: 410,
    );
    expect(visible.map((item) => item['id']).toList(), ['p1']);
  });

  test('does not apply an offer twice when server price is already discounted', () {
    final q = CateringCustomerPrice.forItem({
      ...package,
      'baseTiers': [
        {'minGuests': 1, 'maxGuests': 50, 'price': 101},
      ],
      'tiers': [
        {'minGuests': 1, 'maxGuests': 50, 'price': 51},
      ],
      'discountPct': 50,
    }, 20)!;
    expect(q.offerPerPlate, 51);
    expect(q.total, 1020);
    expect(q.basePerPlate, 101);
  });
}
