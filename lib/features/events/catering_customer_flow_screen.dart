import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/media/profile_photo.dart';
import '../../shared/widgets/gx_calendar.dart';
import 'catering_customer_interest_screen.dart';
import 'catering_customer_pricing.dart';
import 'catering_package_wizard_screen.dart';

const _forest = Color(0xFF14532D);
const _green = Color(0xFF16A34A);
const _light = Color(0xFFF0FDF4);

String cateringMoney(int amount) =>
    '₹${NumberFormat.decimalPattern('en_IN').format(amount)}';

class CateringCustomerPlatePrice extends StatelessWidget {
  const CateringCustomerPlatePrice({
    super.key, required this.price, this.showTotal = false,
  });
  final CateringCustomerPrice price;
  final bool showTotal;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 7, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (price.basePerPlate > price.offerPerPlate)
          Text(cateringMoney(price.basePerPlate), style: const TextStyle(
            decoration: TextDecoration.lineThrough,
            color: Colors.blueGrey, fontSize: 12)),
        Text('${cateringMoney(price.offerPerPlate)} / plate',
          style: const TextStyle(color: _forest,
            fontWeight: FontWeight.w900, fontSize: 16)),
        if (price.discountPercent > 0 &&
            price.basePerPlate > price.offerPerPlate)
          Chip(label: Text('${price.discountPercent}% OFF',
            style: const TextStyle(color: Color(0xFF9D174D),
                fontWeight: FontWeight.w800, fontSize: 10)),
            visualDensity: VisualDensity.compact),
      ]),
      if (showTotal)
        Text('Estimated ${cateringMoney(price.total)} for ${price.guests} guests',
          style: const TextStyle(color: _forest, fontWeight: FontWeight.w700)),
    ],
  );
}

Widget cateringCustomerImage(String? photo, {double height = 150}) {
  final url = resolveProfileImageUrl(photo);
  return ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: url == null
      ? Container(height: height, width: double.infinity,
          color: _light, alignment: Alignment.center,
          child: const Text('🍽️', style: TextStyle(fontSize: 55)))
      : Image.network(url, height: height, width: double.infinity,
          fit: BoxFit.cover, errorBuilder: (_, __, ___) =>
            Container(height: height, color: _light,
              alignment: Alignment.center,
              child: const Icon(Icons.restaurant, size: 60))),
  );
}

/// Caterer profile is intentionally separate from the menu: the HTML
/// reference shows Overview / Photos / Reviews before catalogue selection.
class CateringCustomerProfileScreen extends StatefulWidget {
  const CateringCustomerProfileScreen({
    super.key, required this.vendor, required this.cityId,
    required this.eventType, required this.date, required this.guests,
    required this.location, required this.category,
  });

  final Map<String, dynamic> vendor;
  final String cityId;
  final String eventType;
  final DateTime date;
  final int guests;
  final String location;
  final String category;

  @override
  State<CateringCustomerProfileScreen> createState() =>
      _CateringCustomerProfileScreenState();
}

