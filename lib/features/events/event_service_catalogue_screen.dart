import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../repositories/business_repository.dart';
import '../../repositories/cities_repository.dart';
import '../../repositories/events_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import 'event_service_browser.dart';
import 'catering_package_wizard_screen.dart';
import 'catering_food_item_screen.dart';
import 'photography_package_wizard_screen.dart';
import 'photography_service_wizard_screen.dart';

class EventServiceCatalogueScreen extends ConsumerStatefulWidget {
  const EventServiceCatalogueScreen(
      {super.key, required this.business, required this.service});
  final Business business;
  final String service;

  @override
  ConsumerState<EventServiceCatalogueScreen> createState() =>
      _EventServiceCatalogueScreenState();
}

class _EventServiceCatalogueScreenState
    extends ConsumerState<EventServiceCatalogueScreen> {
  final _about = TextEditingController();
  final _notice = TextEditingController(text: '0');
  final _advance = TextEditingController(text: '730');
  final _perDay = TextEditingController(text: '1');
  Set<String> _serviceCities = {};
  List<Map<String, dynamic>> _items = [];
  List<String> _photos = [];
  int _revision = 0;
  bool _loading = true;
  bool _busy = false;
  bool _hasUnsavedChanges = false;
  String? _error;
  String _menuTab = 'packages';
  String _menuStatus = 'all';
  String _menuSearch = '';
  bool get _catering => widget.service == 'CATERING';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _about.dispose();
    _notice.dispose();
    _advance.dispose();
    _perDay.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(eventsRepositoryProvider)
          .catalogue(widget.business.id, widget.service);
      if (!mounted) return;
      final catalogue = result['catalogue'] as Map;
      setState(() {
        _revision = result['revision'] as int;
        _about.text = catalogue['about']?.toString() ?? '';
        _notice.text = '${catalogue['minNoticeDays'] ?? 0}';
        _advance.text = '${catalogue['maxAdvanceDays'] ?? 730}';
        _perDay.text = '${catalogue['maxBookingsPerDay'] ?? 1}';
        _serviceCities = (catalogue['serviceCityIds'] as List? ?? [])
            .whereType<String>()
            .toSet();
        _items = (catalogue['items'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _photos = (catalogue['photos'] as List).cast<String>().toList();
        _hasUnsavedChanges = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = eventError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _save({List<Map<String, dynamic>>? entries}) async {
    if (_busy) return false;
    final notice = int.tryParse(_notice.text.trim());
    final advance = int.tryParse(_advance.text.trim());
    final limit = int.tryParse(_perDay.text.trim());
    if (notice == null ||
        notice < 0 ||
        notice > 365 ||
        advance == null ||
        advance < 1 ||
        advance > 730 ||
        notice > advance ||
        limit == null ||
        limit < 1 ||
        limit > 50) {
      showGxSnack(
          context, 'Check the notice, booking window and daily booking limit.');
      return false;
    }
    setState(() => _busy = true);
    try {
      final saved = await ref.read(eventsRepositoryProvider).saveCatalogue(
        widget.business.id,
        widget.service,
        _revision,
        {
          'about': _about.text.trim(),
          'items': entries ?? _items,
          'photos': _photos,
          'minNoticeDays': notice,
          'maxAdvanceDays': advance,
          'maxBookingsPerDay': limit,
          'serviceCityIds': _serviceCities.toList(),
        },
      );
      if (!mounted) return false;
      final canonical = saved['catalogue'] as Map?;
      setState(() {
        _revision = saved['revision'] as int;
        // The Rust API enriches package menus on save. Always display
        // the canonical persisted item set, not a stale local approximation.
        _items = (canonical?['items'] as List? ?? entries ?? _items)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _hasUnsavedChanges = false;
      });
      showGxSnack(context, 'Catalogue saved');
      return true;
    } catch (error) {
      if (mounted) {
        showGxSnack(context, eventError(error));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _savePackage(Map<String, dynamic> updated, int? index) async {
    final candidate = [
      for (final entry in _items) Map<String, dynamic>.from(entry)
    ];
    if (index == null) {
      candidate.add(updated);
    } else {
      candidate[index] = updated;
    }
    // Keep the wizard open when the API rejects pricing, a stale
    // revision, or connectivity fails; the owner can correct/retry.
    return _save(entries: candidate);
  }

  Future<void> _reload() async {
    if (_busy) return;
    if (_hasUnsavedChanges) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text('Reloading will replace local changes '
              'with the latest saved catalogue.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep editing')),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Reload saved')),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    await _load();
    if (mounted && _error == null) {
      setState(() => _hasUnsavedChanges = false);
    }
  }

  Future<void> _photo() async {
    if (_busy || _photos.length >= 24) return;
    setState(() => _busy = true);
    try {
      final image = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 1600);
      if (image == null || !mounted) return;
      final repo = ref.read(businessRepositoryProvider);
      final url = await repo.uploadImage(await image.readAsBytes(), image.name);
      if (mounted) setState(() {
        _photos.add(url);
        _hasUnsavedChanges = true;
      });
    } catch (error) {
      if (mounted) showGxSnack(context, eventError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(int? index, {bool createPackage = false}) async {
    final original = index == null ? null : _items[index];
    final packageFlow = _catering &&
        (original?['kind'] == 'PACKAGE' || (index == null && createPackage));
    final cateringDishFlow = _catering &&
        (original?['kind'] == 'ITEM' || (index == null && !createPackage));
    final photoPackageFlow = !_catering &&
        (original?['kind'] == 'PACKAGE' || (index == null && createPackage));
    final photoServiceFlow = !_catering &&
        (original?['kind'] == 'ITEM' || (index == null && !createPackage));
    final dishes = _items.where((item) => item['kind'] == 'ITEM').toList();
    final updated = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => packageFlow
            ? CateringPackageWizardScreen(
                package: original,
                dishes: dishes,
                onSave: (entry) => _savePackage(entry, index),
              )
            : cateringDishFlow
                ? CateringFoodItemScreen(
                    item: original,
                    onSave: (entry) => _savePackage(entry, index),
                  )
            : photoPackageFlow
                ? PhotographyPackageWizardScreen(package: original)
                : photoServiceFlow
                    ? PhotographyServiceWizardScreen(service: original)
                    : _CatalogueEntry(
                        catering: _catering,
                        item: original,
                        dishes: dishes,
                        initialKind: index == null ? 'ITEM' : null,
                      ),
      ),
    );
    if (!mounted || updated == null) return;
    if (photoPackageFlow || photoServiceFlow) {
      await _savePackage(updated, index);
      return;
    }
    setState(() {
      if (index == null) {
        _items.add(updated);
      } else {
        _items[index] = updated;
      }
      _hasUnsavedChanges = true;
    });
  }

  Widget _cateringHub() {
    final matches = _items.indexed.where((entry) {
      final item = entry.$2;
      if ((_menuTab == 'packages') != (item['kind'] == 'PACKAGE')) return false;
      if (_menuStatus == 'live' && item['active'] == false) return false;
      if (_menuStatus == 'draft' && item['active'] != false) return false;
      return '${item['name'] ?? ''} ${item['category'] ?? ''}'
          .toLowerCase().contains(_menuSearch.toLowerCase());
    }).toList();
    final packages = _items.where((e) => e['kind'] == 'PACKAGE').length;
    final dishes = _items.where((e) => e['kind'] == 'ITEM').length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Gixbee  |  Menu & Packages',
          style: TextStyle(fontSize: 19, color: Color(0xFF1B2559),
              fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'packages', label: Text('Packages ($packages)')),
          ButtonSegment(value: 'food', label: Text('Food Items ($dishes)')),
        ],
        selected: {_menuTab},
        onSelectionChanged: (values) =>
            setState(() => _menuTab = values.first),
      ),
      const SizedBox(height: 12),
      TextField(
        onChanged: (value) => setState(() => _menuSearch = value),
        decoration: InputDecoration(
          hintText: _menuTab == 'packages'
              ? 'Search packages...' : 'Search food items...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      Wrap(spacing: 8, children: [
        for (final (value, label) in const [
          ('all', 'All'), ('live', 'Live'), ('draft', 'Draft'),
        ])
          ChoiceChip(label: Text(label), selected: _menuStatus == value,
              onSelected: (_) => setState(() => _menuStatus = value)),
      ]),
      if (matches.isEmpty)
        Padding(padding: const EdgeInsets.all(16),
          child: Text(_menuTab == 'packages'
              ? 'No packages match these filters.'
              : 'No food items match these filters.')),
      for (final entry in matches)
        Card(
          margin: const EdgeInsets.only(bottom: 9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          child: ListTile(
            title: Text(entry.$2['name']?.toString() ?? 'Untitled',
                style: const TextStyle(color: Color(0xFF1B2559),
                    fontWeight: FontWeight.w900)),
            subtitle: Text([
              entry.$2['kind'] == 'PACKAGE'
                  ? '${entry.$2['packageLevel'] ?? 'Basic'} · ${(entry.$2['dishIds'] as List? ?? const []).length} dishes'
                  : '${entry.$2['diet'] == 'non_veg' ? 'Non-veg' : 'Veg'} dish',
              if ((entry.$2['tiers'] as List? ?? const []).isNotEmpty)
                '${(entry.$2['tiers'] as List).length} price slabs',
              if (((entry.$2['discountPct'] as num?)?.toInt() ?? 0) > 0)
                '${entry.$2['discountPct']}% OFF',
              entry.$2['active'] == false ? 'Draft' : 'Live',
            ].join(' · ')),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _edit(entry.$1),
          ),
        ),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF12B76A),
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
        onPressed: _items.length >= 150 ? null :
            () => _edit(null, createPackage: _menuTab == 'packages'),
        icon: Icon(_menuTab == 'packages'
            ? Icons.restaurant_menu : Icons.add),
        label: Text(_menuTab == 'packages'
            ? 'Create Catering Package' : 'Add Food Item'),
      )),
      const SizedBox(height: 16),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title:
                Text(_catering ? 'Menu & packages' : 'Photography catalogue'),
            actions: [
              IconButton(
                  tooltip: 'Reload saved catalogue',
                  onPressed: _busy ? null : _reload,
                  icon: const Icon(Icons.refresh))
            ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: TextButton(
                        onPressed: _load, child: Text('$_error Retry')))
                : AbsorbPointer(
                    absorbing: _busy,
                    child:
                        ListView(padding: const EdgeInsets.all(16), children: [
                       if (_catering) _cateringHub(),
                      TextField(
                          controller: _about,
                           onChanged: (_) => setState(() => _hasUnsavedChanges = true),
                          maxLength: 3000,
                          maxLines: 3,
                          decoration: const InputDecoration(
                              labelText: 'About your business')),
                      Text('Additional service areas',
                          style: Theme.of(context).textTheme.titleMedium),
                      ref.watch(citiesProvider).when(
                            loading: () => const LinearProgressIndicator(),
                            error: (_, __) => TextButton(
                                onPressed: () => ref.invalidate(citiesProvider),
                                child: const Text('Retry service areas')),
                            data: (cities) => Wrap(spacing: 8, children: [
                              for (final city in cities)
                                FilterChip(
                                    label: Text(city.displayName),
                                    selected: _serviceCities.contains(city.id),
                                    onSelected: (on) => setState(() {
                                          _hasUnsavedChanges = true;
                                          if (on &&
                                              _serviceCities.length < 30) {
                                            _serviceCities.add(city.id);
                                          }
                                          if (!on) {
                                            _serviceCities.remove(city.id);
                                          }
                                        })),
                            ]),
                          ),
                      Text('Booking settings',
                          style: Theme.of(context).textTheme.titleMedium),
                      for (final (label, controller) in [
                        ('Minimum notice (days)', _notice),
                        ('Advance booking window (days)', _advance),
                        ('Max bookings per day', _perDay),
                      ])
                        TextField(
                            controller: controller,
                            keyboardType: TextInputType.number,
                             onChanged: (_) => setState(() => _hasUnsavedChanges = true),
                            decoration: InputDecoration(labelText: label)),
                      const SizedBox(height: 16),
                      Text('Gallery',
                          style: Theme.of(context).textTheme.titleMedium),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final photo in _photos)
                          if (eventPhoto(photo) case final image?)
                            Column(mainAxisSize: MainAxisSize.min, children: [
                              image,
                              TextButton(
                                  onPressed: () =>
                                      setState(() {
                                         _photos.remove(photo);
                                         _hasUnsavedChanges = true;
                                       }),
                                  child: const Text('Remove photo')),
                            ]),
                      ]),
                      TextButton.icon(
                        onPressed: _photos.length >= 24 ? null : _photo,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: const Text('Add photo'),
                      ),
                      if (!_catering)
                        for (final (index, item) in _items.indexed)
                          Card(child: ListTile(
                            title: Text(item['name']?.toString() ?? ''),
                            subtitle: Text('${item['kind']} · ${eventMoney(item['price'])}'),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: () => _edit(index),
                          )),
                      if (!_catering) ...[
                        TextButton.icon(
                          onPressed: _items.length >= 150
                              ? null
                              : () => _edit(null, createPackage: true),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Create wedding package'),
                        ),
                        TextButton.icon(
                          onPressed:
                              _items.length >= 150 ? null : () => _edit(null),
                          icon: const Icon(Icons.add),
                          label: const Text('Add individual service'),
                        ),
                      ],
                      GxButton(
                          label: _hasUnsavedChanges ? 'Save changes' : 'Save catalogue',
                          onTap: _save,
                          loading: _busy),
                    ])),
      );
}

