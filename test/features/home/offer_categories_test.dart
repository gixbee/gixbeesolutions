import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/home/offer_categories.dart';

void main() {
  test('offer chips filter by category and skip directories', () {
    expect(matchesOfferCategory('Jewellery', 'All'), isTrue);
    expect(matchesOfferCategory('Jewellery', '💍 Jewellery'), isTrue);
    expect(matchesOfferCategory('Medical', '💍 Jewellery'), isFalse);
    expect(matchesOfferCategory('Fitness', '🏋 Fitness'), isFalse);
    expect(offerCategories.where((c) => c.isDirectory).length, 9);
  });
}
