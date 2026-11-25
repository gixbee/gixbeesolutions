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
import 'photography_owner_pricing.dart';
import 'service_areas_flow_screen.dart';
import 'decoration_entry_screen.dart';
import '../../shared/widgets/gx_network_error.dart';

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
  Set<String> _serviceAreas = {};
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
  String _photoLevel = 'all';
  bool get _catering => widget.service == 'CATERING';
  bool get _photography => widget.service == 'PHOTOGRAPHY';
  bool get _decoration => widget.service == 'DECORATION';

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
        _serviceAreas = (catalogue['serviceAreaIds'] as List? ?? [])
            .map((id) => id.toString())
            .where((id) => id.isNotEmpty)
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
          if (_catering || _photography)
            'serviceAreaIds': _serviceAreas.toList(),
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
      // The wizard shows its own inline retry error. A snackbar from the
      // parent Scaffold would cover the wizard's bottom Save button.
      if (mounted && entries == null) {
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
      if (mounted) {
        setState(() {
          _photos.add(url);
          _hasUnsavedChanges = true;
        });
      }
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
    final photoPackageFlow = _photography &&
        (original?['kind'] == 'PACKAGE' || (index == null && createPackage));
    final photoServiceFlow = _photography &&
        (original?['kind'] == 'ITEM' || (index == null && !createPackage));
    final dishes = _items.where((item) => item['kind'] == 'ITEM').toList();
    final updated = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => _decoration
            ? DecorationEntryScreen(
                item: original,
                createPackage: index == null && createPackage,
                onSave: (entry) => _savePackage(entry, index),
              )
            : packageFlow
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
                ? PhotographyPackageWizardScreen(
                  package: original,
                  onSave: (entry) => _savePackage(entry, index),
                )
                : photoServiceFlow
                    ? PhotographyServiceWizardScreen(
                        service: original,
                        onSave: (entry) => _savePackage(entry, index),
                      )
                    : _CatalogueEntry(
                        catering: _catering,
                        item: original,
                        dishes: dishes,
                        initialKind: index == null ? 'ITEM' : null,
                      ),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() {
      if (index == null) {
        _items.add(updated);
      } else {
        _items[index] = updated;
      }
      _hasUnsavedChanges = true;
    });
  }

  Future<void> _archivePhoto(int index) async {
    final item = _items[index];
    if (item['active'] == false) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Move this listing to Draft?'),
        content: Text('"${item['name']}" will no longer appear in customer '
            'searches. Past customer enquiries will retain their price snapshots.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Move to Draft')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _savePackage({...item, 'active': false}, index);
  }

  Widget _photographyHub() {
    const navy = Color(0xFF1B2559);
    const pink = Color(0xFFDB2777);
    final packagesTab = _menuTab == 'packages';
    final packages = _items.where((entry) => entry['kind'] == 'PACKAGE').length;
    final services = _items.where((entry) => entry['kind'] == 'ITEM').length;
    final matches = PhotographyOwnerPrice.visible(_items,
      packages: packagesTab,
      status: _menuStatus,
      level: _photoLevel,
      search: _menuSearch);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF3),
          borderRadius: BorderRadius.circular(15)),
        padding: const EdgeInsets.all(16),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gixbee  |  Photography catalogue', style:
              TextStyle(color: navy, fontWeight: FontWeight.w900, fontSize: 18)),
            SizedBox(height: 6),
            Text('Wedding packages and standalone photography services. '
                'Manage pricing, inclusions and customer visibility.',
              style: TextStyle(color: Color(0xFF475569))),
          ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        for (final (tab, label, count) in [
          ('packages', 'Wedding packages', packages),
          ('services', 'Individual services', services),
        ])
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() { _menuTab = tab; _photoLevel = 'all'; }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 12),
                decoration: BoxDecoration(
                  color: _menuTab == tab
                    ? const Color(0xFFFDF2F8) : Colors.white,
                  border: Border.all(color: _menuTab == tab
                    ? pink : const Color(0xFFE5E7EB),
                    width: _menuTab == tab ? 2 : 1),
                  borderRadius: BorderRadius.circular(12)),
                child: Text('$label ($count)', maxLines: 2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: _menuTab == tab ? pink : navy)),
              ),
            ),
          )),
      ]),
      const SizedBox(height: 14),
      TextField(
        onChanged: (value) => setState(() => _menuSearch = value),
        decoration: InputDecoration(
          hintText: packagesTab ? 'Search wedding packages...' :
              'Search individual services...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12)),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 7, runSpacing: 7, children: [
        for (final (value, label) in const [
          ('all', 'All'), ('live', 'Live'), ('draft', 'Draft'),
        ])
          ChoiceChip(label: Text(label),
            selected: _menuStatus == value,
            onSelected: (_) => setState(() => _menuStatus = value)),
        if (packagesTab)
          for (final (value, label) in const [
            ('Basic', 'Basic'), ('Standard', 'Standard'),
            ('Premium', 'Premium'),
          ])
            ChoiceChip(label: Text(label),
              selected: _photoLevel == value,
              onSelected: (_) => setState(() =>
                _photoLevel = _photoLevel == value ? 'all' : value)),
      ]),
      const SizedBox(height: 8),
      Text('${matches.length} ${packagesTab ? 'packages' : 'individual services'}',
        style: const TextStyle(color: navy, fontWeight: FontWeight.w800)),
      if (matches.isEmpty)
        Padding(padding: const EdgeInsets.all(18),
          child: Text(packagesTab
            ? 'No wedding packages match the selected filters.'
            : 'No individual services match the selected filters.')),
      for (final entry in _items.indexed)
        if (matches.any((item) => item['id'] == entry.$2['id']))
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('📷', style: TextStyle(fontSize: 30)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(entry.$2['name']?.toString() ?? 'Untitled',
                        style: const TextStyle(
                          color: navy, fontWeight: FontWeight.w900)),
                      Text([
                        packagesTab ? '${entry.$2['packageLevel'] ?? 'Standard'}' :
                          '${entry.$2['category'] ?? 'Service'}',
                        entry.$2['active'] == false ? 'Draft' : 'Live',
                      ].join(' · '),
                        style: const TextStyle(color: Color(0xFF64748B))),
                    ]),
                  ),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 9, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('₹${entry.$2['price'] ?? '—'}',
                    style: const TextStyle(color: navy,
                      fontWeight: FontWeight.w900, fontSize: 17)),
                  if ((entry.$2['discountPct'] as num? ?? 0) > 0 &&
                      entry.$2['listPrice'] is num) ...[
                    Text('₹${entry.$2['listPrice']}',
                      style: const TextStyle(color: Colors.blueGrey,
                        decoration: TextDecoration.lineThrough)),
                    Text('${entry.$2['discountPct']}% OFF',
                      style: const TextStyle(color: pink,
                        fontWeight: FontWeight.w800)),
                  ],
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _edit(entry.$1),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                  const SizedBox(width: 8),
                  if (entry.$2['active'] != false)
                    TextButton.icon(
                      onPressed: _busy ? null : () => _archivePhoto(entry.$1),
                      icon: const Icon(Icons.visibility_off_outlined, size: 18),
                      label: const Text('Move to Draft'),
                    ),
                ]),
              ]),
            ),
          ),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: packagesTab ? pink : const Color(0xFF2563EB),
            padding: const EdgeInsets.symmetric(vertical: 15)),
          onPressed: _busy || _items.length >= 150
            ? null : () => _edit(null, createPackage: packagesTab),
          icon: const Icon(Icons.add),
          label: Text(packagesTab ? 'Add wedding package'
            : 'Add individual service'),
        ),
      ),
      const SizedBox(height: 18),
    ]);
  }

  Widget _decorationHub() {
    final packagesTab = _menuTab == 'packages';
    final packages = _items.where((item) => item['kind'] == 'PACKAGE').length;
    final services = _items.where((item) => item['kind'] == 'ITEM').length;
    final matches = _items.indexed.where((entry) {
      final item = entry.$2;
      if ((item['kind'] == 'PACKAGE') != packagesTab) return false;
      if (_menuStatus == 'live' && item['active'] == false) return false;
      if (_menuStatus == 'draft' && item['active'] != false) return false;
      return (item['name']?.toString() ?? '')
          .toLowerCase().contains(_menuSearch.toLowerCase());
    }).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Decoration catalogue',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Create packages, individual services and optional add-ons. '
          'Customers request a quote before a booking is confirmed.'),
      const SizedBox(height: 14),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'packages', label: Text('Packages ($packages)')),
          ButtonSegment(value: 'services',
              label: Text('Services / add-ons ($services)')),
        ],
        selected: {_menuTab},
        onSelectionChanged: (values) => setState(() => _menuTab = values.first),
      ),
      const SizedBox(height: 12),
      TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          labelText: 'Search decoration listings'),
        onChanged: (value) => setState(() => _menuSearch = value),
      ),
      Wrap(spacing: 8, children: [
        for (final (value, label) in const [
          ('all', 'All'), ('live', 'Live'), ('draft', 'Draft')
        ])
          ChoiceChip(label: Text(label),
            selected: _menuStatus == value,
            onSelected: (_) => setState(() => _menuStatus = value)),
      ]),
      if (matches.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('No decoration listings match the filters.'))),
      for (final entry in matches)
        Card(margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            title: Text(entry.$2['name']?.toString() ?? 'Untitled'),
            subtitle: Text([
              if (entry.$2['addon'] == true) 'Optional add-on',
              if ((entry.$2['category']?.toString() ?? '').isNotEmpty)
                entry.$2['category'].toString(),
              if (entry.$2['price'] != null)
                '₹${entry.$2['price']}',
              entry.$2['active'] == false ? 'Draft' : 'Published',
            ].join(' · ')),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _edit(entry.$1),
          )),
      const SizedBox(height: 10),
      GxButton(label: packagesTab ? 'Create package' : 'Add service / add-on',
        icon: Icons.add,
        onTap: _items.length >= 150 ? null :
            () => _edit(null, createPackage: packagesTab)),
      const SizedBox(height: 16),
    ]);
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

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(title,
            style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF1B2559),
                fontWeight: FontWeight.w800)),
      );

  Widget _labeledField({
    String? label,
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (label != null) ...[
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          onChanged: (_) => setState(() => _hasUnsavedChanges = true),
          decoration: InputDecoration(
            hintText: hint,
            floatingLabelBehavior: FloatingLabelBehavior.never,
          ),
        ),
      ]),
    );
  }

  Widget _serviceAreasEntry() {
    final count = _serviceAreas.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          count == 0
              ? 'No service areas selected yet.'
              : '$count service ${count == 1 ? 'area' : 'areas'} selected.',
          style: const TextStyle(
              fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    final picked = await Navigator.push<Set<String>>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServiceAreasFlowScreen(
                          business: widget.business,
                          service: widget.service,
                          persist: false,
                          initialAreaIds: _serviceAreas,
                        ),
                      ),
                    );
                    if (picked == null || !mounted) return;
                    setState(() {
                      _serviceAreas = picked;
                      _hasUnsavedChanges = true;
                    });
                  },
            icon: const Icon(Icons.map_outlined),
            label: const Text('Manage service areas'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title:
                Text(_catering ? 'Menu & packages' : _decoration ? 'Decoration catalogue' : 'Photography catalogue'),
            actions: [
              IconButton(
                  tooltip: 'Reload saved catalogue',
                  onPressed: _busy ? null : _reload,
                  icon: const Icon(Icons.refresh))
            ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? GxNetworkError(
                    error: _error, title: 'Catalogue unavailable',
                    onRetry: _load)
                : AbsorbPointer(
                    absorbing: _busy,
                    child:
                        ListView(padding: const EdgeInsets.all(16), children: [
                       if (_catering) _cateringHub()
                        else if (_decoration) _decorationHub()
                        else _photographyHub(),
                      _sectionTitle('About your business'),
                      _labeledField(
                        controller: _about,
                        hint: 'What customers should know before they book',
                        maxLines: 4,
                        maxLength: 3000,
                      ),
                      _sectionTitle('Additional service areas'),
                      if (_catering || _photography)
                        _serviceAreasEntry()
                      else
                      ref.watch(citiesProvider).when(
                            loading: () => const LinearProgressIndicator(),
                            error: (_, __) => TextButton(
                                onPressed: () => ref.invalidate(citiesProvider),
                                child: const Text('Retry service areas')),
                            data: (cities) => Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final city in cities)
                                      FilterChip(
                                        label: Text(city.displayName),
                                        selected:
                                            _serviceCities.contains(city.id),
                                        showCheckmark: false,
                                        selectedColor: const Color(0xFFD1FAE5),
                                        labelStyle: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _serviceCities
                                                  .contains(city.id)
                                              ? const Color(0xFF047857)
                                              : const Color(0xFF334155),
                                        ),
                                        side: BorderSide(
                                          color: _serviceCities
                                                  .contains(city.id)
                                              ? const Color(0xFF12B76A)
                                              : const Color(0xFFE2E8F0),
                                        ),
                                        onSelected: (on) => setState(() {
                                          _hasUnsavedChanges = true;
                                          if (on &&
                                              _serviceCities.length < 30) {
                                            _serviceCities.add(city.id);
                                          }
                                          if (!on) {
                                            _serviceCities.remove(city.id);
                                          }
                                        }),
                                      ),
                                  ],
                                ),
                          ),
                      _sectionTitle('Booking settings'),
                      _labeledField(
                        label: 'Minimum notice (days)',
                        controller: _notice,
                        keyboardType: TextInputType.number,
                      ),
                      _labeledField(
                        label: 'Advance booking window (days)',
                        controller: _advance,
                        keyboardType: TextInputType.number,
                      ),
                      _labeledField(
                        label: 'Max bookings per day',
                        controller: _perDay,
                        keyboardType: TextInputType.number,
                      ),
                      _sectionTitle('Gallery'),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final photo in _photos)
                          if (eventPhoto(photo) case final image?)
                            Column(mainAxisSize: MainAxisSize.min, children: [
                              image,
                              TextButton(
                                  onPressed: () => setState(() {
                                        _photos.remove(photo);
                                        _hasUnsavedChanges = true;
                                      }),
                                  child: const Text('Remove photo')),
                            ]),
                      ]),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _photos.length >= 24 ? null : _photo,
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: const Text('Add photo'),
                        ),
                      ),
                      const SizedBox(height: 8),
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
