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
  bool _advancing = false;
  bool _ready = false;
  String? _loadError;
  int _hydrateGen = 0;
  List<_TierEditors> _cancelFields = [];
  List<_TierEditors> _rescheduleFields = [];

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
  final _mFrom = TextEditingController(text: '09:00');
  final _mTo = TextEditingController(text: '14:00');
  final _eFrom = TextEditingController(text: '16:00');
  final _eTo = TextEditingController(text: '22:00');
  final _fFrom = TextEditingController(text: '09:00');
  final _fTo = TextEditingController(text: '21:00');
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

  bool get _offersAc =>
      _spaceType != 'outdoor' && _facilities.contains('AC');

  @override
  void initState() {
    super.initState();
    _cancelFields = [for (final tier in _cancel) _TierEditors(tier)];
    _rescheduleFields = [for (final tier in _reschedule) _TierEditors(tier)];
    _hydrate();
  }

  Future<void> _hydrate() async {
    final gen = ++_hydrateGen;
    if (mounted && _loadError != null) {
      setState(() {
        _ready = false;
        _loadError = null;
      });
    }
    try {
      final hall = await ref
          .read(hallRepositoryProvider)
          .getHall(widget.business.id, widget.hallId);
      if (!mounted || gen != _hydrateGen) return;
      _nameCtrl.text = (hall['name'] as String?) ?? '';
      _spaceType = (hall['spaceType'] as String?) ?? 'indoor';
      final pkg = hall['package'];
      if (pkg is Map) _applyPackage(Map<String, dynamic>.from(pkg));
      setState(() {
        _ready = true;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted || gen != _hydrateGen) return;
      setState(() {
        _ready = false;
        _loadError = '$e';
      });
    }
  }

  void _applyPackage(Map<String, dynamic> m) {
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
    final catering = m['catering'];
    if (catering is Map) {
      _caterIn = _yesNoOr(catering['inHouse'], _caterIn);
      _caterOut = _yesNoOr(catering['outside'], _caterOut);
      _decorHall = _yesNoOr(catering['decorHall'], _decorHall);
      _decorOut = _yesNoOr(catering['decorOutside'], _decorOut);
    }
    final capacity = m['capacity'];
    if (capacity is Map) {
      _setNum(_seatCtrl, capacity['seat']);
      _setNum(_dineCtrl, capacity['dine']);
    }
    final slots = m['slotOffers'];
    if (slots is List) {
      _morning = false;
      _evening = false;
      _fullday = false;
      for (final raw in slots) {
        if (raw is! Map) continue;
        final slot = Map<String, dynamic>.from(raw);
        final enabled = slot['enabled'] != false;
        switch (slot['id']?.toString()) {
          case 'morning':
            _morning = enabled;
            _fillSlot(slot, _mFrom, _mTo, _mNoAc, _mAc);
          case 'evening':
            _evening = enabled;
            _fillSlot(slot, _eFrom, _eTo, _eNoAc, _eAc);
          case 'fullday':
            _fullday = enabled;
            _fillSlot(slot, _fFrom, _fTo, _fNoAc, _fAc);
        }
      }
    }
    final payment = m['payment'];
    if (payment is Map) {
      final type = payment['advanceType']?.toString();
      if (type == 'fixed' || type == 'percent') _advanceType = type!;
      _setOptionalNum(_advanceFixed, payment['advanceFixed']);
      _setOptionalNum(_advancePct, payment['advancePct']);
      _setNum(_fullDue, payment['fullDueDays']);
    }
    final basis = m['deductionBasis']?.toString();
    if (basis == 'ADVANCE' || basis == 'TOTAL_QUOTE') _deductionBasis = basis!;
    _setNum(_bookMonths, m['bookWindowMonths']);
    _setNum(_minNotice, m['minNoticeDays']);
    final cr = m['cancelRules'];
    if (cr is List && cr.isNotEmpty) {
      _cancel = [
        for (final e in cr)
          if (e is Map) HallPolicyTier.fromJson(Map<String, dynamic>.from(e)),
      ];
      _swapFields(_cancelFields, _cancel);
    }
    final rr = m['rescheduleRules'];
    if (rr is List && rr.isNotEmpty) {
      _reschedule = [
        for (final e in rr)
          if (e is Map) HallPolicyTier.fromJson(Map<String, dynamic>.from(e)),
      ];
      _swapFields(_rescheduleFields, _reschedule);
    }
  }

  void _swapFields(List<_TierEditors> current, List<HallPolicyTier> tiers) {
    for (final field in current) {
      field.dispose();
    }
    current
      ..clear()
      ..addAll([for (final tier in tiers) _TierEditors(tier)]);
  }

  void _setOptionalNum(TextEditingController controller, dynamic value) {
    if (value == null) {
      controller.text = '';
      return;
    }
    _setNum(controller, value);
  }

  void _setNum(TextEditingController controller, dynamic value) {
    if (value == null) return;
    if (value is num && value == value.roundToDouble()) {
      controller.text = '${value.toInt()}';
      return;
    }
    controller.text = '$value';
  }

  void _fillSlot(
    Map<String, dynamic> slot,
    TextEditingController from,
    TextEditingController to,
    TextEditingController price,
    TextEditingController acPrice,
  ) {
    if (slot['hallFrom'] != null) from.text = slot['hallFrom'].toString();
    if (slot['hallTo'] != null) to.text = slot['hallTo'].toString();
    _setNum(price, slot['priceNoAc']);
    _setNum(acPrice, slot['priceAc']);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _seatCtrl.dispose();
    _dineCtrl.dispose();
    _mFrom.dispose();
    _mTo.dispose();
    _eFrom.dispose();
    _eTo.dispose();
    _fFrom.dispose();
    _fTo.dispose();
    _mNoAc.dispose();
    _mAc.dispose();
    _eNoAc.dispose();
    _eAc.dispose();
    _fNoAc.dispose();
    _fAc.dispose();
    for (final field in _cancelFields) {
      field.dispose();
    }
    for (final field in _rescheduleFields) {
      field.dispose();
    }
    _advanceFixed.dispose();
    _advancePct.dispose();
    _fullDue.dispose();
    _bookMonths.dispose();
    _minNotice.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildPackage() {
    final offerAc = _offersAc;
    final offers = <Map<String, dynamic>>[];
    void addSlot(
      String id,
      String label,
      bool enabled,
      TextEditingController from,
      TextEditingController to,
      TextEditingController price,
      TextEditingController acPrice,
    ) {
      if (!enabled) return;
      offers.add({
        'id': id,
        'label': label,
        'hallFrom': from.text.trim(),
        'hallTo': to.text.trim(),
        'enabled': true,
        'offerNoAc': true,
        'offerAc': offerAc,
        'priceNoAc': int.parse(price.text.trim()),
        'priceAc': offerAc ? int.parse(acPrice.text.trim()) : 0,
      });
    }

    addSlot('morning', 'Morning', _morning, _mFrom, _mTo, _mNoAc, _mAc);
    addSlot('evening', 'Evening', _evening, _eFrom, _eTo, _eNoAc, _eAc);
    addSlot('fullday', 'Full Day', _fullday, _fFrom, _fTo, _fNoAc, _fAc);
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
        'seat': int.parse(_seatCtrl.text.trim()),
        'dine': int.parse(_dineCtrl.text.trim()),
      },
      'slotOffers': offers,
      'payment': {
        'advanceType': _advanceType,
        'advanceFixed': _advanceType == 'fixed'
            ? int.parse(_advanceFixed.text.trim())
            : _storedWhole(_advanceFixed.text, min: 0, max: 100000000),
        'advancePct': _advanceType == 'percent'
            ? int.parse(_advancePct.text.trim())
            : _storedWhole(_advancePct.text, min: 0, max: 100),
        'fullDueDays': int.parse(_fullDue.text.trim()),
      },
      'deductionBasis': _deductionBasis,
      'cancelRules': _cancel.map((e) => e.toJson()).toList(),
      'rescheduleRules': _reschedule.map((e) => e.toJson()).toList(),
      'cancelPolicyNote': '',
      'reschedulePolicyNote': '',
      'bookWindowMonths': int.parse(_bookMonths.text.trim()),
      'minNoticeDays': int.parse(_minNotice.text.trim()),
    };
  }

  String? _validateStep(int step) {
    if (step == 1 && _events.isEmpty) {
      return 'Select at least one event type';
    }
    if (step == 2) {
      if (_nameCtrl.text.trim().isEmpty) return 'Enter a space name';
      final seat = _whole(_seatCtrl.text, 'Seating capacity', min: 0, max: 100000);
      if (seat != null) return seat;
      final dine = _whole(_dineCtrl.text, 'Dining capacity', min: 0, max: 100000);
      if (dine != null) return dine;
    }
    if (step == 3) {
      if (!_morning && !_evening && !_fullday) {
        return 'Enable at least one slot';
      }
      String? slot(
        String label,
        bool enabled,
        TextEditingController from,
        TextEditingController to,
        TextEditingController price,
        TextEditingController acPrice,
      ) {
        if (!enabled) return null;
        final start = _clock(from.text, '$label start');
        if (start != null) return start;
        final end = _clock(to.text, '$label end');
        if (end != null) return end;
        if (_minutes(from.text) >= _minutes(to.text)) {
          return '$label end time must be after its start time';
        }
        final rent = _whole(price.text, '$label price', min: 0, max: 100000000);
        if (rent != null) return rent;
        if (_offersAc) {
          return _whole(acPrice.text, '$label AC price', min: 0, max: 100000000);
        }
        return null;
      }

      return slot('Morning', _morning, _mFrom, _mTo, _mNoAc, _mAc) ??
          slot('Evening', _evening, _eFrom, _eTo, _eNoAc, _eAc) ??
          slot('Full day', _fullday, _fFrom, _fTo, _fNoAc, _fAc);
    }
    if (step == 4) {
      final advance = _advanceType == 'percent'
          ? _whole(_advancePct.text, 'Advance percent', min: 0, max: 100)
          : _whole(
              _advanceFixed.text,
              'Advance amount',
              min: 0,
              max: 100000000,
            );
      if (advance != null) return advance;
      final due = _whole(_fullDue.text, 'Full payment due', min: 0, max: 3650);
      if (due != null) return due;
      final window = _whole(_bookMonths.text, 'Book window', min: 1, max: 36);
      if (window != null) return window;
      final notice = _whole(_minNotice.text, 'Minimum notice', min: 0, max: 365);
      if (notice != null) return notice;
      final policies = _readPolicies();
      if (policies != null) return policies;
      return validatePolicyTiers(_cancel, 'cancelRules') ??
          validatePolicyTiers(_reschedule, 'rescheduleRules');
    }
    return null;
  }

  String? _readPolicies() {
    String? invalid(List<_TierEditors> fields, String name) {
      for (final field in fields) {
        if (int.tryParse(field.min.text.trim()) == null) {
          return '$name min days must be a whole number';
        }
        final maxText = field.max.text.trim();
        if (maxText.isNotEmpty && int.tryParse(maxText) == null) {
          return '$name max days must be a whole number, or blank for no upper limit';
        }
        if (int.tryParse(field.pct.text.trim()) == null) {
          return '$name deduction percent must be a whole number';
        }
      }
      return null;
    }

    final cancel = invalid(_cancelFields, 'Cancellation');
    if (cancel != null) return cancel;
    final reschedule = invalid(_rescheduleFields, 'Reschedule');
    if (reschedule != null) return reschedule;
    _cancel = [for (final field in _cancelFields) field.read()];
    _reschedule = [for (final field in _rescheduleFields) field.read()];
    return null;
  }

  Future<void> _next() async {
    if (_advancing || _saving || !_ready) return;
    setState(() => _advancing = true);
    try {
      final problem = _validateStep(_step);
      if (problem != null) {
        if (!mounted) return;
        showGxSnack(context, problem, type: GxSnackType.error);
        return;
      }
      if (_step == 2) {
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
      if (_step < 5) {
        setState(() => _step++);
        return;
      }
      await _save();
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  Future<void> _save() async {
    for (final step in [2, 3, 4]) {
      final problem = _validateStep(step);
      if (problem != null) {
        if (!mounted) return;
        showGxSnack(context, problem, type: GxSnackType.error);
        return;
      }
    }
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
    final busy = _saving || _advancing;
    return Scaffold(
      appBar: AppBar(
        title: Text('Price & packages · Step $_step/5'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: busy
              ? null
              : () {
                  if (_step > 1) {
                    setState(() => _step--);
                  } else {
                    Navigator.pop(context);
                  }
                },
        ),
      ),
      body: _loadError != null
          ? _loadFailed()
          : !_ready
              ? const Center(child: CircularProgressIndicator())
              : ListView(
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
                : (_advancing ? 'Please wait…' : 'Continue'),
            onTap: busy ? null : _next,
          ),
        ],
      ),
    );
  }

  Widget _loadFailed() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'The saved package could not be loaded. Saving now would replace it with defaults.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(_loadError!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          GxButton(label: 'Try again', onTap: _hydrate),
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
                if (_spaceType == 'indoor') return;
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
                if (_spaceType == 'outdoor') return;
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
    final priceLabel = outdoor || !_offersAc ? 'Slot rent ₹' : 'Without AC ₹';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _slotEditor('Morning', _morning, (v) => _morning = v, _mFrom, _mTo, _mNoAc, _mAc, priceLabel),
        _slotEditor('Evening', _evening, (v) => _evening = v, _eFrom, _eTo, _eNoAc, _eAc, priceLabel),
        _slotEditor('Full day', _fullday, (v) => _fullday = v, _fFrom, _fTo, _fNoAc, _fAc, priceLabel),
      ],
    );
  }

  Widget _slotEditor(
    String title,
    bool enabled,
    ValueChanged<bool> onEnabled,
    TextEditingController from,
    TextEditingController to,
    TextEditingController price,
    TextEditingController acPrice,
    String priceLabel,
  ) {
    return Column(
      children: [
        SwitchListTile(
          title: Text(title),
          value: enabled,
          onChanged: (v) => setState(() => onEnabled(v)),
        ),
        if (enabled) ...[
          Row(
            children: [
              Expanded(child: GxTextField(controller: from, label: 'From (HH:MM)')),
              const SizedBox(width: 8),
              Expanded(child: GxTextField(controller: to, label: 'To (HH:MM)')),
            ],
          ),
          const SizedBox(height: 8),
          GxTextField(controller: price, label: priceLabel, keyboardType: TextInputType.number),
          if (_offersAc) ...[
            const SizedBox(height: 8),
            GxTextField(controller: acPrice, label: 'With AC ₹', keyboardType: TextInputType.number),
          ],
          const SizedBox(height: 8),
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
        _policyEditor('Cancellation policy', _cancelFields),
        const SizedBox(height: 12),
        _policyEditor('Reschedule policy', _rescheduleFields),
        const SizedBox(height: 8),
        GxTextField(controller: _bookMonths, label: 'Book window (months)', keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        GxTextField(controller: _minNotice, label: 'Min notice (days)', keyboardType: TextInputType.number),
      ],
    );
  }

  Widget _policyEditor(String title, List<_TierEditors> fields) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Leave max days blank on the last tier only. Days must meet with no gaps.'),
        for (var i = 0; i < fields.length; i++) ...[
          const SizedBox(height: 8),
          Text('Tier ${i + 1}'),
          GxTextField(controller: fields[i].min, label: 'Min days before event', keyboardType: TextInputType.number),
          const SizedBox(height: 6),
          GxTextField(controller: fields[i].max, label: 'Max days (blank = no limit)', keyboardType: TextInputType.number),
          const SizedBox(height: 6),
          GxTextField(controller: fields[i].pct, label: 'Deduction %', keyboardType: TextInputType.number),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() {
                final start = fields.isEmpty
                    ? 0
                    : (int.tryParse(fields.last.max.text.trim()) ?? -1) + 1;
                fields.add(_TierEditors(HallPolicyTier(
                  minDaysBeforeEvent: start < 0 ? 0 : start,
                  maxDaysBeforeEvent: null,
                  deductionPercent: 0,
                )));
              }),
              child: const Text('Add tier'),
            ),
            if (fields.length > 1)
              TextButton(
                onPressed: () => setState(() => fields.removeLast().dispose()),
                child: const Text('Remove last'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _step5() {
    final slots = <String>[
      if (_morning) _slotSummary('Morning', _mFrom, _mTo, _mNoAc, _mAc),
      if (_evening) _slotSummary('Evening', _eFrom, _eTo, _eNoAc, _eAc),
      if (_fullday) _slotSummary('Full day', _fFrom, _fTo, _fNoAc, _fAc),
    ];
    final advance = _advanceType == 'percent'
        ? '${_advancePct.text.trim()}% of the quote'
        : '₹${_advanceFixed.text.trim()}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Space: ${_nameCtrl.text.trim()} ($_spaceType)'),
        Text('Events: ${_events.join(', ')}'),
        Text('Facilities: ${_facilities.join(', ')}'),
        Text('Seating ${_seatCtrl.text.trim()}, dining ${_dineCtrl.text.trim()}'),
        Text('Catering in-house $_caterIn, outside $_caterOut'),
        Text('Decor by hall $_decorHall, outside decor $_decorOut'),
        const SizedBox(height: 8),
        const Text('Slots', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final line in slots) Text(line),
        const SizedBox(height: 8),
        Text('Advance: $advance'),
        Text('Full payment due ${_fullDue.text.trim()} days before the event'),
        Text('Deduction basis: $_deductionBasis'),
        Text('Book up to ${_bookMonths.text.trim()} months ahead'),
        Text('Minimum notice: ${_minNotice.text.trim()} days'),
        const SizedBox(height: 8),
        Text('Cancellation: ${_editorSummary(_cancelFields)}'),
        Text('Reschedule: ${_editorSummary(_rescheduleFields)}'),
        const SizedBox(height: 12),
        const Text(
          'Times for customers will be shown in IST (Kolkata). Tap Save Package to unlock calendar and operators.',
        ),
      ],
    );
  }

  String _slotSummary(
    String label,
    TextEditingController from,
    TextEditingController to,
    TextEditingController price,
    TextEditingController acPrice,
  ) {
    final rent = '₹${price.text.trim()}';
    final ac = _offersAc ? ', AC ₹${acPrice.text.trim()}' : '';
    return '$label ${from.text.trim()}–${to.text.trim()} $rent$ac';
  }

  String _editorSummary(List<_TierEditors> fields) {
    return fields.map((field) {
      final max = field.max.text.trim();
      final end = max.isEmpty ? 'and later' : 'to $max days';
      return '${field.min.text.trim()} $end: ${field.pct.text.trim()}%';
    }).join('; ');
  }
}

