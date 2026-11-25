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

/// One state or district from the India location master.
class ServiceGeo {
  const ServiceGeo({
    required this.id,
    required this.name,
    required this.stateName,
  });
  final String id;
  final String name;
  final String stateName;
}

/// Whole states are stored as one state id. A partial state stores only the
/// chosen district ids, so an owner can cover every city without a cap.
List<String> compactServiceAreaIds({
  required List<ServiceGeo> states,
  required List<ServiceGeo> districts,
  required Set<String> stateNames,
  required Set<String> districtIds,
}) {
  final saved = <String>[];
  final ordered = [...states]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  for (final state in ordered) {
    if (!stateNames.contains(state.name)) continue;
    final inState =
        districts.where((district) => district.stateName == state.name).toList();
    if (inState.isEmpty ||
        inState.every((district) => districtIds.contains(district.id))) {
      saved.add(state.id);
    } else {
      saved.addAll(inState
          .where((district) => districtIds.contains(district.id))
          .map((district) => district.id));
    }
  }
  return saved;
}

/// Three-step service areas over every active state and district.
/// A whole state is saved as that state, so the owner can serve all of India.
class ServiceAreasFlowScreen extends ConsumerStatefulWidget {
  const ServiceAreasFlowScreen({
    super.key,
    required this.business,
    required this.service,
    this.persist = true,
    this.initialAreaIds = const {},
  });

  final Business business;
  final String service;

  /// When false, the selection is returned to the caller instead of writing
  /// the catalogue. Used while the catalogue form still has unsaved edits.
  final bool persist;
  final Set<String> initialAreaIds;

  @override
  ConsumerState<ServiceAreasFlowScreen> createState() =>
      _ServiceAreasFlowScreenState();
}

