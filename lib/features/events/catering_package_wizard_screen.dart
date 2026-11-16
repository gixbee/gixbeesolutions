import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'catering_price_math.dart';

/// Categories from the Catering Owner HTML flow. Stored as stable IDs so
/// package selection works even when the display labels change.
class CateringMenuGroups {
  static const all = <CateringMenuGroup>[
    CateringMenuGroup('g01', 'Welcome Drinks', 'Juices, mocktails, etc.', '🥤',
        Color(0xFF0796D2)),
    CateringMenuGroup('g02', 'Starters & Snacks', 'Veg & non-veg starters',
        '🥟', Color(0xFFF26A12)),
    CateringMenuGroup('g03', 'Rice, Biriyani & Mandi',
        'Rice items, biryani, mandi, pulao, etc.', '🍚', Color(0xFF12B76A)),
    CateringMenuGroup('g04', 'Breads & Rotis', 'Porotta, chapati, naan, etc.',
        '🫓', Color(0xFFE83540)),
    CateringMenuGroup('g05', 'Curries & Gravies',
        'Veg & non-veg curries, gravies', '🍲', Color(0xFFE5A000)),
    CateringMenuGroup(
        'g06',
        'Vegetables & Thoran',
        'Vegetable dishes, thoran, mezhukkupuratti, etc.',
        '🥬',
        Color(0xFF9448EF)),
    CateringMenuGroup('g07', 'Accompaniments',
        'Salads, chutney, pickle, pappadam, etc.', '🥗', Color(0xFF0F9F92)),
    CateringMenuGroup('g08', 'Desserts & Sweets',
        'Payasam, sweets, ice cream, etc.', '🍨', Color(0xFFDB4C92)),
    CateringMenuGroup('g09', 'Special Live Counters',
        'Dosa, chaat, BBQ, and more', '👨‍🍳', Color(0xFF64748B)),
    CateringMenuGroup('other', 'Other Dishes',
        'Uncategorized dishes from your catalogue', '🍽️', Color(0xFF64748B)),
  ];

  static String classify(Map<String, dynamic> dish) {
    final raw = (dish['category'] ?? '').toString().trim().toLowerCase();
    for (final group in all) {
      if (raw == group.id || raw == group.title.toLowerCase()) return group.id;
    }
    if (raw.contains('drink') || raw.contains('juice')) {
      return 'g01';
    }
    if (raw.contains('starter') || raw.contains('snack')) {
      return 'g02';
    }
    if (raw.contains('rice') ||
        raw.contains('biriyani') ||
        raw.contains('biryani') ||
        raw.contains('mandi')) {
      return 'g03';
    }
    if (raw.contains('bread') ||
        raw.contains('roti') ||
        raw.contains('naan') ||
        raw.contains('porotta')) {
      return 'g04';
    }
    if (raw.contains('curry') || raw.contains('grav')) {
      return 'g05';
    }
    if (raw.contains('vegetable') || raw.contains('thoran')) {
      return 'g06';
    }
    if (raw.contains('accompan') ||
        raw.contains('pickle') ||
        raw.contains('salad')) {
      return 'g07';
    }
    if (raw.contains('dessert') ||
        raw.contains('sweet') ||
        raw.contains('payasam')) {
      return 'g08';
    }
    if (raw.contains('live') || raw.contains('counter')) {
      return 'g09';
    }
    return 'other';
  }
}