class _CateringCustomerProfileScreenState
    extends State<CateringCustomerProfileScreen> {
  String _tab = 'overview';

  Map get _catalogue => widget.vendor['catalogue'] as Map? ?? const {};
  String get _name => widget.vendor['name']?.toString() ?? 'Caterer';
  List get _photos => _catalogue['photos'] as List? ?? const [];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_name)),
    body: SafeArea(child: Column(children: [
      Expanded(child: ListView(
        padding: const EdgeInsets.all(16), children: [
          cateringCustomerImage(
              _photos.isEmpty ? null : _photos.first?.toString(), height: 200),
          const SizedBox(height: 12),
          Text(_name, style: const TextStyle(
              color: _forest, fontSize: 21, fontWeight: FontWeight.w900)),
          Text(widget.vendor['location']?.toString() ?? '',
              style: const TextStyle(color: Colors.blueGrey)),
          const SizedBox(height: 8),
          const Chip(label: Text('Availability confirmed after enquiry'),
            backgroundColor: _light, visualDensity: VisualDensity.compact),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            selected: {_tab},
            segments: const [
              ButtonSegment(value: 'overview', label: Text('Overview')),
              ButtonSegment(value: 'photos', label: Text('Photos')),
              ButtonSegment(value: 'reviews', label: Text('Reviews')),
            ],
            onSelectionChanged: (values) =>
                setState(() => _tab = values.first),
          ),
          const SizedBox(height: 17),
          if (_tab == 'overview') ...[
            const Text('About Us', style: TextStyle(
                color: _forest, fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 8),
            Text(_catalogue['about']?.toString().trim().isNotEmpty == true
              ? _catalogue['about'].toString()
              : 'Explore available catering packages and food items.'),
            const SizedBox(height: 18),
            const Text('Services', style: TextStyle(
                color: _forest, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Wrap(spacing: 7, runSpacing: 7, children: [
              Chip(label: Text('Catering packages')),
              Chip(label: Text('Individual food items')),
              Chip(label: Text('Guest-count pricing')),
            ]),
          ] else if (_tab == 'photos') ...[
            if (_photos.isEmpty)
              const Text('No gallery photos have been added yet.')
            else
              for (final photo in _photos)
                Padding(padding: const EdgeInsets.only(bottom: 10),
                  child: cateringCustomerImage(photo.toString(), height: 165)),
          ] else
            const Padding(padding: EdgeInsets.all(16),
              child: Text('Customer reviews are not available yet.')),
        ],
      )),
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _green,
              padding: const EdgeInsets.symmetric(vertical: 15)),
            onPressed: () => Navigator.push<void>(context, MaterialPageRoute(
              builder: (_) => CateringCustomerMenuScreen(
                vendor: widget.vendor, cityId: widget.cityId,
                eventType: widget.eventType, date: widget.date,
                guests: widget.guests, location: widget.location,
                category: widget.category,
              ),
            )),
            child: const Text('Show Packages / Individual Food Items'),
          )),
      ),
    ])),
  );
}

class CateringCustomerMenuScreen extends StatefulWidget {
  const CateringCustomerMenuScreen({
    super.key, required this.vendor, required this.cityId,
    required this.eventType, required this.date, required this.guests,
    required this.location, required this.category,
  });

  final Map<String, dynamic> vendor;
  final String cityId;
  final String eventType;
  final DateTime date;
  final int guests;
  final String location;
  final String category;

  @override
  State<CateringCustomerMenuScreen> createState() =>
      _CateringCustomerMenuScreenState();
}

class _CateringCustomerMenuScreenState extends State<CateringCustomerMenuScreen> {
  late DateTime _date = widget.date;
  late int _guests = widget.guests;
  late final _guestCount = TextEditingController(text: '${widget.guests}');
  final _selected = <String, Map<String, dynamic>>{};
  String _tab = 'packages';
  String _diet = 'all';
  String _serve = 'all';

  String get _vendorName => widget.vendor['name']?.toString() ?? 'Caterer';
  Map get _catalogue => widget.vendor['catalogue'] as Map? ?? const {};
  List<Map<String, dynamic>> get _active =>
      CateringCustomerPrice.activeItems(_catalogue);

  List<Map<String, dynamic>> get _packages =>
      CateringCustomerPrice.filterPackages(_active, _guests,
        eventCategory: widget.category, diet: _diet,
        serving: _serve);

  List<Map<String, dynamic>> get _dishes =>
      CateringCustomerPrice.filterDishes(_active, _guests, diet: _diet);

  @override
  void dispose() {
    _guestCount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = await showGxCalendar(context,
      title: 'Event date', initialDate: _date,
      firstDate: today, lastDate: today.add(const Duration(days: 730)));
    if (selected == null || !mounted) return;
    setState(() => _date = selected);
  }

  void _toggleDish(Map<String, dynamic> dish) {
    final id = dish['id'];
    if (id is! String) return;
    setState(() {
      if (_selected.containsKey(id)) {
        _selected.remove(id);
      } else if (_selected.length < 20) {
        _selected[id] = dish;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can select up to 20 dishes.')));
      }
    });
  }

