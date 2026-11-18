import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import 'decoration_price_math.dart';

/// Owner editor for one package, standalone service or optional add-on.
/// The editor only closes after the Rust catalogue API accepts the new revision.
class DecorationEntryScreen extends StatefulWidget {
  const DecorationEntryScreen({
    super.key,
    this.item,
    required this.onSave,
    this.createPackage = true,
  });

  final Map<String, dynamic>? item;
  final Future<bool> Function(Map<String, dynamic>) onSave;
  final bool createPackage;

  @override
  State<DecorationEntryScreen> createState() => _DecorationEntryScreenState();
}

class _DecorationEntryScreenState extends State<DecorationEntryScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _description = TextEditingController();
  final _includes = TextEditingController();
  final _policy = TextEditingController();
  final _listPrice = TextEditingController();
  final _discount = TextEditingController(text: '0');
  bool _saving = false;
  bool _active = true;
  bool _addon = false;
  late String _kind;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _kind = item?['kind']?.toString() ??
        (widget.createPackage ? 'PACKAGE' : 'ITEM');
    _addon = item?['addon'] == true && _kind == 'ITEM';
    _active = item?['active'] != false;
    _name.text = item?['name']?.toString() ?? '';
    _category.text = item?['category']?.toString() ?? '';
    _description.text = item?['description']?.toString() ?? '';
    _includes.text = item?['includes']?.toString() ?? '';
    _policy.text = item?['policy']?.toString() ?? '';
    _listPrice.text =
        (item?['listPrice'] ?? item?['price'])?.toString() ?? '';
    _discount.text = (item?['discountPct'] ?? 0).toString();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _category, _description, _includes, _policy, _listPrice, _discount
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validatePrice(String? raw) {
    final price = int.tryParse(raw?.trim() ?? '');
    if (price == null || price < 1 || price > DecorationPriceMath.maxPrice) {
      return 'Enter a price between ₹1 and ₹1,00,00,000';
    }
    return null;
  }

  String? _validateDiscount(String? raw) {
    final percent = int.tryParse(raw?.trim() ?? '');
    return percent == null || percent < 0 || percent > 90
        ? 'Enter a discount from 0 to 90%'
        : null;
  }

  Future<void> _save({bool draft = false}) async {
    if (_saving || !_form.currentState!.validate()) return;
    final listPrice = int.parse(_listPrice.text.trim());
    final discount = int.parse(_discount.text.trim());
    final price = DecorationPriceMath.offerPrice(listPrice, discount);
    final entry = <String, dynamic>{
      ...?widget.item,
      'id': widget.item?['id'] ?? const Uuid().v4(),
      'kind': _kind,
      'name': _name.text.trim(),
      'category': _category.text.trim(),
      'description': _description.text.trim(),
      'includes': _includes.text.trim(),
      'policy': _policy.text.trim(),
      'addon': _kind == 'ITEM' && _addon,
      'listPrice': listPrice,
      'discountPct': discount,
      'price': price,
      'active': draft ? false : _active,
    };
    setState(() => _saving = true);
    try {
      final saved = await widget.onSave(entry);
      if (!mounted) return;
      if (saved) {
        Navigator.of(context).pop();
      } else {
        showGxSnack(context, 'Could not save. Check pricing or reload the catalogue.',
            type: GxSnackType.error);
      }
    } catch (error) {
      if (mounted) {
        showGxSnack(context, error.toString(), type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listPrice = int.tryParse(_listPrice.text.trim()) ?? 0;
    final discount = int.tryParse(_discount.text.trim()) ?? -1;
    final preview = DecorationPriceMath.isValid(listPrice, discount)
        ? DecorationPriceMath.offerPrice(listPrice, discount)
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.item == null
          ? 'Create decoration listing' : 'Edit decoration listing')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: Column(children: [
            Expanded(child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Listing details',
                  style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'PACKAGE', label: Text('Package'),
                        icon: Icon(Icons.inventory_2_outlined)),
                    ButtonSegment(value: 'ITEM', label: Text('Service / Add-on'),
                        icon: Icon(Icons.add_circle_outline)),
                  ],
                  selected: {_kind},
                  onSelectionChanged: _saving ? null : (choices) =>
                      setState(() {
                        _kind = choices.first;
                        if (_kind == 'PACKAGE') _addon = false;
                      }),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _name,
                  maxLength: 150,
                  decoration: const InputDecoration(labelText: 'Listing name *'),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Enter a name' : null,
                ),
                TextFormField(
                  controller: _category,
                  maxLength: 100,
                  decoration: const InputDecoration(
                      labelText: 'Event / decoration category',
                      hintText: 'Wedding stage, birthday, floral, lighting'),
                ),
                TextFormField(
                  controller: _description,
                  maxLength: 3000,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextFormField(
                  controller: _includes,
                  maxLength: 3000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Included decorations and setup',
                    hintText: 'Backdrop, flowers, installation, dismantling'),
                ),
                TextFormField(
                  controller: _policy,
                  maxLength: 3000,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Cancellation / rescheduling terms'),
                ),
                if (_kind == 'ITEM')
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Optional package add-on'),
                    subtitle: const Text(
                      'Can be selected alongside one decoration package.'),
                    value: _addon,
                    onChanged: _saving ? null : (v) =>
                        setState(() => _addon = v),
                  ),
                const SizedBox(height: 14),
                Text('Pricing',
                  style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _listPrice,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'List price (₹) *'),
                  validator: _validatePrice,
                  onChanged: (_) => setState(() {}),
                ),
                TextFormField(
                  controller: _discount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Discount (%)'),
                  validator: _validateDiscount,
                  onChanged: (_) => setState(() {}),
                ),
                if (preview != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('Customer estimate: ₹$preview',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                        color: context.gx.accent)),
                  ),
                const Text('The Rust API recalculates the published amount. '
                    'A vendor quote determines the final agreed price.'),
                const SizedBox(height: 14),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_active ? 'Published' : 'Draft'),
                  subtitle: Text(_active
                      ? 'Visible in customer search after saving.'
                      : 'Hidden until you publish it.'),
                  value: _active,
                  onChanged: _saving ? null : (v) =>
                      setState(() => _active = v),
                ),
              ],
            )),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(draft: true),
                  child: const Text('Save as draft'),
                )),
                const SizedBox(width: 12),
                Expanded(child: GxButton(
                  label: 'Save listing',
                  onTap: _saving ? null : () => _save(),
                  loading: _saving,
                  height: 48,
                )),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
