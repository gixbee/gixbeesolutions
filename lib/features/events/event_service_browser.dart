import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../repositories/cities_repository.dart';
import '../../repositories/events_repository.dart';
import '../../shared/media/profile_photo.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_calendar.dart';
import 'event_plan_create_screen.dart';
import 'event_plans_screen.dart';
import 'event_interest_customize_screen.dart';
import 'hall_booking_review_screen.dart';
import 'catering_package_wizard_screen.dart';

class EventServiceBrowser extends ConsumerStatefulWidget {
  const EventServiceBrowser({
    super.key,
    required this.service,
    required this.eventType,
    required this.date,
    required this.guests,
  });

  final String service;
  final String eventType;
  final DateTime date;
  final int guests;

  @override
  ConsumerState<EventServiceBrowser> createState() =>
      _EventServiceBrowserState();
}

class _EventServiceBrowserState extends ConsumerState<EventServiceBrowser> {
  String? _city;
  Future<List<Map<String, dynamic>>>? _vendors;
  String _search = '';
  String _sort = 'name';
  String _hallSpace = 'all';
  int? _maxUnitPrice;

  int? _startingPrice(Map<String, dynamic> vendor) {
    if (widget.service == 'HALL') return null;
    final catalogue = vendor['catalogue'];
    final items = catalogue is Map ? (catalogue['items'] as List? ?? []) : [];
    final prices = <int>[];
    for (final item in items.whereType<Map>()) {
      if (item['active'] == false) continue;
      if (widget.service == 'PHOTOGRAPHY' && item['price'] is num) {
        prices.add((item['price'] as num).round());
      } else if (widget.service == 'CATERING') {
        for (final tier in (item['tiers'] as List? ?? []).whereType<Map>()) {
          final min = tier['minGuests'];
          final max = tier['maxGuests'];
          if (min is num && max is num && min <= widget.guests &&
              widget.guests <= max && tier['price'] is num) {
            prices.add((tier['price'] as num).round());
          }
        }
      }
    }
    if (prices.isEmpty) return null;
    prices.sort();
    return prices.first;
  }

  @override
  void initState() {
    super.initState();
    final city = ref.read(currentCityProvider)?.id;
    if (city != null) _load(city);
  }

  void _load(String city) {
    _city = city;
    _vendors =
        ref.read(eventsRepositoryProvider).discover(widget.service, city);
  }

