import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'photography_owner_pricing.dart';

/// Photography owner's ten-step package wizard from the HTML reference.
/// Structured details are retained in catalogue JSON; customer selection and
/// final quote still use the existing Rust API and the base package price.
class PhotographyPackageWizardScreen extends StatefulWidget {
  const PhotographyPackageWizardScreen({super.key, this.package, this.onSave});
  final Map<String, dynamic>? package;
  final Future<bool> Function(Map<String, dynamic> item)? onSave;

  @override
  State<PhotographyPackageWizardScreen> createState() =>
      _PhotographyPackageWizardScreenState();
}

class _PhotographyPackageWizardScreenState
    extends State<PhotographyPackageWizardScreen> {
  static const _blue = Color(0xFF1B2559);
  static const _green = Color(0xFF12B76A);
  static const _steps = [
    'Package basics',
    'Select functions',
    'Ceremony type',
    'Coverage details',
    'Deliverables',
    'Special services & extras',
    'Delivery timeline',
    'Payment stages',
    'Customer requirements',
    'Review & publish',
  ];
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _discount = TextEditingController(text: '0');
  final _equipment = TextEditingController();
  final _quality = TextEditingController();
  final _functionDurations = <String, TextEditingController>{};
  final _functionSides = <String, String>{};
  final _deliveryDays = <String, TextEditingController>{};
  final _deliverableQty = <String, TextEditingController>{};
  final _deliverableFormat = <String, String>{};
  bool _discountEnabled = false;
  bool _saving = false;
  String? _saveError;
  final _coverage = TextEditingController();
  final _photoTeam = TextEditingController();
  final _videoTeam = TextEditingController();
  final _extraHour = TextEditingController();
  final _deliverables = TextEditingController();
  final _delivery = TextEditingController();
  final _requirements = TextEditingController();
  final _policy = TextEditingController();
  final _functions = <String>{};
  final _ceremonies = <String>{};
  final _inclusions = <String>{};
  final _extras = <String>{};
  final _stageNames = <TextEditingController>[];
  final _stageValues = <TextEditingController>[];
  int _step = 0;
  bool _active = true;
  String _level = 'Standard';

  @override
  void initState() {
    super.initState();
    final item = widget.package ?? {};
    _name.text = item['name']?.toString() ?? '';
    _description.text = item['description']?.toString() ?? '';
    _price.text = (item['listPrice'] ?? item['price'])?.toString() ?? '';
    _discount.text = (item['discountPct'] ?? 0).toString();
    _discountEnabled = (item['discountPct'] as num? ?? 0) > 0;
    _equipment.text = item['equipmentNote']?.toString() ?? '';
    _quality.text = item['qualityNote']?.toString() ?? '';
    _coverage.text = item['coverageNotes']?.toString() ?? '';
    _photoTeam.text = item['photographerTeam']?.toString() ?? '';
    _videoTeam.text = item['videographerTeam']?.toString() ?? '';
    _extraHour.text = item['extraHourPrice']?.toString() ?? '';
    _deliverables.text = item['includes']?.toString() ?? '';
    _delivery.text = item['delivery']?.toString() ?? '';
    _requirements.text = item['customerRequirements']?.toString() ?? '';
    _policy.text = item['policy']?.toString() ?? '';
    _level = item['packageLevel']?.toString() ?? 'Standard';
    if (!const ['Basic', 'Standard', 'Premium'].contains(_level)) {
      _level = 'Standard';
    }
    _active = item['active'] != false;
    _functions
        .addAll((item['functions'] as List? ?? const []).whereType<String>());
    _ceremonies
        .addAll((item['ceremonies'] as List? ?? const []).whereType<String>());
    _inclusions
        .addAll((item['inclusions'] as List? ?? const []).whereType<String>());
    _extras.addAll((item['extras'] as List? ?? const []).whereType<String>());
    final coverage = item['functionCoverage'] as Map? ?? {};
    for (final entry in coverage.entries) {
      if (entry.value is! Map) continue;
      final value = entry.value as Map;
      _functionDurations[entry.key.toString()] = TextEditingController(
          text: value['duration']?.toString() ?? '');
      _functionSides[entry.key.toString()] = value['side']?.toString() ?? 'Both';
    }
    final details = item['deliverableDetails'] as Map? ?? {};
    final deadlines = item['deliveryTimelines'] as Map? ?? {};
    for (final name in _inclusions) {
      final d = details[name] as Map? ?? {};
      _deliverableQty[name] = TextEditingController(
        text: (d['quantity'] ?? 1).toString());
      _deliverableFormat[name] = d['format']?.toString() ?? 'JPG';
      final timeline = deadlines[name] as Map? ?? {};
      _deliveryDays[name] = TextEditingController(
        text: timeline['days']?.toString() ?? '15');
    }
    final stages =
        (item['paymentSplit'] as List? ?? const []).whereType<Map>().toList();
    if (stages.isEmpty) {
      _addStage('Booking advance', '30');
      _addStage('Event day', '40');
      _addStage('Before album printing', '20');
      _addStage('Final payment', '10');
    } else {
      for (final stage in stages) {
        _addStage(stage['label']?.toString() ?? '',
            stage['percent']?.toString() ?? '');
      }
    }
  }

  void _addStage(String name, String pct) {
    _stageNames.add(TextEditingController(text: name));
    _stageValues.add(TextEditingController(text: pct));
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _price,
      _discount,
      _equipment,
      _quality,
      ..._functionDurations.values,
      ..._deliverableQty.values,
      ..._deliveryDays.values,
      _coverage,
      _photoTeam,
      _videoTeam,
      _extraHour,
      _deliverables,
      _delivery,
      _requirements,
      _policy,
      ..._stageNames,
      ..._stageValues,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _offerPrice => PhotographyOwnerPrice.discounted(
        int.tryParse(_price.text.trim()) ?? 0,
        _discountEnabled ? (int.tryParse(_discount.text.trim()) ?? -1) : 0,
      );

  void _warn(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  bool _validStep() {
    switch (_step) {
      case 0:
        if (_name.text.trim().isEmpty ||
            _name.text.trim().length > 150 ||
            (int.tryParse(_price.text) ?? 0) < 1 ||
            (int.tryParse(_price.text) ?? 0) > 10000000 ||
            _offerPrice == null || _description.text.trim().isEmpty) {
          _warn('Enter a package name, short description and valid price/discount.');
          return false;
        }
        return _description.text.trim().length <= 3000;
      case 1:
        if (_functions.isEmpty) {
          _warn('Select at least one function.');
          return false;
        }
        return true;
      case 2:
        if (_functions.any((f) => const ['Wedding', 'Reception', 'Engagement'].contains(f)) && _ceremonies.isEmpty) {
          _warn('Select at least one ceremony type.');
          return false;
        }
        return true;
      case 4:
        if (_inclusions.isEmpty) {
          _warn('Select at least one deliverable.');
          return false;
        }
        return true;
      case 6:
        for (final name in _inclusions) {
          final value = int.tryParse(_deliveryDays[name]?.text ?? '15');
          final qty = int.tryParse(_deliverableQty[name]?.text ?? '1');
          if (value == null || value < 0 || value > 730 ||
              qty == null || qty < 1 || qty > 100000) {
            _warn('Check deliverable quantity and delivery days.');
            return false;
          }
        }
        return true;
      case 7:
        if (_stageNames.isEmpty ||
            _stageNames.length > 6 ||
            _stageNames.any((c) => c.text.trim().isEmpty)) {
          _warn('Enter the payment stage names.');
          return false;
        }
        final numbers = _stageValues.map((v) => int.tryParse(v.text)).toList();
        if (numbers.any((v) => v == null || v < 1 || v > 100) ||
            numbers.fold<int>(0, (sum, v) => sum + (v ?? 0)) != 100) {
          _warn('Payment stage percentages must total exactly 100%.');
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _advance() {
    if (!_validStep()) return;
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      _save();
    }
  }

  Future<void> _save({bool draft = false}) async {
    if (_saving) return;
    // Do not close the wizard until the canonical Rust catalogue write succeeds.
    final oldStep = _step;
    for (final step in [0, 1, 2, 4, 6, 7]) {
      _step = step;
      if (!_validStep()) {
        setState(() => _step = step);
        return;
      }
    }
    _step = oldStep;
    final payment = [
      for (var i = 0; i < _stageNames.length; i++)
        {'label': _stageNames[i].text.trim(),
          'percent': int.parse(_stageValues[i].text.trim())},
    ];
    final item = <String, dynamic>{
      ...?widget.package,
      'id': widget.package?['id'] ?? const Uuid().v4(),
      'kind': 'PACKAGE',
      'active': draft ? false : _active,
      'name': _name.text.trim(),
      'category': 'Wedding & related functions',
      'description': _description.text.trim(),
      'listPrice': int.parse(_price.text.trim()),
      'discountPct': _discountEnabled ? int.parse(_discount.text.trim()) : 0,
      'price': _offerPrice,
      'equipmentNote': _equipment.text.trim(),
      'qualityNote': _quality.text.trim(),
      'packageLevel': _level,
      'functions': _functions.toList()..sort(),
      'ceremonies': _ceremonies.toList()..sort(),
      'coverageNotes': _coverage.text.trim(),
      'photographerTeam': _photoTeam.text.trim(),
      'videographerTeam': _videoTeam.text.trim(),
      'extraHourPrice': int.tryParse(_extraHour.text.trim()) ?? 0,
      'functionCoverage': {
        for (final name in _functions)
          name: {
            'duration': _functionDurations[name]?.text.trim() ?? '',
            'side': _functionSides[name] ?? 'Both',
          },
      },
      'inclusions': _inclusions.toList()..sort(),
      'includes': _deliverables.text.trim().isNotEmpty
          ? _deliverables.text.trim()
          : _inclusions.join(', '),
      'deliverableDetails': {
        for (final name in _inclusions)
          name: {
            'quantity': int.tryParse(_deliverableQty[name]?.text ?? '') ?? 1,
            'format': _deliverableFormat[name] ?? 'JPG',
          },
      },
      'deliveryTimelines': {
        for (final name in _inclusions)
          name: {'days': int.tryParse(_deliveryDays[name]?.text ?? '') ?? 15},
      },
      'extras': _extras.toList()..sort(),
      'delivery': _delivery.text.trim(),
      'paymentSplit': payment,
      'paymentStages': payment.map((s) =>
          '${s['label']}: ${s['percent']}%').join(' | '),
      'policy': _policy.text.trim(),
      'customerRequirements': _requirements.text.trim(),
    };
    final validation = PhotographyOwnerPrice.validate(item);
    if (validation != null) {
      _warn(validation);
      return;
    }
    if (widget.onSave == null) {
      Navigator.pop(context, item);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await widget.onSave!(item);
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context);
      } else {
        setState(() => _saveError =
            'Package could not be saved. Check the catalogue and retry.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saveError =
            'Unable to contact the API. Your changes are still here.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _text(String label, TextEditingController ctrl,
          {int lines = 1, TextInputType? keyboardType}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: ctrl,
          onChanged: (_) => setState(() {}),
          maxLength: lines == 1 ? 150 : 1000,
          maxLines: lines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              alignLabelWithHint: lines > 1),
        ),
      );

  Widget _picks(String title, Iterable<String> names, Set<String> selected) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                color: _blue, fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final name in names)
            FilterChip(
                label: Text(name),
                selected: selected.contains(name),
                onSelected: (v) => setState(() {
                      if (v) {
                        selected.add(name);
                      } else {
                        selected.remove(name);
                      }
                    })),
        ]),
        const SizedBox(height: 16),
      ]);

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return Column(children: [
          _text('Package name *', _name),
          _text('Package price including GST (₹) *', _price,
              keyboardType: TextInputType.number),
          SwitchListTile(
            title: const Text('Offer a discount?'),
            value: _discountEnabled,
            onChanged: (v) => setState(() => _discountEnabled = v),
          ),
          if (_discountEnabled)
            _text('Discount % (1–90)', _discount,
              keyboardType: TextInputType.number),
          Card(
            color: const Color(0xFFECFDF3),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Customer will see: ₹${_offerPrice ?? 0}'
                  '${_discountEnabled ? ' (was ₹${_price.text})' : ''}',
                style: const TextStyle(color: _blue,
                    fontWeight: FontWeight.w900, fontSize: 18)),
            ),
          ),
          _text('Short description *', _description, lines: 3),
          _text('Equipment & gear (optional)', _equipment, lines: 3),
          _text('Quality & editing notes (optional)', _quality, lines: 3),
          const Text('Package level',
              style: TextStyle(fontWeight: FontWeight.bold)),
          SegmentedButton<String>(segments: const [
            ButtonSegment(value: 'Basic', label: Text('Basic')),
            ButtonSegment(value: 'Standard', label: Text('Standard')),
            ButtonSegment(value: 'Premium', label: Text('Premium')),
          ], selected: {
            _level
          }, onSelectionChanged: (s) => setState(() => _level = s.first)),
        ]);
      case 1:
        return _picks(
            'Wedding functions covered',
            const [
              'Wedding',
              'Reception',
              'Engagement',
              'Wedding Eve',
              'Pre-wedding Shoot',
              'Post-wedding Shoot',
            ],
            _functions);
      case 2:
        return _picks(
            'Ceremony types',
            const [
              'Hindu',
              'Christian',
              'Muslim',
              'Civil',
              'Other',
            ],
            _ceremonies);
      case 3:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Coverage for each selected function',
            style: TextStyle(color: _blue, fontWeight: FontWeight.w800)),
          for (final name in _functions.toList()..sort())
            Card(
              child: Padding(padding: const EdgeInsets.all(12),
                child: Column(children: [
                  Text(name, style: const TextStyle(
                      fontWeight: FontWeight.w800, color: _blue)),
                  _text('Duration (e.g. 6 hours)',
                      _functionDurations.putIfAbsent(name,
                        () => TextEditingController())),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _functionSides[name] ?? 'Both',
                    decoration: const InputDecoration(
                        labelText: 'Coverage side'),
                    items: const [
                      DropdownMenuItem(value: 'Both', child: Text('Both sides')),
                      DropdownMenuItem(value: 'Bride', child: Text('Bride side')),
                      DropdownMenuItem(value: 'Groom', child: Text('Groom side')),
                    ],
                    onChanged: (v) =>
                      setState(() => _functionSides[name] = v ?? 'Both'),
                  ),
                ]),
              ),
            ),
          _text('Additional coverage notes', _coverage, lines: 4),
          _text('Photography crew', _photoTeam),
          _text('Videography crew', _videoTeam),
          _text('Additional hour price (₹, optional)', _extraHour,
              keyboardType: TextInputType.number),
        ]);
      case 4:
        return Column(children: [
          _picks(
              'Included deliverables',
              const [
                'Edited Photos',
                'Candid Photography',
                'Traditional Photography',
                'Cinematic Video',
                'Highlights Reel',
                'Online Gallery',
                'Physical Album',
                'Parent Albums',
                'Prints',
                'Raw Files',
              ],
              _inclusions),
          const Text('Deliverable quantity and format',
            style: TextStyle(color: _blue, fontWeight: FontWeight.w800)),
          for (final name in _inclusions.toList()..sort())
            Card(child: Padding(padding: const EdgeInsets.all(10),
              child: Column(children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                _text('Quantity',
                    _deliverableQty.putIfAbsent(name,
                        () => TextEditingController(text: '1')),
                    keyboardType: TextInputType.number),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: const ['JPG','PNG','MP4','PDF','RAW','Print','Other']
                      .contains(_deliverableFormat[name])
                      ? _deliverableFormat[name] : 'JPG',
                  decoration: const InputDecoration(labelText: 'Format'),
                  items: [
                    for (final name in const ['JPG','PNG','MP4','PDF','RAW','Print','Other'])
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (v) =>
                    setState(() => _deliverableFormat[name] = v ?? 'JPG'),
                ),
              ]),
            )),
          _text('Additional album, print and delivery details',
              _deliverables, lines: 4),
        ]);
      case 5:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _picks(
              'Optional services (priced separately by vendor quote)',
              const [
                'Drone / Helicam',
                'Live Streaming',
                'Extra Photographer',
                'Extra Videographer',
                'Photo Booth',
                'Extra Hour'
              ],
              _extras),
          const Text(
              'These extras are requests, not included in the base price.',
              style: TextStyle(color: Colors.blueGrey)),
        ]);
      case 6:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Set timelines for included deliverables',
            style: TextStyle(color: _blue, fontWeight: FontWeight.w800)),
          for (final name in _inclusions.toList()..sort())
            _text('$name — delivery within (days)',
              _deliveryDays.putIfAbsent(name,
                () => TextEditingController(text: '15')),
              keyboardType: TextInputType.number),
          _text('Other delivery details', _delivery, lines: 4),
        ]);
      case 7:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Payment split (%)',
              style: TextStyle(fontWeight: FontWeight.w800, color: _blue)),
          const SizedBox(height: 10),
          for (var i = 0; i < _stageNames.length; i++)
            Row(children: [
              Expanded(flex: 3, child: _text('Stage ${i + 1}', _stageNames[i])),
              const SizedBox(width: 8),
              Expanded(
                  child: _text('%', _stageValues[i],
                      keyboardType: TextInputType.number)),
            ]),
          Row(children: [
            TextButton.icon(
                onPressed: _stageNames.length >= 6
                    ? null
                    : () => setState(() => _addStage('Final payment', '0')),
                icon: const Icon(Icons.add),
                label: const Text('Add stage')),
            if (_stageNames.length > 1)
              TextButton(
                  onPressed: () => setState(() {
                        final name = _stageNames.removeLast();
                        final pct = _stageValues.removeLast();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          name.dispose();
                          pct.dispose();
                        });
                      }),
                  child: const Text('Remove last')),
          ]),
          const SizedBox(height: 12),
          _text('Cancellation and rescheduling policies', _policy, lines: 4),
        ]);
      case 8:
        return Column(children: [
          _text('Customer requirements and instructions', _requirements,
              lines: 5),
          const Text(
              'These will be included in the package description for owners.'),
        ]);
      default:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_name.text.trim(),
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 20, color: _blue)),
          Text('$_level · ${eventMoneyShort()}'),
          const SizedBox(height: 12),
          Text('Functions: ${_functions.join(', ')}'),
          Text('Ceremonies: ${_ceremonies.join(', ')}'),
          Text('Included: ${_inclusions.join(', ')}'),
          Text('Extras: ${_extras.join(', ')}'),
          Text('Deliverables: ${_deliverables.text}'),
          Text('Delivery: ${_delivery.text}'),
          const SizedBox(height: 12),
          SwitchListTile(
              title: const Text('Visible to customers'),
              subtitle: const Text('Turn off to save a private draft.'),
              value: _active,
              onChanged: (v) => setState(() => _active = v)),
          const Text(
              'Saving the package writes catalogue JSON to the Rust API. '
              'Payment collection and final service delivery are separate flows.',
              style: TextStyle(color: Colors.blueGrey)),
        ]);
    }
  }

  String eventMoneyShort() {
    final value = int.tryParse(_price.text.trim()) ?? 0;
    return '₹${_offerPrice ?? value}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _blue,
          title: const Text('Gixbee | Photography'),
        ),
        body: SafeArea(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(children: [
                Text('Step ${_step + 1}/${_steps.length} · ${_steps[_step]}',
                    style: const TextStyle(
                        color: _blue, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                    value: (_step + 1) / _steps.length,
                    color: _green,
                    backgroundColor: const Color(0xFFE5E7EB)),
              ])),
          Expanded(
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                  children: [_stepBody()])),
          if (_saveError != null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_saveError!, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red,
                    fontWeight: FontWeight.w700))),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(children: [
                if (_step > 0) ...[
                  OutlinedButton(
                      onPressed: _saving ? null :
                          () => setState(() => _step--),
                      child: const Text('Back')),
                  const SizedBox(width: 10),
                ],
                if (_step == _steps.length - 1) ...[
                  TextButton(
                    onPressed: _saving ? null : () => _save(draft: true),
                    child: const Text('Save draft'),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                    child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      padding: const EdgeInsets.symmetric(vertical: 15)),
                  onPressed: _saving ? null : _advance,
                  child: Text(
                      _step == _steps.length - 1 ? 'Save Package' : 'Next →'),
                )),
              ])),
        ])),
      );
}
