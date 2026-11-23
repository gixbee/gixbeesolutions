import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../theme.dart';
import '../../repositories/hall_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_text_field.dart';
import 'hall_policy.dart';
import 'hall_slot_options.dart';

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
  bool _editing = false;
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
  final _roomsCtrl = TextEditingController(text: '0');

  bool _morning = true;
  final _slotOptions = {
    for (final id in ['morning', 'evening', 'fullday']) id: HallSlotOptions(),
  };
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
  final _discounts = {
    for (final slot in ['morning', 'evening', 'fullday'])
      slot: (
        TextEditingController(text: '0'),
        TextEditingController(text: '0')
      ),
  };

  String _advanceType = 'fixed';
  final _advanceFixed = TextEditingController(text: '20000');
  final _advancePct = TextEditingController(text: '30');
  final _fullDue = TextEditingController(text: '7');
  String _deductionBasis = 'ADVANCE';
  List<HallPolicyTier> _cancel = defaultPolicyTiers();
  List<HallPolicyTier> _reschedule = defaultPolicyTiers();

  final _bookMonths = TextEditingController(text: '6');
  final _minNotice = TextEditingController(text: '3');

  bool get _offersAc => _spaceType != 'outdoor' && _facilities.contains('AC');

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
        _editing =
            hall['packageSaved'] == true || hall['packageRevisionId'] != null;
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
      _setNum(_roomsCtrl, capacity['rooms']);
    }
    final slots = m['slotOffers'];
    if (slots is List) {
      _morning = false;
      _evening = false;
      _fullday = false;
      for (final raw in slots) {
        if (raw is! Map) continue;
        final slot = Map<String, dynamic>.from(raw);
        _slotOptions[slot['id']]?.load(slot);
        final discount = _discounts[slot['id']];
        if (discount != null) {
          discount.$1.text = '${slot['discountNoAcPct'] ?? 0}';
          discount.$2.text = '${slot['discountAcPct'] ?? 0}';
        }
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
    _roomsCtrl.dispose();
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
    for (final options in _slotOptions.values) {
      options.dispose();
    }
    for (final (regular, ac) in _discounts.values) {
      regular.dispose();
      ac.dispose();
    }
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
      final options = _slotOptions[id]!;
      offers.add({
        'id': id,
        'label': label,
        'hallFrom': from.text.trim(),
        'hallTo': to.text.trim(),
        'enabled': enabled,
        'offerNoAc': options.offerNoAc,
        'offerAc': offerAc && options.offerAc,
        'priceNoAc': int.tryParse(price.text.trim()) ?? 0,
        'priceAc': int.tryParse(acPrice.text.trim()) ?? 0,
        'discountNoAcEnabled': options.discountNoAc,
        'discountAcEnabled': options.discountAc,
        'discountNoAcPct': options.discountNoAc
            ? int.tryParse(_discounts[id]!.$1.text.trim()) ?? 0
            : 0,
        'discountAcPct': options.discountAc
            ? int.tryParse(_discounts[id]!.$2.text.trim()) ?? 0
            : 0,
        'acUsage': options.usage,
        'acHours': double.tryParse(options.hours.text) ?? 1,
        'acTiming': options.timing,
        'acFrom': options.from.text.trim(),
        'acTo': options.to.text.trim(),
        if (enabled && offerAc && options.offerAc)
          ...options.json(from.text, to.text),
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
        'rooms': int.parse(_roomsCtrl.text.trim()),
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
      final seat =
          _whole(_seatCtrl.text, 'Seating capacity', min: 0, max: 100000);
      if (seat != null) return seat;
      final dine =
          _whole(_dineCtrl.text, 'Dining capacity', min: 0, max: 100000);
      if (dine != null) return dine;
      final rooms = _whole(_roomsCtrl.text, 'Private / changing rooms',
          min: 0, max: 10000);
      if (rooms != null) return rooms;
    }
    if (step == 3) {
      if (!_morning && !_evening && !_fullday) {
        return 'Enable at least one slot';
      }
      String? slot(
        String id,
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
        final options = _slotOptions[id]!;
        final optionError = options.validate(from.text, to.text, _offersAc);
        if (optionError != null) return '$label: $optionError';
        final rent = options.offerNoAc
            ? _whole(price.text, '$label price', min: 0, max: 100000000)
            : null;
        if (rent != null) return rent;
        final discount = _discounts[id]!;
        final discountError = options.offerNoAc && options.discountNoAc
            ? _whole(discount.$1.text, '$label discount', min: 0, max: 99)
            : null;
        if (discountError != null) return discountError;
        if (_offersAc && options.offerAc) {
          return _whole(acPrice.text, '$label AC price',
                  min: 0, max: 100000000) ??
              (options.discountAc
                  ? _whole(discount.$2.text, '$label AC discount',
                      min: 0, max: 99)
                  : null);
        }
        return null;
      }

      return slot('morning', 'Morning', _morning, _mFrom, _mTo, _mNoAc, _mAc) ??
          slot('evening', 'Evening', _evening, _eFrom, _eTo, _eNoAc, _eAc) ??
          slot('fullday', 'Full day', _fullday, _fFrom, _fTo, _fNoAc, _fAc);
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
      final notice =
          _whole(_minNotice.text, 'Minimum notice', min: 0, max: 365);
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
      showGxSnack(context, _editing ? 'Package updated' : 'Package saved');
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
        title: const Text('Price & packages'),
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
                    Text(
                      'Step $_step of 5 · ${const [
                        'Event categories',
                        'Venue details',
                        'Pricing & time slots',
                        'Payment & policies',
                        'Review package'
                      ][_step - 1]}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: _step / 5,
                      color: context.gx.accent,
                      backgroundColor: context.gx.border,
                      borderRadius: BorderRadius.circular(4),
                      minHeight: 5,
                    ),
                    const SizedBox(height: 24),
                    if (_step == 1) _step1(),
                    if (_step == 2) _step2(),
                    if (_step == 3) _step3(),
                    if (_step == 4) _step4(),
                    if (_step == 5) _step5(),
                    const SizedBox(height: 24),
                  ],
                ),
      bottomNavigationBar: !_ready || _loadError != null
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: context.gx.bg,
                  border: Border(top: BorderSide(color: context.gx.border)),
                ),
                child: GxButton(
                  label: _step == 5
                      ? (_saving
                          ? (_editing ? 'Updating…' : 'Saving…')
                          : (_editing ? 'Update Package' : 'Save Package'))
                      : (_advancing ? 'Please wait…' : 'Continue'),
                  onTap: busy ? null : _next,
                ),
              ),
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
        GxTextField(
            controller: _seatCtrl,
            label: 'Seating capacity',
            keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        GxTextField(
            controller: _dineCtrl,
            label: 'Dining capacity',
            keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        GxTextField(
            controller: _roomsCtrl,
            label: 'Private / Changing Rooms',
            keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        _yesNo(
            'In-house catering', _caterIn, (v) => setState(() => _caterIn = v)),
        _yesNo('Outside catering allowed', _caterOut,
            (v) => setState(() => _caterOut = v)),
        _yesNo(
            'Decor by hall', _decorHall, (v) => setState(() => _decorHall = v)),
        _yesNo('Outside decor allowed', _decorOut,
            (v) => setState(() => _decorOut = v)),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _slotEditor('morning', 'Morning', _morning, (v) => _morning = v, _mFrom,
            _mTo, _mNoAc, _mAc),
        _slotEditor('evening', 'Evening', _evening, (v) => _evening = v, _eFrom,
            _eTo, _eNoAc, _eAc),
        _slotEditor('fullday', 'Full day', _fullday, (v) => _fullday = v,
            _fFrom, _fTo, _fNoAc, _fAc),
      ],
    );
  }

  Widget _panel(String title, List<Widget> children,
      {IconData? icon, Widget? trailing}) {
    final colors = context.gx;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 22, color: colors.accent),
            const SizedBox(width: 10),
          ],
          Expanded(
              child: Text(title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700, color: colors.ink))),
          if (trailing != null) trailing,
        ]),
        if (children.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...children,
        ],
      ]),
    );
  }

  Widget _labelValue(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              flex: 5,
              child: Text(label,
                  style: TextStyle(
                      color: context.gx.ink.withValues(alpha: 0.65)))),
          const SizedBox(width: 12),
          Expanded(
              flex: 6,
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: context.gx.ink))),
        ]),
      );

  String _money(String raw) {
    final value = num.tryParse(raw.trim());
    return value == null
        ? '—'
        : NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
            .format(value);
  }

  Widget _priceTotal(TextEditingController rent, TextEditingController discount,
      bool discounted) {
    return AnimatedBuilder(
      animation: Listenable.merge([rent, discount]),
      builder: (context, _) {
        final base = int.tryParse(rent.text.trim());
        final pct = discounted ? int.tryParse(discount.text.trim()) : 0;
        final valid =
            base != null && base >= 0 && pct != null && pct >= 0 && pct <= 99;
        final total = valid ? (base * (100 - pct) + 50) ~/ 100 : null;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.gx.accentSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Customer price',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Text(
                    valid && pct > 0
                        ? '$pct% off · GST included'
                        : 'GST included',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            )),
            const SizedBox(width: 8),
            Flexible(
                child: Text(total == null ? '—' : _money('$total'),
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: context.gx.accent,
                        fontWeight: FontWeight.w800))),
          ]),
        );
      },
    );
  }

  Widget _slotEditor(
    String id,
    String title,
    bool enabled,
    ValueChanged<bool> onEnabled,
    TextEditingController from,
    TextEditingController to,
    TextEditingController price,
    TextEditingController acPrice,
  ) {
    final options = _slotOptions[id]!;
    Widget pricing(bool ac) {
      final controller = ac ? acPrice : price;
      final discount = ac ? _discounts[id]!.$2 : _discounts[id]!.$1;
      final offered = ac ? options.offerAc : options.offerNoAc;
      final discounted = ac ? options.discountAc : options.discountNoAc;
      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.gx.bg,
          border: Border.all(color: context.gx.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(ac ? Icons.ac_unit : Icons.meeting_room_outlined,
                size: 20, color: context.gx.ink.withValues(alpha: 0.65)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    ac
                        ? 'With AC'
                        : _offersAc
                            ? 'Without AC'
                            : 'Hall rental',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            Checkbox(
              value: offered,
              activeColor: context.gx.accent,
              onChanged: (value) => setState(() {
                if (ac) {
                  options.offerAc = value!;
                } else {
                  options.offerNoAc = value!;
                }
              }),
            ),
          ]),
          if (offered) ...[
            const SizedBox(height: 8),
            GxTextField(
                controller: controller,
                blur: false,
                label: 'Base rent · GST included',
                prefixIcon: Icons.currency_rupee,
                keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Offer a discount'),
              value: discounted,
              activeThumbColor: context.gx.accent,
              onChanged: (value) => setState(() {
                if (ac) {
                  options.discountAc = value;
                } else {
                  options.discountNoAc = value;
                }
              }),
            ),
            if (discounted) ...[
              GxTextField(
                  controller: discount,
                  blur: false,
                  label: 'Discount',
                  suffix: const Text('%'),
                  keyboardType: TextInputType.number),
              const SizedBox(height: 12),
            ],
            _priceTotal(controller, discount, discounted),
          ],
        ]),
      );
    }

    return _panel(
        title,
        enabled
            ? [
                Row(children: [
                  Expanded(
                      child: GxTextField(
                          controller: from,
                          blur: false,
                          label: 'Hall opens',
                          prefixIcon: Icons.schedule_outlined,
                          hint: '09:00')),
                  const SizedBox(width: 12),
                  Expanded(
                      child: GxTextField(
                          controller: to,
                          blur: false,
                          label: 'Hall closes',
                          prefixIcon: Icons.schedule_outlined,
                          hint: '14:00')),
                ]),
                const SizedBox(height: 4),
                Text('24-hour time · IST',
                    style: Theme.of(context).textTheme.bodySmall),
                pricing(false),
                if (_offersAc) ...[
                  pricing(true),
                  if (options.offerAc) ...[
                    const SizedBox(height: 20),
                    const Text('AC availability',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: options.usage,
                      key: ValueKey('$id-usage-${options.usage}'),
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Included AC usage',
                          border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(
                            value: 'full', child: Text('Entire hall booking')),
                        DropdownMenuItem(
                            value: 'partial', child: Text('Limited hours')),
                      ],
                      onChanged: (value) =>
                          setState(() => options.usage = value!),
                    ),
                    if (options.usage == 'partial') ...[
                      const SizedBox(height: 16),
                      GxTextField(
                          controller: options.hours,
                          blur: false,
                          label: 'Included AC hours',
                          suffix: const Text('hrs'),
                          onChanged: (value) {
                            final duration =
                                ((HallSlotOptions.minutes(to.text) ?? 0) -
                                        (HallSlotOptions.minutes(from.text) ??
                                            0)) /
                                    60;
                            if (duration > 0 &&
                                double.tryParse(value) == duration) {
                              setState(() => options.usage = 'full');
                            }
                          },
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true)),
                    ],
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: options.timing,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'AC operating schedule',
                          border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(
                            value: 'flexible',
                            child: Text('Agree timing with customer')),
                        DropdownMenuItem(
                            value: 'fixed',
                            child: Text('Fixed operating hours')),
                      ],
                      onChanged: (value) =>
                          setState(() => options.timing = value!),
                    ),
                    if (options.timing == 'fixed') ...[
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                            child: GxTextField(
                                controller: options.from,
                                blur: false,
                                label: 'AC starts')),
                        const SizedBox(width: 12),
                        Expanded(
                            child: GxTextField(
                                controller: options.to,
                                blur: false,
                                label: 'AC ends')),
                      ]),
                    ],
                  ],
                ],
              ]
            : [],
        icon: switch (id) {
          'morning' => Icons.wb_sunny_outlined,
          'evening' => Icons.nights_stay_outlined,
          _ => Icons.calendar_today_outlined,
        },
        trailing: Switch.adaptive(
            value: enabled,
            activeThumbColor: context.gx.accent,
            onChanged: (value) => setState(() => onEnabled(value))));
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
          GxTextField(
              controller: _advanceFixed,
              label: 'Advance ₹',
              keyboardType: TextInputType.number)
        else
          GxTextField(
              controller: _advancePct,
              label: 'Advance %',
              keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        GxTextField(
            controller: _fullDue,
            label: 'Full payment due (days before)',
            keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        const Text('Deduction basis',
            style: TextStyle(fontWeight: FontWeight.w700)),
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
              onSelected: (_) =>
                  setState(() => _deductionBasis = 'TOTAL_QUOTE'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _policyEditor('Cancellation policy', _cancelFields),
        const SizedBox(height: 12),
        _policyEditor('Reschedule policy', _rescheduleFields),
        const SizedBox(height: 8),
        GxTextField(
            controller: _bookMonths,
            label: 'Book window (months)',
            keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        GxTextField(
            controller: _minNotice,
            label: 'Min notice (days)',
            keyboardType: TextInputType.number),
      ],
    );
  }

  Widget _policyEditor(String title, List<_TierEditors> fields) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
            'Leave max days blank on the last tier only. Days must meet with no gaps.'),
        for (var i = 0; i < fields.length; i++) ...[
          const SizedBox(height: 8),
          Text('Tier ${i + 1}'),
          GxTextField(
              controller: fields[i].min,
              label: 'Min days before event',
              keyboardType: TextInputType.number),
          const SizedBox(height: 6),
          GxTextField(
              controller: fields[i].max,
              label: 'Max days (blank = no limit)',
              keyboardType: TextInputType.number),
          const SizedBox(height: 6),
          GxTextField(
              controller: fields[i].pct,
              label: 'Deduction %',
              keyboardType: TextInputType.number),
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

  Widget _reviewSection(String title, int step, List<Widget> children,
      {IconData? icon}) {
    return _panel(title, children,
        icon: icon,
        trailing: TextButton(
          onPressed: _saving ? null : () => setState(() => _step = step),
          child: const Text('Edit'),
        ));
  }

  Widget _policyTable(String title, List<_TierEditors> fields) {
    return _panel(
        title,
        [
          Text(
          'Deducted from ${_deductionBasis == 'TOTAL_QUOTE' ? 'the booking total' : 'the advance payment'}.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Table(
            columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(2)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder(
                horizontalInside: BorderSide(color: context.gx.border)),
            children: [
              const TableRow(children: [
                Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('Before event',
                        style: TextStyle(fontWeight: FontWeight.w700))),
                Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('Deduction',
                        textAlign: TextAlign.end,
                        style: TextStyle(fontWeight: FontWeight.w700))),
              ]),
              for (final field in fields)
                TableRow(children: [
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(_dayRange(field))),
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text('${field.pct.text.trim()}%',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
            ],
          ),
        ],
        trailing: TextButton(
            onPressed: _saving ? null : () => setState(() => _step = 4),
            child: const Text('Edit')));
  }

  String _dayRange(_TierEditors field) {
    final min = field.min.text.trim();
    final max = field.max.text.trim();
    if (min == '0' && max == '0') return 'Event day';
    if (max.isEmpty) return '$min+ days';
    if (min == max) return '$min day${min == '1' ? '' : 's'}';
    return '$min–$max days';
  }

  Widget _reviewSlot(
    String id,
    String label,
    TextEditingController from,
    TextEditingController to,
    TextEditingController price,
    TextEditingController acPrice,
  ) {
    final options = _slotOptions[id]!;
    String total(bool ac) {
      final raw = ac ? acPrice.text : price.text;
      final discountOn = ac ? options.discountAc : options.discountNoAc;
      final controller = ac ? _discounts[id]!.$2 : _discounts[id]!.$1;
      final base = int.tryParse(raw.trim()) ?? 0;
      final discount = discountOn
          ? (int.tryParse(controller.text.trim()) ?? 0).clamp(0, 99)
          : 0;
      final result = _money('${(base * (100 - discount) + 50) ~/ 100}');
      return discount > 0 ? '$result · $discount% off' : result;
    }

    return _reviewSection(
        label,
        3,
        [
          Text('${from.text.trim()}–${to.text.trim()} · IST',
              style: TextStyle(color: context.gx.ink.withValues(alpha: 0.65))),
          const SizedBox(height: 8),
          if (options.offerNoAc)
            _labelValue(_offersAc ? 'Without AC' : 'Hall rental', total(false)),
          if (_offersAc && options.offerAc) ...[
            _labelValue('With AC', total(true)),
            _labelValue(
                'AC included',
                options.usage == 'full'
                    ? 'Entire hall booking'
                    : '${options.hours.text.trim()} hours'),
            _labelValue(
                'AC schedule',
                options.timing == 'flexible'
                    ? 'Agreed with customer'
                    : '${options.from.text.trim()}–${options.to.text.trim()}'),
          ],
          const SizedBox(height: 8),
          Text('Prices include GST',
              style: Theme.of(context).textTheme.bodySmall),
        ],
        icon: Icons.schedule_outlined);
  }

  Widget _step5() {
    final advance = _advanceType == 'percent'
        ? '${_advancePct.text.trim()}% of the quote'
        : _money(_advanceFixed.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _reviewSection(
            'Venue details',
            2,
            [
              Text(_nameCtrl.text.trim(),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _labelValue(
                  'Space', _spaceType == 'outdoor' ? 'Outdoor' : 'Indoor'),
              _labelValue('Seating capacity', _seatCtrl.text.trim()),
              _labelValue('Dining capacity', _dineCtrl.text.trim()),
              _labelValue('Private / changing rooms', _roomsCtrl.text.trim()),
              const Divider(height: 24),
              const Text('Facilities',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final facility in _facilities)
                  Chip(
                      label: Text(facility),
                      visualDensity: VisualDensity.compact),
              ]),
              const SizedBox(height: 8),
              _labelValue('In-house catering',
                  _caterIn == 'yes' ? 'Available' : 'Unavailable'),
              _labelValue('Outside catering',
                  _caterOut == 'yes' ? 'Allowed' : 'Unavailable'),
              _labelValue('Decor by hall',
                  _decorHall == 'yes' ? 'Available' : 'Unavailable'),
              _labelValue('Outside decor',
                  _decorOut == 'yes' ? 'Allowed' : 'Unavailable'),
            ],
            icon: Icons.meeting_room_outlined),
        _reviewSection(
            'Events you host',
            1,
            [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final event in _events)
                  Chip(
                      label: Text(event.isEmpty
                          ? event
                          : '${event[0].toUpperCase()}${event.substring(1)}'),
                      visualDensity: VisualDensity.compact),
              ]),
            ],
            icon: Icons.celebration_outlined),
        if (_morning)
          _reviewSlot('morning', 'Morning', _mFrom, _mTo, _mNoAc, _mAc),
        if (_evening)
          _reviewSlot('evening', 'Evening', _eFrom, _eTo, _eNoAc, _eAc),
        if (_fullday)
          _reviewSlot('fullday', 'Full day', _fFrom, _fTo, _fNoAc, _fAc),
        _reviewSection(
            'Payment & booking',
            4,
            [
              _labelValue('Advance payment', advance),
              _labelValue(
                  'Balance due', '${_fullDue.text.trim()} days before event'),
              _labelValue(
                  'Booking window', '${_bookMonths.text.trim()} months ahead'),
              _labelValue('Minimum notice', '${_minNotice.text.trim()} days'),
            ],
            icon: Icons.receipt_long_outlined),
        _policyTable('Cancellation policy', _cancelFields),
        _policyTable('Rescheduling policy', _rescheduleFields),
      ],
    );
  }
}

class _TierEditors {
  _TierEditors(HallPolicyTier tier)
      : min = TextEditingController(text: '${tier.minDaysBeforeEvent}'),
        max = TextEditingController(
            text: tier.maxDaysBeforeEvent?.toString() ?? ''),
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