  void _interest(List<Map<String, dynamic>> items, {bool customize = false}) {
    if (CateringCustomerPrice.estimate(items, _guests) == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Price unavailable for the selected guest count.')));
      return;
    }
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => CateringCustomerInterestScreen(
        vendorName: _vendorName,
        businessId: widget.vendor['businessId'] as String,
        cityId: widget.cityId,
        eventType: widget.eventType,
        location: widget.location,
        day: _date,
        guests: _guests,
        items: items,
        customize: customize,
      ),
    ));
  }

  void _details(Map<String, dynamic> item) async {
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CateringCustomerItemDetailScreen(
        vendorName: _vendorName, item: item, allItems: _active,
        guests: _guests, selected: _selected.containsKey(item['id']),
        selectedCount: _selected.length,
        onToggle: () => _toggleDish(item),
        onPackageInterest: (customize) =>
            _interest([item], customize: customize),
      ),
    ));
    if (result == true && mounted) _continueDishes();
  }

  void _continueDishes() {
    final selection = _selected.values.toList();
    if (selection.isEmpty) return;
    _interest(selection, customize: true);
  }

  @override
  Widget build(BuildContext context) {
    final packages = _packages;
    final dishes = _dishes;
    final selectedItems = _selected.values.toList();
    final total = CateringCustomerPrice.estimate(selectedItems, _guests);
    return Scaffold(
      appBar: AppBar(title: Text(_vendorName)),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Column(children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'packages',
                      label: Text('Packages (${_active.where((e) => e['kind'] == 'PACKAGE').length})')),
                  ButtonSegment(value: 'food',
                      label: Text('Individual Food Items (${_active.where((e) => e['kind'] == 'ITEM').length})')),
                ],
                selected: {_tab},
                onSelectionChanged: (values) => setState(() {
                  _tab = values.first;
                  _diet = 'all';
                }),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text(
                '${DateFormat('EEE, d MMM yyyy').format(_date)} · $_guests guests',
                style: const TextStyle(fontWeight: FontWeight.w800,
                  color: _forest))),
              TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Change date'),
              ),
            ]),
            TextField(
              controller: _guestCount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of guests',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (text) {
                final guests = int.tryParse(text.trim()) ?? 0;
                setState(() => _guests = guests);
              },
            ),
            const SizedBox(height: 8),
            if (_tab == 'packages') ...[
              const Align(alignment: Alignment.centerLeft,
                child: Text('How food is served',
                  style: TextStyle(color: _forest,
                    fontWeight: FontWeight.w800))),
              Wrap(spacing: 6, children: [
                for (final (value, label) in const [
                  ('all', 'All'), ('buffet', 'Buffet'),
                  ('table', 'Table Service'), ('both', 'Both'),
                ]) ChoiceChip(
                  label: Text(label), selected: _serve == value,
                  onSelected: (_) => setState(() => _serve = value),
                ),
              ]),
            ],
            Wrap(spacing: 7, children: [
              for (final (value, label) in _tab == 'packages'
                  ? const [('all', 'All'), ('veg', 'Veg only'),
                      ('mixed', 'Veg & Non-veg')]
                  : const [('all', 'All'), ('veg', 'Veg only'),
                      ('non_veg', 'Non-veg only')])
                ChoiceChip(
                  label: Text(label),
                  selected: _diet == value,
                  onSelected: (_) => setState(() => _diet = value),
                ),
            ]),
          ]),
        ),
        Expanded(child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            Text(_tab == 'packages'
              ? 'Choose one catering package. Extra dishes are listed separately.'
              : 'Choose individual dishes. Prices are per plate × $_guests guests.',
              style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
            const SizedBox(height: 8),
            if (_tab == 'packages') ...[
              if (packages.isEmpty)
                const Text('No packages match your event and pricing filters.'),
              for (final item in packages)
                _itemCard(item),
            ] else ...[
              if (dishes.isEmpty)
                const Text('No individual dishes match this guest count and diet.'),
              for (final group in CateringMenuGroups.all) ...[
                if (dishes.any((dish) =>
                    CateringMenuGroups.classify(dish) == group.id)) ...[
                  Padding(padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Text('${group.emoji}  ${group.title}',
                      style: const TextStyle(color: _forest,
                          fontWeight: FontWeight.w900, fontSize: 15))),
                  for (final dish in dishes.where((d) =>
                      CateringMenuGroups.classify(d) == group.id))
                    _itemCard(dish),
                ],
              ],
            ],
          ],
        )),
        if (_tab == 'food' && selectedItems.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            decoration: const BoxDecoration(color: _light,
              border: Border(top: BorderSide(color: Color(0xFFBBF7D0)))),
            child: Column(children: [
              Row(children: [
                Expanded(child: Text(
                  '${selectedItems.length} dishes selected · $_guests guests',
                  style: const TextStyle(color: _forest,
                      fontWeight: FontWeight.w800))),
                Text(total == null ? 'Unavailable' : cateringMoney(total),
                  style: const TextStyle(color: _forest,
                      fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 7),
              Row(children: [
                Expanded(child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _green),
                  onPressed: total == null ? null : _continueDishes,
                  child: Text('Continue with ${selectedItems.length} dishes'),
                )),
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('Clear'),
                ),
              ]),
            ]),
          ),
      ])),
    );
  }

  Widget _itemCard(Map<String, dynamic> item) {
    final package = item['kind'] == 'PACKAGE';
    final quote = CateringCustomerPrice.forItem(item, _guests);
    final selected = _selected.containsKey(item['id']);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: selected ? _light : Colors.white,
      child: Padding(padding: const EdgeInsets.all(10),
        child: Row(children: [
          if (!package)
            IconButton(
              tooltip: selected ? 'Remove dish' : 'Select dish',
              icon: Icon(selected ? Icons.check_circle : Icons.add_circle_outline,
                color: _green),
              onPressed: quote == null ? null : () => _toggleDish(item),
            )
          else
            const Text('🍛', style: TextStyle(fontSize: 29)),
          const SizedBox(width: 8),
          Expanded(child: InkWell(
            onTap: () => _details(item),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['name']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w900,
                    color: _forest)),
                if (package)
                  Text('${item['packageLevel'] ?? 'Basic'} · '
                      '${item['diet'] == 'veg' ? 'Veg' : 'Veg & Non-veg'} · '
                      '${item['serveStyle'] ?? 'Service'}',
                    style: const TextStyle(fontSize: 12,
                      color: Colors.blueGrey)),
                if ((item['description']?.toString() ?? '').isNotEmpty)
                  Text(item['description'].toString(), maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                if (quote != null)
                  CateringCustomerPlatePrice(price: quote)
                else
                  const Text('No price for this guest count',
                    style: TextStyle(color: Colors.red)),
              ],
            )),
          ),
          const Icon(Icons.chevron_right),
        ]),
      ),
    );
  }
}

