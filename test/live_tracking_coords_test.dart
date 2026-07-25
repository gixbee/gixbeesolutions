import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/services/ola_maps_style_service.dart';

/// Coordinate coercion used by live tracking for socket + status-poll payloads.
void main() {
  test('readCoord accepts num, string Decimal, and rejects garbage', () {
    expect(readCoord(12.97), 12.97);
    expect(readCoord(13), 13.0);
    expect(readCoord('77.5946'), closeTo(77.5946, 0.0001));
    expect(readCoord('12.9716'), closeTo(12.9716, 0.0001));
    expect(readCoord(null), isNull);
    expect(readCoord('not-a-coord'), isNull);
  });
}
