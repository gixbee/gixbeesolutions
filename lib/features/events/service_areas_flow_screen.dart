import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/cities_repository.dart';
import '../../repositories/events_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_network_error.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

/// State label used to group serviceable cities. Empty states become Other.
String serviceAreaState(CityEntry city) {
  final state = city.state.trim();
  return state.isEmpty ? 'Other' : state;
}

/// Cities grouped by state, both levels sorted for the owner picker.
Map<String, List<CityEntry>> serviceAreasByState(List<CityEntry> cities) {
  final grouped = <String, List<CityEntry>>{};
  for (final city in cities) {
    grouped.putIfAbsent(serviceAreaState(city), () => []).add(city);
  }
  for (final list in grouped.values) {
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
  final keys = grouped.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return {for (final key in keys) key: grouped[key]!};
}

/// States that already contain one of the saved service-area city ids.
Set<String> statesForSelectedCities(List<CityEntry> cities, Set<String> ids) {
  return {
    for (final city in cities)
      if (ids.contains(city.id)) serviceAreaState(city),
  };
}

/// Three-step service areas: states, cities in those states, then review.
/// Saved as catalogue `serviceCityIds` (the bookable city master). The HTML
/// prototypes call the second step districts; this app's master is cities
/// grouped by state.
class ServiceAreasFlowScreen extends ConsumerStatefulWidget {
  const ServiceAreasFlowScreen({
    super.key,
    required this.business,
    required this.service,
    this.persist = true,
    this.initialCityIds = const {},
  });

  final Business business;
  final String service;

  /// When false, the selection is returned to the caller instead of writing
  /// the catalogue. Used while the catalogue form still has unsaved edits.
  final bool persist;
  final Set<String> initialCityIds;

  @override
  ConsumerState<ServiceAreasFlowScreen> createState() =>
      _ServiceAreasFlowScreenState();
}

class _ServiceAreasFlowScreenState extends ConsumerState<ServiceAreasFlowScreen> {
  static const _maxAreas = 30;
  int _step = 0;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _revision = 0;
  Map<String, dynamic> _catalogue = const {};
  final _selected = <String>{};
  final _states = <String>{};
  String _query = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialCityIds);
    _open();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.persist) {
        final result = await ref
            .read(eventsRepositoryProvider)
            .catalogue(widget.business.id, widget.service);
        if (!mounted) return;
        final catalogue =
            Map<String, dynamic>.from(result['catalogue'] as Map? ?? {});
        _revision = (result['revision'] as num?)?.toInt() ?? 0;
        _catalogue = catalogue;
        _selected
          ..clear()
          ..addAll((catalogue['serviceCityIds'] as List? ?? [])
              .map((id) => id.toString())
              .where((id) => id.isNotEmpty));
      }
      final cities = await ref.read(citiesProvider.future);
      if (!mounted) return;
      setState(() {
        _states
          ..clear()
          ..addAll(statesForSelectedCities(cities, _selected));
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = eventError(error);
          _loading = false;
        });
      }
    }
  }

  void _toggleState(String state, List<CityEntry> cities, bool on) {
    setState(() {
      if (on) {
        _states.add(state);
        return;
      }
      _states.remove(state);
      _selected.removeAll(cities
          .where((city) => serviceAreaState(city) == state)
          .map((city) => city.id));
    });
  }

  void _toggleCity(String id, bool on) {
    if (on && !_selected.contains(id) && _selected.length >= _maxAreas) {
      showGxSnack(context, 'You can list up to $_maxAreas service areas.');
      return;
    }
    setState(() {
      if (on) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    final ids = _selected.take(_maxAreas).toList();
    if (!widget.persist) {
      Navigator.pop(context, ids.toSet());
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(eventsRepositoryProvider).saveCatalogue(
        widget.business.id,
        widget.service,
        _revision,
        {
          ..._catalogue,
          'items': _catalogue['items'] ?? const [],
          'photos': _catalogue['photos'] ?? const [],
          'serviceCityIds': ids,
        },
      );
      if (!mounted) return;
      showGxSnack(context, 'Service areas saved');
      Navigator.pop(context, ids.toSet());
    } catch (error) {
      if (mounted) showGxSnack(context, eventError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cities = ref.watch(citiesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Areas'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: _busy
              ? null
              : () {
                  if (_step == 0) {
                    Navigator.pop(context);
                  } else {
                    setState(() => _step -= 1);
                  }
                },
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? GxNetworkError(
                  error: _error,
                  title: 'Service areas unavailable',
                  onRetry: _open,
                )
              : cities.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => GxNetworkError(
                    error: error,
                    title: 'Service areas unavailable',
                    onRetry: () => ref.invalidate(citiesProvider),
                  ),
                  data: (rows) => _body(rows),
                ),
    );
  }

  Widget _body(List<CityEntry> cities) {
    final grouped = serviceAreasByState(cities);
    final titles = const ['Select states', 'Select cities', 'Review'];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text('Step ${_step + 1} of 3 · ${titles[_step]}',
            style: TextStyle(
              color: context.gx.ink.withValues(alpha: 0.65),
              fontWeight: FontWeight.w700,
            )),
      ),
      Expanded(
        child: switch (_step) {
          0 => _statesStep(grouped),
          1 => _citiesStep(grouped),
          _ => _reviewStep(grouped),
        },
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: GxButton(
          label: _step == 2
              ? (widget.persist ? 'Save Service Areas' : 'Use these areas')
              : 'Continue',
          loading: _busy,
          onTap: _busy
              ? null
              : () {
                  if (_step == 0 && _states.isEmpty) {
                    showGxSnack(context, 'Select at least one state.');
                    return;
                  }
                  if (_step < 2) {
                    setState(() => _step += 1);
                  } else {
                    _save();
                  }
                },
        ),
      ),
    ]);
  }

  Widget _statesStep(Map<String, List<CityEntry>> grouped) {
    if (grouped.isEmpty) {
      return const Center(child: Text('No serviceable cities are available yet.'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Text('Select states where you accept bookings.',
              style: TextStyle(color: context.gx.ink.withValues(alpha: 0.7))),
        ),
        for (final entry in grouped.entries)
          CheckboxListTile(
            value: _states.contains(entry.key),
            title: Text(entry.key,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
                '${entry.value.length} ${entry.value.length == 1 ? 'city' : 'cities'}'),
            onChanged: (on) => _toggleState(entry.key, entry.value, on ?? false),
          ),
      ],
    );
  }

  Widget _citiesStep(Map<String, List<CityEntry>> grouped) {
    final query = _query.trim().toLowerCase();
    final states = _states.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text('Select the cities where you accept bookings.',
            style: TextStyle(color: context.gx.ink.withValues(alpha: 0.7))),
        const SizedBox(height: 10),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            hintText: 'Search cities',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 12),
        for (final state in states) ...[
          Text(state,
              style: TextStyle(
                  color: context.gx.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 16)),
          const SizedBox(height: 6),
          for (final city in grouped[state] ?? const <CityEntry>[])
            if (query.isEmpty ||
                city.name.toLowerCase().contains(query) ||
                city.displayName.toLowerCase().contains(query))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _selected.contains(city.id),
                title: Text(city.name),
                onChanged: (on) => _toggleCity(city.id, on ?? false),
              ),
        ],
      ],
    );
  }

  Widget _reviewStep(Map<String, List<CityEntry>> grouped) {
    final states = _states.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final shown = <String>{};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Review your service areas',
            style: TextStyle(
                color: context.gx.ink,
                fontWeight: FontWeight.w900,
                fontSize: 18)),
        const SizedBox(height: 8),
        Text(
          'You can add or remove states and cities later from your dashboard.',
          style: TextStyle(color: context.gx.ink.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 16),
        if (_selected.isEmpty)
          const Text('No cities selected. Saving clears your service areas.'),
        for (final state in states) ...[
          if ((grouped[state] ?? const <CityEntry>[])
              .any((city) => _selected.contains(city.id))) ...[
            Text(state,
                style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final city in grouped[state] ?? const <CityEntry>[])
                if (_selected.contains(city.id)) ...[
                  if (shown.add(city.id))
                    Chip(
                      label: Text(city.name),
                      onDeleted: () => _toggleCity(city.id, false),
                    ),
                ],
            ]),
            const SizedBox(height: 14),
          ],
        ],
      ],
    );
  }
}
