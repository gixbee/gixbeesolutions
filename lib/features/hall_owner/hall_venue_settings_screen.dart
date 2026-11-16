import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/hall_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_snackbar.dart';

/// Shared venue configuration, independent of individual hall packages.
class HallVenueSettingsScreen extends ConsumerStatefulWidget {
  const HallVenueSettingsScreen({super.key,required this.business});
  final Business business;
  @override
  ConsumerState<HallVenueSettingsScreen> createState()=>
    _HallVenueSettingsScreenState();
}

class _HallVenueSettingsScreenState
    extends ConsumerState<HallVenueSettingsScreen> {
  final _count=TextEditingController();
  final _car=TextEditingController();
  final _bike=TextEditingController();
  bool _loading=true;
  bool _saving=false;
  String? _error;

  @override
  void initState(){super.initState();_load();}

  Future<void> _load() async {
    if(mounted)setState((){_loading=true;_error=null;});
    try {
      final venue=await ref.read(hallRepositoryProvider)
          .getVenue(widget.business.id);
      if(!mounted)return;
      final parking=venue['commonParking'] as Map? ?? const {};
      _count.text='${venue['plannedHallCount']??1}';
      _car.text='${parking['car']??0}';
      _bike.text='${parking['bike']??0}';
      setState(()=>_loading=false);
    } catch(e) {
      if(mounted)setState((){
        _error='$e';_loading=false;
      });
    }
  }

  @override
  void dispose(){
    _count.dispose();_car.dispose();_bike.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if(_saving)return;
    final count=int.tryParse(_count.text.trim());
    final cars=int.tryParse(_car.text.trim());
    final bikes=int.tryParse(_bike.text.trim());
    if(count==null||count<1||count>50||
       cars==null||cars<0||cars>10000||
       bikes==null||bikes<0||bikes>10000) {
      showGxSnack(context,'Hall count: 1–50; parking: 0–10,000.',
        type:GxSnackType.error);
      return;
    }
    setState(()=>_saving=true);
    try {
      await ref.read(hallRepositoryProvider).patchVenue(widget.business.id,{
        'plannedHallCount':count,
        'commonParking':{'car':cars,'bike':bikes},
      });
      if(!mounted)return;
      showGxSnack(context,'Venue settings saved');
      Navigator.pop(context,true);
    } catch(e) {
      if(mounted)showGxSnack(context,'Save failed: $e',
        type:GxSnackType.error);
    } finally {
      if(mounted)setState(()=>_saving=false);
    }
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Venue & Parking')),
    body:_loading?const Center(child:CircularProgressIndicator()):
      _error!=null?Center(child:Column(
        mainAxisSize:MainAxisSize.min,children:[
          Padding(padding:const EdgeInsets.all(12),child:Text(_error!)),
          TextButton(onPressed:_load,child:const Text('Retry')),
        ])):SafeArea(child:ListView(
          padding:const EdgeInsets.all(20),children:[
          Text(widget.business.name,
            style:const TextStyle(color:Color(0xFF1B2559),
              fontSize:20,fontWeight:FontWeight.w900)),
          const SizedBox(height:10),
          TextField(controller:_count,keyboardType:TextInputType.number,
            decoration:const InputDecoration(
              labelText:'Number of halls / spaces',
              border:OutlineInputBorder())),
          const SizedBox(height:18),
          const Text('Common parking',style:TextStyle(
            color:Color(0xFF1B2559),fontWeight:FontWeight.w800)),
          const Text('Shared capacity across your halls',
            style:TextStyle(color:Colors.blueGrey)),
          const SizedBox(height:12),
          TextField(controller:_car,keyboardType:TextInputType.number,
            decoration:const InputDecoration(labelText:'Cars',
              prefixIcon:Icon(Icons.local_parking_outlined),
              border:OutlineInputBorder())),
          const SizedBox(height:13),
          TextField(controller:_bike,keyboardType:TextInputType.number,
            decoration:const InputDecoration(labelText:'Bikes',
              prefixIcon:Icon(Icons.two_wheeler_outlined),
              border:OutlineInputBorder())),
          const SizedBox(height:20),
          FilledButton(
            onPressed:_saving?null:_save,
            child:Text(_saving?'Saving...':'Save Venue Details')),
        ])),
  );
}
