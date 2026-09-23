import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/profile/addresses/address_line.dart';

void main() {
  test('joins house, landmark, area, city and pincode', () {
    expect(
      composeAddressLine(
        house: '12A',
        landmark: 'Near SBI',
        area: 'Powdikonam',
        city: 'Thiruvananthapuram, Kerala',
        pincode: '695110',
      ),
      '12A, Near SBI, Powdikonam, Thiruvananthapuram, Kerala, 695110',
    );
  });

  test('skips empty city and other optional parts', () {
    expect(
      composeAddressLine(house: '12A', area: '  Powdikonam  '),
      '12A, Powdikonam',
    );
  });

  test('appends city only when it is missing from the address', () {
    expect(
      ensureCityInAddress('Powdikonam', 'Thiruvananthapuram, Kerala'),
      'Powdikonam, Thiruvananthapuram, Kerala',
    );
    expect(
      ensureCityInAddress(
        'Powdikonam, Thiruvananthapuram, Keralam 695588',
        'Thiruvananthapuram',
      ),
      'Powdikonam, Thiruvananthapuram, Keralam 695588',
    );
  });
}
