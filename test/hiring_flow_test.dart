import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/jobs/hiring_flow.dart';

void main() {
  test('shortlist does not unlock phone until the candidate shares', () {
    expect(
      hiringContactUnlocked(decision: 'SHORTLISTED', progress: {}),
      isFalse,
    );
    expect(
      hiringContactUnlocked(
        decision: 'SHORTLISTED',
        progress: {'contactShared': true},
      ),
      isTrue,
    );
    expect(hiringContactUnlocked(decision: 'HIRED', progress: {}), isTrue);
  });

  test('mutual interest opens chat, not contact', () {
    expect(
      hiringCanChat(response: 'INTERESTED', decision: 'PENDING'),
      isTrue,
    );
    expect(
      hiringPipelineLabel(response: 'INTERESTED', decision: 'PENDING'),
      'CHATTING',
    );
    expect(
      hiringPipelineLabel(
        response: 'PENDING',
        decision: 'PENDING',
        progress: {'invited': true},
      ),
      'INVITED',
    );
    expect(
      hiringPipelineLabel(
        response: 'PENDING',
        decision: 'PENDING',
        progress: {'viewedByEmployer': true},
      ),
      'VIEWED',
    );
    expect(hiringInterviewTypeLabels['VIDEO'], 'Video');
  });
}
