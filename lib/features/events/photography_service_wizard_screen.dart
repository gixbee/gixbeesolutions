import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'photography_owner_pricing.dart';

/// Eight-step individual photography service setup, following the uploaded
/// Photography Owner reference. Uses the existing Rust catalogue ITEM contract.
class PhotographyServiceWizardScreen extends StatefulWidget {
  const PhotographyServiceWizardScreen({super.key, this.service, this.onSave});
  final Map<String, dynamic>? service;
  final Future<bool> Function(Map<String, dynamic> item)? onSave;

  @override
  State<PhotographyServiceWizardScreen> createState() =>
      _PhotographyServiceWizardScreenState();
}

class _PhotographyServiceWizardScreenState
    extends State<PhotographyServiceWizardScreen> {
  static const _navy = Color(0xFF1B2559);
  static const _accent = Color(0xFF12B76A);
  static const _steps = [
    'Select service category',
    'Service basics',
    'Pricing',
    'Duration & coverage',
    "What's included",
    'Optional extras',
    'Delivery',
    'Policies, requirements & review',
  ];
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _discount = TextEditingController(text: '0');
  final _extraHour = TextEditingController();
  final _deliverableQty = <String, TextEditingController>{};
  final _deliveryDays = <String, TextEditingController>{};
  final _deliverables = <String>{};
  bool _discountEnabled = false;
  bool _saving = false;
  String? _saveError;
  final _duration = TextEditingController();
  final _coverage = TextEditingController();
  final _team = TextEditingController();
  final _includes = TextEditingController();
  final _extras = TextEditingController();
  final _delivery = TextEditingController();
  final _policy = TextEditingController();
  final _requirements = TextEditingController();
  late String _category;
  bool _active = true;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    final item = widget.service ?? {};
    _name.text = item['name']?.toString() ?? '';
    _description.text = item['description']?.toString() ?? '';
    _price.text = (item['listPrice'] ?? item['price'])?.toString() ?? '';
    _discount.text = (item['discountPct'] ?? 0).toString();
    _discountEnabled = (item['discountPct'] as num? ?? 0) > 0;
    _extraHour.text = (item['extraHourPrice'] ?? '').toString();
    _deliverables.addAll((item['inclusions'] as List? ?? const []).whereType<String>());
    final details = item['deliverableDetails'] as Map? ?? {};
    final timelines = item['deliveryTimelines'] as Map? ?? {};
    for (final name in _deliverables) {
      final detail = details[name] as Map? ?? {};
      final time = timelines[name] as Map? ?? {};
      _deliverableQty[name] = TextEditingController(text: (detail['quantity'] ?? 1).toString());
      _deliveryDays[name] = TextEditingController(text: (time['days'] ?? 5).toString());
    }
    _duration.text = item['duration']?.toString() ?? '';
    _coverage.text = item['coverageNotes']?.toString() ?? '';
    _team.text = item['team']?.toString() ?? '';
    _includes.text = item['includes']?.toString() ?? '';
    _extras.text = item['extrasNotes']?.toString() ?? '';
    _delivery.text = item['delivery']?.toString() ?? '';
    _policy.text = item['policy']?.toString() ?? '';
    _requirements.text = item['customerRequirements']?.toString() ?? '';
    _category = item['category']?.toString() ?? 'Portrait & Family';
    _active = item['active'] != false;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _price,
      _discount,
      _extraHour,
      ..._deliverableQty.values,
      ..._deliveryDays.values,
      _duration,
      _coverage,
      _team,
      _includes,
      _extras,
      _delivery,
      _policy,
      _requirements,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(TextEditingController ctrl, String label,
          {int lines = 1, TextInputType? input}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          onChanged: (_) => setState(() {}),
          maxLength: lines == 1 ? 150 : 1000,
          keyboardType: input,
          maxLines: lines,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            alignLabelWithHint: lines > 1,
          ),
        ),
      );

  int? get _offerPrice => PhotographyOwnerPrice.discounted(
    int.tryParse(_price.text.trim()) ?? 0,
    _discountEnabled ? (int.tryParse(_discount.text.trim()) ?? -1) : 0);

  void _error(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  void _next() {
    if (_step == 1 && (_name.text.trim().isEmpty ||
        _name.text.trim().length > 150)) {
      _error('Enter the service name.');
      return;
    }
    if (_step == 2 &&
        ((int.tryParse(_price.text) ?? 0) < 1 ||
            (int.tryParse(_price.text) ?? 0) > 10000000 || _offerPrice == null)) {
      _error('Enter a price between ₹1 and ₹1,00,00,000.');
      return;
    }
    if (_step == 7) {
      _save();
      return;
    }
    setState(() => _step++);
  }

  Future<void> _save({bool draft = false}) async {
    if (_saving) return;
    if (_name.text.trim().isEmpty || _name.text.trim().length > 150 ||
        _offerPrice == null) {
      _error('Enter a service name and valid price/discount.');
      return;
    }
    for (final name in _deliverables) {
      final qty = int.tryParse(_deliverableQty[name]?.text ?? '1');
      final days = int.tryParse(_deliveryDays[name]?.text ?? '5');
      if (qty == null || qty < 1 || qty > 100000 ||
          days == null || days < 0 || days > 730) {
        _error('Check the quantity and delivery days for $name.');
        return;
      }
    }
    final item = <String, dynamic>{
      ...?widget.service,
      'id': widget.service?['id'] ?? const Uuid().v4(),
      'kind': 'ITEM',
      'active': draft ? false : _active,
      'category': _category,
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'listPrice': int.parse(_price.text.trim()),
      'discountPct': _discountEnabled ? int.parse(_discount.text.trim()) : 0,
      'price': _offerPrice,
      'duration': _duration.text.trim(),
      'extraHourPrice': int.tryParse(_extraHour.text.trim()) ?? 0,
      'coverageNotes': _coverage.text.trim(),
      'team': _team.text.trim(),
      'includes': _includes.text.trim(),
      'inclusions': _deliverables.toList()..sort(),
      'deliverableDetails': {
        for (final name in _deliverables)
          name: {'quantity': int.tryParse(_deliverableQty[name]?.text ?? '') ?? 1},
      },
      'deliveryTimelines': {
        for (final name in _deliverables)
          name: {'days': int.tryParse(_deliveryDays[name]?.text ?? '') ?? 5},
      },
      'extrasNotes': _extras.text.trim(),
      'delivery': _delivery.text.trim(),
      'policy': _policy.text.trim(),
      'customerRequirements': _requirements.text.trim(),
      'paymentStages': widget.service?['paymentStages'] ?? '',
    };
    final issue = PhotographyOwnerPrice.validate(item);
    if (issue != null) {
      _error(issue);
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
            'Service not saved. Check the catalogue and retry.');
      }
    } catch (_) {
      if (mounted) setState(() => _saveError =
          'Unable to contact the API. Your changes are still here.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _stepWidget() {
    switch (_step) {
      case 0:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Choose the kind of non-wedding shoot or service.',
              style: TextStyle(color: Colors.blueGrey)),
          const SizedBox(height: 16),
          RadioGroup<String>(
            groupValue: _category,
            onChanged: (v) {
              if (v != null) setState(() => _category = v);
            },
            child: Column(
              children: [
                for (final type in const [
                  'Portrait & Family',
                  'Baby & Maternity',
                  'Product Photography',
                  'Corporate & Commercial',
                  'Birthday & Celebration',
                  'Funeral / Memorial',
                  'Baptism / First Communion',
                  'Event / Get-togethers',
                  'Other Photography',
                ])
                  RadioListTile<String>(
                    value: type,
                    title: Text(type),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
        ]);
      case 1:
        return Column(children: [
          _field(_name, 'Service name *'),
          _field(_description, 'Describe this service', lines: 4),
        ]);
      case 2:
        return Column(children: [
          _field(_price, 'Service price incl. GST (₹) *', input: TextInputType.number),
          SwitchListTile(
            title: const Text('Offer a discount?'),
            value: _discountEnabled,
            onChanged: (v) => setState(() => _discountEnabled = v),
          ),
          if (_discountEnabled)
            _field(_discount, 'Discount % (1–90)', input: TextInputType.number),
          Card(
            color: const Color(0xFFECFDF3),
            child: Padding(padding: const EdgeInsets.all(12),
              child: Text('Customer will see ₹${_offerPrice ?? 0}',
                style: const TextStyle(color: _navy,
                  fontWeight: FontWeight.w900, fontSize: 18)),
            ),
          ),
          const Text('Optional additions are priced separately in the vendor quote.'),
        ]);
      case 3:
        return Column(children: [
          _field(_duration, 'Included duration (e.g. 4 Hours)'),
          _field(_coverage, 'Location, coverage and extra time', lines: 4),
          _field(_team, 'Team & equipment included', lines: 3),
          _field(_extraHour, 'Additional hour charge (₹)',
              input: TextInputType.number),
        ]);
      case 4:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('What is included',
              style: TextStyle(color: _navy, fontWeight: FontWeight.w800)),
          Wrap(spacing: 8, children: [
            for (final label in const [
              'Edited Photos', 'Candid Photography', 'Traditional Photography',
              'Highlights Reel', 'Cinematic Video', 'Online Gallery',
              'Physical Album', 'Prints', 'RAW Files',
            ])
              FilterChip(
                label: Text(label),
                selected: _deliverables.contains(label),
                onSelected: (v) => setState(() {
                  if (v) { _deliverables.add(label); }
                  else { _deliverables.remove(label); }
                }),
              ),
          ]),
          for (final name in _deliverables.toList()..sort())
            _field(_deliverableQty.putIfAbsent(name,
                () => TextEditingController(text: '1')),
                '$name — quantity', input: TextInputType.number),
          _field(_includes, 'Additional inclusions / formats',
              lines: 4),
        ]);
      case 5:
        return Column(children: [
          _field(_extras, 'Optional extras and prices', lines: 5),
          const Text(
              'Extras are negotiated after the customer sends interest.'),
        ]);
      case 6:
        return Column(children: [
          for (final name in _deliverables.toList()..sort())
            _field(_deliveryDays.putIfAbsent(name,
                () => TextEditingController(text: '5')),
                '$name — delivery within (days)', input: TextInputType.number),
          _field(_delivery, 'Other delivery details', lines: 4),
        ]);
      default:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _field(_policy, 'Cancellation / rescheduling policies', lines: 4),
          _field(_requirements, 'Customer requirements', lines: 4),
          const Divider(height: 28),
          Text(_name.text.trim(),
              style: const TextStyle(
                  color: _navy, fontWeight: FontWeight.w900, fontSize: 18)),
          Text(_category),
          Text('₹${_offerPrice ?? 0}'),
          if (_includes.text.isNotEmpty)
            Text('Includes: ${_includes.text.trim()}'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Visible to customers'),
            subtitle: const Text('Turn off for a private draft.'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
        ]);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Gixbee | Individual Service'),
          backgroundColor: Colors.white,
          foregroundColor: _navy,
        ),
        body: SafeArea(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text('Step ${_step + 1}/8 · ${_steps[_step]}',
                    style: const TextStyle(
                        color: _navy, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                    value: (_step + 1) / _steps.length,
                    color: _accent,
                    backgroundColor: const Color(0xFFE5E7EB)),
              ])),
          Expanded(
              child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: [_stepWidget()],
          )),
          if (_saveError != null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_saveError!, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red,
                  fontWeight: FontWeight.w700))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Row(children: [
              if (_step > 0) ...[
                OutlinedButton(
                    onPressed: _saving ? null :
                      () => setState(() => _step--),
                    child: const Text('Back')),
                const SizedBox(width: 10),
              ],
              if (_step == 7) ...[
                TextButton(
                  onPressed: _saving ? null : () => _save(draft: true),
                  child: const Text('Save draft'),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                  child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: _saving ? null : _next,
                child: Text(_step == 7 ? 'Save Service' : 'Next →'),
              )),
            ]),
          ),
        ])),
      );
}
