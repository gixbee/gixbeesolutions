import '../../shared/widgets/gx_empty.dart';
import '../../shared/widgets/gx_network_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../repositories/cities_repository.dart';
import '../../repositories/events_repository.dart';
import '../../shared/media/profile_photo.dart';
import '../../shared/widgets/gx_calendar.dart';
import 'event_plans_screen.dart';
import 'hall_customer_flow_screen.dart';
import 'hall_customer_model.dart';

class HallCustomerSearchScreen extends ConsumerStatefulWidget {
  const HallCustomerSearchScreen({
    super.key, required this.eventType, required this.date,
    required this.guests,
  });
  final String eventType;
  final DateTime date;
  final int guests;

  @override
  ConsumerState<HallCustomerSearchScreen> createState() =>
      _HallCustomerSearchScreenState();
}

class _HallCustomerSearchScreenState
    extends ConsumerState<HallCustomerSearchScreen> {
  static const _navy=Color(0xFF1B2559);
  static const _green=Color(0xFF12B76A);
  final _guests=TextEditingController();
  final _query=TextEditingController();
  String? _cityId;
  String _event='Wedding';
  String _ac='any';
  String _venue='any';
  int _priceMax=200000;
  String _sort='price';
  bool _searched=false;
  late DateTime _day;
  Future<List<Map<String,dynamic>>>? _results;

  @override
  void initState() {
    super.initState();
    _cityId=ref.read(currentCityProvider)?.id;
    _guests.text='${widget.guests.clamp(1,100000)}';
    _day=DateUtils.dateOnly(widget.date);
    final init=widget.eventType.trim();
    if (init.isNotEmpty) _event=init;
  }

  @override
  void dispose() {
    _guests.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final today=DateUtils.dateOnly(DateTime.now());
    final picked=await showGxCalendar(context,
      title:'Hall event date', initialDate:_day.isBefore(today)?today:_day,
      firstDate:today,lastDate:today.add(const Duration(days:730)));
    if (!mounted||picked==null)return;
    setState((){_day=picked;_searched=false;});
  }

  void _search() {
    final n=int.tryParse(_guests.text.trim());
    if (_cityId==null||n==null||n<1||n>100000||
        _day.isBefore(DateUtils.dateOnly(DateTime.now()))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text(
          'Choose a city, future date and guest count from 1 to 100,000.')));
      return;
    }
    setState((){
      _results=ref.read(eventsRepositoryProvider).discover('HALL',_cityId!);
      _searched=true;
    });
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(_searched?'Available Halls':'Find Halls'),
      actions:[TextButton(onPressed:()=>Navigator.push(context,
        MaterialPageRoute<void>(builder:(_)=>
          const EventPlansScreen(interestService:'HALL'))),
        child:const Text('My Events'))]),
    body:_searched?_resultsBody():_searchForm(),
  );

  Widget _searchForm() {
    final cities=ref.watch(citiesProvider);
    return ListView(padding:const EdgeInsets.all(16),children:[
      Card(color:const Color(0xFFECFDF3),child:Padding(
        padding:const EdgeInsets.all(18),child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('Find the perfect Hall',
              style:TextStyle(color:_navy,fontSize:23,
                fontWeight:FontWeight.w900)),
            const SizedBox(height:5),
            const Text('Weddings, receptions, birthdays, baptisms and more.'),
          ]))),
      const SizedBox(height:15),
      cities.when(
        loading:()=>const LinearProgressIndicator(),
        error:(_,__)=>TextButton(
          onPressed:()=>ref.invalidate(citiesProvider),
          child:const Text('Reload cities')),
        data:(items)=>DropdownButtonFormField<String>(
          isExpanded:true,
          initialValue:items.any((c)=>c.id==_cityId)?_cityId:null,
          decoration:const InputDecoration(
            labelText:'Location / City *',border:OutlineInputBorder()),
          items:[for(final c in items)DropdownMenuItem(
            value:c.id,child:Text(c.displayName,
              overflow:TextOverflow.ellipsis))],
          onChanged:(v)=>setState(()=>_cityId=v),
        )),
      const SizedBox(height:14),
      DropdownButtonFormField<String>(
        isExpanded:true,initialValue:const [
          'Wedding','Reception','Birthday','Baptism','Engagement','Other',
        ].contains(_event)?_event:'Other',
        decoration:const InputDecoration(labelText:'Event Type',
          border:OutlineInputBorder()),
        items:[
          for(final s in const ['Wedding','Reception','Birthday','Baptism',
            'Engagement','Other'])
            DropdownMenuItem(value:s,child:Text(s)),
        ],
        onChanged:(v)=>setState(()=>_event=v??'Other'),
      ),
      ListTile(
        contentPadding:EdgeInsets.zero,
        title:const Text('Event Date'),
        subtitle:Text(DateFormat('EEE, d MMM yyyy').format(_day)),
        trailing:const Icon(Icons.calendar_month_outlined),
        onTap:_pickDay,
      ),
      TextField(controller:_guests,
        keyboardType:TextInputType.number,
        decoration:const InputDecoration(
          labelText:'Number of Guests *',
          prefixIcon:Icon(Icons.people_alt_outlined),
          border:OutlineInputBorder()),
      ),
      const SizedBox(height:16),
      const Text('AC Preference',style:TextStyle(
        fontWeight:FontWeight.w800,color:_navy)),
      Wrap(spacing:8,runSpacing:5,children:[
        for(final (key,name) in const [
          ('any','Any'),('ac','With AC'),('noac','Without AC'),
        ])
          ChoiceChip(label:Text(name),selected:_ac==key,
            onSelected:(_)=>setState(()=>_ac=key)),
      ]),
      const SizedBox(height:13),
      const Text('Venue Type',style:TextStyle(
        fontWeight:FontWeight.w800,color:_navy)),
      Wrap(spacing:8,children:[
        for(final (key,name) in const [
          ('any','Any'),('indoor','Indoor'),('outdoor','Outdoor'),
        ])
          ChoiceChip(label:Text(name),selected:_venue==key,
            onSelected:(_)=>setState(()=>_venue=key)),
      ]),
      const SizedBox(height:16),
      Text('Price per slot: ${_priceMax==200000?'₹2,00,000+':'Up to ${_money(_priceMax)}'}',
        style:const TextStyle(fontWeight:FontWeight.w800,color:_navy)),
      Slider(min:0,max:200000,divisions:40,value:_priceMax.toDouble(),
        onChanged:(v)=>setState(()=>_priceMax=v.round())),
      const SizedBox(height:14),
      FilledButton(
        style:FilledButton.styleFrom(backgroundColor:_green,
          padding:const EdgeInsets.symmetric(vertical:16)),
        onPressed:_search,
        child:const Text('Search Halls'),
      ),
    ]);
  }

  Widget _resultsBody()=>Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          Expanded(child:Text('Halls · $_event',
            style:const TextStyle(fontSize:19,color:_navy,
              fontWeight:FontWeight.w900))),
          TextButton(onPressed:()=>setState(()=>_searched=false),
            child:const Text('Edit filters')),
        ]),
        TextField(controller:_query,onChanged:(_)=>setState((){}),
          decoration:const InputDecoration(
            labelText:'Search venue or area',
            prefixIcon:Icon(Icons.search),
            border:OutlineInputBorder())),
        Row(children:[
          const Text('Sort by '),
          DropdownButton<String>(value:_sort,items:const [
            DropdownMenuItem(value:'price',child:Text('Lowest price')),
            DropdownMenuItem(value:'name',child:Text('Hall name')),
          ],onChanged:(v)=>setState(()=>_sort=v??'price')),
          const Spacer(),
          TextButton(onPressed:_search,child:const Text('Refresh')),
        ]),
      ])),
    Expanded(child:FutureBuilder<List<Map<String,dynamic>>>(
      future:_results,builder:(context,snapshot) {
        if(snapshot.connectionState!=ConnectionState.done) {
          return const Center(child:CircularProgressIndicator());
        }
        if (snapshot.hasError) return GxNetworkError(
          error: snapshot.error,
          title: 'Hall search unavailable',
          onRetry: _search,
        );
        final rows=HallCustomerModel.matches(snapshot.data??[],
          guests:int.tryParse(_guests.text.trim())??0,
          event:_event,ac:_ac,venue:_venue,
          maxPrice:_priceMax==200000?100000000:_priceMax,
          query:_query.text,sort:_sort);
        if (rows.isEmpty) return const GxEmptyState(
          icon: Icons.meeting_room_outlined,
          title: 'No matching halls',
          message: 'Try a different date, location, AC preference, or budget.',
        );
        return ListView.builder(
          padding:const EdgeInsets.fromLTRB(12,0,12,22),
          itemCount:rows.length+1,
          itemBuilder:(context,i) {
            if(i==0)return Padding(
              padding:const EdgeInsets.only(bottom:8),
              child:Text('${rows.length} halls found',
                style:const TextStyle(color:_navy,
                  fontWeight:FontWeight.w800)));
            final hall=rows[i-1];
            final capacity=hall['capacity'] as Map? ?? {};
            final parking=hall['parking'] as Map? ?? {};
            final price=HallCustomerModel.minimumPrice(hall,ac:_ac)??0;
            final url=resolveProfileImageUrl(
              hall['coverImageUrl']?.toString());
            return Card(margin:const EdgeInsets.only(bottom:12),
              child:InkWell(onTap:()=>Navigator.of(context).push<void>(
                  MaterialPageRoute(builder:(_)=>HallCustomerProfileScreen(
                    hall:hall,cityId:_cityId!,eventType:_event,
                    date:_day,guests:int.parse(_guests.text.trim()),
                    acPreference:_ac,
                  ))),
                child:Padding(padding:const EdgeInsets.all(12),
                  child:Column(children:[
                    Row(children:[
                      ClipRRect(borderRadius:BorderRadius.circular(9),
                        child:url==null?Container(width:100,height:98,
                          color:const Color(0xFFECFDF3),
                          child:const Icon(Icons.apartment,size:48,color:_green)):
                          Image.network(url,width:100,height:98,
                            fit:BoxFit.cover,errorBuilder:(_,__,___)=>
                              const SizedBox(width:100,height:98,
                                child:Icon(Icons.apartment,size:42)))),
                      const SizedBox(width:10),
                      Expanded(child:Column(
                        crossAxisAlignment:CrossAxisAlignment.start,children:[
                          Text('${hall['businessName']??''}',
                            maxLines:1,overflow:TextOverflow.ellipsis,
                            style:const TextStyle(color:_navy,
                              fontWeight:FontWeight.w900)),
                          Text('${hall['hallName']??'Hall'} · ${hall['spaceType']??'Indoor'}',
                            maxLines:2,overflow:TextOverflow.ellipsis),
                          Text('${hall['location']??''}',
                            maxLines:2,overflow:TextOverflow.ellipsis,
                            style:const TextStyle(color:Colors.blueGrey)),
                          const SizedBox(height:6),
                          Text('From ${_money(price)} · GST included',
                            style:const TextStyle(color:_green,
                              fontWeight:FontWeight.w900)),
                        ])),
                      const Icon(Icons.chevron_right),
                    ]),
                    const SizedBox(height:10),
                    Align(alignment:Alignment.centerLeft,
                      child:Text('Seating ${capacity['seat']??'—'} · '
                        'Dining ${capacity['dine']??'—'} · '
                        'Cars ${parking['car']??0}',
                        style:const TextStyle(color:Colors.blueGrey,
                          fontSize:12))),
                  ])),
              ));
          });
      })),
  ]);

  String _money(int v)=>'₹${NumberFormat.decimalPattern('en_IN').format(v)}';
}
