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

  test('a fully selected state is stored as the state itself', () {
    const kerala = ServiceGeo(id: 'KL', name: 'Kerala', stateName: 'Kerala');
    const tamil = ServiceGeo(
        id: 'TN', name: 'Tamil Nadu', stateName: 'Tamil Nadu');
    const kochi = ServiceGeo(
        id: 'ekm', name: 'Ernakulam', stateName: 'Kerala');
    const thrissur = ServiceGeo(
        id: 'tsr', name: 'Thrissur', stateName: 'Kerala');
    const chennai = ServiceGeo(
        id: 'che', name: 'Chennai', stateName: 'Tamil Nadu');

    expect(
      compactServiceAreaIds(
        states: const [tamil, kerala],
        districts: const [chennai, kochi, thrissur],
        stateNames: {'Kerala', 'Tamil Nadu'},
        districtIds: {'ekm', 'tsr', 'che'},
      ),
      ['KL', 'TN'],
    );
    expect(
      compactServiceAreaIds(
        states: const [kerala],
        districts: const [kochi, thrissur],
        stateNames: {'Kerala'},
        districtIds: {'ekm'},
      ),
      ['ekm'],
    );
  });
}
