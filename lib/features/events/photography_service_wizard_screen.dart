import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// Eight-step individual photography service setup, following the uploaded
/// Photography Owner reference. Uses the existing Rust catalogue ITEM contract.
class PhotographyServiceWizardScreen extends StatefulWidget {
  const PhotographyServiceWizardScreen({super.key, this.service});
  final Map<String, dynamic>? service;

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
    _price.text = item['price']?.toString() ?? '';
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
      _name, _description, _price, _duration, _coverage, _team,
      _includes, _extras, _delivery, _policy, _requirements,
    ]) { c.dispose(); }
    super.dispose();
  }

  Widget _field(TextEditingController ctrl, String label,
      {int lines = 1, TextInputType? input}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: ctrl,
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

  void _error(String message) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(message)));

  void _next() {
    if (_step == 1 && _name.text.trim().isEmpty) {
      _error('Enter the service name.'); return;
    }
    if (_step == 2 && ((int.tryParse(_price.text) ?? 0) < 1 ||
        (int.tryParse(_price.text) ?? 0) > 10000000)) {
      _error('Enter a price between ₹1 and ₹1,00,00,000.'); return;
    }
    if (_step == 7) { _save(); return; }
    setState(() => _step++);
  }

  void _save() {
    final item = <String, dynamic>{
      ...?widget.service,
      'id': widget.service?['id'] ?? const Uuid().v4(),
      'kind': 'ITEM',
      'active': _active,
      'category': _category,
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'price': int.parse(_price.text),
      'duration': _duration.text.trim(),
      'coverageNotes': _coverage.text.trim(),
      'team': _team.text.trim(),
      'includes': _includes.text.trim(),
      'extrasNotes': _extras.text.trim(),
      'delivery': _delivery.text.trim(),
      'policy': _policy.text.trim(),
      'customerRequirements': _requirements.text.trim(),
      'paymentStages': widget.service?['paymentStages'] ?? '',
    };
    Navigator.pop(context, item);
  }

  Widget _stepWidget() {
    switch (_step) {
      case 0: return Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Choose the kind of non-wedding shoot or service.',
              style: TextStyle(color: Colors.blueGrey)),
          const SizedBox(height: 16),
          for (final type in const [
            'Portrait & Family', 'Baby & Maternity', 'Product Photography',
            'Corporate & Commercial', 'Birthday & Celebration',
            'Funeral / Memorial', 'Baptism / First Communion',
            'Event / Get-togethers', 'Other Photography',
          ])
            RadioListTile<String>(
              value: type,
              groupValue: _category,
              title: Text(type),
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
        ]);
      case 1: return Column(children: [
        _field(_name, 'Service name *'),
        _field(_description, 'Describe this service', lines: 4),
      ]);
      case 2: return Column(children: [
        _field(_price, 'Fixed price (₹) *', input: TextInputType.number),
        const Text('Optional additions are priced separately in the vendor quote.'),
      ]);
      case 3: return Column(children: [
        _field(_duration, 'Included duration (e.g. 4 Hours)'),
        _field(_coverage, 'Location, coverage and extra time', lines: 4),
        _field(_team, 'Team & equipment included', lines: 3),
      ]);
      case 4: return Column(children: [
        _field(_includes, 'Edited photos, videos, gallery, prints, etc.', lines: 5),
      ]);
      case 5: return Column(children: [
        _field(_extras, 'Optional extras and prices', lines: 5),
        const Text('Extras are negotiated after the customer sends interest.'),
      ]);
      case 6: return Column(children: [
        _field(_delivery, 'Delivery deadlines and format', lines: 5),
      ]);
      default: return Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(_policy, 'Cancellation / rescheduling policies', lines: 4),
          _field(_requirements, 'Customer requirements', lines: 4),
          const Divider(height: 28),
          Text(_name.text.trim(), style: const TextStyle(
              color: _navy, fontWeight: FontWeight.w900, fontSize: 18)),
          Text(_category),
          Text('₹${_price.text.trim()}'),
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
    body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        Text('Step ${_step + 1}/8 · ${_steps[_step]}',
            style: const TextStyle(color: _navy,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (_step + 1) / _steps.length,
          color: _accent,
          backgroundColor: const Color(0xFFE5E7EB)),
      ])),
      Expanded(child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [_stepWidget()],
      )),
      Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Row(children: [
          if (_step > 0) ...[
            OutlinedButton(onPressed: () => setState(() => _step--),
                child: const Text('Back')),
            const SizedBox(width: 10),
          ],
          Expanded(child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: _next,
            child: Text(_step == 7 ? 'Save Service' : 'Next →'),
          )),
        ]),
      ),
    ])),
  );
}
