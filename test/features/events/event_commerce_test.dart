import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/event_quote_commerce.dart';

void main() {
  final submitted = <Map<String, dynamic>>[
    {'version': 1, 'status': 'SUBMITTED'},
  ];
  final revisions = <Map<String, dynamic>>[
    {'version': 1, 'status': 'REVISION_REQUESTED'},
  ];
  final accepted = <Map<String, dynamic>>[
    {'version': 1, 'status': 'APPROVED'},
  ];
  test('photographer can upload initial file or requested revision only', () {
    expect(EventCommerceRules.canUpload(false, 'CONFIRMED', []), isTrue);
    expect(EventCommerceRules.canUpload(false, 'CONFIRMED', revisions), isTrue);
    expect(EventCommerceRules.canUpload(false, 'CONFIRMED', submitted), isFalse);
    expect(EventCommerceRules.canUpload(false, 'CONFIRMED', accepted), isFalse);
    expect(EventCommerceRules.canUpload(true, 'CONFIRMED', []), isFalse);
    expect(EventCommerceRules.canUpload(false, 'CANCELLED', []), isFalse);
  });
  test('only customer can approve latest submitted delivery', () {
    expect(EventCommerceRules.canReviewDelivery(true, 'CONFIRMED', submitted), isTrue);
    expect(EventCommerceRules.canReviewDelivery(false, 'CONFIRMED', submitted), isFalse);
    expect(EventCommerceRules.canReviewDelivery(true, 'CONFIRMED', revisions), isFalse);
    expect(EventCommerceRules.canReviewDelivery(true, 'COMPLETED', submitted), isFalse);
  });
  test('customer can re-report after rejected claim but not during dispute', () {
    final rejected = <Map<String, dynamic>>[
      {'version': 1, 'status': 'REJECTED'},
    ];
    final pending = <Map<String, dynamic>>[
      {'version': 1, 'status': 'REPORTED'},
    ];
    expect(EventCommerceRules.canReport(true, 'CONFIRMED', [], false), isTrue);
    expect(EventCommerceRules.canReport(true, 'CONFIRMED', rejected, false), isTrue);
    expect(EventCommerceRules.canReport(true, 'CONFIRMED', pending, false), isFalse);
    expect(EventCommerceRules.canReport(true, 'CONFIRMED', rejected, true), isFalse);
    expect(EventCommerceRules.canReport(false, 'CONFIRMED', [], false), isFalse);
  });
  test('customer receipt uploads require an active claim and limit', () {
    final pending = <String, dynamic>{'status': 'REPORTED'};
    final contested = <String, dynamic>{'status': 'CONTESTED'};
    expect(EventCommerceRules.canAttachReceipt(true, 'CONFIRMED', pending, 0), isTrue);
    expect(EventCommerceRules.canAttachReceipt(true, 'CONFIRMED', contested, 4), isTrue);
    expect(EventCommerceRules.canAttachReceipt(true, 'CONFIRMED', pending, 5), isFalse);
    expect(EventCommerceRules.canAttachReceipt(true, 'CANCELLED', pending, 0), isFalse);
    expect(EventCommerceRules.canAttachReceipt(false, 'CONFIRMED', pending, 0), isFalse);
    expect(EventCommerceRules.canAttachReceipt(true, 'CONFIRMED', null, 0), isFalse);
  });

  test('only vendor can reconcile a reported claim', () {
    final pending = <Map<String, dynamic>>[{'status': 'REPORTED'}];
    expect(EventCommerceRules.canReconcile(false, 'CONFIRMED', pending), isTrue);
    expect(EventCommerceRules.canReconcile(true, 'CONFIRMED', pending), isFalse);
    expect(EventCommerceRules.canReconcile(false, 'COMPLETED', pending), isFalse);
    expect(EventCommerceRules.canReconcile(false, 'CONFIRMED', []), isFalse);
  });
}
