import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/hall_owner/hall_slot_options.dart';

void main() {
  test('partial AC cannot exceed window; equal hours persist as full', () {
    final options = HallSlotOptions()..usage = 'partial';
    addTearDown(options.dispose);
    options.hours.text = '6';
    expect(options.validate('10:00', '15:00', true), isNotNull);
    options.hours.text = '5';
    expect(options.validate('10:00', '15:00', true), isNull);
    expect(options.json('10:00', '15:00')['acUsage'], 'full');
  });

  test('fixed schedule must fit window and match fractional hours', () {
    final options = HallSlotOptions()
      ..usage = 'partial'
      ..timing = 'fixed';
    addTearDown(options.dispose);
    options.hours.text = '1.5';
    options.from.text = '11:00';
    options.to.text = '12:30';
    expect(options.validate('10:00', '15:00', true), isNull);
    options.to.text = '13:00';
    expect(options.validate('10:00', '15:00', true), isNotNull);
    options.from.text = '09:00';
    options.to.text = '10:30';
    expect(options.validate('10:00', '15:00', true), isNotNull);
  });

  test('reload retains independent pricing switches and AC configuration', () {
    final options = HallSlotOptions();
    addTearDown(options.dispose);
    options.load({
      'offerNoAc': false,
      'offerAc': true,
      'discountNoAcEnabled': false,
      'discountAcEnabled': true,
      'acUsage': 'partial',
      'acHours': 2,
      'acTiming': 'fixed',
      'acFrom': '11:00',
      'acTo': '13:00'
    });
    expect(options.offerNoAc, isFalse);
    expect(options.discountAc, isTrue);
    expect(options.discountNoAc, isFalse);
    expect(options.json('10:00', '15:00')['acFrom'], '11:00');
    options.offerAc = false;
    expect(options.validate('10:00', '15:00', true), isNotNull);
    options.offerNoAc = true;
    expect(options.validate('10:00', '15:00', false), isNull);
  });
}
