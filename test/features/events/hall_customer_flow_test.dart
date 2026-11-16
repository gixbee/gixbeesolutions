import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:gixbee/features/events/hall_customer_flow_screen.dart';
import 'package:gixbee/repositories/events_repository.dart';

void main() {
  const hallId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const businessId='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  const cityId='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  late DateTime day;
  late String start,end;

  setUp(() {
    day=DateUtils.dateOnly(DateTime.now().add(const Duration(days:40)));
    start=DateTime.utc(day.year,day.month,day.day,3,30)
      .toIso8601String();
    end=DateTime.utc(day.year,day.month,day.day,8,30)
      .toIso8601String();
  });

  void phone(WidgetTester t) {
    t.view.physicalSize=const Size(440,960);
    t.view.devicePixelRatio=1;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
  }

  final overview=<String,dynamic>{
    'hallId':hallId,'businessId':businessId,'businessName':'Hall Center',
    'hallName':'Grand Hall','location':'Kottayam',
    'spaceType':'indoor',
    'coverImageUrl':null,
  };

  Map<String,dynamic> detail()=>{
    ...overview,
    'package':{
      'capacity':{'seat':500,'dine':300,'rooms':2},
      'facilities':['AC','Stage'],
      'payment':{
        'advanceType':'fixed','advanceFixed':10000,
        'advancePct':0,'fullDueDays':5,
      },
      'cancelRules':[
        {'minDaysBeforeEvent':30,'maxDaysBeforeEvent':null,
          'deductionPercent':10},
      ],
    },
    'parking':{'car':90,'bike':130},
    'photos':<String>[],
    'slots':[
      {
        'start':start,'end':end,'available':true,
        'offer':{
          'id':'morning','label':'Morning',
          'hallFrom':'09:00','hallTo':'14:00',
          'offerNoAc':true,'offerAc':true,
          'priceNoAc':49500,'priceAc':60000,
          'listPriceNoAc':55000,'listPriceAc':75000,
          'discountNoAcPct':10,'discountAcPct':20,
        },
      },
      {
        'start':start,'end':end,'available':false,
        'offer':{'id':'evening','label':'Evening',
          'offerNoAc':true,'priceNoAc':55000},
      },
    ],
  };

  testWidgets('real hall profile, price breakdown, slot and review display',
      (t) async {
    phone(t);
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) {
      expect(o.method,'GET');
      expect(o.path,'/halls/$hallId/customer');
      h.resolve(Response(requestOptions:o,data:detail()));
    }));
    await t.pumpWidget(ProviderScope(overrides:[
      eventsRepositoryProvider.overrideWithValue(EventsRepository(dio)),
    ],child:MaterialApp(home:HallCustomerProfileScreen(
      hall:overview,cityId:cityId,eventType:'Wedding',
      date:day,guests:200,acPreference:'any'))));
    await t.pumpAndSettle();
    expect(find.text('Grand Hall'),findsWidgets);
    expect(find.textContaining('Seating'),findsWidgets);
    await t.tap(find.text('Continue · Select Date & Time'));
    await t.pumpAndSettle();
    expect(find.text('Select Date & Time'),findsOneWidget);
    expect(find.text('₹49,500'),findsOneWidget);
    expect(find.text('₹55,000'),findsOneWidget);
    expect(find.text('10% OFF'),findsOneWidget);
    expect(find.textContaining('Unavailable / already booked'),findsOneWidget);
    await t.tap(find.byType(RadioListTile<String>).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Continue · Review Booking Details'));
    await t.pumpAndSettle();
    expect(find.text('Booking Details'),findsOneWidget);
    expect(find.text('₹49,500'),findsWidgets);
    expect(find.text('₹10,000'),findsWidgets);
    expect(find.textContaining('Remaining balance'),findsWidgets);
  });

  testWidgets('Request to Book posts one idempotent hall selection and shows success',
      (t) async {
    phone(t);
    var requests=0;
    Map<String,dynamic>? sent;
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) {
      if(o.method=='GET'&&o.path=='/halls/$hallId/customer'){
        h.resolve(Response(requestOptions:o,data:detail()));
      }else if(o.method=='POST'&&o.path=='/events'){
        sent=Map<String,dynamic>.from(o.data as Map);
        requests++;
        h.resolve(Response(requestOptions:o,
          data:{'id':'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'}));
      }else{
        h.reject(DioException(requestOptions:o,
          message:'Unexpected ${o.method} ${o.path}'));
      }
    }));
    await t.pumpWidget(ProviderScope(overrides:[
      eventsRepositoryProvider.overrideWithValue(EventsRepository(dio)),
    ],child:MaterialApp(home:HallCustomerSlotsScreen(
      hall:overview,cityId:cityId,eventType:'Wedding',
      date:day,guests:200,acPreference:'ac'))));
    await t.pumpAndSettle();
    await t.tap(find.byType(RadioListTile<String>).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Continue · Review Booking Details'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('I understand this sends a booking request, not a confirmed reservation.'),
      280,scrollable:find.byType(Scrollable).last);
    await t.pumpAndSettle();
    await t.tap(find.text('I understand this sends a booking request, not a confirmed reservation.'));
    await t.pumpAndSettle();
    await t.tap(find.text('Request to Book'));
    await t.pumpAndSettle();
    expect(requests,1);
    expect((sent?['serviceRequest'] as Map)['expectedEstimate'],60000);
    expect((sent?['serviceRequest'] as Map)['withAc'],true);
    expect((sent?['serviceRequest'] as Map)['slotId'],'morning');
    expect(sent?['clientRequestId'],isNotNull);
    expect(sent?['services'],['HALL']);
    expect(find.text('Your Hall Request Has Been Sent!'),findsOneWidget);
  });
}
