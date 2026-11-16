import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/repositories/events_repository.dart';

void main() {
  const businessId = '11111111-1111-4111-8111-111111111111';
  const photoId = '22222222-2222-4222-8222-222222222222';
  const serviceId = '33333333-3333-4333-8333-333333333333';
  final package = <String,dynamic>{
    'id': photoId, 'kind':'PACKAGE', 'name':'Wedding Photo Premium',
    'active':true, 'price':90000,'listPrice':100000,'discountPct':10,
    'functions':['Wedding'], 'ceremonies':['Hindu'],
    'inclusions':['Edited Photos'],
    'paymentSplit':[
      {'label':'Advance','percent':30},
      {'label':'Event','percent':40},
      {'label':'Album','percent':20},
      {'label':'Final','percent':10},
    ],
    'extraPrices':{'Drone / Helicam':3000},
    'extras':['Drone / Helicam'],
    'functionCoverage':{
      'Wedding':{'side':'Both','duration':'8 hours'},
    },
    'deliverableDetails':{
      'Edited Photos':{'quantity':500, 'format':'JPG'},
    },
    'deliveryTimelines':{
      'Edited Photos':{'days':21},
    },
    'cancelRules':[
      {'label':'30+ days','deductionPercent':10},
    ],
    'rescheduleRules':[
      {'label':'30+ days','deductionPercent':0},
    ],
  };
  final service = <String,dynamic>{
    'id':serviceId, 'kind':'ITEM','name':'Portrait Session',
    'price':8000,'listPrice':10000,'discountPct':20,
    'category':'Portrait & Family','active':true,
  };

  test('photo catalogue API preserves structured details on save, edit, reload',
      () async {
    var revision = 0;
    var catalogue = <String,dynamic>{
      'items':<Map<String,dynamic>>[],
      'photos':<String>[],
      'about':'',
      'minNoticeDays':0,
      'maxAdvanceDays':365,
      'maxBookingsPerDay':3,
      'serviceCityIds':<String>[],
    };
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) {
      if (o.path != '/events/catalogues/$businessId/PHOTOGRAPHY') {
        return h.reject(DioException(requestOptions:o,message:'Unexpected API route'));
      }
      if (o.method == 'GET') return h.resolve(Response(requestOptions:o,
        data:{'revision':revision, 'catalogue':catalogue}));
      if (o.method == 'PUT') {
        final payload = Map<String,dynamic>.from(o.data as Map);
        if (payload['revision'] != revision) {
          return h.reject(DioException(requestOptions:o,
            response:Response(requestOptions:o,statusCode:409,
              data:{'message':'Revision conflict'})));
        }
        revision++;
        catalogue = Map<String,dynamic>.from(payload['catalogue'] as Map);
        return h.resolve(Response(requestOptions:o,
          data:{'revision':revision,'catalogue':catalogue}));
      }
      h.reject(DioException(requestOptions:o,message:'Unexpected HTTP method'));
    }));
    final api = EventsRepository(dio);
    await api.saveCatalogue(businessId,'PHOTOGRAPHY',revision,
      {...catalogue,'items':[package,service]});
    final created = await api.catalogue(businessId,'PHOTOGRAPHY');
    final items = ((created['catalogue'] as Map)['items'] as List);
    expect(items.length,2);
    expect((items.first as Map)['discountPct'],10);
    expect((items.first as Map)['functionCoverage'],package['functionCoverage']);
    expect((items.first as Map)['deliveryTimelines'],package['deliveryTimelines']);

    final edited = {...package,'name':'Wedding Premium Plus','active':false,
      'price':95000,'listPrice':100000,'discountPct':5};
    await api.saveCatalogue(businessId,'PHOTOGRAPHY',1,
      {...catalogue,'items':[edited,service]});
    final reloaded=await api.catalogue(businessId,'PHOTOGRAPHY');
    final stored=((reloaded['catalogue'] as Map)['items'] as List).first as Map;
    expect(reloaded['revision'],2);
    expect(stored['id'],photoId);
    expect(stored['name'],'Wedding Premium Plus');
    expect(stored['active'],false);
    expect(stored['price'],95000);
    expect(stored['extraPrices'],{'Drone / Helicam':3000});
    await expectLater(api.saveCatalogue(businessId,'PHOTOGRAPHY',1,
        catalogue),throwsA(isA<DioException>()));
  });

  test('owner calendar uses protected combined overview endpoint',
      () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h) {
      expect(o.method,'GET');
      expect(o.path,'/events/vendor/calendar/$businessId/overview');
      h.resolve(Response(requestOptions:o,data:[
        {
          'id':'a','source':'gixbee','title':'Wedding',
          'startAt':'2026-12-20T10:00:00Z',
          'endAt':'2026-12-20T16:00:00Z','status':'CONFIRMED'
        },
        {
          'id':'b','source':'offline','title':'Portrait',
          'startAt':'2026-12-22T09:00:00Z',
          'endAt':'2026-12-22T11:00:00Z'
        }
      ]));
    }));
    final entries=await EventsRepository(dio).photographyCalendar(businessId);
    expect(entries.length,2);
    expect(entries.first['source'],'gixbee');
    expect(entries.last['source'],'offline');
  });
}
