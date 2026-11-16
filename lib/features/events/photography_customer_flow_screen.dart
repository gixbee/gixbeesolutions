import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/media/profile_photo.dart';
import '../../shared/widgets/gx_calendar.dart';
import 'photography_customer_interest_screen.dart';
import 'photography_customer_model.dart';

const _photoNavy = Color(0xFF1B2559);
const _photoPink = Color(0xFFDB2777);
const _photoSoft = Color(0xFFFDF2F8);

String photographyMoney(int value) =>
    '₹${NumberFormat.decimalPattern('en_IN').format(value)}';

Widget photographyImage(String? path, {double height = 185}) {
  final url = resolveProfileImageUrl(path);
  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: url == null ? Container(
      height:height,color:_photoSoft,alignment:Alignment.center,
      child:const Icon(Icons.camera_alt_outlined,color:_photoPink,size:62),
    ) : Image.network(url,height:height,width:double.infinity,
      fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(
        height:height,color:_photoSoft,
        child:const Icon(Icons.camera_alt_outlined,size:50))),
  );
}

class PhotographyCustomerProfileScreen extends StatefulWidget {
  const PhotographyCustomerProfileScreen({
    super.key,required this.vendor,required this.cityId,
    required this.eventType,required this.date,required this.guests,
    required this.location,required this.need,required this.community,
    required this.level,required this.minBudget,required this.maxBudget,
  });
  final Map<String,dynamic> vendor;
  final String cityId,eventType,location,need,community,level;
  final DateTime date;
  final int guests,minBudget,maxBudget;

  @override
  State<PhotographyCustomerProfileScreen> createState() =>
      _PhotographyCustomerProfileScreenState();
}

class _PhotographyCustomerProfileScreenState
    extends State<PhotographyCustomerProfileScreen> {
  String _tab='overview';
  Map get _catalogue=>widget.vendor['catalogue'] as Map? ?? const {};
  List get _photos=>_catalogue['photos'] as List? ?? const [];
  String get _name=>widget.vendor['name']?.toString()??'Photography Studio';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:Text(_name)),
    body:SafeArea(child:Column(children:[
      Expanded(child:ListView(
        padding:const EdgeInsets.all(16),children:[
          photographyImage(_photos.isEmpty?null:_photos.first?.toString(),
            height:220),
          const SizedBox(height:12),
          Text(_name,style:const TextStyle(color:_photoNavy,
            fontSize:21,fontWeight:FontWeight.w900)),
          Text(widget.vendor['location']?.toString()??'',
            style:const TextStyle(color:Colors.blueGrey)),
          const SizedBox(height:10),
          const Wrap(spacing:8,children:[
            Chip(label:Text('Verified provider')),
            Chip(label:Text('Booking confirmed after quote')),
          ]),
          const SizedBox(height:12),
          SingleChildScrollView(scrollDirection:Axis.horizontal,
            child:SegmentedButton<String>(
              selected:{_tab},segments:const [
                ButtonSegment(value:'overview',label:Text('Overview')),
                ButtonSegment(value:'portfolio',label:Text('Portfolio')),
                ButtonSegment(value:'reviews',label:Text('Reviews')),
              ],
              onSelectionChanged:(v)=>setState(()=>_tab=v.first),
            )),
          const SizedBox(height:16),
          if(_tab=='overview') ...[
            const Text('About Studio',style:TextStyle(color:_photoNavy,
              fontWeight:FontWeight.w900,fontSize:17)),
            const SizedBox(height:8),
            Text((_catalogue['about']??'').toString().trim().isEmpty
              ? 'Explore published photography packages and services.'
              : _catalogue['about'].toString()),
            const SizedBox(height:18),
            const Text('Photography services',
              style:TextStyle(color:_photoNavy,fontWeight:FontWeight.w800)),
            const SizedBox(height:8),
            Wrap(spacing:8,runSpacing:6,children:[
              if((_catalogue['items'] as List? ?? const [])
                  .whereType<Map>().any((i)=>i['kind']=='PACKAGE' &&
                  i['active']!=false))
                const Chip(label:Text('Wedding packages')),
              if((_catalogue['items'] as List? ?? const [])
                  .whereType<Map>().any((i)=>i['kind']=='ITEM' &&
                  i['active']!=false))
                const Chip(label:Text('Individual services')),
            ]),
          ] else if(_tab=='portfolio') ...[
            if(_photos.isEmpty)
              const Text('No portfolio photos have been published yet.')
            else for(final p in _photos)
              Padding(padding:const EdgeInsets.only(bottom:12),
                child:photographyImage(p.toString(),height:180)),
          ] else
            const Text('Reviews are not available from this provider yet.'),
        ])),
      Padding(padding:const EdgeInsets.fromLTRB(16,8,16,16),
        child:Row(children:[
          Expanded(child:OutlinedButton(
            onPressed:()=>ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content:Text(
                'Send an interest to start the enquiry and quotation process.'))),
            child:const Text('Message'),
          )),
          const SizedBox(width:8),
          Expanded(flex:2,child:FilledButton(
            style:FilledButton.styleFrom(backgroundColor:_photoPink,
              padding:const EdgeInsets.symmetric(vertical:14)),
            onPressed:()=>Navigator.of(context).push<void>(MaterialPageRoute(
              builder:(_)=>PhotographyCustomerCatalogueScreen(
                vendor:widget.vendor,cityId:widget.cityId,
                eventType:widget.eventType,date:widget.date,
                guests:widget.guests,location:widget.location,need:widget.need,
                community:widget.community,level:widget.level,
                minBudget:widget.minBudget,maxBudget:widget.maxBudget,
              ))),
            child:Text(PhotographyCustomerCatalogue.wedding(widget.need)
              ?'View Packages':'View Services'),
          )),
        ])),
    ])),
  );
}

