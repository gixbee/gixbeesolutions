import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/catering_price_math.dart';

void main() {
  group('CateringPriceMath', () {
    test('matches Rust half-up integer discount rounding', () {
      expect(CateringPriceMath.discountedPrice(500, 10), 450);
      expect(CateringPriceMath.discountedPrice(101, 50), 51);
      expect(CateringPriceMath.discountedPrice(1, 90), 1);
      expect(CateringPriceMath.discountedPrice(100, 0), 100);
    });

    test('keeps base tiers unchanged when building offer tiers', () {
      final original = [
        {'minGuests': 1, 'maxGuests': 25, 'price': 500},
        {'minGuests': 26, 'maxGuests': 50, 'price': 450},
      ];
      final prices = CateringPriceMath.offerTiers(original, 10);
      expect(original.first['price'], 500);
      expect(prices[0]['price'], 450);
      expect(prices[1]['price'], 405);
      expect(CateringPriceMath.platePriceForGuests(prices, 25), 450);
      expect(CateringPriceMath.platePriceForGuests(prices, 26), 405);
      expect(CateringPriceMath.estimateForGuests(prices, 26), 10530);
    });

    test('flat pricing supports the full guest range', () {
      final flat = CateringPriceMath.offerTiers([
        {'minGuests': 1, 'maxGuests': 100000, 'price': 400}
      ], 25);
      expect(CateringPriceMath.platePriceForGuests(flat, 1), 300);
      expect(CateringPriceMath.platePriceForGuests(flat, 100000), 300);
      expect(CateringPriceMath.platePriceForGuests(flat, 100001), isNull);
    });

    test('normalizes tier order but rejects overlaps', () {
      final tiers = CateringPriceMath.validateBaseTiers([
        {'minGuests': 26, 'maxGuests': 50, 'price': 450},
        {'minGuests': 1, 'maxGuests': 25, 'price': 500},
      ]);
      expect(tiers.first['minGuests'], 1);
      expect(
        () => CateringPriceMath.validateBaseTiers([
          {'minGuests': 1, 'maxGuests': 25, 'price': 500},
          {'minGuests': 25, 'maxGuests': 50, 'price': 450},
        ]),
        throwsFormatException,
      );
    });

    test('rejects invalid percentage, empty and negative tiers', () {
      expect(() => CateringPriceMath.discountedPrice(100, 91),
          throwsFormatException);
      expect(() => CateringPriceMath.discountedPrice(0, 10),
          throwsFormatException);
      expect(() => CateringPriceMath.validateBaseTiers([]),
          throwsFormatException);
      expect(() => CateringPriceMath.validateBaseTiers([
        {'minGuests': 1, 'maxGuests': 50, 'price': 0},
      ]), throwsFormatException);
    });
  });
}
