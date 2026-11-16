import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/photography_customer_model.dart';

void main() {
  final package = <String,dynamic>{
    'id':'11111111-1111-4111-8111-111111111111',
    'kind':'PACKAGE','active':true,'name':'Wedding Premium',
    'packageLevel':'Premium','price':90000,
    'listPrice':100000,'discountPct':10,
    'functions':['Wedding','Reception'],
    'ceremonies':['Hindu','Christian'],
  };
  final service = <String,dynamic>{
    'id':'22222222-2222-4222-8222-222222222222',
    'kind':'ITEM','active':true,'name':'Family Portrait Shoot',
    'category':'Portrait & Family','price':5000,
    'listPrice':6250,'discountPct':20,
  };
  final draft = {...package,'id':'33333333-3333-4333-8333-333333333333',
    'active':false};
  final vendor=<String,dynamic>{'catalogue':{
    'items':[package,service,draft],
  }};

  test('wedding and individual shoots only show matching published items',() {
    expect(PhotographyCustomerCatalogue.lowestPrice(vendor,'wedding'),
      90000);
    expect(PhotographyCustomerCatalogue.lowestPrice(vendor,'portrait'),5000);
    expect(PhotographyCustomerCatalogue.lowestPrice(vendor,'corporate'),isNull);
    expect(PhotographyCustomerCatalogue.items(vendor['catalogue'] as Map,
      'wedding',level:'Basic'),isEmpty);
    expect(PhotographyCustomerCatalogue.items(vendor['catalogue'] as Map,
      'wedding',community:'Christian').length,1);
    expect(PhotographyCustomerCatalogue.items(vendor['catalogue'] as Map,
      'wedding',community:'Muslim'),isEmpty);
    expect(PhotographyCustomerCatalogue.items(vendor['catalogue'] as Map,
      'engagement'),isEmpty);
  });

  test('displays exact published prices and does not apply discount twice',() {
    expect(PhotographyCustomerCatalogue.priceOf(package),90000);
    expect(PhotographyCustomerCatalogue.listPriceOf(package),100000);
    expect(PhotographyCustomerCatalogue.discountOf(package),10);
    expect(PhotographyCustomerCatalogue.priceOf(service),5000);
    expect(PhotographyCustomerCatalogue.priceOf({...service,'price':null}),
      isNull);
    expect(PhotographyCustomerCatalogue.items(vendor['catalogue'] as Map,
      'portrait',minPrice:5001),isEmpty);
  });

  final now=DateTime(2026,11,16,11);
  Map<String,dynamic> build({
    Map<String,dynamic>? selection,
    Map<String,dynamic>? custom,
    DateTime? start,DateTime? end,
    String notes='',
  })=>PhotographyCustomerRequest.build(
    clientRequestId:'44444444-4444-4444-8444-444444444444',
    businessId:'55555555-5555-4555-8555-555555555555',
    cityId:'66666666-6666-4666-8666-666666666666',
    eventType:'Wedding',location:'Thrissur',
    start:start??DateTime(2026,12,15,10),
    end:end??DateTime(2026,12,15,14),
    guests:100,item:selection??package,
    customization:custom??{
      'functions':['Reception'],
      'coverage':'Both sides',
      'team':'',
      'deliverables':'Extra album',
      'extras':'Drone',
    },
    notes:notes,now:now,
  );

  test('Rust event request keeps item id, base estimate and idempotency',() {
    final request=build();
    expect(request['services'],['PHOTOGRAPHY']);
    expect(request['targetBusinessId'],
      '55555555-5555-4555-8555-555555555555');
    expect(request['clientRequestId'],
      '44444444-4444-4444-8444-444444444444');
    final selection=request['serviceRequest'] as Map;
    expect(selection['itemIds'],[package['id']]);
    expect(selection['expectedEstimate'],90000);
    expect(selection['customization'],containsPair('extras','Drone'));
    expect(request['guestCount'],100);
  });

  test('disallows draft items, unsupported field, invalid dates and too many requirements',() {
    expect(()=>build(selection:draft),throwsFormatException);
    expect(()=>build(custom:{
      'functions':[],'expectedEstimate':1,
    }),throwsFormatException);
    expect(()=>build(custom:{
      'functions':['Wedding','Wedding'],
    }),throwsFormatException);
    expect(()=>build(notes:List.filled(5001,'x').join()),
      throwsFormatException);
    expect(()=>build(start:now.subtract(const Duration(days:1))),
      throwsFormatException);
    expect(()=>build(end:DateTime(2026,12,15,9)),
      throwsFormatException);
    expect(()=>build(selection:{...package,'price':0}),
      throwsFormatException);
  });
}
