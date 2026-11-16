import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/repositories/events_repository.dart';

void main() {
  test('catalogue create, edit and reload preserve pricing and revision', () async {
    const businessId = '11111111-1111-4111-8111-111111111111';
    const dishId = '22222222-2222-4222-8222-222222222222';
    const packageId = '33333333-3333-4333-8333-333333333333';
    var revision = 0;
    var catalogue = <String, dynamic>{
      'about': '',
      'photos': <String>[],
      'items': <Map<String, dynamic>>[],
      'serviceCityIds': <String>[],
      'minNoticeDays': 0,
      'maxAdvanceDays': 730,
      'maxBookingsPerDay': 1,
    };
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path != '/events/catalogues/$businessId/CATERING') {
        return handler.reject(DioException(
            requestOptions: options, message: 'Unexpected route'));
      }
      if (options.method == 'GET') {
        return handler.resolve(Response(requestOptions: options, data: {
          'revision': revision,
          'catalogue': catalogue,
        }));
      }
      if (options.method == 'PUT') {
        final request = Map<String, dynamic>.from(options.data as Map);
        if (request['revision'] != revision) {
          return handler.reject(DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 409,
                data: {'message': 'Revision conflict'}),
          ));
        }
        revision++;
        catalogue = Map<String, dynamic>.from(request['catalogue'] as Map);
        return handler.resolve(Response(requestOptions: options, data: {
          'revision': revision, 'catalogue': catalogue,
        }));
      }
      handler.reject(DioException(requestOptions: options,
          message: 'Unexpected method'));
    }));
    final repository = EventsRepository(dio);
    final original = [
      {'minGuests': 1, 'maxGuests': 100, 'price': 500},
    ];
    final offered = [
      {'minGuests': 1, 'maxGuests': 100, 'price': 450},
    ];
    final dish = {
      'id': dishId, 'kind': 'ITEM', 'name': 'Welcome Drink',
      'active': true, 'diet': 'veg', 'category': 'g01',
      'tiers': original,
    };
    final entry = <String, dynamic>{
      'id': packageId,
      'kind': 'PACKAGE',
      'name': 'Wedding Feast',
      'category': 'Wedding & Related Functions',
      'packageLevel': 'Basic',
      'diet': 'veg',
      'serveStyle': 'buffet',
      'dishIds': [dishId],
      'active': true,
      'baseTiers': original,
      'discountPct': 10,
      'rateMode': 'tiered',
      'tiers': offered,
    };
    final created = await repository.saveCatalogue(
        businessId, 'CATERING', 0,
        {...catalogue, 'items': [dish, entry]});
    expect(created['revision'], 1);
    final reloaded = await repository.catalogue(businessId, 'CATERING');
    final reloadedItems = (reloaded['catalogue'] as Map)['items'] as List;
    final saved = reloadedItems[1] as Map;
    expect(saved['id'], packageId);
    expect(saved['dishIds'], [dishId]);
    expect(saved['baseTiers'], original);
    expect(saved['tiers'], offered);
    expect(saved['discountPct'], 10);

    final edited = {...entry,
      'name': 'Wedding Feast Premium',
      'active': false,
      'baseTiers': [
        {'minGuests': 1, 'maxGuests': 100, 'price': 600},
      ],
      'tiers': [
        {'minGuests': 1, 'maxGuests': 100, 'price': 540},
      ],
    };
    await repository.saveCatalogue(businessId, 'CATERING', 1,
        {...catalogue, 'items': [dish, edited]});
    final afterEdit = await repository.catalogue(businessId, 'CATERING');
    final finalEntry =
        ((afterEdit['catalogue'] as Map)['items'] as List)[1] as Map;
    expect(afterEdit['revision'], 2);
    expect(finalEntry['id'], packageId);
    expect(finalEntry['active'], false);
    expect(finalEntry['name'], 'Wedding Feast Premium');
    expect((finalEntry['tiers'] as List)[0]['price'], 540);

    await expectLater(
      repository.saveCatalogue(businessId, 'CATERING', 1, catalogue),
      throwsA(isA<DioException>()),
    );
  });
}
