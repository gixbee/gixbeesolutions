import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/rentals/rental_images.dart';

void main() {
  test('cover first, then extras, de-duplicated and capped at 6', () {
    final urls = rentalImageUrls({
      'imageUrl': '/a.jpg',
      'imageUrls': ['/a.jpg', '/b.jpg', ' /c.jpg ', '', '/d.jpg', '/e.jpg', '/f.jpg', '/g.jpg'],
    });
    expect(urls, ['/a.jpg', '/b.jpg', '/c.jpg', '/d.jpg', '/e.jpg', '/f.jpg']);
  });

  test('falls back to extras when cover is missing', () {
    expect(
      rentalImageUrls({
        'imageUrls': ['/b.jpg', '/c.jpg'],
      }),
      ['/b.jpg', '/c.jpg'],
    );
  });

  test('empty item has a growable photo list', () {
    final urls = rentalImageUrls(null);
    urls.add('/x.jpg');
    expect(urls, ['/x.jpg']);
  });

  test('distance label hides missing or invalid values', () {
    expect(rentalDistanceLabel(null), isNull);
    expect(rentalDistanceLabel({'distanceKm': 'nope'}), isNull);
    expect(rentalDistanceLabel({'distanceKm': -1}), isNull);
  });

  test('distance label uses metres under 1 km', () {
    expect(rentalDistanceLabel({'distanceKm': 0.04}), 'Nearby');
    expect(rentalDistanceLabel({'distanceKm': 0.4}), '400 m away');
    expect(rentalDistanceLabel({'distanceKm': 2.36}), '2.4 km away');
  });
}
