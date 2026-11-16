import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/photography_owner_pricing.dart';

void main() {
  test('photography half-up discount rounding matches Rust', () {
    expect(PhotographyOwnerPrice.discounted(101, 50), 51);
    expect(PhotographyOwnerPrice.discounted(100000, 10), 90000);
    expect(PhotographyOwnerPrice.discounted(100, 0), 100);
    expect(PhotographyOwnerPrice.discounted(100, 91), isNull);
    expect(PhotographyOwnerPrice.discounted(0, 0), isNull);
  });

  test('requires exact customer price and payment stages totaling 100', () {
    final pkg = <String, dynamic>{
      'name':'Wedding Premium', 'kind':'PACKAGE',
      'price':90000, 'listPrice':100000, 'discountPct':10,
      'functions':['Wedding'],
      'paymentSplit':[
        {'label':'Advance','percent':30},
        {'label':'Event','percent':40},
        {'label':'Albums','percent':20},
        {'label':'Final','percent':10},
      ],
    };
    expect(PhotographyOwnerPrice.validate(pkg), isNull);
    expect(PhotographyOwnerPrice.validate({...pkg,'price':89999}), isNotNull);
    final stages=(pkg['paymentSplit'] as List).cast<Map>();
    expect(PhotographyOwnerPrice.validate({...pkg,'paymentSplit':[
      ...stages.take(3),
      {'label':'Final','percent':9}
    ]}), isNotNull);
    expect(PhotographyOwnerPrice.validate({
      ...pkg,'paymentSplit':[...stages.take(3),stages[0]]
    }), isNotNull);
  });

  test('filters packages and standalone services by level/status', () {
    final rows = <Map<String,dynamic>>[
      {'id':'p1','name':'Wedding Basic','kind':'PACKAGE','packageLevel':'Basic','active':true},
      {'id':'p2','name':'Premium Wedding','kind':'PACKAGE','packageLevel':'Premium','active':false},
      {'id':'s1','name':'Portrait','kind':'ITEM','category':'Portrait','active':true},
    ];
    expect(PhotographyOwnerPrice.visible(rows, packages:true,
      level:'Premium', status:'draft').map((x)=>x['id']).toList(),['p2']);
    expect(PhotographyOwnerPrice.visible(rows, packages:false,
      search:'portrait').map((x)=>x['id']).toList(),['s1']);
    expect(PhotographyOwnerPrice.visible(rows, packages:true,
      status:'live').map((x)=>x['id']).toList(),['p1']);
  });
}
