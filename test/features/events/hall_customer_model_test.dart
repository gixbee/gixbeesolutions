import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/hall_customer_model.dart';

void main() {
  final indoor=<String,dynamic>{
    'hallId':'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'hallName':'Grand Indoor','businessName':'Convention Center',
    'spaceType':'indoor','location':'Kottayam',
    'capacity':{'seat':500,'dine':400,'rooms':2},
    'events':['Wedding','Reception','Baptism'],
    'slotOffers':[
      {
        'id':'morning','enabled':true,'offerNoAc':true,'offerAc':true,
        'priceNoAc':55000,'discountNoAcPct':10,
        'priceAc':75000,'discountAcPct':20,
      },
      {
        'id':'evening','enabled':false,'offerNoAc':true,
        'priceNoAc':45000,'discountNoAcPct':0,
      },
    ],
  };
  final outdoor=<String,dynamic>{
    'hallId':'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'hallName':'Garden','businessName':'Outdoor Venue',
    'spaceType':'outdoor','capacity':{'seat':300},
    'events':['Wedding'],
    'slotOffers':[{
      'id':'day','enabled':true,'offerNoAc':true,'offerAc':false,
      'priceNoAc':40000,'discountNoAcPct':0,
    }],
  };

  test('hall offer is rounded half up exactly like Rust',() {
    expect(HallCustomerModel.offer({
      'enabled':true,'offerNoAc':true,
      'priceNoAc':101,'discountNoAcPct':50,
    },false),51);
    expect(HallCustomerModel.offer(indoor['slotOffers']![0] as Map,false),
      49500);
    expect(HallCustomerModel.offer(indoor['slotOffers']![0] as Map,true),
      60000);
    expect(HallCustomerModel.minimumPrice(indoor),49500);
    expect(HallCustomerModel.minimumPrice(indoor,ac:'ac'),60000);
    expect(HallCustomerModel.minimumPrice(outdoor,ac:'ac'),isNull);
  });

  test('uses active slot prices, seat capacity, venue type and event',() {
    final halls=[indoor,outdoor];
    expect(HallCustomerModel.matches(halls,guests:250,
      event:'Wedding').length,2);
    expect(HallCustomerModel.matches(halls,guests:400,
      event:'Wedding').map((e)=>e['hallName']),['Grand Indoor']);
    expect(HallCustomerModel.matches(halls,guests:600,
      event:'Wedding'),isEmpty);
    expect(HallCustomerModel.matches(halls,guests:250,
      event:'Baptism').map((e)=>e['hallName']),['Grand Indoor']);
    expect(HallCustomerModel.matches(halls,guests:250,event:'Wedding',
      venue:'outdoor').map((e)=>e['hallName']),['Garden']);
    expect(HallCustomerModel.matches(halls,guests:250,event:'Wedding',
      ac:'ac',maxPrice:55000),isEmpty);
    expect(HallCustomerModel.matches(halls,guests:250,event:'Wedding',
      maxPrice:41000).map((e)=>e['hallName']),['Garden']);
  });

  test('only available slots shown; customer price is not discounted twice',() {
    final detail=<String,dynamic>{
      'hallId':indoor['hallId'],
      'slots':[
        {
          'start':'2026-12-20T03:30:00Z',
          'end':'2026-12-20T09:00:00Z',
          'available':true,
          'offer':{
            'id':'morning','label':'Morning',
            'offerNoAc':true,'offerAc':true,
            'priceNoAc':49500,'priceAc':60000,
            'listPriceNoAc':55000,'listPriceAc':75000,
            'discountNoAcPct':10,'discountAcPct':20,
          },
        },
        {'available':false,'offer':{
          'id':'evening','offerNoAc':true,'priceNoAc':45000,
        }},
      ],
    };
    final slots=HallCustomerModel.availableSlots(detail);
    expect(slots.length,2);
    expect(slots[0]['price'],49500);
    expect(slots[0]['basePrice'],55000);
    expect(slots[1]['price'],60000);
    expect(slots[1]['basePrice'],75000);
    final request=HallCustomerModel.request(detail:detail,slot:slots[1]);
    expect(request,{
      'hallId':indoor['hallId'],
      'slotId':'morning',
      'withAc':true,
      'expectedEstimate':60000,
    });
  });

  test('malformed slot never becomes a valid paid request',() {
    expect(()=>HallCustomerModel.request(
      detail:{'hallId':'id'},
      slot:{'slotId':'x','price':0,'withAc':true}),
      throwsFormatException);
  });
}