class PhotographyCustomerCatalogueScreen extends StatefulWidget {
  const PhotographyCustomerCatalogueScreen({
    super.key,required this.vendor,required this.cityId,
    required this.eventType,required this.date,required this.guests,
    required this.location,required this.need,required this.community,
    required this.level,required this.minBudget,required this.maxBudget,
  });
  final Map<String,dynamic> vendor;
  final String cityId,eventType,location,need,community,level;
  final DateTime date;
  final int guests,minBudget,maxBudget;
  @override
  State<PhotographyCustomerCatalogueScreen> createState() =>
      _PhotographyCustomerCatalogueScreenState();
}

class _PhotographyCustomerCatalogueScreenState
    extends State<PhotographyCustomerCatalogueScreen> {
  late DateTime _date=widget.date;
  late String _level=widget.level;
  late String _community=widget.community;
  Map get _catalogue=>widget.vendor['catalogue'] as Map? ?? const {};

  Future<void> _pickDate() async {
    final today=DateUtils.dateOnly(DateTime.now());
    final d=await showGxCalendar(context,title:'Event date',
      initialDate:_date.isBefore(today)?today:_date,firstDate:today,
      lastDate:today.add(const Duration(days:730)));
    if(mounted && d!=null) setState(()=>_date=d);
  }

  @override
  Widget build(BuildContext context) {
    final wedding=PhotographyCustomerCatalogue.wedding(widget.need);
    final matching=PhotographyCustomerCatalogue.items(_catalogue,widget.need,
      level:_level,community:_community,
      minPrice:widget.minBudget,maxPrice:widget.maxBudget);
    return Scaffold(
      appBar:AppBar(title:Text(wedding?'Wedding Packages':'Photography Services')),
      body:ListView(padding:const EdgeInsets.all(16),children:[
        Text(widget.vendor['name']?.toString()??'Studio',
          style:const TextStyle(color:_photoNavy,
            fontSize:20,fontWeight:FontWeight.w900)),
        const SizedBox(height:10),
        if(wedding) ...[
          Wrap(spacing:7,runSpacing:7,children:[
            for(final l in const ['All','Basic','Standard','Premium'])
              ChoiceChip(label:Text(l),selected:_level==l,
                onSelected:(_)=>setState(()=>_level=l)),
          ]),
          Wrap(spacing:7,runSpacing:7,children:[
            for(final c in const ['All','Hindu','Christian','Muslim','Other'])
              ChoiceChip(label:Text(c),selected:_community==c,
                onSelected:(_)=>setState(()=>_community=c)),
          ]),
        ],
        Card(color:_photoSoft,child:ListTile(
          title:const Text('Event date'),
          subtitle:Text(DateFormat('EEE, d MMM yyyy').format(_date)),
          trailing:const Icon(Icons.edit_calendar),
          onTap:_pickDate,
        )),
        const Text('Date availability will be confirmed by the photographer.',
          style:TextStyle(fontSize:11,color:Colors.blueGrey)),
        const SizedBox(height:12),
        Text('Showing ${matching.length} ${wedding?'packages':'services'}',
          style:const TextStyle(color:_photoNavy,fontWeight:FontWeight.w800)),
        if(matching.isEmpty)
          Padding(padding:const EdgeInsets.all(18),
            child:Text(wedding
              ? 'No published packages match these filters. Try All or another studio.'
              : 'This studio has not published a matching service.')),
        for(final item in matching)
          Card(margin:const EdgeInsets.only(top:10),child:InkWell(
            onTap:()=>_open(item),
            child:Padding(padding:const EdgeInsets.all(13),
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Row(children:[
                  const Icon(Icons.photo_camera_outlined,color:_photoPink,size:35),
                  const SizedBox(width:10),
                  Expanded(child:Column(
                    crossAxisAlignment:CrossAxisAlignment.start,children:[
                      Text(item['name']?.toString()??'Photography',
                        style:const TextStyle(color:_photoNavy,
                          fontWeight:FontWeight.w900,fontSize:16)),
                      Text(wedding
                        ?'${item['packageLevel']??'Standard'} package'
                        :'${item['category']??'Individual service'}',
                        style:const TextStyle(color:Colors.blueGrey)),
                    ])),
                  const Icon(Icons.chevron_right),
                ]),
                const SizedBox(height:9),
                PhotographyCustomerOfferPrice(item:item),
                const SizedBox(height:8),
                if((item['description']?.toString()??'').isNotEmpty)
                  Text(item['description'].toString(),
                    maxLines:3,overflow:TextOverflow.ellipsis),
                if((item['inclusions'] as List? ?? const []).isNotEmpty)
                  Wrap(spacing:6,runSpacing:4,children:[
                    for(final feature in (item['inclusions'] as List).take(4))
                      Chip(label:Text(feature.toString(),
                        style:const TextStyle(fontSize:11))),
                  ]),
                const SizedBox(height:7),
                const Text('View Details',
                  style:TextStyle(color:_photoPink,fontWeight:FontWeight.w800)),
              ]))),
          ),
      ]),
    );
  }

  void _open(Map<String,dynamic> item) => Navigator.of(context).push<void>(
    MaterialPageRoute(builder:(_)=>PhotographyCustomerDetailScreen(
      vendor:widget.vendor,item:item,cityId:widget.cityId,
      eventType:widget.eventType,date:_date,guests:widget.guests,
      location:widget.location,need:widget.need,
    )));
}

