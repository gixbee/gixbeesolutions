import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../repositories/cities_repository.dart';
import '../../repositories/events_repository.dart';
import '../../shared/widgets/gx_calendar.dart';
import 'catering_customer_flow_screen.dart';
import 'catering_customer_pricing.dart';
import 'event_plans_screen.dart';

/// Catering-specific search from the uploaded customer reference. All
/// provider records come from Rust discovery, never demo/placeholder data.
class CateringCustomerSearchScreen extends ConsumerStatefulWidget {
  const CateringCustomerSearchScreen({
    super.key, required this.eventType,
    required this.date, required this.guests,
  });

  final String eventType;
  final DateTime date;
  final int guests;

  @override
  ConsumerState<CateringCustomerSearchScreen> createState() =>
      _CateringCustomerSearchScreenState();
}

class _CateringCustomerSearchScreenState
    extends ConsumerState<CateringCustomerSearchScreen> {
  static const _forest = Color(0xFF14532D);
  static const _accent = Color(0xFF16A34A);
  final _area = TextEditingController();
  final _guestInput = TextEditingController();
  final _vendorQuery = TextEditingController();
  String? _cityId;
  late DateTime _day;
  int _guests = 1;
  String _category = 'all';
  double _minBudget = 0;
  double _maxBudget = 3000;
  Future<List<Map<String, dynamic>>>? _results;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _day = DateUtils.dateOnly(widget.date);
    _guests = widget.guests.clamp(1, 100000).toInt();
    _guestInput.text = '$_guests';
    _cityId = ref.read(currentCityProvider)?.id;
  }

  @override
  void dispose() {
    _area.dispose();
    _guestInput.dispose();
    _vendorQuery.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = await showGxCalendar(context,
      title: 'Catering event date',
      initialDate: _day.isBefore(today) ? today : _day,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)));
    if (!mounted || selected == null) return;
    setState(() {
      _day = selected;
      _searched = false;
    });
  }

  void _search() {
    final guests = int.tryParse(_guestInput.text.trim());
    if (_cityId == null || _area.text.trim().isEmpty ||
        guests == null || guests < 1 || guests > 100000 ||
        _day.isBefore(DateUtils.dateOnly(DateTime.now()))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a city, area, future date and valid guest count.')),
      );
      return;
    }
    setState(() {
      _guests = guests;
      _results = ref.read(eventsRepositoryProvider)
          .discover('CATERING', _cityId!);
      _searched = true;
    });
  }

  List<int> _packagePrices(Map<String, dynamic> vendor) {
    final catalogue = vendor['catalogue'] as Map? ?? const {};
    final all = CateringCustomerPrice.activeItems(catalogue);
    final matching = CateringCustomerPrice.filterPackages(all, _guests,
        eventCategory: _category);
    final candidates = matching.isEmpty && _category == 'all'
        ? CateringCustomerPrice.filterDishes(all, _guests)
        : matching;
    return [
      for (final item in candidates)
        if (CateringCustomerPrice.forItem(item, _guests)
            case final CateringCustomerPrice price)
          price.offerPerPlate,
    ]..sort();
  }

  List<Map<String, dynamic>> _matches(List<Map<String, dynamic>> vendors) {
    final search = _vendorQuery.text.trim().toLowerCase();
    return vendors.where((vendor) {
      final prices = _packagePrices(vendor);
      if (prices.isEmpty || !prices.any((price) =>
          price >= _minBudget.round() && price <= _maxBudget.round())) {
        return false;
      }
      final listingText =
          '${vendor['name'] ?? ''} ${vendor['location'] ?? ''}'.toLowerCase();
      return search.isEmpty || listingText.contains(search);
    }).toList()
      ..sort((a, b) {
        final aPrices = _packagePrices(a);
        final bPrices = _packagePrices(b);
        final priceOrder = aPrices.first.compareTo(bPrices.first);
        return priceOrder != 0 ? priceOrder :
            '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}');
      });
  }

  void _openVendor(Map<String, dynamic> vendor) {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => CateringCustomerProfileScreen(
        vendor: vendor,
        cityId: _cityId!,
        eventType: widget.eventType,
        date: _day,
        guests: _guests,
        location: _area.text.trim(),
        category: _category,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cities = ref.watch(citiesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_searched ? 'Catering Services' : 'Find Catering Services'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
              builder: (_) => const EventPlansScreen(interestService: 'CATERING'),
            )),
            child: const Text('My Interests'),
          ),
        ],
      ),
      body: _searched ? _resultsBody() : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(color: const Color(0xFFF0FDF4),
            child: Padding(padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Find Catering Services',
                    style: TextStyle(color: _forest,
                        fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                const Text('Weddings, receptions & other functions',
                    style: TextStyle(color: Color(0xFF166534))),
              ]),
            )),
          const SizedBox(height: 12),
          cities.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => TextButton(
              onPressed: () => ref.invalidate(citiesProvider),
              child: const Text('Reload cities')),
            data: (options) => DropdownButtonFormField<String>(
              initialValue: options.any((e) => e.id == _cityId) ? _cityId : null,
              decoration: const InputDecoration(
                labelText: 'Event city *', border: OutlineInputBorder()),
              items: [
                for (final city in options)
                  DropdownMenuItem(value: city.id,
                    child: Text(city.displayName)),
              ],
              onChanged: (value) => setState(() => _cityId = value),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _area,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Location / Area *',
              hintText: 'Town, area or venue',
              prefixIcon: Icon(Icons.location_on_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Event date'),
            subtitle: Text(DateFormat('EEE, dd MMM yyyy').format(_day)),
            trailing: const Icon(Icons.calendar_month_outlined),
            onTap: _pickDay,
          ),
          TextField(
            controller: _guestInput,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Number of Guests *',
              prefixIcon: Icon(Icons.people_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 17),
          const Text('What type of function? (Optional)',
            style: TextStyle(color: _forest, fontWeight: FontWeight.w900)),
          const SizedBox(height: 9),
          for (final (code, label, subtitle, icon) in const [
            ('Wedding & Related Functions', 'Wedding & Related',
                'Wedding, engagement, reception', '💍'),
            ('Other Functions', 'Other Functions',
                'Birthday, baptism, housewarming, etc.', '🎉'),
          ])
            Card(color: _category == code
                ? const Color(0xFFF0FDF4) : Colors.white,
              child: ListTile(
                leading: Text(icon, style: const TextStyle(fontSize: 27)),
                title: Text(label),
                subtitle: Text(subtitle),
                trailing: Icon(_category == code
                    ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: _accent),
                onTap: () => setState(() =>
                    _category = _category == code ? 'all' : code),
              ),
            ),
          const SizedBox(height: 18),
          const Text('Expected Budget per Plate (Optional)',
            style: TextStyle(color: _forest, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          RangeSlider(
            min: 0, max: 3000, divisions: 300,
            values: RangeValues(_minBudget, _maxBudget),
            onChanged: (value) => setState(() {
              _minBudget = value.start;
              _maxBudget = value.end;
            }),
          ),
          Center(child: Text(
            '${cateringMoney(_minBudget.round())} to '
            '${cateringMoney(_maxBudget.round())} per plate',
            style: const TextStyle(color: _forest,
                fontWeight: FontWeight.w800))),
          const SizedBox(height: 17),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent,
              padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: _search,
            child: const Text('Search Caterers'),
          ),
        ],
      ),
    );
  }

  Widget _resultsBody() => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${DateFormat('dd MMM yyyy').format(_day)} · '
            '$_guests guests · ${_area.text.trim()}',
            style: const TextStyle(fontWeight: FontWeight.w800, color: _forest))),
          TextButton(
            onPressed: () => setState(() => _searched = false),
            child: const Text('Edit search'),
          ),
        ]),
        const SizedBox(height: 7),
        TextField(
          controller: _vendorQuery,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Filter caterers by name or listed area',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 5),
        const Text('Results are serviceable by city. Exact venue availability '
          'is confirmed by the caterer after your enquiry.',
          style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
      ]),
    ),
    Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(
      future: _results,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return Center(
          child: TextButton(
            onPressed: _search,
            child: Text('${eventError(snapshot.error!)} Retry'),
          ),
        );
        final providers = _matches(snapshot.data ?? []);
        if (providers.isEmpty) return const Center(
          child: Padding(padding: EdgeInsets.all(20),
            child: Text('No caterers match this guest-count and budget range. '
                'Try increasing the per-plate budget or changing the function filter.')),
        );
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
          itemCount: providers.length,
          itemBuilder: (context, index) {
            final vendor = providers[index];
            final prices = _packagePrices(vendor);
            return Card(
              margin: const EdgeInsets.only(bottom: 11),
              child: InkWell(
                borderRadius: BorderRadius.circular(15),
                onTap: () => _openVendor(vendor),
                child: Padding(padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const SizedBox(width: 70,
                      child: Text('🍽️', style: TextStyle(fontSize: 44))),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(vendor['name']?.toString() ?? 'Caterer',
                          style: const TextStyle(color: _forest,
                              fontWeight: FontWeight.w900)),
                        Text(vendor['location']?.toString() ?? '',
                          style: const TextStyle(fontSize: 12,
                              color: Colors.blueGrey)),
                        const SizedBox(height: 5),
                        Text(
                          '${cateringMoney(prices.first)}'
                          '${prices.length == 1 ? '' : ' – ${cateringMoney(prices.last)}'} per plate',
                          style: const TextStyle(color: _forest,
                            fontWeight: FontWeight.w800)),
                        const Text('Availability on request',
                          style: TextStyle(fontSize: 11,
                            color: Colors.blueGrey)),
                      ]),
                    )),
                    const Icon(Icons.chevron_right),
                  ]),
                ),
              ),
            );
          },
        );
      },
    )),
  ]);
}