  @override
  Widget build(BuildContext context) {
    final cities = ref.watch(citiesProvider);
    final title = switch (widget.service) {
      'HALL' => 'Find a hall',
      'CATERING' => 'Find a caterer',
      _ => 'Find a photographer',
    };
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [
        TextButton(
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => EventPlansScreen(
              interestService: widget.service == 'HALL' ? null : widget.service,
            ),
          )),
          child: Text(widget.service == 'HALL' ? 'My events' : 'My interests'),
        ),
        PopupMenuButton<String>(
          onSelected: (_) => Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => EventPlanCreateScreen(
              eventType: widget.eventType,
              date: widget.date,
              guests: widget.guests,
              services: [widget.service],
            ),
          )),
          itemBuilder: (_) => const [
            PopupMenuItem(
                value: 'general', child: Text('Send a general enquiry')),
          ],
        ),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            cities.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => TextButton(
                onPressed: () => ref.invalidate(citiesProvider),
                child: const Text('Reload cities'),
              ),
              data: (items) => DropdownButtonFormField<String>(
                initialValue:
                    items.any((city) => city.id == _city) ? _city : null,
                decoration: const InputDecoration(labelText: 'Event city'),
                items: [
                  for (final city in items)
                    DropdownMenuItem(
                        value: city.id, child: Text(city.displayName)),
                ],
                onChanged: (city) {
                  if (city != null) setState(() => _load(city));
                },
              ),
            ),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search by name or area',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => _search = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 7),
            Wrap(spacing: 12, runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center, children: [
              DropdownButton<String>(
                value: _sort,
                items: [
                  const DropdownMenuItem(value: 'name', child: Text('Name')),
                  if (widget.service != 'HALL')
                    const DropdownMenuItem(
                        value: 'price', child: Text('Lowest price')),
                ],
                onChanged: (value) => setState(() => _sort = value ?? 'name'),
              ),
              if (widget.service == 'HALL')
                DropdownButton<String>(
                  value: _hallSpace,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All spaces')),
                    DropdownMenuItem(value: 'indoor', child: Text('Indoor')),
                    DropdownMenuItem(value: 'outdoor', child: Text('Outdoor')),
                  ],
                  onChanged: (value) =>
                      setState(() => _hallSpace = value ?? 'all'),
                )
              else
                DropdownButton<int?>(
                  value: _maxUnitPrice,
                  items: const [
                    DropdownMenuItem<int?>(
                        value: null, child: Text('Any price')),
                    DropdownMenuItem<int?>(
                        value: 1000, child: Text('Up to ₹1,000')),
                    DropdownMenuItem<int?>(
                        value: 5000, child: Text('Up to ₹5,000')),
                    DropdownMenuItem<int?>(
                        value: 25000, child: Text('Up to ₹25,000')),
                    DropdownMenuItem<int?>(
                        value: 100000, child: Text('Up to ₹1,00,000')),
                  ],
                  onChanged: (v) => setState(() => _maxUnitPrice = v),
                ),
              ],
            ),
          ]),
        ),
        Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _vendors,
          builder: (context, snapshot) {
            if (_city == null) {
              return const Center(child: Text('Choose an event city.'));
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                  child: TextButton(
                onPressed: () => setState(() => _load(_city!)),
                child: Text('${eventError(snapshot.error!)} Retry'),
              ));
            }
            final vendors = snapshot.data!
                .where((vendor) =>
                    '${vendor['name'] ?? vendor['hallName']} ${vendor['businessName'] ?? ''} ${vendor['location'] ?? ''}'
                        .toLowerCase()
                        .contains(_search))
                .where((vendor) => widget.service != 'HALL' ||
                    _hallSpace == 'all' ||
                    '${vendor['spaceType'] ?? ''}'.toLowerCase() == _hallSpace)
                .where((vendor) => _maxUnitPrice == null ||
                    (_startingPrice(vendor) ?? 2147483647) <= _maxUnitPrice!)
                .toList()
              ..sort((a, b) {
                if (_sort == 'price') {
                  final byPrice = (_startingPrice(a) ?? 2147483647)
                      .compareTo(_startingPrice(b) ?? 2147483647);
                  if (byPrice != 0) return byPrice;
                }
                return '${a['name'] ?? a['hallName'] ?? ''}'
                    .compareTo('${b['name'] ?? b['hallName'] ?? ''}');
              });
            if (vendors.isEmpty) {
              return const Center(child: Text('No matching listings.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: vendors.length,
              itemBuilder: (context, index) {
                final vendor = vendors[index];
                final photos =
                    (vendor['catalogue'] as Map?)?['photos'] as List? ?? [];
                final cover = vendor['coverImageUrl']?.toString() ??
                    photos.firstOrNull?.toString();
                final price = _startingPrice(vendor);
                return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                    child: ListTile(
                  contentPadding: const EdgeInsets.all(10),
                  leading: eventPhoto(cover, width: 82, height: 76) ??
                      const SizedBox(width: 82, child: Icon(Icons.storefront)),
                  title: Text('${vendor['name'] ?? vendor['hallName']}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text([
                    '${vendor['businessName'] ?? ''}',
                    '${vendor['location'] ?? ''}',
                    if (price != null)
                      'From ${eventMoney(price)}${widget.service == 'CATERING' ? ' / plate' : ''}',
                    if (widget.service == 'HALL')
                      '${vendor['spaceType'] ?? 'Hall'}',
                  ].where((value) => value.trim().isNotEmpty).join('\n')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final city = _city!;
                    await Navigator.of(context).push<void>(MaterialPageRoute(
                      builder: (_) => _ProviderDetail(
                        service: widget.service,
                        eventType: widget.eventType,
                        date: widget.date,
                        guests: widget.guests,
                        city: city,
                        vendor: vendor,
                      ),
                    ));
                    if (mounted) setState(() => _load(city));
                  },
                ));
              },
            );
          },
        )),
      ]),
    );
  }
}

Widget? eventPhoto(String? path, {double width = 150, double height = 100}) {
  final url = resolveProfileImageUrl(path);
  if (url == null) return null;
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Image.network(
      url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => SizedBox(
        width: width,
        height: height,
        child: const Icon(Icons.broken_image_outlined),
      ),
    ),
  );
}

class _ProviderDetail extends ConsumerStatefulWidget {
  const _ProviderDetail({
    required this.service,
    required this.eventType,
    required this.date,
    required this.guests,
    required this.city,
    required this.vendor,
  });

  final String service;
  final String eventType;
  final DateTime date;
  final int guests;
  final String city;
  final Map<String, dynamic> vendor;

