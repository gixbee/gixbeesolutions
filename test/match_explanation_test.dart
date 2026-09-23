import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/jobs/match_explanation.dart';

void main() {
  testWidgets('match card shows score and real reasons, not a fake verified badge',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MatchExplanationBlock(
          score: 92,
          reasons: [
            '5 of 6 required skills match',
            '3.2 km away',
            'Salary matches your expectation',
          ],
          warnings: ['Employer prefers 2 years experience; you have 1.5 years'],
        ),
      ),
    ));
    expect(find.text('92% Match'), findsOneWidget);
    expect(find.text('5 of 6 required skills match'), findsOneWidget);
    expect(find.text('3.2 km away'), findsOneWidget);
    expect(find.text('Business Verified'), findsNothing);
    expect(find.textContaining('1.5'), findsOneWidget);
  });
}