class _ServiceAreasFlowScreenState extends ConsumerState<ServiceAreasFlowScreen> {
  int _step = 0;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _revision = 0;
  Map<String, dynamic> _catalogue = const {};
  List<ServiceGeo> _stateRows = const [];
  List<ServiceGeo> _districts = const [];
  final _selected = <String>{};
  final _states = <String>{};
  String _query = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialAreaIds);
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
          ..addAll((catalogue['serviceAreaIds'] as List? ?? [])
              .map((id) => id.toString())
              .where((id) => id.isNotEmpty));
      } else {
        _selected
          ..clear()
          ..addAll(widget.initialAreaIds);
      }
      final geography =
          await ref.read(eventsRepositoryProvider).serviceGeography();
      if (!mounted) return;
      final states = _places(geography['states']);
      final districts = _places(geography['districts']);
      _applySaved(states, districts);
      setState(() {
        _stateRows = states;
        _districts = districts;
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

  List<ServiceGeo> _places(Object? raw) {
    final rows = raw is List ? raw : const [];
    return [
      for (final row in rows)
        if (row is Map)
          ServiceGeo(
            id: '${row['id'] ?? ''}',
            name: '${row['name'] ?? ''}'.trim(),
            stateName: '${row['stateName'] ?? row['name'] ?? ''}'.trim(),
          ),
    ].where((place) => place.id.isNotEmpty && place.name.isNotEmpty).toList();
  }

  void _applySaved(List<ServiceGeo> states, List<ServiceGeo> districts) {
    final saved = {..._selected};
    final stateById = {for (final state in states) state.id: state};
    final districtById = {for (final district in districts) district.id: district};
    _states.clear();
    _selected.clear();
    for (final id in saved) {
      final state = stateById[id];
      if (state != null) {
        _states.add(state.name);
        _selected.addAll(districts
            .where((district) => district.stateName == state.name)
            .map((district) => district.id));
        continue;
      }
      final district = districtById[id];
      if (district != null) {
        _states.add(district.stateName);
        _selected.add(district.id);
      }
    }
  }

  List<ServiceGeo> _districtsIn(String state) => _districts
      .where((district) => district.stateName == state)
      .toList();

  bool get _everywhere =>
      _stateRows.isNotEmpty &&
      _stateRows.every((state) => _states.contains(state.name)) &&
      _districts.every((district) => _selected.contains(district.id));

  void _toggleEverywhere(bool on) {
    setState(() {
      if (!on) {
        _states.clear();
        _selected.clear();
        return;
      }
      _states.addAll(_stateRows.map((state) => state.name));
      _selected.addAll(_districts.map((district) => district.id));
    });
  }

  void _toggleState(String state, bool on) {
    setState(() {
      if (on) {
        _states.add(state);
        return;
      }
      _states.remove(state);
      _selected.removeAll(_districtsIn(state).map((district) => district.id));
    });
  }

  void _toggleAllInState(String state, bool on) {
    setState(() {
      final ids = _districtsIn(state).map((district) => district.id);
      if (on) {
        _states.add(state);
        _selected.addAll(ids);
      } else {
        _selected.removeAll(ids);
      }
    });
  }

  void _toggleCity(String id, bool on) {
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
    final ids = compactServiceAreaIds(
      states: _stateRows,
      districts: _districts,
      stateNames: _states,
      districtIds: _selected,
    );
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
          'serviceAreaIds': ids,
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
              : _body(),
    );
  }

  Widget _body() {
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
          0 => _statesStep(),
          1 => _citiesStep(),
          _ => _reviewStep(),
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

  Widget _statesStep() {
    if (_stateRows.isEmpty) {
      return const Center(child: Text('No states are available yet.'));
    }
    final rows = [..._stateRows]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Text(
              'Choose the states you serve. This is your business, so you can cover every state.',
              style: TextStyle(color: context.gx.ink.withValues(alpha: 0.7))),
        ),
        CheckboxListTile(
          value: _everywhere,
          title: const Text('All states and cities',
              style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${_stateRows.length} states · ${_districts.length} cities'),
          onChanged: (on) => _toggleEverywhere(on ?? false),
        ),
        for (final state in rows)
          CheckboxListTile(
            value: _states.contains(state.name),
            title: Text(state.name,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(() {
              final count = _districtsIn(state.name).length;
              return count == 0
                  ? 'Whole state'
                  : '$count ${count == 1 ? 'city' : 'cities'}';
            }()),
            onChanged: (on) => _toggleState(state.name, on ?? false),
          ),
      ],
    );
  }

  Widget _citiesStep() {
    final query = _query.trim().toLowerCase();
    final states = _states.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text('Select the cities where you accept bookings, or take the whole state.',
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
          if (_districtsIn(state).isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Selecting this state covers the whole state.'),
            )
          else ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _districtsIn(state)
                  .every((district) => _selected.contains(district.id)),
              title: Text('All cities in $state'),
              onChanged: (on) => _toggleAllInState(state, on ?? false),
            ),
            for (final city in ([..._districtsIn(state)]
              ..sort((a, b) =>
                  a.name.toLowerCase().compareTo(b.name.toLowerCase()))))
              if (query.isEmpty || city.name.toLowerCase().contains(query))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _selected.contains(city.id),
                  title: Text(city.name),
                  onChanged: (on) => _toggleCity(city.id, on ?? false),
                ),
          ],
        ],
      ],
    );
  }

  Widget _reviewStep() {
    final states = _states.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final any = states.any((state) =>
        _districtsIn(state).isEmpty ||
        _districtsIn(state).any((city) => _selected.contains(city.id)));
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
          'You can change this later. A whole state means you serve every city there.',
          style: TextStyle(color: context.gx.ink.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 16),
        if (!any)
          const Text('No cities selected. Saving clears your service areas.'),
        for (final state in states) ...[
          if (_districtsIn(state).isEmpty ||
              _districtsIn(state).any((city) => _selected.contains(city.id))) ...[
            Text(state, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            if (_districtsIn(state).isEmpty ||
                _districtsIn(state)
                    .every((city) => _selected.contains(city.id)))
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Text('All cities'),
              )
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final city in _districtsIn(state))
                  if (_selected.contains(city.id))
                    Chip(
                      label: Text(city.name),
                      onDeleted: () => _toggleCity(city.id, false),
                    ),
              ]),
            const SizedBox(height: 14),
          ],
        ],
      ],
    );
  }
}