class PhotographyCustomerOfferPrice extends StatelessWidget {
  const PhotographyCustomerOfferPrice({super.key,required this.item});
  final Map<String,dynamic> item;
  @override
  Widget build(BuildContext context) {
    final price=PhotographyCustomerCatalogue.priceOf(item)??0;
    final before=PhotographyCustomerCatalogue.listPriceOf(item);
    final discount=PhotographyCustomerCatalogue.discountOf(item);
    return Wrap(spacing:9,runSpacing:6,
      crossAxisAlignment:WrapCrossAlignment.center,children:[
      Text(photographyMoney(price),
        style:const TextStyle(color:_photoNavy,
          fontSize:19,fontWeight:FontWeight.w900)),
      if(before!=null) Text(photographyMoney(before),
        style:const TextStyle(color:Colors.blueGrey,
          decoration:TextDecoration.lineThrough)),
      if(discount!=null) Text('$discount% OFF',
        style:const TextStyle(color:_photoPink,fontWeight:FontWeight.w800)),
    ]);
  }
}

class PhotographyCustomerDetailScreen extends StatefulWidget {
  const PhotographyCustomerDetailScreen({
    super.key,required this.vendor,required this.item,
    required this.cityId,required this.eventType,required this.date,
    required this.guests,required this.location,required this.need,
  });
  final Map<String,dynamic> vendor,item;
  final String cityId,eventType,location,need;
  final DateTime date;
  final int guests;
  @override
  State<PhotographyCustomerDetailScreen> createState() =>
      _PhotographyCustomerDetailScreenState();
}