  @override
  ConsumerState<_ProviderDetail> createState() => _ProviderDetailState();
}

class _ProviderDetailState extends ConsumerState<_ProviderDetail> {
  final _requirements = TextEditingController();
  final _coverage = TextEditingController();
  final _delivery = TextEditingController();
  final Map<String, Map> _selected = {};
  late DateTime _day = widget.date;
  late int _guests = widget.guests;
  late final _guestInput = TextEditingController(text: '$_guests');
  Future<Map<String, dynamic>>? _hall;
  String _diet = 'All';
  String _kind = 'All';
  int? _unitBudget;
  String _category = 'All';

  bool get _isHall => widget.service == 'HALL';
  bool get _isCatering => widget.service == 'CATERING';
  Map get _catalogue => widget.vendor['catalogue'] as Map? ?? {};

  String _categoryLabel(String value) {
    for (final group in CateringMenuGroups.all) {
      if (group.id == value) return group.title;
    }
    return value;
  }

  String _detailText(Object? value) {
    if (value is List) return value.join(', ');
    return value?.toString() ?? '';
  }

  @override
  void initState() {
    super.initState();
    if (_isHall) _loadHall();
  }

  void _loadHall() {
    _hall = ref.read(eventsRepositoryProvider).hallDetails(
          widget.vendor['hallId'] as String,
          DateFormat('yyyy-MM-dd').format(_day),
        );
  }

  @override
  void dispose() {
    _requirements.dispose();
    _coverage.dispose();
    _delivery.dispose();
    _guestInput.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showGxCalendar(context,
        title: 'Event date',
        initialDate: _day,
        firstDate: today,
        lastDate: today.add(const Duration(days: 730)));
    if (!mounted || picked == null) return;
    setState(() {
      _day = picked;
      if (_isHall) _loadHall();
    });
  }

  int? _price(Map item) {
    if (!_isCatering) return (item['price'] as num?)?.toInt();
    for (final tier in (item['tiers'] as List? ?? []).whereType<Map>()) {
      if (_guests >= (tier['minGuests'] as num) &&
          _guests <= (tier['maxGuests'] as num)) {
        return (tier['price'] as num).toInt();
      }
    }
    return null;
  }

