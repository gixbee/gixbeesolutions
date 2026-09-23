import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/repositories/cities_repository.dart';

void main() {
  const cities = [
    CityEntry(
      id: 'tvm',
      name: 'Thiruvananthapuram',
      state: 'Kerala',
      lat: 8.5241,
      lng: 76.9366,
    ),
    CityEntry(
      id: 'blr',
      name: 'Bangalore',
      state: 'Karnataka',
      lat: 12.9716,
      lng: 77.5946,
    ),
  ];

  test('matches exact city name and display name', () {
    expect(matchTypedCity(cities, 'Thiruvananthapuram')?.id, 'tvm');
    expect(matchTypedCity(cities, 'Thiruvananthapuram, Kerala')?.id, 'tvm');
  });

  test('matches a typed prefix', () {
    expect(matchTypedCity(cities, 'Thiru')?.id, 'tvm');
    expect(matchTypedCity(cities, 'bang')?.id, 'blr');
  });

  test('aliases map Trivandrum and TVM to Thiruvananthapuram', () {
    expect(matchTypedCity(cities, 'Trivandrum')?.id, 'tvm');
    expect(matchTypedCity(cities, 'tvm')?.id, 'tvm');
    expect(cityMatchesQuery(cities.first, 'trivandrum'), isTrue);
  });

  test('parses a city even when lat/lng are missing', () {
    final city = CityEntry.fromJson({
      'id': 'tvm',
      'name': 'Thiruvananthapuram',
      'state': 'Kerala',
    });
    expect(city.id, 'tvm');
    expect(city.name, 'Thiruvananthapuram');
    expect(city.lat, 0);
    expect(city.lng, 0);
  });
}