class _PhotographyCustomerDetailScreenState
    extends State<PhotographyCustomerDetailScreen> {
  String _tab='Overview';
  late DateTime _date=widget.date;
  bool get _wedding=>PhotographyCustomerCatalogue.wedding(widget.need);

  Future<void> _pickDay() async {
    final today=DateUtils.dateOnly(DateTime.now());
    final selected=await showGxCalendar(context,title:'Change event date',
      initialDate:_date.isBefore(today)?today:_date,
      firstDate:today,lastDate:today.add(const Duration(days:730)));
    if(mounted && selected!=null) setState(()=>_date=selected);
  }

  void _interest(bool custom) {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder:(_)=>PhotographyCustomerInterestScreen(
        vendor:widget.vendor,item:widget.item,cityId:widget.cityId,
        eventType:widget.eventType,date:_date,
        guests:widget.guests,location:widget.location,
        need:widget.need,customizeFirst:custom,
      )));
  }

  @override
  Widget build(BuildContext context) {
    final item=widget.item;
    final photos=(widget.vendor['catalogue'] as Map?)?['photos'] as List? ??
        const [];
    final tabs=_wedding ?
      const ['Overview','Inclusions','Coverage','Extras','Policies','Reviews']:
      const ['Overview','Coverage','Extras','Policies','Reviews'];
    return Scaffold(
      appBar:AppBar(title:Text(item['name']?.toString()??'Photography')),
      body:SafeArea(child:Column(children:[
        Expanded(child:ListView(children:[
          photographyImage(photos.isEmpty?null:photos.first?.toString(),
            height:200),
          Padding(padding:const EdgeInsets.all(16),child:Column(
            crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(item['name']?.toString()??'Photography',
                style:const TextStyle(color:_photoNavy,
                  fontSize:19,fontWeight:FontWeight.w900)),
              const SizedBox(height:7),
              PhotographyCustomerOfferPrice(item:item),
              const SizedBox(height:8),
              Card(color:_photoSoft,child:ListTile(
                title:const Text('Event date'),
                subtitle:Text(DateFormat('EEE, d MMM yyyy').format(_date)),
                trailing:const Icon(Icons.edit_calendar),
                onTap:_pickDay,
              )),
              const Text('Availability and add-ons confirmed after enquiry.',
                style:TextStyle(color:Colors.blueGrey,fontSize:11)),
              const SizedBox(height:12),
              SingleChildScrollView(scrollDirection:Axis.horizontal,
                child:Row(children:[
                  for(final tab in tabs)
                    Padding(padding:const EdgeInsets.only(right:6),
                      child:ChoiceChip(label:Text(tab),selected:_tab==tab,
                        onSelected:(_)=>setState(()=>_tab=tab))),
                ])),
              const SizedBox(height:13),
              ..._tabContent(),
            ])),
        ])),
        Padding(padding:const EdgeInsets.fromLTRB(12,8,12,16),
          child:Row(children:[
            Expanded(child:OutlinedButton(
              onPressed:()=>_interest(true),
              child:const Text('Customize Requirements',
                textAlign:TextAlign.center))),
            const SizedBox(width:8),
            Expanded(child:FilledButton(
              style:FilledButton.styleFrom(backgroundColor:_photoPink,
                padding:const EdgeInsets.symmetric(vertical:15)),
              onPressed:()=>_interest(false),
              child:const Text('Initiate Interest'))),
          ])),
      ])),
    );
  }

  List<Widget> _tabContent() {
    final item=widget.item;
    if(_tab=='Reviews') return [
      const Text('Customer reviews have not been published for this listing.')];
    if(_tab=='Overview') return [
      Text(item['description']?.toString().trim().isNotEmpty==true
        ? item['description'].toString()
        : 'Review this package’s details before submitting an enquiry.'),
      const SizedBox(height:14),
      if(!_wedding) ..._section('What is included',item['inclusions']),
      if((item['duration']?.toString()??'').isNotEmpty)
        Text('Duration: ${item['duration']}'),
      if((item['delivery']?.toString()??'').isNotEmpty)
        Text('Delivery: ${item['delivery']}'),
      const SizedBox(height:12),
      Text('Base estimate: ${photographyMoney(
        PhotographyCustomerCatalogue.priceOf(item)??0)}',
        style:const TextStyle(fontWeight:FontWeight.w800,color:_photoNavy)),
    ];
    if(_tab=='Inclusions') return [
      ..._section('Included photography & video',item['inclusions']),
      ..._mapSection('Deliverable quantities & formats',
        item['deliverableDetails']),
      ..._mapSection('Delivery timelines',item['deliveryTimelines']),
      if((item['includes']?.toString()??'').isNotEmpty)
        Text(item['includes'].toString()),
    ];
    if(_tab=='Coverage') return [
      ..._section('Functions',item['functions']),
      ..._section('Ceremony types',item['ceremonies']),
      ..._mapSection('Function coverage',item['functionCoverage']),
      for(final key in const [
        'coverageNotes','photographerTeam','videographerTeam',
        'team','duration','extraHourPrice',
      ])
        if((item[key]?.toString()??'').trim().isNotEmpty)
          Padding(padding:const EdgeInsets.only(bottom:8),
            child:Text('${_heading(key)}: ${item[key]}')),
    ];
    if(_tab=='Extras') return [
      const Text('Optional services (not included in the base price)',
        style:TextStyle(color:_photoNavy,fontWeight:FontWeight.w800)),
      ..._section('Available extras',item['extras'],
        prices:item['extraPrices'] as Map?),
      if((item['extrasNotes']?.toString()??'').isNotEmpty)
        Text(item['extrasNotes'].toString()),
    ];
    return [
      for(final key in const ['policy','customerRequirements','delivery'])
        if((item[key]?.toString()??'').trim().isNotEmpty)
          Padding(padding:const EdgeInsets.only(bottom:12),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,
              children:[
                Text(_heading(key),style:const TextStyle(
                  color:_photoNavy,fontWeight:FontWeight.w800)),
                Text(item[key].toString()),
              ])),
      ..._mapSection('Payment stages',_paymentMap(item['paymentSplit'])),
      ..._policySection('Cancellation',item['cancelRules']),
      ..._policySection('Rescheduling',item['rescheduleRules']),
      const Text('Refunds and policy terms must be confirmed with the provider.',
        style:TextStyle(color:Colors.blueGrey,fontSize:12)),
    ];
  }

  String _heading(String key)=>key.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),(m)=>'${m[1]} ${m[2]}');

  List<Widget> _section(String title,Object? rows,{Map? prices}) {
    if(rows is! List || rows.isEmpty)return [];
    return [
      Padding(padding:const EdgeInsets.only(bottom:6),
        child:Text(title,style:const TextStyle(
          color:_photoNavy,fontWeight:FontWeight.w800))),
      for(final row in rows)
        Padding(padding:const EdgeInsets.only(bottom:5),
          child:Text('• ${row.toString()}'
            '${prices?[row.toString()] is num ?
              ' · ${photographyMoney((prices![row.toString()] as num).toInt())} extra'
              : ''}')),
      const SizedBox(height:12),
    ];
  }

  List<Widget> _mapSection(String title,Object? object) {
    if(object is! Map || object.isEmpty)return [];
    return [
      Padding(padding:const EdgeInsets.only(top:8,bottom:7),
        child:Text(title,style:const TextStyle(
          color:_photoNavy,fontWeight:FontWeight.w800))),
      for(final entry in object.entries)
        Padding(padding:const EdgeInsets.only(bottom:8),
          child:Text('${entry.key}: ${_detail(entry.value)}')),
    ];
  }

  List<Widget> _policySection(String title,Object? obj) {
    if(obj is! List || obj.isEmpty)return [];
    return [
      Text(title,style:const TextStyle(
        color:_photoNavy,fontWeight:FontWeight.w800)),
      for(final row in obj.whereType<Map>())
        Padding(padding:const EdgeInsets.only(bottom:6),
          child:Text('${row['label']}: ${row['deductionPercent']}% deduction')),
      const SizedBox(height:12),
    ];
  }

  Map<String,dynamic> _paymentMap(Object? rows) {
    if(rows is! List)return {};
    return {for(final row in rows.whereType<Map>())
      '${row['label']??''}':'${row['percent']??0}%'};
  }

  String _detail(Object? value) {
    if(value is Map)return value.entries.map((e)=>
      '${_heading(e.key.toString())}: ${e.value}').join(' · ');
    if(value is List)return value.map(_detail).join(' · ');
    return value?.toString()??'';
  }
}
