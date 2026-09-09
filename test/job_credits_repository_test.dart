import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/repositories/job_credits_repository.dart';

void main() {
  test('an unavailable pack never becomes a made-up purchasable offer',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
      }));
    await expectLater(
        JobCreditsRepository(dio).getPackInfo(), throwsA(isA<DioException>()));
  });

  test('old or incomplete pack contracts surface an error before checkout',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        handler.resolve(Response(
            requestOptions: request,
            data: {'credits': 3, 'price': 49, 'currency': 'INR'}));
      }));
    await expectLater(
        JobCreditsRepository(dio).getPackInfo(), throwsFormatException);
  });

  test('a valid pack retains the server credit count and acceptance cost',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        handler.resolve(Response(requestOptions: request, data: {
          'credits': 45,
          'creditsPerAccept': 15,
          'price': 49,
          'currency': 'INR'
        }));
      }));
    final pack = await JobCreditsRepository(dio).getPackInfo();
    expect((pack['credits'] as int) ~/ (pack['creditsPerAccept'] as int), 3);
  });
}