  void _review(EventServiceSelection selection, {Map<String, dynamic>? hall}) {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => _isHall && hall != null
          ? HallBookingReviewScreen(
              hall: hall,
              selection: selection,
              eventType: widget.eventType,
              eventDate: _day,
              guests: _guests,
            )
          : EventInterestCustomizeScreen(
              service: widget.service,
              selection: selection,
              eventType: widget.eventType,
              eventDate: _day,
              guests: _guests,
            ),
    ));
  }

  void _reviewItems() {
    final items = _selected.values.toList();
    final unitTotal =
        items.fold(0, (total, item) => total + (_price(item) ?? 0));
    final estimate = unitTotal * (_isCatering ? _guests : 1);
    _review(EventServiceSelection(
      businessId: widget.vendor['businessId'] as String,
      cityId: widget.city,
      summary:
          '${widget.vendor['name']} · ${items.map((item) => item['name']).join(', ')}\n'
          'Estimated total ${eventMoney(estimate)}',
      requirements: [
        if (_coverage.text.trim().isNotEmpty)
          'Coverage: ${_coverage.text.trim()}',
        if (_delivery.text.trim().isNotEmpty)
          'Deliverables: ${_delivery.text.trim()}',
        _requirements.text.trim(),
      ].where((value) => value.isNotEmpty).join('\n'),
      request: {
        'itemIds': items.map((item) => item['id']).toList(),
        'expectedEstimate': estimate
      },
    ));
  }

  Widget _gallery(List photos) {
    final images = photos
        .map((photo) => eventPhoto(photo?.toString()))
        .whereType<Widget>()
        .toList();
    return Wrap(spacing: 8, runSpacing: 8, children: images);
  }

  List<Widget> _hallBody(Map data) {
    final pkg = data['package'] as Map;
    final capacity = pkg['capacity'] as Map? ?? {};
    final parking = data['parking'] as Map? ?? {};
    final payment = pkg['payment'] as Map? ?? {};
    final slots = (data['slots'] as List? ?? []).whereType<Map>();
    return [
      _gallery([data['coverImageUrl'], ...(data['photos'] as List? ?? [])]),
      Text('${data['businessName']} · ${data['location'] ?? ''}'),
      Text(
          'Seats ${capacity['seat'] ?? '—'} · Dining ${capacity['dine'] ?? '—'}'),
      Text(
          'Parking · ${parking['car'] ?? 0} cars · ${parking['bike'] ?? 0} bikes'),
      if (pkg['facilities'] is List)
        Text((pkg['facilities'] as List).join(' · ')),
      if (payment.isNotEmpty)
        Text(
            'Advance · ${payment['advanceType'] == 'percent' ? '${payment['advancePct']}%' : eventMoney(payment['advanceFixed'])} paid to the hall'),
      ExpansionTile(
        title: const Text('Booking and cancellation policies'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (payment['fullDueDays'] != null)
            Text(
                'Full payment due ${payment['fullDueDays']} days before the event'),
          for (final (key, label) in [
            ('cancelRules', 'Cancellation'),
            ('rescheduleRules', 'Rescheduling'),
          ])
            for (final tier in (pkg[key] as List? ?? []).whereType<Map>())
              Text('$label · ${tier['minDaysBeforeEvent'] ?? 0}'
                  '${tier['maxDaysBeforeEvent'] == null ? '+' : '–${tier['maxDaysBeforeEvent']}'} days before'
                  ' · ${tier['deductionPercent']}% of '
                  '${pkg['deductionBasis'] == 'TOTAL' ? 'the total' : 'the advance'}'),
        ],
      ),
      const SizedBox(height: 12),
      if (slots.isEmpty) const Text('No slots are listed for this date.'),
      for (final slot in slots)
        Card(
            child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '${slot['offer']['label']} · ${slot['offer']['hallFrom']}–${slot['offer']['hallTo']} IST'),
            if (slot['available'] != true) const Text('Unavailable'),
            for (final withAc in [false, true])
              if (slot['available'] == true &&
                  slot['offer'][withAc ? 'offerAc' : 'offerNoAc'] == true)
                TextButton(
                  onPressed: _guests < 1 || _guests > 100000
                      ? null
                      : () => _review(EventServiceSelection(
                            businessId: data['businessId'] as String,
                            cityId: widget.city,
                            start: DateTime.parse(slot['start'] as String),
                            end: DateTime.parse(slot['end'] as String),
                            address: data['location']?.toString(),
                            requirements: _requirements.text,
                            summary:
                                '${data['hallName']} · ${slot['offer']['label']} · ${withAc ? 'With AC' : 'Without AC'}\n'
                                '${eventMoney(slot['offer'][withAc ? 'priceAc' : 'priceNoAc'])}',
                            request: {
                              'hallId': data['hallId'],
                              'slotId': slot['offer']['id'],
                              'withAc': withAc,
                              'expectedEstimate': slot['offer']
                                  [withAc ? 'priceAc' : 'priceNoAc'],
                            },
                          ), hall: data),
                  child: Text(
                      '${withAc ? 'With AC' : 'Without AC'} · ${eventMoney(slot['offer'][withAc ? 'priceAc' : 'priceNoAc'])}'),
                ),
          ]),
        )),
    ];
  }

  List<Widget> _catalogueBody() {
    final all = (_catalogue['items'] as List? ?? [])
        .whereType<Map>()
        .where((item) => item['active'] != false)
        .toList();
    final diets = {
      'All',
      ...all
          .map((item) => item['diet'])
          .whereType<String>()
          .where((value) => value.isNotEmpty)
    };
    final items = all.where((item) =>
        (_diet == 'All' || _diet == item['diet']) &&
        (_category == 'All' || _category == item['category']) &&
        (_kind == 'All' || _kind == item['kind']) &&
        (_unitBudget == null ||
            (_price(item) ?? _unitBudget! + 1) <= _unitBudget!));
    return [
      _gallery(_catalogue['photos'] as List? ?? []),
      if ('${_catalogue['about'] ?? ''}'.isNotEmpty)
        Text('${_catalogue['about']}'),
      Wrap(spacing: 8, children: [
        for (final (kind, label) in [
          ('All', 'All'),
          ('PACKAGE', 'Packages'),
          ('ITEM', _isCatering ? 'Dishes' : 'Individual services'),
        ])
          ChoiceChip(
              label: Text(label),
              selected: _kind == kind,
              onSelected: (_) => setState(() => _kind = kind)),
      ]),
      TextField(
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: _isCatering ? 'Max price per plate (₹)' : 'Max price (₹)',
        ),
        onChanged: (value) =>
            setState(() => _unitBudget = int.tryParse(value.trim())),
      ),
      if (_isCatering)
        DropdownButtonFormField<String>(
          initialValue: _category == 'All' ||
                  all.any((item) => item['category'] == _category)
              ? _category : 'All',
          decoration: const InputDecoration(
              labelText: 'Dish / package category'),
          items: [
            const DropdownMenuItem(
                value: 'All', child: Text('All categories')),
            for (final category in all.map((item) => item['category'])
                .whereType<String>().where((name) => name.isNotEmpty).toSet())
              DropdownMenuItem(
                value: category, child: Text(_categoryLabel(category))),
          ],
          onChanged: (value) =>
              setState(() => _category = value ?? 'All'),
        ),
      if (_isCatering && diets.length > 1)
        Wrap(spacing: 8, children: [
          for (final diet in diets)
            ChoiceChip(
                label: Text(diet),
                selected: _diet == diet,
                onSelected: (_) => setState(() => _diet = diet)),
        ]),
      for (final item in items)
        Card(
            child: CheckboxListTile(
          value: _selected.containsKey(item['id']),
          title: Text('${item['name']}'),
          subtitle: Text([
            item['kind'] == 'PACKAGE'
                ? 'Package'
                : (_isCatering ? 'Dish' : 'Service'),
            if (item['menuItems'] case final List dishes when dishes.isNotEmpty)
              dishes.join(' · '),
            if (_price(item) case final price?)
              '${eventMoney(price)}${_isCatering ? ' per plate' : ''}'
            else
              'Unavailable for this guest count',
            for (final key in [
              'diet', 'serveStyle', 'description',
              'packageLevel', 'functions', 'ceremonies',
              'coverageNotes', 'photographerTeam', 'videographerTeam',
              'duration', 'team', 'includes', 'inclusions',
              'extras', 'extrasNotes', 'delivery',
              'paymentStages', 'policy',
            ])
              if (_detailText(item[key]).isNotEmpty)
                '${key.replaceAll(RegExp(r'([A-Z])'), r' $1')}: ${_detailText(item[key])}',
          ].join('\n')),
          onChanged: _price(item) == null
              ? null
              : (selected) => setState(() {
                    final id = item['id'] as String;
                    if (selected != true) {
                      _selected.remove(id);
                      return;
                    }
                    if (!_isCatering ||
                        item['kind'] == 'PACKAGE' ||
                        _selected.values
                            .any((item) => item['kind'] == 'PACKAGE')) {
                      _selected.clear();
                    }
                    if (_selected.length < 20) _selected[id] = item;
                  }),
        )),
      if (items.isEmpty) const Text('No matching packages or services.'),
      if (_selected.isNotEmpty)
        GxButton(
            label: 'Review interest',
            onTap: _guests < 1 || _guests > 100000 ? null : _reviewItems),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title:
                Text('${widget.vendor['hallName'] ?? widget.vendor['name']}')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Event date'),
            subtitle: Text(DateFormat.yMMMd().format(_day)),
            onTap: _pickDay,
            trailing: const Icon(Icons.calendar_month_outlined),
          ),
          TextField(
            controller: _guestInput,
            decoration: const InputDecoration(labelText: 'Guest count'),
            keyboardType: TextInputType.number,
            onChanged: (input) => setState(() {
              _guests = int.tryParse(input) ?? 0;
              _selected.removeWhere((_, item) => _price(item) == null);
            }),
          ),
          const SizedBox(height: 12),
          if (widget.service == 'PHOTOGRAPHY') ...[
            TextField(
                controller: _coverage,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Functions and coverage',
                  hintText: 'Ceremony, reception, hours or crew',
                )),
            TextField(
                controller: _delivery,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Deliverables',
                  hintText: 'Albums, video, digital gallery or live stream',
                )),
          ],
          TextField(
            controller: _requirements,
            maxLength: 3000,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Requirements',
              hintText: switch (widget.service) {
                'PHOTOGRAPHY' => 'Coverage, albums, video and delivery',
                'CATERING' => 'Menu changes, dietary needs and serving style',
                _ => 'Setup, catering and access',
              },
            ),
          ),
          if (_isHall)
            FutureBuilder<Map<String, dynamic>>(
              future: _hall,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return TextButton(
                      onPressed: () => setState(_loadHall),
                      child: Text('${eventError(snapshot.error!)} Retry'));
                }
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _hallBody(snapshot.data!));
              },
            )
          else
            ..._catalogueBody(),
        ]),
      );
}
