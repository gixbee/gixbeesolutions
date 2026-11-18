import '../../shared/widgets/gx_network_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../repositories/events_repository.dart';
import '../../shared/media/profile_photo.dart';
import '../../shared/widgets/gx_calendar.dart';
import 'event_plan_create_screen.dart';
import 'hall_booking_review_screen.dart';
import 'hall_customer_model.dart';

const _hallInk=Color(0xFF1B2559);
const _hallGreen=Color(0xFF12B76A);
const _hallLight=Color(0xFFECFDF3);

String hallMoney(num value) =>
  '₹${NumberFormat.decimalPattern('en_IN').format(value)}';

Widget hallPhoto(String? path, {double height=195}) {
  final url=resolveProfileImageUrl(path);
  return ClipRRect(borderRadius:BorderRadius.circular(12),
    child:url==null?Container(
      height:height,color:_hallLight,
      alignment:Alignment.center,
      child:const Icon(Icons.apartment,size:70,color:_hallGreen)):
      Image.network(url,height:height,width:double.infinity,
        fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(
          height:height,color:_hallLight,
          child:const Icon(Icons.apartment,size:52))),
  );
}

class HallCustomerProfileScreen extends ConsumerStatefulWidget {
  const HallCustomerProfileScreen({
    super.key,required this.hall,required this.cityId,
    required this.eventType,required this.date,
    required this.guests,required this.acPreference,
  });
  final Map<String,dynamic> hall;
  final String cityId,eventType,acPreference;
  final DateTime date;
  final int guests;
  @override
  ConsumerState<HallCustomerProfileScreen> createState() =>
    _HallCustomerProfileScreenState();
}

class _HallCustomerProfileScreenState
    extends ConsumerState<HallCustomerProfileScreen> {
  late Future<Map<String,dynamic>> _details=_load();
  Map<String,dynamic>? _current;

  Future<Map<String,dynamic>> _load() =>
      ref.read(eventsRepositoryProvider).hallDetails(
        widget.hall['hallId'] as String,
        DateFormat('yyyy-MM-dd').format(widget.date));

  void _reload()=>setState(()=>_details=_load());

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Hall Details')),
    body:FutureBuilder<Map<String,dynamic>>(
      future:_details,builder:(context,snap) {
        if(snap.connectionState!=ConnectionState.done) {
          return const Center(child:CircularProgressIndicator());
        }
        if (snap.hasError) return GxNetworkError(
          error: snap.error,
          title: 'Hall details unavailable',
          onRetry: _reload,
        );
        final data=snap.data!;
        _current=data;
        final pkg=data['package'] as Map? ?? const {};
        final capacity=pkg['capacity'] as Map? ?? const {};
        final parking=data['parking'] as Map? ?? const {};
        final photos=(data['photos'] as List? ?? const [])
          .whereType<String>().toList();
        final facilities=(pkg['facilities'] as List? ?? const [])
          .map((e)=>e.toString()).toList();
        final catering=pkg['catering'] as Map? ?? const {};
        return SafeArea(child:Column(children:[
          Expanded(child:ListView(
            padding:const EdgeInsets.all(16),children:[
              hallPhoto(data['coverImageUrl']?.toString() ??
                (photos.isNotEmpty?photos.first:null),height:220),
              const SizedBox(height:12),
              Text(data['businessName']?.toString()??'Venue',
                style:const TextStyle(color:_hallInk,
                  fontSize:20,fontWeight:FontWeight.w900)),
              Text(data['hallName']?.toString()??'Hall',
                style:const TextStyle(color:_hallInk,
                  fontWeight:FontWeight.w700,fontSize:16)),
              Text('${data['location']??''} · ${data['spaceType']??'indoor'}',
                style:const TextStyle(color:Colors.blueGrey)),
              const SizedBox(height:9),
              const Chip(label:Text('Verified hall · availability checked per slot'),
                backgroundColor:_hallLight),
              const SizedBox(height:18),
              const Text('Capacity & Parking',style:TextStyle(
                color:_hallInk,fontSize:17,fontWeight:FontWeight.w900)),
              const SizedBox(height:9),
              Wrap(spacing:8,runSpacing:7,children:[
                _metric(Icons.chair_alt_outlined,
                  'Seating',capacity['seat']),
                _metric(Icons.restaurant_outlined,
                  'Dining',capacity['dine']),
                _metric(Icons.local_parking_outlined,
                  'Cars',parking['car']),
                _metric(Icons.two_wheeler_outlined,
                  'Bikes',parking['bike']),
                if(capacity['rooms']!=null)
                  _metric(Icons.bed_outlined,'Private rooms',
                    capacity['rooms']),
              ]),
              const SizedBox(height:18),
              const Text('Facilities & Services',style:TextStyle(
                color:_hallInk,fontSize:17,fontWeight:FontWeight.w900)),
              if(facilities.isEmpty)
                const Text('No facilities listed.')
              else Wrap(spacing:7,runSpacing:5,children:[
                for(final facility in facilities)
                  Chip(label:Text(facility)),
              ]),
              if(catering.isNotEmpty)...[
                const SizedBox(height:10),
                for(final (key,label) in const [
                  ('inHouse','In-house catering'),
                  ('outside','Outside catering'),
                  ('decorHall','Hall decoration'),
                  ('decorOutside','Outside decoration'),
                ])
                  if(catering[key]!=null)
                    ListTile(dense:true,
                      leading:Icon(catering[key]=='yes'?
                        Icons.check_circle_outline:Icons.remove_circle_outline,
                        color:catering[key]=='yes'?_hallGreen:Colors.blueGrey),
                      title:Text(label),subtitle:Text(
                        catering[key]=='yes'?'Available':'Not included')),
              ],
              if(photos.isNotEmpty)...[
                const SizedBox(height:18),
                Text('Gallery · ${photos.length} photos',style:const TextStyle(
                  color:_hallInk,fontWeight:FontWeight.w900,fontSize:17)),
                const SizedBox(height:9),
                SizedBox(height:105,child:ListView.separated(
                  scrollDirection:Axis.horizontal,itemCount:photos.length,
                  separatorBuilder:(_,__)=>const SizedBox(width:8),
                  itemBuilder:(_,i)=>SizedBox(width:135,
                    child:hallPhoto(photos[i],height:105)))),
              ],
              const SizedBox(height:18),
              const Text('Location',style:TextStyle(
                color:_hallInk,fontWeight:FontWeight.w800)),
              Text('${data['location']??''}'),
            ])),
          Padding(padding:const EdgeInsets.fromLTRB(16,8,16,16),
            child:SizedBox(width:double.infinity,child:FilledButton(
              style:FilledButton.styleFrom(backgroundColor:_hallGreen,
                padding:const EdgeInsets.symmetric(vertical:15)),
              onPressed:()=>Navigator.push(context,
                MaterialPageRoute<void>(builder:(_)=>HallCustomerSlotsScreen(
                  hall:_current!,cityId:widget.cityId,
                  eventType:widget.eventType,date:widget.date,
                  guests:widget.guests,acPreference:widget.acPreference))),
              child:const Text('Continue · Select Date & Time'),
            ))),
        ]));
      }),
  );

  Widget _metric(IconData icon,String label,Object? count)=>Card(
    color:_hallLight,child:Padding(padding:const EdgeInsets.all(9),
      child:Row(mainAxisSize:MainAxisSize.min,children:[
        Icon(icon,size:18,color:_hallInk),
        const SizedBox(width:6),
        Text('${count??'—'} $label',
          style:const TextStyle(color:_hallInk,
            fontWeight:FontWeight.w700,fontSize:12)),
      ])));
}