class CateringCustomerItemDetailScreen extends StatefulWidget {
  const CateringCustomerItemDetailScreen({
    super.key, required this.vendorName, required this.item,
    required this.allItems, required this.guests, required this.selected,
    required this.selectedCount, required this.onToggle,
    required this.onPackageInterest,
  });

  final String vendorName;
  final Map<String, dynamic> item;
  final List<Map<String, dynamic>> allItems;
  final int guests;
  final bool selected;
  final int selectedCount;
  final VoidCallback onToggle;
  final void Function(bool customize) onPackageInterest;

  @override
  State<CateringCustomerItemDetailScreen> createState() =>
      _CateringCustomerItemDetailScreenState();
}

class _CateringCustomerItemDetailScreenState
    extends State<CateringCustomerItemDetailScreen> {
  String _tab = 'menu';
  late bool _selected = widget.selected;
  bool get _package => widget.item['kind'] == 'PACKAGE';
  CateringCustomerPrice? get _price =>
      CateringCustomerPrice.forItem(widget.item, widget.guests);

  Map<String, List<String>> get _menu {
    final groups = <String, List<String>>{};
    final ids = (widget.item['dishIds'] as List? ?? const []).toSet();
    final included = widget.allItems.where((dish) =>
        dish['kind'] == 'ITEM' && ids.contains(dish['id']));
    for (final dish in included) {
      final group = CateringMenuGroups.classify(dish);
      groups.putIfAbsent(group, () => []).add(dish['name'].toString());
    }
    if (groups.isEmpty &&
        (widget.item['menuItems'] as List? ?? const []).isNotEmpty) {
      groups['other'] = (widget.item['menuItems'] as List)
          .map((dish) => dish.toString()).toList();
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final price = _price;
    return Scaffold(
      appBar: AppBar(title: Text(item['name']?.toString() ?? 'Menu details')),
      body: SafeArea(child: Column(children: [
        Expanded(child: ListView(
          padding: const EdgeInsets.all(16), children: [
            cateringCustomerImage(null, height: 125),
            const SizedBox(height: 12),
            Text(item['name']?.toString() ?? '',
              style: const TextStyle(color: _forest, fontSize: 20,
                  fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            if (_package)
              Text('${item['packageLevel'] ?? 'Basic'} · '
                  '${item['category'] ?? ''} · ${item['serveStyle'] ?? 'Service'}',
                  style: const TextStyle(color: Colors.blueGrey)),
            if ((item['description']?.toString() ?? '').isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 5),
                child: Text(item['description'].toString())),
            const SizedBox(height: 10),
            if (price != null)
              Card(color: _light, child: Padding(
                padding: const EdgeInsets.all(13),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Price for ${widget.guests} guests',
                      style: const TextStyle(color: _forest,
                        fontWeight: FontWeight.w800)),
                    CateringCustomerPlatePrice(price: price, showTotal: true),
                  ]),
              ))
            else
              const Text('Unavailable for this guest count.'),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'menu',
                  label: Text(_package ? 'Menu inclusions' : 'About')),
                const ButtonSegment(value: 'pricing',
                  label: Text('Per plate pricing')),
              ],
              selected: {_tab},
              onSelectionChanged: (values) => setState(() => _tab = values.first),
            ),
            const SizedBox(height: 14),
            if (_tab == 'pricing')
              for (final slab in (item['tiers'] as List? ?? const [])
                  .whereType<Map>())
                Builder(builder: (_) {
                  final base = (item['baseTiers'] as List? ?? const [])
                      .whereType<Map>()
                      .where((b) => b['minGuests'] == slab['minGuests'] &&
                          b['maxGuests'] == slab['maxGuests'])
                      .firstOrNull;
                  final active = widget.guests >= (slab['minGuests'] as num) &&
                      widget.guests <= (slab['maxGuests'] as num);
                  return Card(
                    color: active ? _light : Colors.white,
                    child: ListTile(
                      title: Text(
                        '${slab['minGuests']}–${slab['maxGuests']} guests',
                        style: TextStyle(fontWeight: active ?
                            FontWeight.w900 : FontWeight.normal)),
                      subtitle: base != null && base['price'] != slab['price']
                        ? Text('Original: ${cateringMoney((base['price'] as num).toInt())}')
                        : null,
                      trailing: Text(
                        '${cateringMoney((slab['price'] as num).toInt())}/plate',
                        style: const TextStyle(color: _forest,
                            fontWeight: FontWeight.w800)),
                    ),
                  );
                })
            else if (_package) ...[
              const Text('What’s included in the plate price',
                style: TextStyle(color: _forest, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (_menu.isEmpty)
                Text(item['includes']?.toString() ??
                    'Contact the caterer for the full menu.'),
              for (final group in CateringMenuGroups.all)
                if (_menu[group.id] case final List<String> rows when rows.isNotEmpty)
                  Card(child: ExpansionTile(
                    leading: Text(group.emoji),
                    title: Text(group.title),
                    subtitle: Text('${rows.length} dishes'),
                    children: [
                      for (final name in rows)
                        ListTile(dense: true, title: Text(name)),
                    ],
                  )),
              if (_menu['other'] case final List<String> other when other.isNotEmpty)
                Card(child: ExpansionTile(
                  title: const Text('Other included dishes'),
                  children: [for (final name in other)
                    ListTile(dense: true, title: Text(name))],
                )),
            ] else
              Text(item['description']?.toString() ??
                  'Select this dish to include it in your enquiry.'),
          ],
        )),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _package
            ? Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: price == null ? null : () =>
                      widget.onPackageInterest(true),
                  child: const Text('Customise Requirement'),
                )),
                const SizedBox(width: 8),
                Expanded(child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _green),
                  onPressed: price == null ? null : () =>
                      widget.onPackageInterest(false),
                  child: const Text('Initiate Interest'),
                )),
              ])
            : Row(children: [
                Expanded(child: OutlinedButton.icon(
                  icon: Icon(_selected ? Icons.check : Icons.add),
                  onPressed: price == null ? null : () {
                    widget.onToggle();
                    setState(() => _selected = !_selected);
                  },
                  label: Text(_selected ? 'Added · Remove' : 'Add to selection'),
                )),
                if (widget.selectedCount > 0 || _selected) ...[
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _green),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Continue'),
                  )),
                ],
              ]),
        ),
      ])),
    );
  }
}
