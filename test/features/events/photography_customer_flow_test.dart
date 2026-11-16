import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/photography_customer_flow_screen.dart';
import 'package:gixbee/repositories/events_repository.dart';

void main() {
  const packageId='11111111-1111-4111-8111-111111111111';
  const serviceId='22222222-2222-4222-8222-222222222222';
  final studio=<String,dynamic>{
    'businessId':'33333333-3333-4333-8333-333333333333',
    'name':'Kerala Wedding Photography','location':'Thrissur',
    'catalogue':{
      'about':'Wedding and portrait shoots',
      'photos':<String>[],
      'items':[
        {
          'id':packageId,'kind':'PACKAGE','active':true,
          'name':'Wedding Premium','description':'Full wedding coverage',
          'packageLevel':'Premium','price':90000,
          'listPrice':100000,'discountPct':10,
          'functions':['Wedding','Reception'],
          'ceremonies':['Hindu'],
          'inclusions':['Edited Photos','Highlights Reel'],
          'extras':['Drone / Helicam'],
          'extraPrices':{'Drone / Helicam':3000},
          'paymentSplit':[{'label':'Booking advance','percent':30}],
        },
        {
          'id':serviceId,'kind':'ITEM','active':true,
          'name':'Family Portrait','category':'Portrait & Family',
          'price':5000,'listPrice':6250,'discountPct':20,
          'inclusions':['Edited Photos'],
        },
      ]
    }
  };

  void phone(WidgetTester t) {
    t.view.physicalSize=const Size(440,960);
    t.view.devicePixelRatio=1;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
  }

  Widget app({String need='wedding',EventsRepository? repo})=>
    ProviderScope(overrides:[
      if(repo!=null) eventsRepositoryProvider.overrideWithValue(repo),
    ],child:MaterialApp(home:PhotographyCustomerProfileScreen(
      vendor:studio,
      cityId:'44444444-4444-4444-8444-444444444444',
      eventType:need=='wedding'?'Wedding':'Portrait',
      date:DateTime(2026,12,15),
      guests:100,location:'Thrissur',
      need:need,community:'All',level:'All',
      minBudget:0,maxBudget:10000000,
    )));

  testWidgets('customer sees real package, discount, extras and review',
      (tester) async {
    phone(tester);
    await tester.pumpWidget(app());
    expect(find.text('Kerala Wedding Photography'),findsWidgets);
    await tester.tap(find.text('View Packages'));
    await tester.pumpAndSettle();
    expect(find.text('Wedding Premium'),findsOneWidget);
    expect(find.text('₹90,000'),findsOneWidget);
    expect(find.text('10% OFF'),findsOneWidget);
    await tester.tap(find.text('Wedding Premium'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Extras'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extras'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Drone / Helicam'),findsOneWidget);
    await tester.tap(find.text('Initiate Interest'));
    await tester.pumpAndSettle();
    expect(find.text('Review Your Interest'),findsOneWidget);
    expect(find.text('I understand this is an enquiry, not a booking.'),
      findsOneWidget);
  });

  testWidgets('individual service is accessible without wedding package filter',
      (tester) async {
    phone(tester);
    await tester.pumpWidget(app(need:'portrait'));
    await tester.tap(find.text('View Services'));
    await tester.pumpAndSettle();
    expect(find.text('Family Portrait'),findsOneWidget);
    expect(find.text('₹5,000'),findsOneWidget);
    expect(find.text('20% OFF'),findsOneWidget);
    expect(find.text('Wedding Premium'),findsNothing);
  });

  testWidgets('send interest posts only stored base price then shows timeline',
      (tester) async {
    phone(tester);
    Map<String,dynamic>? posted;
    var calls=0;
    final dio=Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler) {
      expect(options.method,'POST');
      expect(options.path,'/events');
      posted=Map<String,dynamic>.from(options.data as Map);
      calls++;
      handler.resolve(Response(requestOptions:options,
        data:{'id':'55555555-5555-4555-8555-555555555555'}));
    }));
    await tester.pumpWidget(app(repo:EventsRepository(dio)));
    await tester.tap(find.text('View Packages'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wedding Premium'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Initiate Interest'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('I understand this is an enquiry, not a booking.'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('I understand this is an enquiry, not a booking.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send Interest'));
    await tester.pumpAndSettle();
    expect(find.text('Your Interest has been Sent!'),findsOneWidget);
    expect(calls,1);
    expect(posted?['services'],['PHOTOGRAPHY']);
    expect((posted?['serviceRequest'] as Map)['expectedEstimate'],90000);
    expect((posted?['serviceRequest'] as Map)['itemIds'],[packageId]);
  });
}