class HallCustomerSlotsScreen extends ConsumerStatefulWidget {
  const HallCustomerSlotsScreen({
    super.key,required this.hall,required this.cityId,
    required this.eventType,required this.date,
    required this.guests,required this.acPreference,
  });
  final Map<String,dynamic> hall;
  final String cityId,eventType,acPreference;
  final DateTime date;
  final int guests;
  @override
  ConsumerState<HallCustomerSlotsScreen> createState()=>
    _HallCustomerSlotsScreenState();
}

class _HallCustomerSlotsScreenState
    extends ConsumerState<HallCustomerSlotsScreen> {
  late DateTime _day=DateUtils.dateOnly(widget.date);
  late Future<Map<String,dynamic>> _future=_load();
  String? _selected;

  Future<Map<String,dynamic>> _load()=>
    ref.read(eventsRepositoryProvider).hallDetails(
      widget.hall['hallId'] as String,
      DateFormat('yyyy-MM-dd').format(_day));

  void _refresh()=>setState((){
    _selected=null;_future=_load();
  });

  Future<void> _pickDay() async {
    final today=DateUtils.dateOnly(DateTime.now());
    final selected=await showGxCalendar(context,title:'Select Hall Date',
      initialDate:_day.isBefore(today)?today:_day,firstDate:today,
      lastDate:today.add(const Duration(days:730)));
    if(!mounted||selected==null)return;
    setState((){
      _day=selected;_selected=null;
      _future=_load();
    });
  }

  String _selectionId(Map<String,dynamic> row)=>
    '${row['slotId']}|${row['withAc']}';

  void _review(Map<String,dynamic> detail,Map<String,dynamic> row) {
    final request=HallCustomerModel.request(detail:detail,slot:row);
    final amount=row['price'] as int;
    Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>
      HallBookingReviewScreen(
        hall:detail,guests:widget.guests,
        eventType:widget.eventType,eventDate:_day,
        selection:EventServiceSelection(
          businessId:detail['businessId'] as String,
          cityId:widget.cityId,
          start:DateTime.parse(row['start'] as String),
          end:DateTime.parse(row['end'] as String),
          address:detail['location']?.toString(),
          summary:'${detail['hallName']} · ${row['label']} · '
            '${row['withAc']==true?'With AC':'Without AC'}\n'
            '${hallMoney(amount)}',
          request:request,
        ),
        slot:row,
      )));
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Select Date & Time'),
      actions:[IconButton(icon:const Icon(Icons.refresh),
        tooltip:'Refresh availability',onPressed:_refresh)]),
    body:FutureBuilder<Map<String,dynamic>>(
      future:_future,builder:(context,snapshot){
        if(snapshot.connectionState!=ConnectionState.done)return
          const Center(child:CircularProgressIndicator());
        if (snapshot.hasError) return GxNetworkError(
          error: snapshot.error,
          title: 'Availability unavailable',
          onRetry: _refresh,
        );
        final detail=snapshot.data!;
        final offers=detail['slots'] as List? ?? const [];
        final rows=HallCustomerModel.availableSlots(
          detail,ac:widget.acPreference);
        final Map<String,dynamic>? selected=rows.where(
          (row)=>_selectionId(row)==_selected).firstOrNull;
        return SafeArea(child:Column(children:[
          Expanded(child:ListView(padding:const EdgeInsets.all(16),children:[
            Card(color:_hallLight,child:ListTile(
              title:Text(detail['businessName']?.toString()??'Venue',
                style:const TextStyle(color:_hallInk,
                  fontWeight:FontWeight.w900)),
              subtitle:Text('${detail['hallName']??'Hall'} · '
                '${widget.guests} guests'),
            )),
            ListTile(contentPadding:EdgeInsets.zero,
              title:const Text('Select Date'),
              subtitle:Text(DateFormat('EEEE, d MMM yyyy').format(_day)),
              trailing:const Icon(Icons.edit_calendar),
              onTap:_pickDay),
            const SizedBox(height:8),
            const Text('Select Time Slot · Prices include GST',
              style:TextStyle(color:_hallInk,
                fontSize:16,fontWeight:FontWeight.w900)),
            const SizedBox(height:8),
            if(offers.isEmpty)
              const Text('No slots are published for this date.'),
            if(rows.isEmpty && offers.isNotEmpty)
              const Text('No selectable AC/non-AC prices are available on '
                'this date. Choose another day.'),
            for(final offer in offers.whereType<Map>())
              if(offer['available']==false)
                Card(child:ListTile(
                  enabled:false,
                  title:Text(offer['offer'] is Map
                    ? (offer['offer'] as Map)['label']?.toString()??'Slot'
                    : 'Slot'),
                  subtitle:const Text('Unavailable / already booked'))),
            for(final row in rows)
              Card(
                margin:const EdgeInsets.only(bottom:8),
                child:RadioListTile<String>(
                  key:ValueKey('hall-slot-${_selectionId(row)}'),
                  groupValue:_selected,
                  value:_selectionId(row),
                  onChanged:(v)=>setState(()=>_selected=v),
                  title:Text('${row['label']} · '
                    '${row['withAc']==true?'With AC':'Without AC'}',
                    style:const TextStyle(color:_hallInk,
                      fontWeight:FontWeight.w800)),
                  subtitle:Column(
                    crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text('${_time(row['start'])} – ${_time(row['end'])} IST'),
                    Wrap(spacing:8,children:[
                      Text(hallMoney(row['price'] as int),
                        style:const TextStyle(color:_hallGreen,
                          fontSize:17,fontWeight:FontWeight.w900)),
                      if(row['basePrice'] is int &&
                          (row['basePrice'] as int)>(row['price'] as int))
                        Text(hallMoney(row['basePrice'] as int),
                          style:const TextStyle(
                            decoration:TextDecoration.lineThrough,
                            color:Colors.blueGrey)),
                      if(row['discountPercent'] is int &&
                          (row['discountPercent'] as int)>0)
                        Text('${row['discountPercent']}% OFF',
                          style:const TextStyle(color:_hallGreen,
                            fontWeight:FontWeight.w800)),
                    ]),
                  ]),
                )),
            const SizedBox(height:14),
            const Text('The hall owner confirms availability and booking '
              'terms before payment. This is a request, not a reservation.',
              style:TextStyle(fontSize:12,color:Colors.blueGrey)),
          ])),
          Padding(padding:const EdgeInsets.fromLTRB(16,7,16,16),
            child:SizedBox(width:double.infinity,child:FilledButton(
              style:FilledButton.styleFrom(backgroundColor:_hallGreen,
                padding:const EdgeInsets.symmetric(vertical:15)),
              onPressed:selected==null?null:()=>_review(detail,selected),
              child:const Text('Continue · Review Booking Details'),
            ))),
        ]));
      }),
  );

  String _time(Object? raw) {
    final parsed=DateTime.tryParse(raw?.toString()??'');
    if(parsed==null)return '—';
    // Existing hall slots use the venue timezone Asia/Kolkata.
    final ist=parsed.toUtc().add(
      const Duration(hours:5,minutes:30));
    return DateFormat('hh:mm a').format(ist);
  }
}