class _TierEditors {
  _TierEditors(HallPolicyTier tier)
      : min = TextEditingController(text: '${tier.minDaysBeforeEvent}'),
        max = TextEditingController(text: tier.maxDaysBeforeEvent?.toString() ?? ''),
        pct = TextEditingController(text: '${tier.deductionPercent}');

  final TextEditingController min;
  final TextEditingController max;
  final TextEditingController pct;

  HallPolicyTier read() {
    final maxText = max.text.trim();
    return HallPolicyTier(
      minDaysBeforeEvent: int.parse(min.text.trim()),
      maxDaysBeforeEvent: maxText.isEmpty ? null : int.parse(maxText),
      deductionPercent: int.parse(pct.text.trim()),
    );
  }

  void dispose() {
    min.dispose();
    max.dispose();
    pct.dispose();
  }
}

String _yesNoOr(dynamic value, String fallback) {
  final text = value?.toString();
  if (text == 'yes' || text == 'no') return text!;
  return fallback;
}

int? _storedWhole(String raw, {required int min, required int max}) {
  final value = int.tryParse(raw.trim());
  if (value == null || value < min || value > max) return null;
  return value;
}

String? _whole(String raw, String label, {required int min, required int max}) {
  final text = raw.trim();
  if (text.isEmpty) return '$label is required';
  final value = int.tryParse(text);
  if (value == null) return '$label must be a whole number';
  if (value < min || value > max) return '$label must be between $min and $max';
  return null;
}

String? _clock(String raw, String label) {
  if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(raw.trim())) {
    return '$label must be HH:MM';
  }
  return null;
}

int _minutes(String raw) {
  final parts = raw.trim().split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}
