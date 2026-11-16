import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../repositories/cities_repository.dart';
import '../../repositories/events_repository.dart';
import '../../shared/media/profile_photo.dart';
import '../../shared/widgets/gx_calendar.dart';
import 'event_plans_screen.dart';
import 'photography_customer_flow_screen.dart';
import 'photography_customer_model.dart';

class PhotographyCustomerSearchScreen extends ConsumerStatefulWidget {
  const PhotographyCustomerSearchScreen({
    super.key, required this.eventType,
    required this.date, required this.guests,
  });

  final String eventType;
  final DateTime date;
  final int guests;

  @override
  ConsumerState<PhotographyCustomerSearchScreen> createState() =>
      _PhotographyCustomerSearchScreenState();
}

class _PhotographyCustomerSearchScreenState
    extends ConsumerState<PhotographyCustomerSearchScreen> {
  static const _navy = Color(0xFF1B2559);
  static const _pink = Color(0xFFDB2777);
  final _area = TextEditingController();
  final _query = TextEditingController();
  String? _city;
  late DateTime _day;
  String _need = 'wedding';
  String _community = 'All';
  String _level = 'All';
  int _budgetMin = 0;
  int _budgetMax = 10000000;
  String _sort = 'price';
  bool _searched = false;
  Future<List<Map<String,dynamic>>>? _vendors;

  @override
  void initState() {
    super.initState();
    _city = ref.read(currentCityProvider)?.id;
    _day = DateUtils.dateOnly(widget.date);
    final description = widget.eventType.toLowerCase();
    for (final need in PhotographyCustomerCatalogue.needs) {
      if (description.contains(need.key) ||
          description == need.label.toLowerCase() ||
          (need.key == 'wedding' && description.contains('marriage'))) {
        _need = need.key;
        break;
      }
    }
  }

  @override
  void dispose() {
    _area.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showGxCalendar(context,
      title: 'Photography event date',
      initialDate: _day.isBefore(today) ? today : _day,
      firstDate: today,
      lastDate: today.add(const Duration(days:730)));
    if (!mounted || picked == null) return;
    setState(() {
      _day = picked;
      _searched = false;
    });
  }

  void _search() {
    if (_city == null || _area.text.trim().isEmpty ||
        _day.isBefore(DateUtils.dateOnly(DateTime.now())) ||
        _budgetMin > _budgetMax) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Choose a city, venue/area, date and valid budget.')));
      return;
    }
    setState(() {
      _vendors = ref.read(eventsRepositoryProvider)
          .discover('PHOTOGRAPHY', _city!);
      _searched = true;
    });
  }

  List<Map<String,dynamic>> _filter(List<Map<String,dynamic>> rows) {
    final search = _query.text.trim().toLowerCase();
    final result = rows.where((vendor) {
      if (search.isNotEmpty &&
          !'${vendor['name'] ?? ''} ${vendor['location'] ?? ''}'
              .toLowerCase().contains(search)) return false;
      return PhotographyCustomerCatalogue.lowestPrice(
        vendor, _need,
        level:_level, community:_community,
        minPrice:_budgetMin, maxPrice:_budgetMax) != null;
    }).toList();
    result.sort((a,b) {
      if (_sort == 'price') {
        final p = PhotographyCustomerCatalogue.lowestPrice(a, _need,
            level:_level, community:_community,
            minPrice:_budgetMin,maxPrice:_budgetMax)!;
        final q = PhotographyCustomerCatalogue.lowestPrice(b, _need,
            level:_level, community:_community,
            minPrice:_budgetMin,maxPrice:_budgetMax)!;
        final c = p.compareTo(q);
        if (c != 0) return c;
      }
      return '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}');
    });
    return result;
  }

  void _profile(Map<String,dynamic> vendor) {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => PhotographyCustomerProfileScreen(
        vendor:vendor,cityId:_city!,eventType:widget.eventType,
        date:_day,guests:widget.guests,location:_area.text.trim(),
        need:_need, community:_community,level:_level,
        minBudget:_budgetMin,maxBudget:_budgetMax,
      )));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_searched ? 'Photographers' : 'Find Photographers'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) =>
              const EventPlansScreen(interestService:'PHOTOGRAPHY'))),
          child: const Text('My Interests'),
        ),
      ],
    ),
    body: _searched ? _results() : _searchForm(),
  );

  Widget _searchForm() {
    final wedding = PhotographyCustomerCatalogue.wedding(_need);
    final cities = ref.watch(citiesProvider);
    final mins = wedding ?
      const [0,50000,75000,100000] : const [0,5000,10000,15000];
    final maxes = wedding ?
      const [100000,150000,200000,10000000] :
      const [25000,50000,100000,10000000];
    return ListView(padding: const EdgeInsets.all(16),children:[
      Card(color:const Color(0xFFFDF2F8),child:
        Padding(padding:const EdgeInsets.all(18),child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('Gixbee Photography',
              style:TextStyle(color:_navy,fontSize:23,fontWeight:FontWeight.w900)),
            const SizedBox(height:6),
            Text(wedding ? 'Find a photographer for your celebration' :
              'Portraits, events, corporate and other shoots',
              style: const TextStyle(color:Color(0xFF6B7280))),
          ]))),
      const SizedBox(height:14),
      cities.when(
        loading:()=>const LinearProgressIndicator(),
        error:(_,__)=>TextButton(onPressed:()=>ref.invalidate(citiesProvider),
          child:const Text('Reload cities')),
        data:(options)=>DropdownButtonFormField<String>(
          isExpanded:true,
          initialValue:options.any((c)=>c.id==_city)?_city:null,
          decoration:const InputDecoration(labelText:'Location / city *',
              border:OutlineInputBorder()),
          items:[for(final c in options)DropdownMenuItem(
            value:c.id,child:Text(c.displayName,overflow:TextOverflow.ellipsis))],
          onChanged:(v)=>setState(()=>_city=v),
        )),
      const SizedBox(height:14),
      TextField(controller:_area,maxLength:200,
        decoration:const InputDecoration(
          labelText:'Venue / area *',prefixIcon:Icon(Icons.location_on_outlined),
          border:OutlineInputBorder())),
      ListTile(contentPadding:EdgeInsets.zero,
        title:const Text('Event Date'),subtitle:Text(
          DateFormat('EEE, d MMM yyyy').format(_day)),
        trailing:const Icon(Icons.calendar_month_outlined),
        onTap:_pickDate),
      const SizedBox(height:8),
      DropdownButtonFormField<String>(
        isExpanded:true,initialValue:_need,
        decoration:const InputDecoration(
          labelText:'What do you need photography for?',
          border:OutlineInputBorder()),
        items:[for(final n in PhotographyCustomerCatalogue.needs)
          DropdownMenuItem(value:n.key,
            child:Text(n.label,overflow:TextOverflow.ellipsis))],
        onChanged:(v)=>setState(() {
          _need=v??'wedding';
          _level='All'; _community='All';
          _budgetMin=0;_budgetMax=10000000;
        }),
      ),
      if (wedding) ...[
        const SizedBox(height:16),
        const Text('Community / Ceremony',
          style:TextStyle(fontWeight:FontWeight.w800,color:_navy)),
        Wrap(spacing:7,runSpacing:4,children:[
          for(final c in const ['All','Hindu','Muslim','Christian','Other'])
            ChoiceChip(label:Text(c),selected:_community==c,
              onSelected:(_)=>setState(()=>_community=c)),
        ]),
        const SizedBox(height:10),
        const Text('Package Type',
          style:TextStyle(fontWeight:FontWeight.w800,color:_navy)),
        Wrap(spacing:7,children:[
          for(final l in const ['All','Basic','Standard','Premium'])
            ChoiceChip(label:Text(l),selected:_level==l,
              onSelected:(_)=>setState(()=>_level=l)),
        ]),
      ],
      const SizedBox(height:14),
      Text(wedding?'Package budget (optional)':'Service budget (optional)',
        style:const TextStyle(fontWeight:FontWeight.w800,color:_navy)),
      Row(children:[
        Expanded(child:DropdownButtonFormField<int>(
          isExpanded:true,initialValue:_budgetMin,
          decoration:const InputDecoration(labelText:'Min',
              border:OutlineInputBorder()),
          items:[for(final n in mins)DropdownMenuItem(
            value:n,child:Text(_money(n)))],
          onChanged:(v)=>setState(()=>_budgetMin=v??0),
        )),
        const SizedBox(width:10),
        Expanded(child:DropdownButtonFormField<int>(
          isExpanded:true,initialValue:_budgetMax,
          decoration:const InputDecoration(labelText:'Max',
              border:OutlineInputBorder()),
          items:[for(final n in maxes)DropdownMenuItem(
            value:n,child:Text(n==10000000?'Any':_money(n)))],
          onChanged:(v)=>setState(()=>_budgetMax=v??10000000),
        )),
      ]),
      const SizedBox(height:24),
      FilledButton(
        style:FilledButton.styleFrom(backgroundColor:_pink,
          padding:const EdgeInsets.symmetric(vertical:16)),
        onPressed:_search,child:const Text('Search Photographers')),
    ]);
  }

  Widget _results() => Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:Column(children:[
      Row(children:[
        Expanded(child:Text(PhotographyCustomerCatalogue.label(_need),
          style:const TextStyle(fontSize:18,color:_navy,
            fontWeight:FontWeight.w900))),
        TextButton(onPressed:()=>setState(()=>_searched=false),
          child:const Text('Edit search')),
      ]),
      TextField(controller:_query,
        onChanged:(_)=>setState((){}),
        decoration:const InputDecoration(hintText:'Search studio or area',
          prefixIcon:Icon(Icons.search),border:OutlineInputBorder())),
      const SizedBox(height:8),
      Row(children:[
        const Text('Sort by '),
        DropdownButton<String>(value:_sort,items:const [
          DropdownMenuItem(value:'price',child:Text('Lowest price')),
          DropdownMenuItem(value:'name',child:Text('Studio name')),
        ],onChanged:(v)=>setState(()=>_sort=v??'price')),
        const Spacer(),
        TextButton(onPressed:_search,child:const Text('Refresh')),
      ]),
    ])),
    Expanded(child:FutureBuilder<List<Map<String,dynamic>>>(
      future:_vendors,builder:(context,snapshot) {
        if(snapshot.connectionState!=ConnectionState.done) {
          return const Center(child:CircularProgressIndicator());
        }
        if(snapshot.hasError) return Center(child:TextButton(
          onPressed:_search,child:Text('${eventError(snapshot.error!)} Retry')));
        final matches=_filter(snapshot.data??[]);
        if(matches.isEmpty) return const Center(child:Padding(
          padding:EdgeInsets.all(24),child:Text(
            'No studios currently list a matching published package or service. '
            'Try another district, budget or photography need.',
            textAlign:TextAlign.center)));
        return ListView.builder(
          padding:const EdgeInsets.fromLTRB(12,0,12,18),
          itemCount:matches.length+1,
          itemBuilder:(context,index) {
            if(index==0) return Padding(
              padding:const EdgeInsets.only(bottom:8),
              child:Text('${matches.length} studios found',
                style:const TextStyle(color:_navy,fontWeight:FontWeight.w800)));
            final vendor=matches[index-1];
            final amount=PhotographyCustomerCatalogue.lowestPrice(vendor,_need,
              level:_level,community:_community,
              minPrice:_budgetMin,maxPrice:_budgetMax)!;
            final photos=(vendor['catalogue'] as Map?)?['photos'] as List? ??[];
            final cover=photos.isEmpty ? null :
                resolveProfileImageUrl(photos.first.toString());
            return Card(margin:const EdgeInsets.only(bottom:12),
              child:InkWell(onTap:()=>_profile(vendor),
                child:Padding(padding:const EdgeInsets.all(12),
                  child:Row(children:[
                    ClipRRect(borderRadius:BorderRadius.circular(10),
                      child:cover==null ? Container(width:86,height:85,
                        color:const Color(0xFFFDF2F8),
                        child:const Icon(Icons.camera_alt,size:38,color:_pink)) :
                        Image.network(cover,width:86,height:85,fit:BoxFit.cover,
                          errorBuilder:(_,__,___)=>const SizedBox(
                            width:86,height:85,child:Icon(Icons.camera_alt)))),
                    const SizedBox(width:12),
                    Expanded(child:Column(
                      crossAxisAlignment:CrossAxisAlignment.start,children:[
                        Text(vendor['name']?.toString()??'Photography studio',
                          style:const TextStyle(color:_navy,
                            fontWeight:FontWeight.w900)),
                        Text(vendor['location']?.toString()??'',
                          maxLines:2,overflow:TextOverflow.ellipsis,
                          style:const TextStyle(color:Colors.blueGrey)),
                        Text('From ${_money(amount)}',
                          style:const TextStyle(color:_pink,
                            fontWeight:FontWeight.w900)),
                        const Text('Availability on request',
                          style:TextStyle(fontSize:11,color:Colors.blueGrey)),
                      ])),
                    const Icon(Icons.chevron_right),
                  ])) ));
          });
      })),
  ]);

  String _money(int amount)=>amount>=10000000?'Any':
      '₹${NumberFormat.decimalPattern('en_IN').format(amount)}';
}
