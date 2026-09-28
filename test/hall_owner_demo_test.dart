import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/hall/hall_owner_demo_screen.dart';

void main() {
  testWidgets('Hall owner demo opens dashboard', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HallOwnerDemoScreen()),
    );
    expect(find.text('List My Business'), findsWidgets);
    expect(find.text('Vijaya Convention Center'), findsOneWidget);
    expect(find.text('Manage'), findsWidgets);
  });
}
