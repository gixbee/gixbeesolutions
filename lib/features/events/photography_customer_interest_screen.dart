import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../repositories/events_repository.dart';
import 'event_plan_detail_screen.dart';
import 'event_plans_screen.dart';
import 'photography_customer_model.dart';

const _ink = Color(0xFF1B2559);
const _accent = Color(0xFFDB2777);
const _soft = Color(0xFFFDF2F8);

class PhotographyCustomerInterestScreen extends ConsumerStatefulWidget {
  const PhotographyCustomerInterestScreen({
    super.key, required this.vendor,required this.item,required this.cityId,
    required this.eventType,required this.date,required this.guests,
    required this.location,required this.need,this.customizeFirst=false,
  });
  final Map<String,dynamic> vendor,item;
  final String cityId,eventType,location,need;
  final DateTime date;
  final int guests;
  final bool customizeFirst;

  @override
  ConsumerState<PhotographyCustomerInterestScreen> createState() =>
      _PhotographyCustomerInterestScreenState();
}

class _PhotographyCustomerInterestScreenState
    extends ConsumerState<PhotographyCustomerInterestScreen> {
  final _requestId=const Uuid().v4();
  final _location=TextEditingController();
  final _coverage=TextEditingController();
  final _team=TextEditingController();
  final _deliverables=TextEditingController();
  final _notes=TextEditingController();
  final _selectedExtras=<String>{};
  final _functions=<String>{};
  late DateTime _start=DateTime(widget.date.year,widget.date.month,
      widget.date.day,10);
  late DateTime _end=_start.add(const Duration(hours:4));
  late int _stage=widget.customizeFirst?0:1;
  bool _sending=false;
  bool _ack=false;
  String? _sentId;

  @override
  void initState() {
    super.initState();
    _location.text=widget.location;
  }

  @override
  void dispose() {
    for(final c in [_location,_coverage,_team,_deliverables,_notes]){
      c.dispose();
    }
    super.dispose();
  }

  String get _studio=>widget.vendor['name']?.toString()??'Photography studio';
  int get _price=>PhotographyCustomerCatalogue.priceOf(widget.item)??0;
  String _money(int n)=>'₹${NumberFormat.decimalPattern('en_IN').format(n)}';

  Map<String,dynamic> _customization() => {
    'functions':_functions.toList()..sort(),
    'coverage':_coverage.text.trim(),
    'team':_team.text.trim(),
    'deliverables':_deliverables.text.trim(),
    'extras':(_selectedExtras.toList()..sort()).join(', '),
  };

  Future<void> _pickTime(bool start) async {
    final original=start?_start:_end;
    final today=DateUtils.dateOnly(DateTime.now());
    final first=today;
    final day=await showDatePicker(context:context,
      initialDate:original.isBefore(first)?first:original,
      firstDate:first,lastDate:today.add(const Duration(days:730)));
    if(day==null || !mounted)return;
    final clock=await showTimePicker(context:context,
      initialTime:TimeOfDay.fromDateTime(original));
    if(clock==null || !mounted)return;
    final date=DateTime(day.year,day.month,day.day,clock.hour,clock.minute);
    setState(() {
      if(start){
        _start=date;
        if(!_end.isAfter(_start))_end=_start.add(const Duration(hours:4));
      }else {
        _end=date;
      }
    });
  }

  Map<String,dynamic> _request() => PhotographyCustomerRequest.build(
    clientRequestId:_requestId,
    businessId:widget.vendor['businessId'] as String,
    cityId:widget.cityId,eventType:widget.eventType,
    location:_location.text,start:_start,end:_end,
    guests:widget.guests,item:widget.item,
    notes:_notes.text,customization:_customization(),
  );

  Future<void> _send() async {
    if(_sending || _sentId!=null)return;
    if(!_ack){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('Acknowledge that this is an enquiry, not a booking.')));
      return;
    }
    late final Map<String,dynamic> request;
    try { request=_request(); }
    on FormatException catch(e){
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text(e.message)));
      return;
    }
    setState(()=>_sending=true);
    try {
      final saved=await ref.read(eventsRepositoryProvider).create(request);
      if(!mounted)return;
      setState(() {
        _sentId=saved['id'] as String;
        _stage=2;
      });
    } catch(error){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text(eventError(error))));
    } finally {
      if(mounted)setState(()=>_sending=false);
    }
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(_stage==0?'Customize Requirements':
      _stage==1?'Review Your Interest':'Interest sent')),
    body:SafeArea(child:_stage==2?_sent():Column(children:[
      Expanded(child:ListView(
        padding:const EdgeInsets.all(16),
        children:_stage==0?_customize():_review())),
      Padding(padding:const EdgeInsets.fromLTRB(12,8,12,16),
        child:Row(children:[
          Expanded(child:OutlinedButton(
            onPressed:_sending?null:()=>setState(() {
              if(_stage==1)_stage=0;
              else Navigator.pop(context);
            }),
            child:Text(_stage==1?'Edit Requirements':'Back'),
          )),
          const SizedBox(width:10),
          Expanded(child:FilledButton(
            style:FilledButton.styleFrom(backgroundColor:_accent,
              padding:const EdgeInsets.symmetric(vertical:15)),
            onPressed:_sending?null:()=>_stage==0?
              setState(()=>_stage=1):_send(),
            child:Text(_sending?'Sending...':
              _stage==0?'Review Interest':'Send Interest'),
          )),
        ])),
    ])),
  );

  List<Widget> _customize(){
    final extras=(widget.item['extras'] as List? ?? const [])
        .whereType<String>().take(20).toList();
    final functions=(widget.item['functions'] as List? ?? const [])
        .whereType<String>().take(8).toList();
    return [
      _summary(),
      const SizedBox(height:15),
      const Text('Requested changes will be quoted by the photographer. '
        'They are not included in the displayed base price.',
        style:TextStyle(color:Colors.blueGrey)),
      if(functions.isNotEmpty)...[
        const SizedBox(height:14),
        const Text('Additional functions to discuss',
          style:TextStyle(fontWeight:FontWeight.w800,color:_ink)),
        Wrap(spacing:7,runSpacing:4,children:[
          for(final name in functions)
            FilterChip(label:Text(name),
              selected:_functions.contains(name),
              onSelected:(value)=>setState(() {
                if(value)_functions.add(name);else _functions.remove(name);
              })),
        ]),
      ],
      const SizedBox(height:16),
      _input(_coverage,'Coverage and duration preferences',3),
      _input(_team,'Crew and equipment preferences',3),
      _input(_deliverables,'Albums, video, photo-selection or delivery changes',3),
      if(extras.isNotEmpty)...[
        const Text('Optional extras',
          style:TextStyle(fontWeight:FontWeight.w800,color:_ink)),
        const SizedBox(height:6),
        for(final name in extras)
          CheckboxListTile(
            contentPadding:EdgeInsets.zero,
            dense:true,
            value:_selectedExtras.contains(name),
            title:Text(name),
            subtitle:widget.item['extraPrices'] is Map &&
                (widget.item['extraPrices'] as Map)[name] is num ?
              Text('Owner list price: ${_money(
                ((widget.item['extraPrices'] as Map)[name] as num).toInt())}; '
                'final quote may vary.') : null,
            onChanged:(v)=>setState(() {
              if(v==true)_selectedExtras.add(name);
              else _selectedExtras.remove(name);
            }),
          ),
      ],
      const SizedBox(height:10),
      _input(_notes,'Additional requests or special instructions',4,maxLength:5000),
      const SizedBox(height:10),
      const Text('The studio confirms any additional charges in its quote.',
        style:TextStyle(color:Colors.blueGrey)),
    ];
  }

  Widget _input(TextEditingController c,String name,int rows,
      {int maxLength=900}) => Padding(
        padding:const EdgeInsets.only(bottom:16),
        child:TextField(controller:c,maxLines:rows,maxLength:maxLength,
          decoration:InputDecoration(labelText:name,
            border:const OutlineInputBorder(),
            alignLabelWithHint:true)),
      );

  Widget _summary()=>Card(color:_soft,
    child:Padding(padding:const EdgeInsets.all(14),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(widget.item['name']?.toString()??'Photography',
          style:const TextStyle(color:_ink,fontWeight:FontWeight.w900,
            fontSize:16)),
        Text(_studio,style:const TextStyle(color:Colors.blueGrey)),
        const SizedBox(height:6),
        Text('Base estimate ${_money(_price)}',
          style:const TextStyle(color:_ink,fontWeight:FontWeight.w900,
            fontSize:17)),
        const Text('Optional extras are not included.',
          style:TextStyle(fontSize:11,color:Colors.blueGrey)),
      ]),
    ));

  Widget _row(String title,String value)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:8),
    child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      SizedBox(width:113,child:Text(title,
        style:const TextStyle(color:Colors.blueGrey))),
      Expanded(child:Text(value,style:const TextStyle(
        fontWeight:FontWeight.w800,color:_ink))),
    ]),
  );

  List<Widget> _review()=>[
    _summary(),
    const SizedBox(height:14),
    const Text('Event Details',style:TextStyle(color:_ink,
      fontSize:17,fontWeight:FontWeight.w900)),
    _row('Studio',_studio),
    _row('Photography for',PhotographyCustomerCatalogue.label(widget.need)),
    _row('Date',DateFormat('EEE, dd MMM yyyy').format(_start)),
    ListTile(
      contentPadding:EdgeInsets.zero,
      leading:const Icon(Icons.event),
      title:const Text('Starts'),
      subtitle:Text(DateFormat('dd MMM yyyy · hh:mm a').format(_start)),
      trailing:const Icon(Icons.edit_calendar),
      onTap:_sending?null:()=>_pickTime(true),
    ),
    ListTile(
      contentPadding:EdgeInsets.zero,
      leading:const Icon(Icons.event_available),
      title:const Text('Ends'),
      subtitle:Text(DateFormat('dd MMM yyyy · hh:mm a').format(_end)),
      trailing:const Icon(Icons.edit_calendar),
      onTap:_sending?null:()=>_pickTime(false),
    ),
    _input(_location,'Venue / area *',2,maxLength:2000),
    const Text('Selected Requirements',
      style:TextStyle(color:_ink,fontWeight:FontWeight.w900)),
    for(final e in _customization().entries)
      if(e.value is List && (e.value as List).isNotEmpty)
        _row('Functions',(e.value as List).join(', '))
      else if(e.value is String && (e.value as String).trim().isNotEmpty)
        _row(e.key,e.value as String),
    if(_notes.text.trim().isNotEmpty)
      _row('Notes',_notes.text.trim()),
    const SizedBox(height:10),
    const Text('Policies & payment',
      style:TextStyle(color:_ink,fontWeight:FontWeight.w900)),
    if((widget.item['policy']?.toString()??'').isNotEmpty)
      Text(widget.item['policy'].toString()),
    for(final row in (widget.item['paymentSplit'] as List? ?? const [])
        .whereType<Map>())
      _row(row['label']?.toString()??'Stage','${row['percent']??0}%'),
    const SizedBox(height:9),
    const Text('The price shown is the base estimate. The studio may '
      'confirm availability and adjust its quote for requested extras.',
      style:TextStyle(color:Colors.blueGrey)),
    const SizedBox(height:8),
    CheckboxListTile(
      value:_ack,contentPadding:EdgeInsets.zero,
      title:const Text('I understand this is an enquiry, not a booking.'),
      onChanged:_sending?null:(v)=>setState(()=>_ack=v??false),
    ),
  ];

  Widget _sent()=>ListView(
    padding:const EdgeInsets.all(20),
    children:[
      const SizedBox(height:24),
      const Icon(Icons.send_rounded,color:_accent,size:64),
      const SizedBox(height:14),
      const Text('Your Interest has been Sent!',
        textAlign:TextAlign.center,
        style:TextStyle(color:_ink,fontWeight:FontWeight.w900,fontSize:22)),
      const SizedBox(height:9),
      const Text('The photographer can review your request and send a quote. '
        'This does not confirm a booking or payment.',
        textAlign:TextAlign.center,
        style:TextStyle(color:Colors.blueGrey)),
      const SizedBox(height:18),
      for(final (done,title,detail) in const [
        (true,'Interest sent','Your enquiry was submitted'),
        (false,'Under review','Awaiting photographer response'),
        (false,'Quote & discussion','Review the price and conditions'),
        (false,'Booking','Confirm separately after agreement'),
      ])
        ListTile(
          leading:Icon(done?Icons.check_circle:Icons.circle_outlined,
            color:done?_accent:Colors.blueGrey),
          title:Text(title),
          subtitle:Text(detail),
        ),
      const SizedBox(height:19),
      FilledButton(
        style:FilledButton.styleFrom(backgroundColor:_accent,
          padding:const EdgeInsets.symmetric(vertical:16)),
        onPressed:()=>Navigator.of(context).pushReplacement<void,
          void>(MaterialPageRoute(
            builder:(_)=>EventPlanDetailScreen(planId:_sentId!))),
        child:const Text('View Interest Details'),
      ),
      const SizedBox(height:8),
      OutlinedButton(
        onPressed:()=>Navigator.of(context).pushReplacement<void,
          void>(MaterialPageRoute(
            builder:(_)=>const EventPlansScreen(
              interestService:'PHOTOGRAPHY'))),
        child:const Text('View My Interests'),
      ),
    ],
  );
}
