import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'catering_package_wizard_screen.dart';
import 'catering_price_math.dart';

/// Edit an individual catering dish using the same guest slabs and offers
/// as packages. A successful save is confirmed by the Rust catalogue API.
class CateringFoodItemScreen extends StatefulWidget {
  const CateringFoodItemScreen({
    super.key,
    this.item,
    required this.onSave,
  });

  final Map<String, dynamic>? item;
  final Future<bool> Function(Map<String, dynamic>) onSave;

  @override
  State<CateringFoodItemScreen> createState() =>
      _CateringFoodItemScreenState();
}

class _DishTier {
  _DishTier({required int from, required int to, int price = 0})
      : min = TextEditingController(text: '$from'),
        max = TextEditingController(text: '$to'),
        amount = TextEditingController(text: '$price');

  final TextEditingController min;
  final TextEditingController max;
  final TextEditingController amount;

  Map<String, int>? get values {
    final from = int.tryParse(min.text.trim());
    final to = int.tryParse(max.text.trim());
    final price = int.tryParse(amount.text.trim());
    if (from == null || to == null || price == null) return null;
    return {'minGuests': from, 'maxGuests': to, 'price': price};
  }

  void dispose() {
    min.dispose();
    max.dispose();
    amount.dispose();
  }
}

class _CateringFoodItemScreenState extends State<CateringFoodItemScreen> {
  static const _navy = Color(0xFF1B2559);
  static const _green = Color(0xFF12B76A);
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _discount = TextEditingController();
  final _flatPrice = TextEditingController();
  final _tiers = <_DishTier>[];
  String _category = 'g01';
  String _diet = 'veg';
  bool _active = true;
  bool _flat = false;
  bool _offer = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name.text = item?['name']?.toString() ?? '';
    _description.text = item?['description']?.toString() ?? '';
    _category = item == null ? 'g01' : CateringMenuGroups.classify(item);
    _diet = item?['diet']?.toString() == 'non_veg' ? 'non_veg' : 'veg';
    _active = item?['active'] != false;
    final pct = (item?['discountPct'] as num?)?.toInt() ?? 0;
    _offer = pct > 0;
    _discount.text = pct > 0 ? '$pct' : '';
    final slabs = (item?['baseTiers'] as List?) ??
        (item?['tiers'] as List?) ??
        const [];
    for (final row in slabs.whereType<Map>()) {
      _tiers.add(_DishTier(
        from: (row['minGuests'] as num?)?.toInt() ?? 1,
        to: (row['maxGuests'] as num?)?.toInt() ?? 100,
        price: (row['price'] as num?)?.toInt() ?? 0,
      ));
    }
    if (_tiers.isEmpty) {
      _tiers.add(_DishTier(from: 1, to: 25, price: 100));
      _tiers.add(_DishTier(from: 26, to: 50, price: 90));
      _tiers.add(_DishTier(from: 51, to: 100, price: 80));
    }
    _flat = item?['rateMode'] == 'flat' ||
        (item?['rateMode'] == null &&
            _tiers.length == 1 &&
            _tiers.first.min.text == '1' &&
            _tiers.first.max.text == '100000');
    _flatPrice.text = _tiers.first.amount.text;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _discount.dispose();
    _flatPrice.dispose();
    for (final tier in _tiers) { tier.dispose(); }
    super.dispose();
  }

  void _error(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  List<Map<String, int>> _base() {
    if (_flat) {
      return CateringPriceMath.validateBaseTiers([
        {'minGuests': 1, 'maxGuests': CateringPriceMath.maxGuests,
         'price': int.tryParse(_flatPrice.text) ?? 0}
      ]);
    }
    return CateringPriceMath.validateBaseTiers([
      for (final row in _tiers) row.values ?? <String, int>{},
    ]);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty || _name.text.trim().length > 150 ||
        _description.text.trim().length > 3000) {
      _error('Enter a food item name and a valid description.');
      return;
    }
    final pct = _offer ? (int.tryParse(_discount.text.trim()) ?? -1) : 0;
    if (pct < 0 || pct > 90 || (_offer && pct == 0)) {
      _error('Choose a discount from 1% to 90%.');
      return;
    }
    late List<Map<String, int>> base;
    late List<Map<String, int>> offered;
    try {
      base = _base();
      offered = CateringPriceMath.offerTiers(base, pct);
    } on FormatException catch (error) {
      _error(error.message);
      return;
    }
    final item = <String, dynamic>{
      ...?widget.item,
      'id': widget.item?['id'] ?? const Uuid().v4(),
      'kind': 'ITEM',
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'category': _category,
      'diet': _diet,
      'active': _active,
      'rateMode': _flat ? 'flat' : 'tiered',
      'baseTiers': base,
      'discountPct': pct,
      'tiers': offered,
    };
    setState(() => _saving = true);
    try {
      final saved = await widget.onSave(item);
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context);
      } else {
        _error('Food item was not saved. Check the error and retry.');
      }
    } catch (_) {
      if (mounted) _error('Unable to save the food item. Retry.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _changeRate(bool flat) => setState(() {
    if (flat && !_flat && _flatPrice.text.isEmpty) {
      _flatPrice.text = _tiers.first.amount.text;
    }
    _flat = flat;
  });

  Widget _slab(_DishTier tier, int index) => Card(
    key: ObjectKey(tier),
    child: Padding(padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text('Guest slab ${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.w800))),
          if (_tiers.length > 1)
            IconButton(
              tooltip: 'Remove slab',
              onPressed: () => setState(() {
                _tiers.removeAt(index);
                WidgetsBinding.instance.addPostFrameCallback(
                    (_) => tier.dispose());
              }),
              icon: const Icon(Icons.remove_circle_outline)),
        ]),
        Row(children: [
          for (final (label, ctrl) in [
            ('From', tier.min), ('To', tier.max), ('₹ / plate', tier.amount),
          ])
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: TextField(
                controller: ctrl,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder()),
              ),
            )),
        ]),
      ]),
    ),
  );

  Widget _preview() {
    List<Map<String, int>> base;
    List<Map<String, int>> offered;
    try {
      base = _base();
      final pct = _offer ? int.tryParse(_discount.text) ?? -1 : 0;
      offered = CateringPriceMath.offerTiers(base, pct);
    } on FormatException {
      return const Text('Complete the prices to see the customer offer.');
    }
    return Card(
      color: const Color(0xFFF8FAFC),
      child: Padding(padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Guest Count          Base / Plate          Offer / Plate',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          const Divider(),
          for (var i = 0; i < offered.length; i++)
            Padding(padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(
                '${_flat ? 'All guests' : '${base[i]['minGuests']}–${base[i]['maxGuests']}'}'
                '     ₹${base[i]['price']}     →     ₹${offered[i]['price']}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.item == null ? 'Add Food Item' : 'Edit Food Item')),
    body: SafeArea(child: Column(children: [
      Expanded(child: ListView(
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(14)),
            child: const Text('🍲', style: TextStyle(fontSize: 50)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _name, maxLength: 150,
            decoration: const InputDecoration(
              labelText: 'Food Item Name *',
              border: OutlineInputBorder())),
          TextField(
            controller: _description, maxLines: 2, maxLength: 3000,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              border: OutlineInputBorder())),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Dish Group *'),
            items: [
              for (final group in CateringMenuGroups.all)
                DropdownMenuItem(value: group.id, child: Text(group.title)),
            ],
            onChanged: (value) => setState(() => _category = value ?? _category),
          ),
          const SizedBox(height: 14),
          const Text('Diet', style: TextStyle(
              color: _navy, fontWeight: FontWeight.w800)),
          RadioGroup<String>(
            groupValue: _diet,
            onChanged: (value) {
              if (value != null) setState(() => _diet = value);
            },
            child: Row(children: [
              for (final (value, title) in const [
                ('veg', 'Vegetarian'), ('non_veg', 'Non-vegetarian')
              ])
                Expanded(child: RadioListTile<String>(
                  value: value,
                  title: Text(title, style: const TextStyle(fontSize: 12)),
                  contentPadding: EdgeInsets.zero,
                )),
            ]),
          ),
          const SizedBox(height: 12),
          const Text('Set guest count pricing',
              style: TextStyle(fontWeight: FontWeight.w900, color: _navy)),
          RadioGroup<bool>(
            groupValue: _flat,
            onChanged: (v) { if (v != null) _changeRate(v); },
            child: const Column(children: [
              RadioListTile<bool>(
                title: Text('Rate reduces as guest count increases'),
                subtitle: Text('Lower price for larger groups.'), value: false),
              RadioListTile<bool>(
                title: Text('Same rate for all guests'),
                subtitle: Text('One price for every guest count.'), value: true),
            ]),
          ),
          CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Offer for customers',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Plate price stays as entered. '
                'Customers see a lower price.'),
            value: _offer,
            onChanged: (v) => setState(() {
              _offer = v ?? false;
              if (_offer && _discount.text.isEmpty) _discount.text = '10';
            }),
          ),
          if (_offer)
            Row(children: [
              IconButton(
                onPressed: () => setState(() =>
                  _discount.text = '${((int.tryParse(_discount.text) ?? 1) - 1).clamp(1, 90)}'),
                icon: const Icon(Icons.remove_circle_outline)),
              Expanded(child: TextField(
                controller: _discount,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Discount (%)', border: OutlineInputBorder()),
              )),
              IconButton(
                onPressed: () => setState(() =>
                  _discount.text = '${((int.tryParse(_discount.text) ?? 0) + 1).clamp(1, 90)}'),
                icon: const Icon(Icons.add_circle_outline)),
            ]),
          const SizedBox(height: 10),
          if (_flat)
            TextField(
              controller: _flatPrice,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Price per plate (₹)', border: OutlineInputBorder()))
          else ...[
            for (final (i, tier) in _tiers.indexed) _slab(tier, i),
            TextButton.icon(
              onPressed: _tiers.length >= 20 ? null : () => setState(() {
                final last = int.tryParse(_tiers.last.max.text) ?? 0;
                if (last >= CateringPriceMath.maxGuests) {
                  _error('Maximum guest count reached.');
                  return;
                }
                final start = last + 1;
                final price =
                    (int.tryParse(_tiers.last.amount.text) ?? 100) - 10;
                _tiers.add(_DishTier(
                  from: start,
                  to: (start + 24).clamp(start, CateringPriceMath.maxGuests).toInt(),
                  price: price.clamp(1, CateringPriceMath.maxPlatePrice).toInt(),
                ));
              }),
              icon: const Icon(Icons.add),
              label: const Text('Add Another Slab')),
          ],
          const SizedBox(height: 13),
          _preview(),
          const SizedBox(height: 14),
          SwitchListTile(
            value: _active,
            title: Text(_active ? 'Live' : 'Draft'),
            subtitle: Text(_active
                ? 'Visible to customers on Gixbee.'
                : 'Save privately and publish later.'),
            onChanged: (v) => setState(() => _active = v),
          ),
        ],
      )),
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: _saving ? null : () {
              setState(() => _active = false);
              _save();
            }, child: const Text('Save as Draft'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _green),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save Food Item'),
          )),
        ]),
      ),
    ])),
  );
}