class _CatalogueEntry extends StatefulWidget {
  const _CatalogueEntry(
      {required this.catering,
      required this.dishes,
      this.item,
      this.initialKind});
  final bool catering;
  final Map<String, dynamic>? item;
  final List<Map<String, dynamic>> dishes;
  final String? initialKind;

  @override
  State<_CatalogueEntry> createState() => _CatalogueEntryState();
}

class _CatalogueEntryState extends State<_CatalogueEntry> {
  final _form = GlobalKey<FormState>();
  late final Map<String, String> _fields = {
    'name': 'Name',
    'category': 'Event or collection',
    if (widget.catering) ...{
      'diet': 'Diet type',
      'serveStyle': 'Serving style'
    },
    'description': 'Description',
    'includes':
        widget.catering ? 'Included menu items' : 'Coverage and deliverables',
    if (!widget.catering) 'delivery': 'Delivery schedule',
    'paymentStages': 'Payment schedule',
    'policy': 'Cancellation and rescheduling terms',
  };
  late final _controllers = {
    for (final key in _fields.keys)
      key: TextEditingController(text: widget.item?[key]?.toString() ?? ''),
  };
  late final _price =
      TextEditingController(text: widget.item?['price']?.toString() ?? '');
  late final _tiers = <_GuestTier>[
    for (final row
        in (widget.item?['tiers'] as List? ?? const []).whereType<Map>())
      _GuestTier(row),
    if (widget.catering && widget.item == null) _GuestTier({'minGuests': 1}),
  ];
  late String _kind =
      widget.item?['kind'] as String? ?? widget.initialKind ?? 'PACKAGE';
  late bool _active = widget.item?['active'] != false;
  late final _dishIds =
      (widget.item?['dishIds'] as List? ?? []).whereType<String>().toSet();

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final tier in _tiers) {
      tier.dispose();
    }
    _price.dispose();
    super.dispose();
  }

  String? _number(String? value, int max) {
    final number = int.tryParse(value?.trim() ?? '');
    return number == null || number < 1 || number > max ? 'Enter 1–$max' : null;
  }

  void _finish() {
    if (!_form.currentState!.validate()) return;
    final tiers = _tiers.map((tier) => tier.values).toList()
      ..sort((a, b) => a['minGuests']!.compareTo(b['minGuests']!));
    var lastMax = 0;
    for (final tier in tiers) {
      if (tier['minGuests']! <= lastMax ||
          tier['minGuests']! > tier['maxGuests']!) {
        showGxSnack(
            context, 'Guest ranges must run from low to high without overlap.');
        return;
      }
      lastMax = tier['maxGuests']!;
    }
    if (widget.catering &&
        _kind == 'ITEM' &&
        _controllers['diet']!.text.trim().isEmpty) {
      _controllers['diet']!.text = 'veg';
    }
    Navigator.of(context).pop({
      'id': widget.item?['id'] ?? const Uuid().v4(),
      'kind': _kind,
      'active': _active,
      for (final field in _controllers.entries)
        field.key: field.value.text.trim(),
      if (widget.catering)
        'tiers': tiers
      else
        'price': int.parse(_price.text.trim()),
      if (widget.catering && _kind == 'PACKAGE') 'dishIds': _dishIds.toList(),
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.item == null
                ? 'Add to catalogue'
                : 'Edit catalogue entry')),
        body: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  const DropdownMenuItem(
                      value: 'PACKAGE', child: Text('Package')),
                  DropdownMenuItem(
                      value: 'ITEM',
                      child: Text(widget.catering
                          ? 'Individual dish'
                          : 'Individual service')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _kind = value);
                },
              ),
              for (final field in _fields.entries)
                if (widget.catering &&
                    _kind == 'ITEM' &&
                    field.key == 'category')
                  DropdownButtonFormField<String>(
                    initialValue: CateringMenuGroups.all.any((group) =>
                            group.id == _controllers['category']!.text)
                        ? _controllers['category']!.text
                        : null,
                    decoration:
                        const InputDecoration(labelText: 'Dish group *'),
                    items: [
                      for (final group in CateringMenuGroups.all)
                        DropdownMenuItem(
                          value: group.id,
                          child: Text(group.title),
                        ),
                    ],
                    validator: (value) =>
                        value == null ? 'Choose a dish group' : null,
                    onChanged: (value) =>
                        _controllers['category']!.text = value ?? '',
                  )
                else if (widget.catering &&
                    _kind == 'ITEM' &&
                    field.key == 'diet')
                  DropdownButtonFormField<String>(
                    initialValue:
                        _controllers['diet']!.text.toLowerCase().contains('non')
                            ? 'non_veg'
                            : 'veg',
                    decoration: const InputDecoration(labelText: 'Food type *'),
                    items: const [
                      DropdownMenuItem(value: 'veg', child: Text('Vegetarian')),
                      DropdownMenuItem(
                          value: 'non_veg', child: Text('Non-vegetarian')),
                    ],
                    onChanged: (value) =>
                        _controllers['diet']!.text = value ?? 'veg',
                  )
                else
                  TextFormField(
                    controller: _controllers[field.key],
                    maxLength: field.key == 'name' ? 150 : 3000,
                    decoration: InputDecoration(labelText: field.value),
                    maxLines: field.key == 'name' ? 1 : null,
                    validator: field.key == 'name'
                        ? (value) =>
                            (value ?? '').trim().isEmpty ? 'Enter a name' : null
                        : null,
                  ),
              if (widget.catering) ...[
                if (_kind == 'PACKAGE' && widget.dishes.isNotEmpty) ...[
                  const Text('Dishes in this package'),
                  for (final dish in widget.dishes)
                    CheckboxListTile(
                      title: Text(dish['name'] as String),
                      value: _dishIds.contains(dish['id']),
                      onChanged: (value) => setState(() {
                        final id = dish['id'] as String;
                        if (value == true) {
                          _dishIds.add(id);
                        } else {
                          _dishIds.remove(id);
                        }
                      }),
                    ),
                ],
                const Text('Per-plate pricing by guest count'),
                for (final tier in _tiers)
                  Row(key: ObjectKey(tier), children: [
                    for (final (label, controller, max) in [
                      ('Min guests', tier.min, 100000),
                      ('Max guests', tier.max, 100000),
                      ('₹ / plate', tier.price, 10000000),
                    ])
                      Expanded(
                          child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: TextFormField(
                                controller: controller,
                                decoration: InputDecoration(labelText: label),
                                keyboardType: TextInputType.number,
                                validator: (value) => _number(value, max),
                              ))),
                    IconButton(
                        tooltip: 'Remove tier',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _tiers.length <= 1
                            ? null
                            : () {
                                setState(() => _tiers.remove(tier));
                                WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => tier.dispose());
                              }),
                  ]),
                TextButton(
                    onPressed: _tiers.length >= 20
                        ? null
                        : () => setState(() => _tiers.add(_GuestTier({}))),
                    child: const Text('Add price tier')),
              ] else
                TextFormField(
                    controller: _price,
                    decoration: const InputDecoration(labelText: 'Price (₹)'),
                    keyboardType: TextInputType.number,
                    validator: (value) => _number(value, 10000000)),
              SwitchListTile(
                  title: const Text('Visible to customers'),
                  value: _active,
                  onChanged: (value) => setState(() => _active = value)),
              GxButton(label: 'Review and keep entry', onTap: _finish),
            ])),
      );
}

class _GuestTier {
  _GuestTier(Map item)
      : min = TextEditingController(text: item['minGuests']?.toString() ?? ''),
        max = TextEditingController(text: item['maxGuests']?.toString() ?? ''),
        price = TextEditingController(text: item['price']?.toString() ?? '');
  final TextEditingController min;
  final TextEditingController max;
  final TextEditingController price;

  Map<String, int> get values => {
        'minGuests': int.parse(min.text.trim()),
        'maxGuests': int.parse(max.text.trim()),
        'price': int.parse(price.text.trim()),
      };

  void dispose() {
    min.dispose();
    max.dispose();
    price.dispose();
  }
}
