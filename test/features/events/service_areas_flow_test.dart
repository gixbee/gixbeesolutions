import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/service_areas_flow_screen.dart';
import 'package:gixbee/repositories/cities_repository.dart';

void main() {
  const kochi = CityEntry(
      id: 'kochi', name: 'Kochi', state: 'Kerala', lat: 0, lng: 0);
  const thrissur = CityEntry(
      id: 'thrissur', name: 'Thrissur', state: 'Kerala', lat: 0, lng: 0);
  const chennai = CityEntry(
      id: 'chennai', name: 'Chennai', state: 'Tamil Nadu', lat: 0, lng: 0);
  const blank = CityEntry(
      id: 'blank', name: 'Somewhere', state: '  ', lat: 0, lng: 0);

  test('service areas group cities under their state', () {
    final grouped = serviceAreasByState([chennai, thrissur, kochi, blank]);
    expect(grouped.keys.toList(), ['Kerala', 'Other', 'Tamil Nadu']);
    expect(grouped['Kerala']!.map((city) => city.name),
        ['Kochi', 'Thrissur']);
    expect(statesForSelectedCities(
        [kochi, thrissur, chennai], {'thrissur', 'chennai'}),
        {'Kerala', 'Tamil Nadu'});
  });
}
