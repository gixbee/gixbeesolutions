import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/shared/widgets/gx_empty.dart';
import 'package:gixbee/shared/widgets/location_required_host.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: child,
    );

void main() {
  test('copy for device location off', () {
    expect(locationRequiredTitle('service_off'), 'Turn on location');
    expect(locationRequiredAction('service_off'), 'Turn on location');
    expect(locationRequiredMessage('service_off'), contains('Turn location on'));
  });

  test('copy for permission denied forever', () {
    expect(locationRequiredTitle('denied_forever'), 'Allow location access');
    expect(locationRequiredAction('denied_forever'), 'Open settings');
  });

  testWidgets('blocking panel cannot be dismissed and shows the CTA',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(LocationRequiredPanel(
      reason: 'service_off',
      onEnable: () => taps++,
    )));
    expect(find.text('Turn on location'), findsWidgets);
    expect(find.byType(GxEmptyState), findsOneWidget);
    await tester.tap(find.text('Turn on location').last);
    await tester.pump();
    expect(taps, 1);
  });
}
