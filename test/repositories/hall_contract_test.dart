import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gixbee/repositories/events_repository.dart';
import 'package:gixbee/repositories/hall_repository.dart';

void main() {
  const business='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const hall='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

  test('venue hall count and parking are saved with owner-only route',() async {
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) {
      expect(o.path,'/businesses/$business/venue');
      expect(o.method,'PATCH');
      final p=Map<String,dynamic>.from(o.data as Map);
      expect(p['plannedHallCount'],3);
      expect(p['commonParking'],{'car':100,'bike':200});
      h.resolve(Response(requestOptions:o,data:{
        'plannedHallCount':3,'commonParking':{'car':100,'bike':200},
      }));
    }));
    final result=await HallRepository(dio).patchVenue(business,{
      'plannedHallCount':3,'commonParking':{'car':100,'bike':200},
    });
    expect(result['plannedHallCount'],3);
  });

  test('hall package booking settings update keeps existing slot and policy',() async {
    final package=<String,dynamic>{
      'events':['Wedding'],'capacity':{'seat':500,'dine':400,'rooms':2},
      'facilities':['AC'],'slotOffers':[{
        'id':'morning','enabled':true,'hallFrom':'09:00',
        'hallTo':'14:00','offerNoAc':true,'offerAc':true,
        'priceNoAc':55000,'priceAc':75000,
        'discountNoAcPct':10,'discountAcPct':20,
      }],
      'payment':{
        'advanceType':'fixed','advanceFixed':10000,
        'fullDueDays':5,
      },
      'cancelRules':[{
        'minDaysBeforeEvent':30,'maxDaysBeforeEvent':null,
        'deductionPercent':10,
      }],
      'rescheduleRules':[],
      'bookWindowMonths':6,'minNoticeDays':3,
    };
    var revision=1;
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) {
      expect(o.path,'/businesses/$business/halls/$hall/package');
      if(o.method=='GET') {
        h.resolve(Response(requestOptions:o,
          data:{'packageSaved':true,'revision':revision,'package':package}));
      }else if(o.method=='PUT') {
        final data=Map<String,dynamic>.from(o.data as Map);
        final changed=Map<String,dynamic>.from(data['package'] as Map);
        expect(changed['payment'],package['payment']);
        expect(changed['slotOffers'],package['slotOffers']);
        expect(changed['cancelRules'],package['cancelRules']);
        expect(changed['capacity'],package['capacity']);
        package.addAll(changed);
        revision++;
        h.resolve(Response(requestOptions:o,
          data:{'revision':revision,'packageSaved':true,'package':package}));
      }else{
        h.reject(DioException(requestOptions:o,message:'Unexpected method'));
      }
    }));
    final api=HallRepository(dio);
    final existing=await api.getPackage(business,hall);
    final before=Map<String,dynamic>.from(existing['package'] as Map);
    await api.savePackage(business,hall,{
      ...before,'bookWindowMonths':12,'minNoticeDays':7,
    });
    final reloaded=await api.getPackage(business,hall);
    final saved=reloaded['package'] as Map;
    expect(saved['bookWindowMonths'],12);
    expect(saved['minNoticeDays'],7);
    expect(saved['slotOffers'],before['slotOffers']);
    expect(saved['payment'],before['payment']);
    expect(reloaded['revision'],2);
  });

  test('customer hall discovery and selected date details use canonical APIs',
      () async {
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) {
      if(o.path=='/halls/discover') {
        expect(o.queryParameters['cityId'],'city-123');
        h.resolve(Response(requestOptions:o,data:[
          {
            'hallId':hall,'businessId':business,
            'capacity':{'seat':300},
            'slotOffers':[{
              'id':'morning','priceNoAc':20000,
              'offerNoAc':true,'discountNoAcPct':0,
            }],
          }
        ]));
      }else if(o.path=='/halls/$hall/customer') {
        expect(o.queryParameters['day'],'2026-12-20');
        h.resolve(Response(requestOptions:o,data:{
          'hallId':hall,'slots':[
            {'available':true,'offer':{'id':'morning','priceNoAc':20000}},
          ],
        }));
      }else {
        h.reject(DioException(requestOptions:o,message:'Unexpected route'));
      }
    }));
    final events=EventsRepository(dio);
    final results=await events.discover('HALL','city-123');
    expect(results.length,1);
    final detail=await events.hallDetails(hall,'2026-12-20');
    expect((detail['slots'] as List).length,1);
  });
}
