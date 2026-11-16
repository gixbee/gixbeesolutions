import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/hall_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_snackbar.dart';

/// Hall-specific customer booking constraints. The package is always
/// reloaded immediately before saving to preserve the other pricing fields.
class HallBookingSettingsScreen extends ConsumerStatefulWidget {
  const HallBookingSettingsScreen({
    super.key, required this.business,required this.hallId,
  });
  final Business business;
  final String hallId;

  @override
  ConsumerState<HallBookingSettingsScreen> createState() =>
      _HallBookingSettingsScreenState();
}

class _HallBookingSettingsScreenState
    extends ConsumerState<HallBookingSettingsScreen> {
  static const _navy=Color(0xFF1B2559);
  int _months=6;
  int _notice=3;
  bool _loading=true;
  bool _saving=false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if(mounted)setState((){
      _loading=true;
      _loadError=null;
    });
    try {
      final data=await ref.read(hallRepositoryProvider)
        .getPackage(widget.business.id,widget.hallId);
      final pkg=data['package'] as Map?;
      if(!mounted)return;
      if(pkg==null) {
        setState((){
          _loadError='Save your hall package before editing booking settings.';
          _loading=false;
        });
        return;
      }
      setState((){
        _months=(pkg['bookWindowMonths'] as num?)?.toInt()??6;
        _notice=(pkg['minNoticeDays'] as num?)?.toInt()??3;
        _loading=false;
      });
    } catch(error) {
      if(mounted)setState((){
        _loadError='$error';
        _loading=false;
      });
    }
  }

  Future<void> _save() async {
    if(_saving||_loading)return;
    if(_notice>_months*31) {
      showGxSnack(context,'Minimum notice cannot exceed the booking window.',
        type:GxSnackType.error);
      return;
    }
    setState(()=>_saving=true);
    try {
      final repo=ref.read(hallRepositoryProvider);
      final latest=await repo.getPackage(widget.business.id,widget.hallId);
      final raw=latest['package'];
      if(raw is! Map)throw StateError('Hall package is missing');
      final pkg=Map<String,dynamic>.from(raw);
      pkg['bookWindowMonths']=_months;
      pkg['minNoticeDays']=_notice;
      await repo.savePackage(widget.business.id,widget.hallId,pkg);
      if(!mounted)return;
      showGxSnack(context,'Booking settings saved');
      Navigator.pop(context,true);
    } catch(error){
      if(mounted)showGxSnack(context,'Unable to save: $error',
        type:GxSnackType.error);
    } finally {
      if(mounted)setState(()=>_saving=false);
    }
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Booking Settings')),
    body: _loading?const Center(child:CircularProgressIndicator()):
      _loadError!=null?Center(child:Column(
        mainAxisSize:MainAxisSize.min,children:[
          Padding(padding:const EdgeInsets.all(14),
            child:Text(_loadError!)),
          TextButton(onPressed:_load,child:const Text('Retry')),
        ])):SafeArea(child:ListView(
          padding:const EdgeInsets.all(18),children:[
            const Text('Customer Booking Window',style:TextStyle(
              color:_navy,fontWeight:FontWeight.w900,fontSize:20)),
            const SizedBox(height:5),
            const Text('How many months in advance may customers request a slot?'),
            const SizedBox(height:10),
            Wrap(spacing:8,runSpacing:5,children:[
              for(final months in const [1,3,6,9,12,18,24,36])
                ChoiceChip(
                  label:Text('$months mo'),
                  selected:_months==months,
                  onSelected:_saving?null:(_)=>setState(()=>_months=months)),
            ]),
            Card(color:const Color(0xFFECFDF3),child:Padding(
              padding:const EdgeInsets.all(12),
              child:Text('Customers can request bookings up to '
                '$_months months ahead.'))),
            const SizedBox(height:20),
            const Text('Minimum Booking Notice',style:TextStyle(
              color:_navy,fontWeight:FontWeight.w900,fontSize:20)),
            const SizedBox(height:5),
            const Text('How early must the customer send a request?'),
            const SizedBox(height:10),
            Wrap(spacing:8,runSpacing:5,children:[
              for(final days in const [0,1,2,3,7,14,30,60,90])
                ChoiceChip(
                  label:Text(days==0?'Same day':'$days days'),
                  selected:_notice==days,
                  onSelected:_saving?null:(_)=>setState(()=>_notice=days)),
            ]),
            Card(color:const Color(0xFFEFF6FF),child:Padding(
              padding:const EdgeInsets.all(12),
              child:Text(_notice==0
                ? 'Requests may be made on the event date before slot start.'
                : 'Requests must be made at least $_notice days before the event.'))),
            const SizedBox(height:18),
            const Text('These settings are checked by Rust when customers '
              'request a hall slot. A request does not confirm a reservation.',
              style:TextStyle(color:Colors.blueGrey)),
            const SizedBox(height:22),
            FilledButton(
              style:FilledButton.styleFrom(
                backgroundColor:const Color(0xFF12B76A),
                padding:const EdgeInsets.symmetric(vertical:15)),
              onPressed:_saving?null:_save,
              child:Text(_saving?'Saving...':'Save Booking Settings')),
          ])),
  );
}
