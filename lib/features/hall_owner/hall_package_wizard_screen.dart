import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/hall_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_text_field.dart';
import 'hall_policy.dart';

const _eventOptions = [
  'wedding',
  'reception',
  'engagement',
  'birthday',
  'baptism',
  'anniversary',
  'religious',
];

const _facilitiesIndoor = [
  'AC',
  'Generator / Power Backup',
  'Chairs & Tables',
  'Stage',
  'Sound System',
  'Restrooms',
];

const _facilitiesOutdoor = [
  'Generator / Power Backup',
  'Chairs & Tables',
  'Stage',
  'Sound System',
  'Restrooms',
  'Parking',
];

class HallPackageWizardScreen extends ConsumerStatefulWidget {
  const HallPackageWizardScreen({
    super.key,
    required this.business,
    required this.hallId,
  });
  final Business business;
  final String hallId;

  @override
  ConsumerState<HallPackageWizardScreen> createState() =>
      _HallPackageWizardScreenState();
}

class _HallPackageWizardScreenState
    extends ConsumerState<HallPackageWizardScreen> {
  int _step = 1;
  bool _saving = false;

  final _nameCtrl = TextEditingController();
  String _spaceType = 'indoor';
  final Set<String> _events = {..._eventOptions};
  final Set<String> _facilities = {..._facilitiesIndoor};
  String _caterIn = 'yes';
  String _caterOut = 'yes';
  String _decorHall = 'no';
  String _decorOut = 'yes';
  final _seatCtrl = TextEditingController(text: '500');
  final _dineCtrl = TextEditingController(text: '400');

  bool _morning = true;
  bool _evening = true;
  bool _fullday = true;
  final _mNoAc = TextEditingController(text: '55000');
  final _mAc = TextEditingController(text: '75000');
  final _eNoAc = TextEditingController(text: '55000');
  final _eAc = TextEditingController(text: '75000');
  final _fNoAc = TextEditingController(text: '75000');
  final _fAc = TextEditingController(text: '90000');

  String _advanceType = 'fixed';
  final _advanceFixed = TextEditingController(text: '20000');
  final _advancePct = TextEditingController(text: '30');
  final _fullDue = TextEditingController(text: '7');
  String _deductionBasis = 'ADVANCE';
  List<HallPolicyTier> _cancel = defaultPolicyTiers();
  List<HallPolicyTier> _reschedule = defaultPolicyTiers();

  final _bookMonths = TextEditingController(text: '6');
  final _minNotice = TextEditingController(text: '3');

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    try {
      final hall = await ref
          .read(hallRepositoryProvider)
          .getHall(widget.business.id, widget.hallId);
      _nameCtrl.text = (hall['name'] as String?) ?? '';
      _spaceType = (hall['spaceType'] as String?) ?? 'indoor';
      final pkg = hall['package'];
      if (pkg is Map) {
        final m = Map<String, dynamic>.from(pkg);
        final ev = m['events'];
        if (ev is List) {
          _events
            ..clear()
            ..addAll(ev.map((e) => e.toString()));
        }
        final fac = m['facilities'];
        if (fac is List) {
          _facilities
            ..clear()
            ..addAll(fac.map((e) => e.toString()));
        }
        _deductionBasis = (m['deductionBasis'] as String?) ?? 'ADVANCE';
        final cr = m['cancelRules'];
        if (cr is List && cr.isNotEmpty) {
          _cancel = cr
              .map((e) => HallPolicyTier.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        }
        final rr = m['rescheduleRules'];
        if (rr is List && rr.isNotEmpty) {
          _reschedule = rr
              .map((e) => HallPolicyTier.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _seatCtrl.dispose();
    _dineCtrl.dispose();
    _mNoAc.dispose();
    _mAc.dispose();
    _eNoAc.dispose();
    _eAc.dispose();
    _fNoAc.dispose();
    _fAc.dispose();
    _advanceFixed.dispose();
    _advancePct.dispose();
    _fullDue.dispose();
    _bookMonths.dispose();
    _minNotice.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildPackage() {
    final outdoor = _spaceType == 'outdoor';
    final offers = <Map<String, dynamic>>[];
    if (_morning) {
      offers.add({
        'id': 'morning',
        'label': 'Morning',
        'hallFrom': '09:00',
        'hallTo': '14:00',
        'enabled': true,
        'offerNoAc': true,
        'offerAc': !outdoor,
        'priceNoAc': int.tryParse(_mNoAc.text) ?? 0,
        'priceAc': int.tryParse(_mAc.text) ?? 0,
      });
    }
    if (_evening) {
      offers.add({
        'id': 'evening',
        'label': 'Evening',
        'hallFrom': '16:00',
        'hallTo': '22:00',
        'enabled': true,
        'offerNoAc': true,
        'offerAc': !outdoor,
        'priceNoAc': int.tryParse(_eNoAc.text) ?? 0,
        'priceAc': int.tryParse(_eAc.text) ?? 0,
      });
    }
    if (_fullday) {
      offers.add({
        'id': 'fullday',
        'label': 'Full Day',
        'hallFrom': '09:00',
        'hallTo': '21:00',
        'enabled': true,
        'offerNoAc': true,
        'offerAc': !outdoor,
        'priceNoAc': int.tryParse(_fNoAc.text) ?? 0,
        'priceAc': int.tryParse(_fAc.text) ?? 0,
      });
    }
    return {
      'events': _events.toList(),
      'facilities': _facilities.toList(),
      'catering': {
        'inHouse': _caterIn,
        'outside': _caterOut,
        'decorHall': _decorHall,
        'decorOutside': _decorOut,
      },
      'capacity': {
        'seat': int.tryParse(_seatCtrl.text) ?? 0,
        'dine': int.tryParse(_dineCtrl.text) ?? 0,
      },
      'slotOffers': offers,
      'payment': {
        'advanceType': _advanceType,
        'advanceFixed': int.tryParse(_advanceFixed.text) ?? 0,
        'advancePct': int.tryParse(_advancePct.text) ?? 0,
        'fullDueDays': int.tryParse(_fullDue.text) ?? 7,
      },
      'deductionBasis': _deductionBasis,
      'cancelRules': _cancel.map((e) => e.toJson()).toList(),
      'rescheduleRules': _reschedule.map((e) => e.toJson()).toList(),
      'cancelPolicyNote': '',
      'reschedulePolicyNote': '',
      'bookWindowMonths': int.tryParse(_bookMonths.text) ?? 6,
      'minNoticeDays': int.tryParse(_minNotice.text) ?? 3,
    };
  }

  Future<void> _next() async {
    if (_step == 1 && _events.isEmpty) {
      showGxSnack(context, 'Select at least one event type',
          type: GxSnackType.error);
      return;
    }
    if (_step == 2) {
      if (_nameCtrl.text.trim().isEmpty) {
        showGxSnack(context, 'Enter a space name', type: GxSnackType.error);
        return;
      }
      try {
        await ref.read(hallRepositoryProvider).patchHall(
          widget.business.id,
          widget.hallId,
          {'name': _nameCtrl.text.trim(), 'spaceType': _spaceType},
        );
      } catch (e) {
        if (!mounted) return;
        showGxSnack(context, '$e', type: GxSnackType.error);
        return;
      }
      if (!mounted) return;
    }
    if (_step == 3 && !_morning && !_evening && !_fullday) {
      showGxSnack(context, 'Enable at least one slot', type: GxSnackType.error);
      return;
    }
    if (_step == 4) {
      final cErr = validatePolicyTiers(_cancel, 'cancelRules');
      final rErr = validatePolicyTiers(_reschedule, 'rescheduleRules');
      if (cErr != null || rErr != null) {
        showGxSnack(context, cErr ?? rErr!, type: GxSnackType.error);
        return;
      }
    }
    if (_step < 5) {
      setState(() => _step++);
      return;
    }
    await _save();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(hallRepositoryProvider).savePackage(
            widget.business.id,
            widget.hallId,
            _buildPackage(),
          );
      if (!mounted) return;
      showGxSnack(context, 'Package saved');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, '$e', type: GxSnackType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Price & packages · Step $_step/5'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step > 1) {
              setState(() => _step--);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_step == 1) _step1(),
          if (_step == 2) _step2(),
          if (_step == 3) _step3(),
          if (_step == 4) _step4(),
          if (_step == 5) _step5(),
          const SizedBox(height: 20),
          GxButton(
            label: _step == 5
                ? (_saving ? 'Saving…' : 'Save Package')
                : 'Continue',
            onTap: _saving ? null : _next,
          ),
        ],
      ),
    );
  }

  Widget _chips(Iterable<String> options, Set<String> selected) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          FilterChip(
            label: Text(o),
            selected: selected.contains(o),
            onSelected: (v) => setState(() {
              if (v) {
                selected.add(o);
              } else {
                selected.remove(o);
              }
            }),
          ),
      ],
    );
  }

  Widget _step1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Which events do you host?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _chips(_eventOptions, _events),
      ],
    );
  }

  Widget _step2() {
    final fac =
        _spaceType == 'outdoor' ? _facilitiesOutdoor : _facilitiesIndoor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GxTextField(controller: _nameCtrl, label: 'Space name'),
        const SizedBox(height: 12),
        const Text('Venue type', style: TextStyle(fontWeight: FontWeight.w700)),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Indoor'),
              selected: _spaceType == 'indoor',
              onSelected: (_) => setState(() {
                _spaceType = 'indoor';
                _facilities
                  ..clear()
                  ..addAll(_facilitiesIndoor);
              }),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Outdoor'),
              selected: _spaceType == 'outdoor',
              onSelected: (_) => setState(() {
                _spaceType = 'outdoor';
                _facilities
                  ..clear()
                  ..addAll(_facilitiesOutdoor);
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Facilities', style: TextStyle(fontWeight: FontWeight.w700)),
        _chips(fac, _facilities),
        const SizedBox(height: 12),
        GxTextField(controller: _seatCtrl, label: 'Seating capacity', keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        GxTextField(controller: _dineCtrl, label: 'Dining capacity', keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        _yesNo('In-house catering', _caterIn, (v) => setState(() => _caterIn = v)),
        _yesNo('Outside catering allowed', _caterOut, (v) => setState(() => _caterOut = v)),
        _yesNo('Decor by hall', _decorHall, (v) => setState(() => _decorHall = v)),
        _yesNo('Outside decor allowed', _decorOut, (v) => setState(() => _decorOut = v)),
      ],
    );
  }

  Widget _yesNo(String label, String value, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          ChoiceChip(
            label: const Text('Yes'),
            selected: value == 'yes',
            onSelected: (_) => onChanged('yes'),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('No'),
            selected: value == 'no',
            onSelected: (_) => onChanged('no'),
          ),
        ],
      ),
    );
  }

  Widget _step3() {
    final outdoor = _spaceType == 'outdoor';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Morning'),
          value: _morning,
          onChanged: (v) => setState(() => _morning = v),
        ),
        if (_morning) ...[
          GxTextField(controller: _mNoAc, label: outdoor ? 'Slot rent ₹' : 'Without AC ₹', keyboardType: TextInputType.number),
          if (!outdoor) ...[
            const SizedBox(height: 8),
            GxTextField(controller: _mAc, label: 'With AC ₹', keyboardType: TextInputType.number),
          ],
        ],
        SwitchListTile(
          title: const Text('Evening'),
          value: _evening,
          onChanged: (v) => setState(() => _evening = v),
        ),
        if (_evening) ...[
          GxTextField(controller: _eNoAc, label: outdoor ? 'Slot rent ₹' : 'Without AC ₹', keyboardType: TextInputType.number),
          if (!outdoor) ...[
            const SizedBox(height: 8),
            GxTextField(controller: _eAc, label: 'With AC ₹', keyboardType: TextInputType.number),
          ],
        ],
        SwitchListTile(
          title: const Text('Full day'),
          value: _fullday,
          onChanged: (v) => setState(() => _fullday = v),
        ),
        if (_fullday) ...[
          GxTextField(controller: _fNoAc, label: outdoor ? 'Slot rent ₹' : 'Without AC ₹', keyboardType: TextInputType.number),
          if (!outdoor) ...[
            const SizedBox(height: 8),
            GxTextField(controller: _fAc, label: 'With AC ₹', keyboardType: TextInputType.number),
          ],
        ],
      ],
    );
  }

  Widget _step4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Advance (terms only — not collected by Gixbee yet)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Fixed ₹'),
              selected: _advanceType == 'fixed',
              onSelected: (_) => setState(() => _advanceType = 'fixed'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Percent'),
              selected: _advanceType == 'percent',
              onSelected: (_) => setState(() => _advanceType = 'percent'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_advanceType == 'fixed')
          GxTextField(controller: _advanceFixed, label: 'Advance ₹', keyboardType: TextInputType.number)
        else
          GxTextField(controller: _advancePct, label: 'Advance %', keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        GxTextField(controller: _fullDue, label: 'Full payment due (days before)', keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        const Text('Deduction basis', style: TextStyle(fontWeight: FontWeight.w700)),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Of advance'),
              selected: _deductionBasis == 'ADVANCE',
              onSelected: (_) => setState(() => _deductionBasis = 'ADVANCE'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Of total'),
              selected: _deductionBasis == 'TOTAL_QUOTE',
              onSelected: (_) => setState(() => _deductionBasis = 'TOTAL_QUOTE'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Cancel tiers: ${_cancel.length} (validated on save)'),
        Text('Reschedule tiers: ${_reschedule.length}'),
        const SizedBox(height: 8),
        GxTextField(controller: _bookMonths, label: 'Book window (months)', keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        GxTextField(controller: _minNotice, label: 'Min notice (days)', keyboardType: TextInputType.number),
      ],
    );
  }

  Widget _step5() {
    final pkg = _buildPackage();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Space: ${_nameCtrl.text.trim()} ($_spaceType)'),
        Text('Events: ${(pkg['events'] as List).join(', ')}'),
        Text('Slots: ${(pkg['slotOffers'] as List).length} enabled'),
        Text('Deduction basis: $_deductionBasis'),
        const SizedBox(height: 12),
        const Text(
          'Times for customers will be shown in IST (Kolkata). Tap Save Package to unlock calendar and operators.',
        ),
      ],
    );
  }
}
