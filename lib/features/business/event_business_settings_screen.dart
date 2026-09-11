import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/business_repository.dart';
import '../../repositories/cities_repository.dart';
import '../../repositories/events_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_text_field.dart';

class EventBusinessSettingsScreen extends ConsumerStatefulWidget {
  const EventBusinessSettingsScreen({super.key, required this.business});
  final Business business;
  @override
  ConsumerState<EventBusinessSettingsScreen> createState() => _EventBusinessSettingsScreenState();
}

class _EventBusinessSettingsScreenState extends ConsumerState<EventBusinessSettingsScreen> {
  late final TextEditingController _phone;
  late final Set<String> _services;
  String? _cityId;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _phone = TextEditingController(text: widget.business.phone);
    _services = {...widget.business.eventServices, if (widget.business.serviceType != null) widget.business.serviceType!};
    _cityId = widget.business.cityId;
  }
  @override
  void dispose() { _phone.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_busy) return;
    if (_services.isEmpty || _cityId == null || _phone.text.replaceAll(RegExp(r'\D'), '').length < 10) {
      showGxSnack(context, 'Select services, a city and a valid business phone number'); return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(businessRepositoryProvider).updateBusiness(widget.business.id,
        {'phone': _phone.text.trim(), 'eventServices': _services.toList(), 'cityId': _cityId});
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showGxSnack(context, eventError(e));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Event services & contact')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text(widget.business.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      const Text('Choose every service this business offers. A confirmed event reserves the business for its schedule, including all selected services at that event.'),
      const SizedBox(height: 16),
      Wrap(spacing: 8, children: eventServices.entries.map((e) => FilterChip(label: Text(e.value),
        selected: _services.contains(e.key), onSelected: _busy ? null : (selected) => setState(() {
          if (selected) { _services.add(e.key); } else { _services.remove(e.key); }
        }))).toList()),
      const SizedBox(height: 20),
      ref.watch(citiesProvider).when(
        loading: () => const LinearProgressIndicator(),
        error: (_, __) => TextButton(onPressed: () => ref.invalidate(citiesProvider), child: const Text('Reload cities')),
        data: (cities) => cities.isEmpty
          ? TextButton(onPressed: () => ref.invalidate(citiesProvider), child: const Text('Reload serviceable cities'))
          : DropdownButtonFormField<String>(initialValue: cities.any((c) => c.id == _cityId) ? _cityId : null,
            decoration: const InputDecoration(labelText: 'Service city'),
            items: cities.map((c) => DropdownMenuItem(value: c.id, child: Text(c.displayName))).toList(),
            onChanged: _busy ? null : (value) => setState(() => _cityId = value)),
      ),
      const SizedBox(height: 20),
      GxTextField(controller: _phone, label: 'Business contact number', keyboardType: TextInputType.phone, maxLength: 30),
      const SizedBox(height: 12),
      const Text('Confirmed customers use this number to coordinate the service and direct payment.'),
      const SizedBox(height: 24),
      GxButton(label: 'Save services & contact', onTap: _save, loading: _busy),
    ]),
  );
}