class CateringMenuGroup {
  const CateringMenuGroup(
      this.id, this.title, this.hint, this.emoji, this.color);
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
    this.onSave,
  });

  final List<Map<String, dynamic>> dishes;
  final Map<String, dynamic>? package;
  final Future<bool> Function(Map<String, dynamic> entry)? onSave;

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
    if (min == null ||
        max == null ||
        price == null ||
        min < 1 ||
        max < min ||
        max > 100000 ||
        price < 1 ||
        price > 10000000) {
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
  bool _saving = false;
  String? _saveError;

  List<Map<String, dynamic>> get _dishes => widget.dishes
      .where((d) =>
          d['kind'] == 'ITEM' && d['active'] != false && d['id'] is String)
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
    final category = existing?['category']?.toString();
    _eventCategory = category == 'Other Functions' || category == 'other'
        ? 'Other Functions' : 'Wedding & Related Functions';
    final level = existing?['packageLevel']?.toString();
    _level = const ['Basic', 'Standard', 'Premium'].contains(level)
        ? level! : 'Basic';
    _diet = existing?['diet']?.toString() == 'veg' ? 'veg' : 'mixed';
    final serve = existing?['serveStyle']?.toString();
    if (const ['table', 'buffet', 'both'].contains(serve)) _serve = serve!;
    _active = existing?['active'] != false;
    _dishIds.addAll((existing?['dishIds'] as List? ?? const [])
        .whereType<String>()
        .where((id) => _dishes.any((d) => d['id'] == id)));
    final discount = (existing?['discountPct'] as num?)?.toInt() ?? 0;
    _offer = discount > 0;
    _discount.text = discount > 0 ? '$discount' : '';
    final base = (existing?['baseTiers'] as List?) ??
        (existing?['tiers'] as List?) ??
        const [];
    for (final t in base.whereType<Map>()) {
      _tiers.add(_PriceTier(
        min: (t['minGuests'] as num?)?.toInt() ?? 1,
        max: (t['maxGuests'] as num?)?.toInt() ?? 1000,
        price: (t['price'] as num?)?.toInt(),
      ));
    }
    if (_tiers.isEmpty) {
      for (final tier in CateringPriceMath.referenceSlabs) {
        _tiers.add(_PriceTier(
          min: tier['minGuests']!,
          max: tier['maxGuests']!,
          price: tier['price'],
        ));
      }
    }
    _flat = existing?['rateMode'] == 'flat' ||
        (existing?['rateMode'] == null &&
            _tiers.length == 1 &&
            _tiers.first.minGuests.text == '1' &&
            _tiers.first.maxGuests.text == '100000');
    _flatPrice.text = _tiers.first.pricePerPlate.text;
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

  List<Map<String, int>> _baseTiers() {
    final raw = _flat
        ? <Map<String, int>>[
            {
              'minGuests': 1,
              'maxGuests': CateringPriceMath.maxGuests,
              'price': int.tryParse(_flatPrice.text.trim()) ?? 0,
            },
          ]
        : _tiers.map((tier) => tier.value ?? <String, int>{}).toList();
    return CateringPriceMath.validateBaseTiers(raw);
  }

  int get _discountPct => _offer ? (int.tryParse(_discount.text.trim()) ?? -1) : 0;

  List<Map<String, int>>? _pricedTiers() {
    try {
      return CateringPriceMath.offerTiers(_baseTiers(), _discountPct);
    } on FormatException {
      return null;
    }
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
          _notice(
              'Select at least one dish. Add dishes to the catalogue first if needed.');
          return false;
        }
        return true;
      case 3:
        if (_offer && (_discountPct < 1 || _discountPct > 90)) {
          _notice('Enter a discount between 1% and 90%.');
          return false;
        }
        try {
          _baseTiers();
          return true;
        } on FormatException catch (error) {
          _notice(error.message);
          return false;
        }
      default:
        return true;
    }
  }

  void _next() {
    if (_saving || !_validate()) return;
    if (_step == 4) {
      _finish();
    } else {
      setState(() => _step++);
    }
  }

  Future<void> _finish() async {
    final base = _baseTiers();
    final pct = _discountPct;
    final billed = CateringPriceMath.offerTiers(base, pct);
    final selected =
        _dishes.where((dish) => _dishIds.contains(dish['id'])).toList();
    final result = <String, dynamic>{
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
      'rateMode': _flat ? 'flat' : 'tiered',
      'tiers': billed,
      'active': _active,
      'paymentStages': widget.package?['paymentStages'] ?? '',
      'policy': widget.package?['policy'] ?? '',
    };
    if (widget.onSave == null) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await widget.onSave!(result);
      if (!mounted) return;
      if (saved) {
        Navigator.of(context).pop();
      } else {
        setState(() => _saveError =
            'Package not saved. Check the error and retry.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saveError = 'Unable to save package. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
          const Text('Gixbee',
              style: TextStyle(
                  color: _green, fontSize: 15, fontWeight: FontWeight.w900)),
          const Text('  |  ',
              style: TextStyle(fontSize: 15, color: Colors.blueGrey)),
          Flexible(
              child: Text(titles[_step],
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800))),
        ]),
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 10),
            child: Column(children: [
              Row(children: [
                for (var index = 0; index < 5; index++) ...[
                  if (index > 0)
                    Expanded(
                        child: Container(
                            height: 2,
                            color: index <= _step
                                ? _green
                                : const Color(0xFFE5E7EB))),
                  Container(
                    width: 17,
                    height: 17,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index < _step
                            ? _green
                            : index == _step
                                ? _pink
                                : Colors.white,
                        border: Border.all(
                            color: index <= _step
                                ? Colors.transparent
                                : const Color(0xFFE5E7EB),
                            width: 2.5)),
                  ),
                ]
              ]),
              const SizedBox(height: 7),
              Text('Step ${_step + 1} of 5',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: _navy)),
            ]),
          ),
          Expanded(
              child: ListView(
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
          if (_saveError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(_saveError!, textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C), fontWeight: FontWeight.w700,
                  )),
            ),
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
              Expanded(
                  child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _step == 4 ? const Color(0xFF2563EB) : _green,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: _saving ? null : _next,
                child: _saving
                    ? const SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_step == 4
                    ? 'Save Package'
                    : _step == 2
                        ? 'Next: Set Guest Count Pricing →'
                        : 'Next →'),
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
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w900, color: _navy, fontSize: 16)),
          if (hint != null)
            Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(hint,
                    style:
                        const TextStyle(color: Colors.blueGrey, fontSize: 12))),
        ]),
      );

  Widget _categoryStep() {
    const categories = [
      (
        'Wedding & Related Functions',
        'Wedding, engagement, reception and anniversary',
        '💍',
      ),
      (
        'Other Functions',
        'Birthday, baptism, housewarming, and more',
        '📅',
      ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('Select Package Category *',
          hint: 'Choose the category that best describes this package.'),
      LayoutBuilder(builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final (name, sub, emoji) in categories)
            SizedBox(width: cardWidth, height: 178,
              child: Card(
                margin: EdgeInsets.zero,
                color: _eventCategory == name
                    ? const Color(0xFFECFDF3) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: _eventCategory == name
                        ? _green : const Color(0xFFE2E8F0),
                    width: _eventCategory == name ? 2 : 1,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _eventCategory = name),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(emoji, style: const TextStyle(fontSize: 33)),
                          const Spacer(),
                          if (_eventCategory == name)
                            const Icon(Icons.check_circle, color: _green),
                        ]),
                        const SizedBox(height: 10),
                        Text(name, maxLines: 2,
                            style: const TextStyle(
                              fontSize: 13, color: _navy,
                              fontWeight: FontWeight.w900)),
                        const SizedBox(height: 5),
                        Expanded(child: Text(sub,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF64748B), fontSize: 11))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ]);
      }),
    ]);
  }

  Widget _identityStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              border: Border.all(color: const Color(0xFFBBF7D0)),
              borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Text('📅  '),
              Expanded(child: Text(_eventCategory, style: const TextStyle(
                fontWeight: FontWeight.w800, color: _navy))),
              TextButton(
                onPressed: () => setState(() => _step = 0),
                child: const Text('Change')),
            ]),
          ),
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
            ChoiceChip(
                label: const Text('🟢 Vegetarian only'),
                selected: _diet == 'veg',
                onSelected: (_) => setState(() {
                      _diet = 'veg';
                      _dishIds.removeWhere((id) =>
                          !_allowed(_dishes.firstWhere((d) => d['id'] == id)));
                    })),
            ChoiceChip(
                label: const Text('🟢🟠 Veg + Non-vegetarian'),
                selected: _diet == 'mixed',
                onSelected: (_) => setState(() => _diet = 'mixed')),
          ]),
          _heading('Serving Style *',
              hint:
                  'Choose how guests receive the food. Plate price stays the same.'),
          RadioGroup<String>(
            groupValue: _serve,
            onChanged: (v) {
              if (v != null) setState(() => _serve = v);
            },
            child: Column(
              children: [
                for (final option in const [
                  ('table', 'Traditional Table Service'),
                  ('buffet', 'Buffet Service'),
                  ('both', 'Both'),
                ])
                  RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: option.$1,
                    title: Text(option.$2),
                  ),
              ],
            ),
          ),
          TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              maxLength: 150,
              decoration: const InputDecoration(
                  labelText: 'Package Name *',
                  hintText: 'Wedding Feast',
                  border: OutlineInputBorder())),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              'Customer preview: $_level – ${_name.text.trim().isEmpty ? 'Your package name' : _name.text.trim()}',
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w800),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              'Customer preview: $_level – ${_name.text.trim().isEmpty ? 'Your package name' : _name.text.trim()}',
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
              controller: _description,
              maxLines: 3,
              maxLength: 3000,
              decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder())),
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
        decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                border: Border.all(color: const Color(0xFFBBF7D0)),
                borderRadius: BorderRadius.circular(13)),
            child: Row(children: [
              Expanded(
                  child: Text(
                      _diet == 'veg'
                          ? '🟢  Vegetarian only'
                          : '🟢🟠  Veg + Non-vegetarian',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12))),
              Text(
                  _serve == 'buffet'
                      ? '🍽 Buffet Service'
                      : _serve == 'table'
                          ? '🍽 Table Service'
                          : '🍽 Both',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF1F5),
                borderRadius: BorderRadius.circular(14)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(
                    child: Text('🍴  Your Selected Menu',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, color: _navy))),
                Text('${selected.length} Dishes',
                    style: const TextStyle(
                        fontSize: 11,
                        color: _pink,
                        fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 7),
              Text(
                  'Veg: $veg · Non-veg: $nonVeg\nSelect dishes from the categories below.',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF49668C))),
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
            suffixIcon: term.isEmpty
                ? null
                : IconButton(
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.close)),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(13))),
      ),
      const SizedBox(height: 10),
      for (final group in CateringMenuGroups.all)
        if (term.isEmpty ||
            group.title.toLowerCase().contains(term) ||
            visible.any((dish) =>
                CateringMenuGroups.classify(dish) == group.id &&
                dish['name'].toString().toLowerCase().contains(term)))
          _groupCard(
              group,
              visible
                  .where((d) =>
                      CateringMenuGroups.classify(d) == group.id &&
                      (term.isEmpty ||
                          group.title.toLowerCase().contains(term) ||
                          d['name'].toString().toLowerCase().contains(term)))
                  .toList()),
      if (visible.isEmpty)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
              'No individual dishes available. Add dishes in Menu & packages, save the catalogue, then create a package.'),
        ),
    ]);
  }

  bool _allowedByDiet(Map<String, dynamic> dish) {
    final raw = (dish['diet'] ?? '').toString().toLowerCase();
    return !raw.contains('non') && !raw.contains('meat');
  }

  Widget _groupCard(
      CateringMenuGroup group, List<Map<String, dynamic>> dishes) {
    final selected = _dishes
        .where((dish) =>
            CateringMenuGroups.classify(dish) == group.id &&
            _dishIds.contains(dish['id']))
        .length;
    final expanded =
        _expandedGroup == group.id || _search.text.trim().isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(15)),
      color: Colors.white,
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () =>
              setState(() => _expandedGroup = expanded ? null : group.id),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Row(children: [
              Container(
                height: 52,
                width: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: group.color,
                    borderRadius: BorderRadius.circular(12)),
                child: Text(group.emoji, style: const TextStyle(fontSize: 27)),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.title,
                      style: const TextStyle(
                          fontSize: 13,
                          color: _navy,
                          fontWeight: FontWeight.w900)),
                  Text(group.hint,
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF64748B))),
                ],
              )),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    color: const Color(0xFFFFF1F5)),
                child: Text('$selected dishes',
                    style: const TextStyle(
                        color: _pink,
                        fontWeight: FontWeight.w900,
                        fontSize: 10)),
              ),
              Icon(expanded ? Icons.keyboard_arrow_up : Icons.chevron_right,
                  color: const Color(0xFFCBD5E1)),
            ]),
          ),
        ),
        if (expanded) ...[
          const Divider(height: 1),
          if (dishes.isEmpty)
            const Padding(
                padding: EdgeInsets.all(15),
                child: Text(
                    'No dishes in this group yet. Create an individual dish first.')),
          for (final dish in dishes)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(dish['name'].toString()),
              subtitle:
                  Text(_allowedByDiet(dish) ? 'Vegetarian' : 'Non-vegetarian'),
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

  void _toggleRate(bool flat) {
    setState(() {
      if (flat && !_flat) {
        final tierPrice = _tiers.isEmpty ? '' : _tiers.first.pricePerPlate.text;
        if (_flatPrice.text.trim().isEmpty) _flatPrice.text = tierPrice;
      }
      _flat = flat;
    });
  }

  Widget _offerPriceRow(String range, int original, int discounted) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(flex: 3, child: Text(range,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
          Expanded(flex: 3, child: Text('₹$original',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(flex: 4, child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_offer)
                Text('₹$original', style: const TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: Color(0xFF94A3B8), fontSize: 11)),
              Text('₹$discounted', textAlign: TextAlign.right,
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: _offer ? const Color(0xFF047857) : _navy)),
            ],
          )),
        ]),
      );

  Widget _pricePreview({bool compact = false}) {
    final priced = _pricedTiers();
    if (priced == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Enter valid guest ranges, prices and discount to preview.'),
      );
    }
    final base = _baseTiers();
    final exampleGuests = _flat ? 100 : base.first['minGuests']!;
    final examplePrice =
        CateringPriceMath.estimateForGuests(priced, exampleGuests);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Guest Pricing',
              style: TextStyle(color: _navy, fontWeight: FontWeight.w900))),
          if (_offer)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFCE7F3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${_discountPct}% off',
                  style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w900, color: _pink)),
            ),
        ]),
        const SizedBox(height: 10),
        const Row(children: [
          Expanded(flex: 3, child: Text('Guest Count',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
          Expanded(flex: 3, child: Text('Price / Plate',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
          Expanded(flex: 4, child: Text('Offer Price',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
        ]),
        const Divider(),
        for (var i = 0; i < priced.length; i++) ...[
          _offerPriceRow(
            _flat
                ? 'All guests'
                : '${base[i]['minGuests']}–${base[i]['maxGuests']}',
            base[i]['price']!,
            priced[i]['price']!,
          ),
          if (i < priced.length - 1) const Divider(height: 1),
        ],
        if (!compact && examplePrice != null) ...[
          const Divider(),
          Text('Example: $exampleGuests guests × ₹${priced.first['price']} '
              '= ₹$examplePrice',
              style: const TextStyle(fontSize: 12,
                  color: _navy, fontWeight: FontWeight.w800)),
        ],
      ]),
    );
  }

  Widget _pricingStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('Set Guest Count Pricing', hint:
          'The base plate price stays as entered. Offer prices are calculated separately.'),
      RadioGroup<bool>(
        groupValue: _flat,
        onChanged: (v) { if (v != null) _toggleRate(v); },
        child: const Column(children: [
          RadioListTile<bool>(
            title: Text('Rate reduces as guest count increases'),
            subtitle: Text('Lower price for higher guest count.'),
            value: false,
          ),
          RadioListTile<bool>(
            title: Text('Same rate for all guests'),
            subtitle: Text('One price for any guest count.'),
            value: true,
          ),
        ]),
      ),
      Card(
        color: _offer ? const Color(0xFFFFF1F5) : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: const BorderSide(color: Color(0xFFE2E8F0))),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Offer for customers',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Plate price stays as you type it. '
                  'Customers see a lower price.'),
              value: _offer,
              onChanged: (v) => setState(() {
                _offer = v ?? false;
                if (_offer && _discount.text.trim().isEmpty) {
                  _discount.text = '10';
                }
              }),
            ),
            if (_offer) ...[
              Row(children: [
                IconButton(
                  tooltip: 'Decrease discount',
                  onPressed: () => setState(() {
                    final n = int.tryParse(_discount.text) ?? 1;
                    _discount.text = '${(n - 1).clamp(1, 90)}';
                  }),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Expanded(child: TextField(
                  controller: _discount,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'Discount (%)',
                    border: OutlineInputBorder(),
                  ),
                )),
                IconButton(
                  tooltip: 'Increase discount',
                  onPressed: () => setState(() {
                    final n = int.tryParse(_discount.text) ?? 0;
                    _discount.text = '${(n + 1).clamp(1, 90)}';
                  }),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ]),
              const Padding(
                padding: EdgeInsets.only(top: 7, bottom: 4),
                child: Text('Type 1 to 90% off. Each plate price updates on its own.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
              ),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 13),
      if (_flat) ...[
        TextField(
          controller: _flatPrice,
          onChanged: (_) => setState(() {}),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Price per plate (₹)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 7),
        const Text('One rate for every guest count.',
            style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
      ] else ...[
        for (final (index, tier) in _tiers.indexed)
          Card(
            key: ObjectKey(tier),
            margin: const EdgeInsets.only(bottom: 9),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Text('Guest slab ${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w800))),
                  if (_tiers.length > 1)
                    IconButton(
                      tooltip: 'Remove slab',
                      onPressed: () => setState(() {
                        _tiers.removeAt(index);
                        WidgetsBinding.instance.addPostFrameCallback((_) =>
                            tier.dispose());
                      }),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                ]),
                Row(children: [
                  for (final (label, controller) in [
                    ('From', tier.minGuests),
                    ('To', tier.maxGuests),
                    ('₹ / plate', tier.pricePerPlate),
                  ])
                    Expanded(child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: TextField(
                        controller: controller,
                        onChanged: (_) => setState(() {}),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: label,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    )),
                ]),
              ]),
            ),
          ),
        TextButton.icon(
          onPressed: _tiers.length >= 20 ? null : () => setState(() {
            final last = int.tryParse(_tiers.last.maxGuests.text) ?? 0;
            if (last >= CateringPriceMath.maxGuests) {
              _notice('Maximum supported guest count reached.');
              return;
            }
            final start = last + 1;
            final previousPrice =
                int.tryParse(_tiers.last.pricePerPlate.text) ?? 500;
            _tiers.add(_PriceTier(
              min: start,
              max: (start + 24).clamp(start, CateringPriceMath.maxGuests).toInt(),
              price: (previousPrice - 50).clamp(1, CateringPriceMath.maxPlatePrice).toInt(),
            ));
          }),
          icon: const Icon(Icons.add),
          label: const Text('Add Another Slab'),
        ),
      ],
      const SizedBox(height: 12),
      _pricePreview(),
    ]);
  }

  Widget _previewStep() {
    final selected = _dishes
        .where((dish) => _dishIds.contains(dish['id']))
        .toList();
    final count = selected.length;
    final veg = selected.where(_allowedByDiet).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Row(children: [
          const Text('🍛  ', style: TextStyle(fontSize: 31)),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$_level – ${_name.text.trim()}',
                  style: const TextStyle(color: _navy, fontSize: 17,
                      fontWeight: FontWeight.w900)),
              Text(_diet == 'veg' ? 'Vegetarian only' : 'Veg + Non-vegetarian'),
              Text(_serve == 'buffet' ? 'Buffet Service'
                  : _serve == 'table'
                    ? 'Traditional Table Service' : 'Both'),
              Text(_eventCategory,
                  style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
            ],
          )),
        ]),
      ),
      if (_description.text.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(_description.text.trim()),
        ),
      _heading('🍴  Menu Summary', hint:
        'Total: $count dishes · $veg veg · ${count - veg} non-veg'),
      for (final group in CateringMenuGroups.all)
        if (selected.any((dish) =>
            CateringMenuGroups.classify(dish) == group.id))
          Card(
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              leading: Container(
                height: 40, width: 40, alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: group.color,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(group.emoji, style: const TextStyle(fontSize: 23)),
              ),
              title: Text(group.title,
                  style: const TextStyle(color: _navy,
                      fontWeight: FontWeight.w800)),
              trailing: Text(
                '${selected.where((dish) => CateringMenuGroups.classify(dish) == group.id).length} dishes',
                style: const TextStyle(color: _pink,
                    fontWeight: FontWeight.w800, fontSize: 12),
              ),
              children: [
                for (final dish in selected.where((dish) =>
                    CateringMenuGroups.classify(dish) == group.id))
                  ListTile(
                    dense: true,
                    title: Text(dish['name'].toString()),
                    subtitle: Text(_allowedByDiet(dish)
                        ? 'Vegetarian' : 'Non-vegetarian'),
                  ),
              ],
            ),
          ),
      const SizedBox(height: 12),
      _pricePreview(compact: true),
      const SizedBox(height: 14),
      _heading('🚀  Publish Your Package'),
      RadioGroup<bool>(
        groupValue: _active,
        onChanged: (v) {
          if (v != null) setState(() => _active = v);
        },
        child: const Column(children: [
          RadioListTile<bool>(
            value: true,
            title: Text('Live', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Visible to customers on Gixbee.'),
          ),
          RadioListTile<bool>(
            value: false,
            title: Text('Draft', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Save privately and publish later.'),
          ),
        ]),
      ),
    ]);
  }

}
