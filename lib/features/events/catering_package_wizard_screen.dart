import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// Categories from the Catering Owner HTML flow. Stored as stable IDs so
/// package selection works even when the display labels change.
class CateringMenuGroups {
  static const all = <CateringMenuGroup>[
    CateringMenuGroup('g01', 'Welcome Drinks', 'Juices, mocktails, etc.', '🥤', Color(0xFF0796D2)),
    CateringMenuGroup('g02', 'Starters & Snacks', 'Veg & non-veg starters', '🥟', Color(0xFFF26A12)),
    CateringMenuGroup('g03', 'Rice, Biriyani & Mandi', 'Rice items, biryani, mandi, pulao, etc.', '🍚', Color(0xFF12B76A)),
    CateringMenuGroup('g04', 'Breads & Rotis', 'Porotta, chapati, naan, etc.', '🫓', Color(0xFFE83540)),
    CateringMenuGroup('g05', 'Curries & Gravies', 'Veg & non-veg curries, gravies', '🍲', Color(0xFFE5A000)),
    CateringMenuGroup('g06', 'Vegetables & Thoran', 'Vegetable dishes, thoran, mezhukkupuratti, etc.', '🥬', Color(0xFF9448EF)),
    CateringMenuGroup('g07', 'Accompaniments', 'Salads, chutney, pickle, pappadam, etc.', '🥗', Color(0xFF0F9F92)),
    CateringMenuGroup('g08', 'Desserts & Sweets', 'Payasam, sweets, ice cream, etc.', '🍨', Color(0xFFDB4C92)),
    CateringMenuGroup('g09', 'Special Live Counters', 'Dosa, chaat, BBQ, and more', '👨‍🍳', Color(0xFF64748B)),
    CateringMenuGroup('other', 'Other Dishes', 'Uncategorized dishes from your catalogue', '🍽️', Color(0xFF64748B)),
  ];

  static String classify(Map<String, dynamic> dish) {
    final raw = (dish['category'] ?? '').toString().trim().toLowerCase();
    for (final group in all) {
      if (raw == group.id || raw == group.title.toLowerCase()) return group.id;
    }
    if (raw.contains('drink') || raw.contains('juice')) return 'g01';
    if (raw.contains('starter') || raw.contains('snack')) return 'g02';
    if (raw.contains('rice') || raw.contains('biriyani') || raw.contains('biryani') || raw.contains('mandi')) return 'g03';
    if (raw.contains('bread') || raw.contains('roti') || raw.contains('naan') || raw.contains('porotta')) return 'g04';
    if (raw.contains('curry') || raw.contains('grav')) return 'g05';
    if (raw.contains('vegetable') || raw.contains('thoran')) return 'g06';
    if (raw.contains('accompan') || raw.contains('pickle') || raw.contains('salad')) return 'g07';
    if (raw.contains('dessert') || raw.contains('sweet') || raw.contains('payasam')) return 'g08';
    if (raw.contains('live') || raw.contains('counter')) return 'g09';
    return 'other';
  }
}

class CateringMenuGroup {
  const CateringMenuGroup(this.id, this.title, this.hint, this.emoji, this.color);
  final String id;
  final String title;
  final String hint;
  final String emoji;
  final Color color;
}

class CateringPackageWizardScreen extends StatefulWidget {
  const CateringPackageWizardScreen({
    super.key,
    required this.dishes,
    this.package,
  });

  final List<Map<String, dynamic>> dishes;
  final Map<String, dynamic>? package;

  @override
  State<CateringPackageWizardScreen> createState() =>
      _CateringPackageWizardScreenState();
}

class _PriceTier {
  _PriceTier({int min = 1, int max = 1000, int? price})
      : minGuests = TextEditingController(text: '$min'),
        maxGuests = TextEditingController(text: '$max'),
        pricePerPlate = TextEditingController(text: price?.toString() ?? '');

