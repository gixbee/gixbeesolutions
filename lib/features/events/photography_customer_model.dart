/// Customer-facing photo categories, catalogue filtering and request
/// validation. Prices always come from the published Rust catalogue.
class PhotographyCustomerCatalogue {
  const PhotographyCustomerCatalogue._();

  static const needs = <({String key, String label, bool wedding})>[
    (key:'wedding',label:'Wedding / Marriage',wedding:true),
    (key:'engagement',label:'Engagement',wedding:true),
    (key:'save-date',label:'Save the Date',wedding:true),
    (key:'pre-wedding',label:'Pre-Wedding Shoot',wedding:true),
    (key:'post-wedding',label:'Post-Wedding Shoot',wedding:true),
    (key:'reception',label:'Reception',wedding:true),
    (key:'wedding-eve',label:'Wedding Eve',wedding:true),
    (key:'funeral',label:'Funeral / Memorial',wedding:false),
    (key:'baptism',label:'Baptism',wedding:false),
    (key:'event',label:'Event Photography',wedding:false),
    (key:'portrait',label:'Portrait',wedding:false),
    (key:'corporate',label:'Corporate',wedding:false),
    (key:'baby',label:'Baby & Maternity',wedding:false),
    (key:'product',label:'Product Photography',wedding:false),
  ];

  static bool wedding(String need) =>
      needs.any((n) => n.key == need && n.wedding);

  static String label(String need) {
    for (final n in needs) {
      if (n.key == need) return n.label;
    }
    return 'Photography';
  }

  static const _weddingFunctions = <String,String>{
    'wedding':'wedding','engagement':'engagement',
    'save-date':'save the date', 'pre-wedding':'pre-wedding',
    'post-wedding':'post-wedding','reception':'reception',
    'wedding-eve':'wedding eve',
  };

  static const _serviceCategories = <String,List<String>>{
    'funeral':['funeral','memorial'],
    'baptism':['baptism','communion'],
    'event':['event','celebration','birthday','get-together','get together'],
    'portrait':['portrait','family'],
    'corporate':['corporate','commercial'],
    'baby':['baby','maternity'],
    'product':['product'],
  };

  static List<Map<String,dynamic>> items(Map? catalogue, String need, {
    String level = 'All', String community = 'All',
    int minPrice = 0, int maxPrice = 10000000,
  }) {
    if (minPrice < 0 || maxPrice < minPrice) return [];
    final wantedWedding = wedding(need);
    final matched = <Map<String,dynamic>>[];
    for (final raw in (catalogue?['items'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final item = Map<String,dynamic>.from(raw);
      if (item['active'] == false ||
          (item['kind'] == 'PACKAGE') != wantedWedding) continue;
      final price = priceOf(item);
      if (price == null || price < minPrice || price > maxPrice) continue;
      if (wantedWedding) {
        if (level != 'All' && item['packageLevel'] != level) continue;
        if (community != 'All') {
          final ceremonies = (item['ceremonies'] as List? ?? const [])
              .map((v) => v.toString().toLowerCase()).toList();
          if (!ceremonies.any((c) => c.contains(community.toLowerCase()))) {
            continue;
          }
        }
        final functions = (item['functions'] as List? ?? const [])
            .map((v)=>v.toString().toLowerCase()).toList();
        final target = _weddingFunctions[need] ?? 'wedding';
        if (functions.isNotEmpty &&
            !functions.any((f) => f.contains(target))) continue;
      } else {
        final category = '${item['category'] ?? ''} ${item['name'] ?? ''}'
            .toLowerCase();
        final matches = _serviceCategories[need] ?? const <String>[];
        if (matches.isNotEmpty && !matches.any(category.contains)) continue;
      }
      matched.add(item);
    }
    matched.sort((a,b) {
      final byPrice = priceOf(a)!.compareTo(priceOf(b)!);
      return byPrice != 0 ? byPrice :
          '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}');
    });
    return matched;
  }

  static int? priceOf(Map item) {
    final p = item['price'];
    if (p is! int || p < 1 || p > 10000000) return null;
    return p;
  }

  static int? listPriceOf(Map item) {
    final p = item['listPrice'];
    final current = priceOf(item);
    return p is int && current != null && p > current ? p : null;
  }

  static int? discountOf(Map item) {
    if (listPriceOf(item) == null) return null;
    final v = item['discountPct'];
    return v is int && v > 0 && v <= 90 ? v : null;
  }

  static int? lowestPrice(Map<String,dynamic> vendor, String need, {
    String level='All', String community='All',
    int minPrice=0, int maxPrice=10000000,
  }) {
    final rows = items(vendor['catalogue'] as Map?, need,
      level:level,community:community,minPrice:minPrice,maxPrice:maxPrice);
    return rows.isEmpty ? null : priceOf(rows.first);
  }
}

/// Mirrors the existing Rust /events creation contract for a single published
/// photography item. Extras remain quotation preferences, not client-set prices.
class PhotographyCustomerRequest {
  const PhotographyCustomerRequest._();

  static Map<String,dynamic> build({
    required String clientRequestId,
    required String businessId,
    required String cityId,
    required String eventType,
    required String location,
    required DateTime start,
    required DateTime end,
    required int guests,
    required Map<String,dynamic> item,
    required Map<String,dynamic> customization,
    String notes = '',
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final price = PhotographyCustomerCatalogue.priceOf(item);
    final id = item['id'];
    final acceptedFields = {
      'functions','coverage','team','deliverables','extras'
    };
    final functions = customization['functions'];
    if (businessId.trim().isEmpty || cityId.trim().isEmpty ||
        clientRequestId.trim().isEmpty ||
        eventType.trim().isEmpty || eventType.length > 100 ||
        location.trim().isEmpty || location.length > 2000 ||
        notes.length > 5000 || guests < 1 || guests > 100000 ||
        !start.isAfter(current) || !end.isAfter(start) ||
        end.difference(start) > const Duration(days:14) ||
        start.difference(current) > const Duration(days:730) ||
        id is! String || id.isEmpty || item['active'] == false ||
        price == null ||
        customization.keys.any((k)=>!acceptedFields.contains(k)) ||
        functions is! List ||
        functions.length > 8 ||
        functions.any((x)=>x is! String ||
            x.trim().isEmpty || x.length > 90) ||
        functions.toSet().length != functions.length ||
        customization.entries.any((e)=>e.key != 'functions' &&
            (e.value is! String || (e.value as String).length > 900))) {
      throw const FormatException(
        'Review the selected service, event time, notes and requirements.');
    }
    return {
      'clientRequestId': clientRequestId,
      'targetBusinessId': businessId,
      'cityId': cityId,
      'services': ['PHOTOGRAPHY'],
      'eventType': eventType.trim(),
      'location': location.trim(),
      'guestCount': guests,
      'startTime': start.toUtc().toIso8601String(),
      'endTime': end.toUtc().toIso8601String(),
      'notes': notes.trim(),
      'serviceRequest': {
        'itemIds': [id],
        'expectedEstimate': price,
        'customization': customization,
      },
    };
  }
}
