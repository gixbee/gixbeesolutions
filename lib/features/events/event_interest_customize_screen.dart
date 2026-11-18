import 'package:flutter/material.dart';

import '../../repositories/events_repository.dart';
import '../../theme.dart';
import 'event_plan_create_screen.dart';

/// Customer-side customization before sending an interest. Choices are stored
/// as enquiry notes, not as additional payable catalogue items: only a vendor
/// quote can change the agreed booking amount.
class EventInterestCustomizeScreen extends StatefulWidget {
  const EventInterestCustomizeScreen({
    super.key,
    required this.service,
    required this.selection,
    required this.eventType,
    required this.eventDate,
    required this.guests,
  });

  final String service;
  final EventServiceSelection selection;
  final String eventType;
  final DateTime eventDate;
  final int guests;

  @override
  State<EventInterestCustomizeScreen> createState() =>
      _EventInterestCustomizeScreenState();
}

class _EventInterestCustomizeScreenState
    extends State<EventInterestCustomizeScreen> {
  static const _accent = Color(0xFF12B76A);
  final _notes = TextEditingController();
  final _dietNeeds = TextEditingController();
  final _menuChanges = TextEditingController();
  final _coverage = TextEditingController();
  final _team = TextEditingController();
  final _deliverables = TextEditingController();
  final _extras = TextEditingController();
  final _decorTheme = TextEditingController();
  final _decorColors = TextEditingController();
  final _decorSetup = TextEditingController();
  final _decorExtras = TextEditingController();
  final _selectedFunctions = <String>{};
  String _serviceStyle = 'As offered';
  bool _requiresQuote = true;

  bool get _photography => widget.service == 'PHOTOGRAPHY';
  bool get _decoration => widget.service == 'DECORATION';

  @override
  void initState() {
    super.initState();
    // Existing package requirements are preserved separately; this field is for new notes.
    _notes.text = '';
  }

  @override
  void dispose() {
    _notes.dispose();
    _dietNeeds.dispose();
    _menuChanges.dispose();
    _coverage.dispose();
    _team.dispose();
    _deliverables.dispose();
    _extras.dispose();
    _decorTheme.dispose();
    _decorColors.dispose();
    _decorSetup.dispose();
    _decorExtras.dispose();
    super.dispose();
  }

  Widget _section(String title, {String? subtitle}) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(color: context.gx.ink, fontSize: 16, fontWeight: FontWeight.w800)),
          if (subtitle != null)
            Text(subtitle,
                style: TextStyle(fontSize: 12, color: context.gx.ink.withValues(alpha: 0.60))),
        ]),
      );

  Widget _field(TextEditingController controller, String label,
          {String? hint, int lines = 2}) =>
      TextField(
        controller: controller,
        maxLength: 900,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          alignLabelWithHint: lines > 1,
          border: const OutlineInputBorder(),
        ),
      );

  String _requirements() {
    final lines = <String>[
      widget.selection.requirements?.trim() ?? '',
      if (_photography) ...[
        if (_selectedFunctions.isNotEmpty)
          'Requested functions: ${_selectedFunctions.join(', ')}',
        if (_coverage.text.trim().isNotEmpty)
          'Coverage requests: ${_coverage.text.trim()}',
        if (_team.text.trim().isNotEmpty)
          'Team preferences: ${_team.text.trim()}',
        if (_deliverables.text.trim().isNotEmpty)
          'Delivery & albums: ${_deliverables.text.trim()}',
        if (_extras.text.trim().isNotEmpty)
          'Optional extras (price to be confirmed): ${_extras.text.trim()}',
      ] else if (_decoration) ...[
        if (_decorTheme.text.trim().isNotEmpty)
          'Decoration theme: ${_decorTheme.text.trim()}',
        if (_decorColors.text.trim().isNotEmpty)
          'Preferred colors: ${_decorColors.text.trim()}',
        if (_decorSetup.text.trim().isNotEmpty)
          'Setup requirements: ${_decorSetup.text.trim()}',
        if (_decorExtras.text.trim().isNotEmpty)
          'Optional extras (quote required): ${_decorExtras.text.trim()}',
      ] else ...[
        'Preferred serving style: $_serviceStyle',
        if (_dietNeeds.text.trim().isNotEmpty)
          'Dietary needs: ${_dietNeeds.text.trim()}',
        if (_menuChanges.text.trim().isNotEmpty)
          'Requested menu changes (price to be confirmed): ${_menuChanges.text.trim()}',
      ],
      if (_notes.text.trim().isNotEmpty)
        'Additional notes: ${_notes.text.trim()}',
    ];
    return lines.where((s) => s.isNotEmpty).join('\n');
  }

  void _continue() {
    final details = _requirements();
    if (details.length > 5000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Reduce your requirements to 5,000 characters.')),
      );
      return;
    }
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => EventPlanCreateScreen(
        eventType: widget.eventType,
        date: widget.eventDate,
        guests: widget.guests,
        services: [widget.service],
        selection: EventServiceSelection(
          businessId: widget.selection.businessId,
          cityId: widget.selection.cityId,
          summary: widget.selection.summary,
          request: {
            ...widget.selection.request,
            'customization': _photography
                ? {
                    'functions': _selectedFunctions.toList(),
                    'coverage': _coverage.text.trim(),
                    'team': _team.text.trim(),
                    'deliverables': _deliverables.text.trim(),
                    'extras': _extras.text.trim(),
                  }
                
                 : _decoration
                 ? {
                     'theme': _decorTheme.text.trim(),
                     'colors': _decorColors.text.trim(),
                     'setup': _decorSetup.text.trim(),
                     'extras': _decorExtras.text.trim(),
                   }
                 : {
                    'servingStyle': _serviceStyle,
                    'dietaryNeeds': _dietNeeds.text.trim(),
                    'menuChanges': _menuChanges.text.trim(),
                  },
          },
          address: widget.selection.address,
          start: widget.selection.start,
          end: widget.selection.end,
          requirements: details,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gx.bg,
      appBar: AppBar(
        title:
            Text(_photography ? 'Customize Photography' : _decoration ? 'Customize Decoration' : 'Customize Catering'),
        backgroundColor: context.gx.card,
        foregroundColor: context.gx.ink,
      ),
      body: SafeArea(
          child: Column(children: [
        Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            color: context.gx.card2,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your selected offer',
                         style: TextStyle(color: context.gx.ink, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 5),
                    Text(widget.selection.summary),
                  ]),
            ),
          ),
          _section('Customize requirements',
              subtitle:
                  'The displayed price is an estimate. Changes will be confirmed by the vendor in a quote.'),
          if (_photography) ...[
            const Text('Functions you want covered',
                style: TextStyle(fontWeight: FontWeight.w700)),
            Wrap(spacing: 7, children: [
              for (final function in const [
                'Wedding',
                'Reception',
                'Engagement',
                'Wedding Eve',
                'Pre-wedding Shoot',
                'Post-wedding Shoot',
                'Other event',
              ])
                FilterChip(
                  label: Text(function),
                  selected: _selectedFunctions.contains(function),
                  onSelected: (value) => setState(() {
                    if (value) {
                      _selectedFunctions.add(function);
                    } else {
                      _selectedFunctions.remove(function);
                    }
                  }),
                ),
            ]),
            const SizedBox(height: 12),
            _field(_coverage, 'Coverage and time',
                hint: 'Hours, venue coverage, side of family, schedule'),
            _field(_team, 'Crew preferences',
                hint: 'Photographers, videographers, drones, live stream'),
            _field(_deliverables, 'Albums, gallery and delivery',
                hint: 'Edited photos, videos, prints, albums, dates'),
            _field(_extras, 'Optional extras',
                hint: 'Extra crew, drone, photobooth (vendor quote required)'),
          ] else if (_decoration) ...[
             _field(_decorTheme, 'Decoration theme',
               hint: 'Traditional, floral, minimalist, cinematic'),
             _field(_decorColors, 'Preferred colors',
               hint: 'White and gold, pastel pink, earthy tones'),
             _field(_decorSetup, 'Stage, venue and setup details',
               hint: 'Backdrop size, indoor/outdoor, installation time'),
             _field(_decorExtras, 'Optional additions',
               hint: 'Flower arch, lights, aisle, photo booth; quote required'),
           ] else ...[
            DropdownButtonFormField<String>(
              initialValue: _serviceStyle,
              decoration: const InputDecoration(
                labelText: 'Preferred serving style',
                border: OutlineInputBorder(),
              ),
              items: const [
                'As offered',
                'Buffet Service',
                'Traditional Table Service',
                'Both',
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (s) =>
                  setState(() => _serviceStyle = s ?? _serviceStyle),
            ),
            const SizedBox(height: 12),
            _field(_dietNeeds, 'Dietary preferences',
                hint: 'Vegetarian, non-vegetarian, Jain, allergies, etc.'),
            _field(_menuChanges, 'Menu customization',
                hint: 'Dishes to add/remove, portions, special requests'),
          ],
          _section('Additional instructions'),
          _field(_notes, 'Notes for the vendor', lines: 3),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _requiresQuote,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
                'I understand this is an enquiry, not a confirmed booking'),
            subtitle: const Text(
                'The vendor will confirm availability and the final price. Payment is made directly to the vendor.'),
            onChanged: (v) => setState(() => _requiresQuote = v ?? false),
          ),
        ])),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _requiresQuote ? _continue : null,
              icon: const Icon(Icons.arrow_forward),
              label: Text(
                  'Continue to ${eventServices[widget.service] ?? 'Event'} Review'),
            ),
          ),
        ),
      ])),
    );
  }
}