  final TextEditingController minGuests;
  final TextEditingController maxGuests;
  final TextEditingController pricePerPlate;

  Map<String, int>? get value {
    final min = int.tryParse(minGuests.text);
    final max = int.tryParse(maxGuests.text);
    final price = int.tryParse(pricePerPlate.text);
    if (min == null || max == null || price == null ||
        min < 1 || max < min || max > 100000 || price < 1 || price > 10000000) {
      return null;
    }
    return {'minGuests': min, 'maxGuests': max, 'price': price};
  }

  void dispose() {
    minGuests.dispose();
    maxGuests.dispose();
    pricePerPlate.dispose();
  }
}

class _CateringPackageWizardScreenState
    extends State<CateringPackageWizardScreen> {
  static const _navy = Color(0xFF1B2559);
  static const _green = Color(0xFF12B76A);
  static const _pink = Color(0xFFBE185D);
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _search = TextEditingController();
  final _flatPrice = TextEditingController();
  final _discount = TextEditingController();
  final _tiers = <_PriceTier>[];
  final _dishIds = <String>{};

  int _step = 0;
  String _eventCategory = 'Wedding & Related Functions';
  String _level = 'Basic';
  String _diet = 'mixed';
  String _serve = 'buffet';
  String? _expandedGroup;
  bool _active = true;
  bool _flat = false;
  bool _offer = false;

  List<Map<String, dynamic>> get _dishes => widget.dishes
      .where((d) => d['kind'] == 'ITEM' && d['active'] != false && d['id'] is String)
      .toList();

  bool _allowed(Map<String, dynamic> dish) {
    if (_diet != 'veg') return true;
    final value = (dish['diet'] ?? '').toString().toLowerCase();
    return !value.contains('non') && !value.contains('meat');
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.package;
    _name.text = existing?['name']?.toString() ?? '';
    _description.text = existing?['description']?.toString() ?? '';
    _eventCategory = existing?['category']?.toString() ?? _eventCategory;
    _level = existing?['packageLevel']?.toString() ?? _level;
    _diet = existing?['diet']?.toString() == 'veg' ? 'veg' : 'mixed';
    final serve = existing?['serveStyle']?.toString();
    if (const ['table', 'buffet', 'both'].contains(serve)) _serve = serve!;
    _active = existing?['active'] != false;
    _dishIds.addAll((existing?['dishIds'] as List? ?? const [])
        .whereType<String>().where((id) => _dishes.any((d) => d['id'] == id)));
    final discount = (existing?['discountPct'] as num?)?.toInt() ?? 0;
    _offer = discount > 0;
    _discount.text = discount > 0 ? '$discount' : '';
    final base = (existing?['baseTiers'] as List?) ??
        (existing?['tiers'] as List?) ?? const [];
    for (final t in base.whereType<Map>()) {
      _tiers.add(_PriceTier(
        min: (t['minGuests'] as num?)?.toInt() ?? 1,
        max: (t['maxGuests'] as num?)?.toInt() ?? 1000,
        price: (t['price'] as num?)?.toInt(),
      ));
    }
    if (_tiers.isEmpty) _tiers.add(_PriceTier());
    _flat = _tiers.length == 1 && _tiers.first.minGuests.text == '1' &&
        _tiers.first.maxGuests.text == '100000';
    if (_flat) _flatPrice.text = _tiers.first.pricePerPlate.text;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _search.dispose();
    _flatPrice.dispose();
    _discount.dispose();
    for (final tier in _tiers) {
      tier.dispose();
    }
    super.dispose();
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool _validate() {
    switch (_step) {
      case 0:
        return _eventCategory.isNotEmpty;
      case 1:
        if (_name.text.trim().isEmpty || _name.text.trim().length > 150) {
          _notice('Enter a package name (up to 150 characters).');
          return false;
        }
        if (_description.text.trim().length > 3000) {
          _notice('Description is too long.');
          return false;
        }
        return true;
      case 2:
        if (_dishIds.isEmpty) {
          _notice('Select at least one dish. Add dishes to the catalogue first if needed.');
          return false;
        }
        return true;
      case 3:
        if (_offer) {
          final pct = int.tryParse(_discount.text);
          if (pct == null || pct < 1 || pct > 90) {
            _notice('Enter a discount between 1% and 90%.');
            return false;
          }
        }
        if (_flat) {
          final value = int.tryParse(_flatPrice.text);
          if (value == null || value < 1 || value > 10000000) {
            _notice('Enter a valid price per plate.');
            return false;
          }
        } else {
          if (_tiers.isEmpty || _tiers.length > 20) return false;
          final rows = _tiers.map((tier) => tier.value).toList();
          if (rows.any((row) => row == null)) {
            _notice('Enter valid guest ranges and plate prices.');
            return false;
          }
          final sorted = rows.cast<Map<String, int>>()
            ..sort((a, b) => a['minGuests']!.compareTo(b['minGuests']!));
          var end = 0;
          for (final row in sorted) {
            if (row['minGuests']! <= end) {
              _notice('Guest-count ranges must not overlap.');
              return false;
            }
            end = row['maxGuests']!;
          }
        }
        return true;
      default:
        return true;
    }
  }

  void _next() {
    if (!_validate()) return;
    if (_step == 4) {
      _finish();
    } else {
      setState(() => _step++);
    }
  }

  void _finish() {
    final base = _flat
        ? <Map<String, int>>[{
            'minGuests': 1,
            'maxGuests': 100000,
            'price': int.parse(_flatPrice.text)
          }]
        : _tiers.map((tier) => tier.value!).toList()
          ..sort((a, b) => a['minGuests']!.compareTo(b['minGuests']!));
    final pct = _offer ? int.parse(_discount.text) : 0;
    final billed = [
      for (final tier in base)
        {
          ...tier,
          'price': ((tier['price']! * (100 - pct) + 50) ~/ 100).clamp(1, 10000000),
        }
    ];
    final selected = _dishes.where((dish) => _dishIds.contains(dish['id'])).toList();
    Navigator.of(context).pop(<String, dynamic>{
      ...?widget.package,
      'id': widget.package?['id'] ?? const Uuid().v4(),
      'kind': 'PACKAGE',
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'category': _eventCategory,
      'packageLevel': _level,
      'diet': _diet,
      'serveStyle': _serve,
      'includes': selected.map((d) => d['name'].toString()).join(', '),
      'dishIds': selected.map((d) => d['id'].toString()).toList(),
      'baseTiers': base,
      'discountPct': pct,
      'tiers': billed,
      'active': _active,
      'paymentStages': widget.package?['paymentStages'] ?? '',
      'policy': widget.package?['policy'] ?? '',
    });
  }

  @override
  Widget build(BuildContext context) {
    const titles = [
      'Create Package',
      'Package Type & Name',
      'Add Menu Items',
      'Set Guest Count Pricing',
      'Preview Package'
    ];
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _navy,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('Gixbee', style: TextStyle(
              color: _green, fontSize: 15, fontWeight: FontWeight.w900)),
          const Text('  |  ', style: TextStyle(fontSize: 15, color: Colors.blueGrey)),
          Flexible(child: Text(titles[_step],
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
        ]),
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 10),
            child: Column(children: [
              Row(children: [
                for (var index = 0; index < 5; index++) ...[
                  if (index > 0) Expanded(child: Container(height: 2,
                      color: index <= _step ? _green : const Color(0xFFE5E7EB))),
                  Container(width: 17, height: 17,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index < _step ? _green : index == _step
                          ? _pink : Colors.white,
                      border: Border.all(
                          color: index <= _step ? Colors.transparent
                              : const Color(0xFFE5E7EB), width: 2.5)),
                  ),
                ]
              ]),
              const SizedBox(height: 7),
              Text('Step ${_step + 1} of 5',
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w700, color: _navy)),
            ]),
          ),
          Expanded(child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (_step == 0) _categoryStep(),
              if (_step == 1) _identityStep(),
              if (_step == 2) _menuStep(),
              if (_step == 3) _pricingStep(),
              if (_step == 4) _previewStep(),
            ],
          )),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(children: [
              if (_step > 0)
                OutlinedButton(
                  onPressed: () => setState(() => _step--),
                  child: const Text('← Back'),
                ),
              if (_step > 0) const SizedBox(width: 10),
              Expanded(child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _step == 4 ? const Color(0xFF2563EB) : _green,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: _next,
                child: Text(_step == 4 ? 'Save Package' : _step == 2
                  ? 'Next: Set Guest Count Pricing →' : 'Next →'),
              )),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _heading(String title, {String? hint}) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w900,
          color: _navy, fontSize: 16)),
      if (hint != null) Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(hint, style: const TextStyle(color: Colors.blueGrey, fontSize: 12))),
    ]),
  );

  Widget _categoryStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('Select Package Category *',
          hint: 'Choose the category that best describes this package.'),
      for (final (name, sub, emoji) in [
        ('Wedding & Related Functions', 'Wedding, engagement, reception and anniversary', '💍'),
        ('Other Functions', 'Birthday, baptism, housewarming, and more', '📅')
      ])
        Card(
          color: _eventCategory == name ? const Color(0xFFECFDF3) : Colors.white,
          child: RadioListTile<String>(
            value: name, groupValue: _eventCategory,
            secondary: Text(emoji, style: const TextStyle(fontSize: 27)),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(sub),
            onChanged: (v) => setState(() => _eventCategory = v ?? name),
          ),
        ),
    ]);
  }

  Widget _identityStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(_eventCategory),
      _heading('Package Type *'),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'Basic', label: Text('Basic')),
          ButtonSegment(value: 'Standard', label: Text('Standard')),
          ButtonSegment(value: 'Premium', label: Text('Premium')),
        ],
        selected: {_level},
        onSelectionChanged: (value) => setState(() => _level = value.first),
      ),
      _heading('Food Preference *'),
      Wrap(spacing: 8, children: [
        ChoiceChip(label: const Text('🟢 Vegetarian only'), selected: _diet == 'veg',
            onSelected: (_) => setState(() {
              _diet = 'veg';
              _dishIds.removeWhere((id) => !_allowed(
                  _dishes.firstWhere((d) => d['id'] == id)));
            })),
        ChoiceChip(label: const Text('🟢🟠 Veg + Non-vegetarian'),
            selected: _diet == 'mixed',
            onSelected: (_) => setState(() => _diet = 'mixed')),
      ]),
      _heading('Serving Style *',
          hint: 'Choose how guests receive the food. Plate price stays the same.'),
      for (final option in const [
        ('table', 'Traditional Table Service'),
        ('buffet', 'Buffet Service'),
        ('both', 'Both'),
      ])
        RadioListTile<String>(
          dense: true, contentPadding: EdgeInsets.zero,
          value: option.$1, groupValue: _serve, title: Text(option.$2),
          onChanged: (v) => setState(() => _serve = v ?? _serve),
        ),
      TextField(controller: _name, maxLength: 150,
          decoration: const InputDecoration(labelText: 'Package Name *',
              hintText: 'Wedding Feast', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: _description, maxLines: 3, maxLength: 3000,
          decoration: const InputDecoration(
            labelText: 'Description (optional)', border: OutlineInputBorder())),
    ],
  );

  Widget _menuStep() {
    final visible = _dishes.where(_allowed).toList();
    final selected = visible.where((d) => _dishIds.contains(d['id'])).toList();
    final veg = selected.where((d) => _allowedByDiet(d)).length;
    final nonVeg = selected.length - veg;
    final term = _search.text.trim().toLowerCase();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF0FDF4),
                border: Border.all(color: const Color(0xFFBBF7D0)),
                borderRadius: BorderRadius.circular(13)),
            child: Row(children: [
              Expanded(child: Text(
                _diet == 'veg' ? '🟢  Vegetarian only' : '🟢🟠  Veg + Non-vegetarian',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
              Text(_serve == 'buffet' ? '🍽 Buffet Service' :
                _serve == 'table' ? '🍽 Table Service' : '🍽 Both',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ]),
          ),
          const SizedBox(height: 14),
          Container(width: double.infinity, padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: const Color(0xFFFFF1F5),
                borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Text('🍴  Your Selected Menu',
                    style: TextStyle(fontWeight: FontWeight.w900, color: _navy))),
                Text('${selected.length} Dishes',
                    style: const TextStyle(fontSize: 11,
                        color: _pink, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 7),
              Text('Veg: $veg · Non-veg: $nonVeg\nSelect dishes from the categories below.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF49668C))),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Search dish groups or dishes...',
          prefixIcon: const Icon(Icons.search, color: Color(0xFF60A5FA)),
          suffixIcon: term.isEmpty ? null : IconButton(
            onPressed: () => setState(_search.clear),
            icon: const Icon(Icons.close)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(13))),
      ),
      const SizedBox(height: 10),
      for (final group in CateringMenuGroups.all)
        if (term.isEmpty ||
            group.title.toLowerCase().contains(term) ||
            visible.any((dish) => CateringMenuGroups.classify(dish) == group.id &&
                dish['name'].toString().toLowerCase().contains(term)))
          _groupCard(group, visible.where((d) =>
              CateringMenuGroups.classify(d) == group.id &&
              (term.isEmpty || group.title.toLowerCase().contains(term) ||
               d['name'].toString().toLowerCase().contains(term))).toList()),
      if (visible.isEmpty)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('No individual dishes available. Add dishes in Menu & packages, save the catalogue, then create a package.'),
        ),
    ]);
  }

  bool _allowedByDiet(Map<String, dynamic> dish) {
    final raw = (dish['diet'] ?? '').toString().toLowerCase();
    return !raw.contains('non') && !raw.contains('meat');
  }

  Widget _groupCard(CateringMenuGroup group, List<Map<String, dynamic>> dishes) {
    final selected = dishes.where((d) => _dishIds.contains(d['id'])).length;
    final expanded = _expandedGroup == group.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(15)),
      color: Colors.white,
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => setState(() =>
            _expandedGroup = expanded ? null : group.id),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Row(children: [
              Container(height: 52, width: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: group.color, borderRadius: BorderRadius.circular(12)),
                child: Text(group.emoji, style: const TextStyle(fontSize: 27)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.title, style: const TextStyle(
                      fontSize: 13, color: _navy, fontWeight: FontWeight.w900)),
                  Text(group.hint, style: const TextStyle(
                      fontSize: 10, color: Color(0xFF64748B))),
                ],
              )),
              Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    color: const Color(0xFFFFF1F5)),
                child: Text('$selected dishes',
                    style: const TextStyle(color: _pink,
                        fontWeight: FontWeight.w900, fontSize: 10)),
              ),
              Icon(expanded ? Icons.keyboard_arrow_up : Icons.chevron_right,
                  color: const Color(0xFFCBD5E1)),
            ]),
          ),
        ),
        if (expanded) ...[
          const Divider(height: 1),
          if (dishes.isEmpty)
            const Padding(padding: EdgeInsets.all(15),
                child: Text('No dishes in this group yet. Create an individual dish first.')),
          for (final dish in dishes)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(dish['name'].toString()),
              subtitle: Text(_allowedByDiet(dish) ? 'Vegetarian' : 'Non-vegetarian'),
              value: _dishIds.contains(dish['id']),
              onChanged: (checked) => setState(() {
                final id = dish['id'] as String;
                if (checked == true) {
                  _dishIds.add(id);
                } else {
                  _dishIds.remove(id);
                }
              }),
            ),
        ],
      ]),
    );
  }

  Widget _pricingStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('Price per plate'),
      RadioListTile<bool>(
        title: const Text('Rate reduces as guest count increases'),
        subtitle: const Text('Lower price for larger groups.'),
        value: false, groupValue: _flat,
        onChanged: (_) => setState(() => _flat = false)),
      RadioListTile<bool>(
        title: const Text('Same rate for all guests'),
        subtitle: const Text('One price for every guest count.'),
        value: true, groupValue: _flat,
        onChanged: (_) => setState(() => _flat = true)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Offer for customers'),
        subtitle: const Text('Show a discounted price per plate.'),
        value: _offer, onChanged: (v) => setState(() => _offer = v)),
      if (_offer)
        TextField(controller: _discount, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Discount (%)',
              border: OutlineInputBorder()),
        ),
      const SizedBox(height: 16),
      if (_flat)
        TextField(controller: _flatPrice, keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Price per plate (₹)', border: OutlineInputBorder()))
      else ...[
        for (final (index, tier) in _tiers.indexed)
          Card(key: ObjectKey(tier),
            child: Padding(padding: const EdgeInsets.all(12),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Text('Guest slab ${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold))),
                  if (_tiers.length > 1)
                    IconButton(onPressed: () => setState(() {
                      _tiers.removeAt(index);
                      WidgetsBinding.instance.addPostFrameCallback((_) => tier.dispose());
                    }), icon: const Icon(Icons.remove_circle_outline)),
                ]),
                Row(children: [
                  for (final (label, controller) in [
                    ('From', tier.minGuests), ('To', tier.maxGuests),
                    ('₹ / plate', tier.pricePerPlate),
                  ])
                    Expanded(child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: TextField(controller: controller,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: label,
                            border: const OutlineInputBorder())),
                    )),
                ]),
              ]),
            ),
          ),
        TextButton.icon(
          onPressed: _tiers.length >= 20 ? null : () => setState(() {
            final last = int.tryParse(_tiers.last.maxGuests.text) ?? 0;
            final start = (last + 1).clamp(1, 100000);
            _tiers.add(_PriceTier(min: start,
                max: (start + 499).clamp(start, 100000)));
          }),
          icon: const Icon(Icons.add),
          label: const Text('Add Another Slab'),
        ),
      ],
      const Text('Prices are saved to the Rust catalogue as guest-count tiers.'),
    ],
  );

  Widget _previewStep() {
    final count = _dishIds.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('Review your package'),
      Card(child: Padding(padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$_level – ${_name.text.trim()}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text(_eventCategory),
          Text(_diet == 'veg' ? 'Vegetarian only' : 'Veg + Non-vegetarian'),
          Text(_serve == 'buffet' ? 'Buffet Service'
              : _serve == 'table' ? 'Traditional Table Service' : 'Both'),
          Text('$count dishes selected'),
          const Divider(),
          Text(_description.text.trim()),
          const SizedBox(height: 10),
          for (final dish in _dishes.where((d) => _dishIds.contains(d['id'])))
            Text('• ${dish['name']}'),
          const Divider(),
          Text(_flat ? 'Flat rate ₹${_flatPrice.text} per plate'
                  : '${_tiers.length} guest-count price slabs',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (_offer) Text('${_discount.text}% discount applied to the saved plate prices'),
        ]),
      )),
      _heading('Publish Your Package'),
      RadioListTile<bool>(
        value: true, groupValue: _active,
        title: const Text('Live'),
        subtitle: const Text('Visible to customers after catalogue save.'),
        onChanged: (_) => setState(() => _active = true)),
      RadioListTile<bool>(
        value: false, groupValue: _active,
        title: const Text('Draft'),
        subtitle: const Text('Keep the package private.'),
        onChanged: (_) => setState(() => _active = false)),
    ]);
  }
}
