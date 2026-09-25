import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/matching_repository.dart';
import '../../theme.dart';

class HiringLocationPick {
  final String id;
  final String name;
  final String districtName;
  final String stateName;
  final double? lat;
  final double? lng;
  final bool needsConfirmation;

  const HiringLocationPick({
    required this.id,
    required this.name,
    required this.districtName,
    required this.stateName,
    this.lat,
    this.lng,
    required this.needsConfirmation,
  });

  String get label {
    final place = [name, districtName, stateName].where((part) => part.isNotEmpty).join(', ');
    return place;
  }
}

class HiringPositionPick {
  final String id;
  final String label;
  final String subtitle;

  const HiringPositionPick({required this.id, required this.label, required this.subtitle});
}

/// Backend search. Suggestions are listed but only a tap confirms them.
class HiringLocationSearch extends ConsumerStatefulWidget {
  final String? selectedLabel;
  final ValueChanged<HiringLocationPick> onPick;
  const HiringLocationSearch({super.key, this.selectedLabel, required this.onPick});

  @override
  ConsumerState<HiringLocationSearch> createState() => _HiringLocationSearchState();
}

class _HiringLocationSearchState extends ConsumerState<HiringLocationSearch> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<HiringLocationPick> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  String _query = '';
  int _loadSeq = 0;
  bool _showNoMatches = false;

  @override
  void initState() {
    super.initState();
    if (widget.selectedLabel != null) _ctrl.text = widget.selectedLabel!;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  List<HiringLocationPick> _parse(List<Map<String, dynamic>> page) {
    return page.map((row) => HiringLocationPick(
          id: '${row['id']}',
          name: '${row['name'] ?? ''}',
          districtName: '${row['districtName'] ?? ''}',
          stateName: '${row['stateName'] ?? ''}',
          lat: (row['lat'] as num?)?.toDouble(),
          lng: (row['lng'] as num?)?.toDouble(),
          needsConfirmation: row['needsConfirmation'] == true,
        )).toList();
  }

  /// Drop in-flight HTTP responses and any scheduled debounced search.
  void _invalidatePendingLoads({String? query}) {
    _debounce?.cancel();
    _debounce = null;
    _loadSeq++;
    setState(() {
      if (query != null) _query = query;
      _items = [];
      _hasMore = false;
      _error = null;
      _loading = false;
      _loadingMore = false;
      _showNoMatches = false;
    });
  }

  void _search(String value) {
    final trimmed = value.trim();
    _invalidatePendingLoads(query: trimmed);
    if (trimmed.length < 2) return;
    setState(() => _loading = true);
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _load(trimmed, reset: true),
    );
  }

  Future<void> _load(String value, {required bool reset}) async {
    if (value.length < 2) {
      _invalidatePendingLoads(query: value);
      return;
    }
    final seq = ++_loadSeq;
    final requestQuery = value;
    final offset = reset ? 0 : _items.length;
    setState(() {
      if (reset) {
        _loading = true;
        _items = [];
      } else {
        _loadingMore = true;
      }
      _error = null;
      _query = value;
    });
    try {
      final page = await ref.read(matchingRepositoryProvider).searchHiringLocations(
            requestQuery,
            offset: offset,
          );
      if (!mounted || seq != _loadSeq) return;
      if (requestQuery != _query) return;
      final parsed = _parse(page);
      setState(() {
        _items = reset ? parsed : [..._items, ...parsed];
        _hasMore = parsed.length == 20;
        _loading = false;
        _loadingMore = false;
        if (reset) _showNoMatches = parsed.isEmpty;
      });
    } catch (_) {
      if (!mounted || seq != _loadSeq) return;
      if (requestQuery != _query) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = 'Unable to search locations';
        if (reset) _items = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _ctrl,
          decoration: const InputDecoration(
            hintText: 'Search city or town',
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
          onChanged: _search,
        ),
        if (_loading) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        if (!_loading && _showNoMatches && _error == null)
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('No locations match')),
        if (_hasMore)
          TextButton(
            onPressed: _loadingMore ? null : () => _load(_query, reset: false),
            child: Text(_loadingMore ? 'Loading…' : 'Load more'),
          ),
        for (final item in _items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.name),
            subtitle: Text([item.districtName, item.stateName].where((p) => p.isNotEmpty).join(', ')),
            trailing: item.needsConfirmation ? const Text('Confirm') : null,
            onTap: () {
              _invalidatePendingLoads(query: item.label);
              widget.onPick(item);
              setState(() => _ctrl.text = item.label);
            },
          ),
      ],
    );
  }
}

class HiringPositionSearch extends ConsumerStatefulWidget {
  final String? sectorId;
  final String? selectedLabel;
  final ValueChanged<HiringPositionPick> onPick;
  final int initialVisible;
  const HiringPositionSearch({
    super.key,
    this.sectorId,
    this.selectedLabel,
    required this.onPick,
    this.initialVisible = 8,
  });

  @override
  ConsumerState<HiringPositionSearch> createState() => _HiringPositionSearchState();
}

class _HiringPositionSearchState extends ConsumerState<HiringPositionSearch> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<HiringPositionPick> _items = [];
  List<HiringPositionPick> _sectorPool = [];
  bool _loading = false;
  bool _showAll = false;
  String? _error;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _loadSectorPositions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HiringPositionSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sectorId != widget.sectorId) {
      _items = [];
      _sectorPool = [];
      _showAll = false;
      _ctrl.clear();
      _loadSectorPositions();
    }
  }

  Future<void> _loadSectorPositions() async {
    if (widget.sectorId == null || widget.sectorId!.isEmpty) return;
    final gen = ++_loadGen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(matchingRepositoryProvider).searchHiringPositions(
            query: '',
            sectorId: widget.sectorId,
            limit: 200,
          );
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _sectorPool = page
            .map((row) => HiringPositionPick(
                  id: '${row['id']}',
                  label: '${row['label'] ?? ''}',
                  subtitle: '${row['subtitle'] ?? ''}',
                ))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load positions';
      });
    }
  }

  void _search(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final q = value.trim();
      if (q.isEmpty) {
        setState(() => _items = []);
        return;
      }
      final gen = ++_loadGen;
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final page = await ref.read(matchingRepositoryProvider).searchHiringPositions(
              query: q,
              sectorId: widget.sectorId,
            );
        if (!mounted || gen != _loadGen) return;
        setState(() {
          _items = page
              .map((row) => HiringPositionPick(
                    id: '${row['id']}',
                    label: '${row['label'] ?? ''}',
                    subtitle: '${row['subtitle'] ?? ''}',
                  ))
              .toList();
          _loading = false;
        });
      } catch (_) {
        if (!mounted || gen != _loadGen) return;
        setState(() {
          _loading = false;
          _error = 'Unable to search positions';
        });
      }
    });
  }

  List<HiringPositionPick> get _visible {
    if (_ctrl.text.trim().isNotEmpty) return _items;
    final pool = _sectorPool;
    if (_showAll || pool.length <= widget.initialVisible) return pool;
    return pool.take(widget.initialVisible).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _ctrl,
          decoration: InputDecoration(
            hintText: 'Search position',
            prefixIcon: const Icon(Icons.search),
            suffixText: widget.selectedLabel,
          ),
          onChanged: _search,
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        for (final item in _visible)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.label, style: const TextStyle(color: GixbeeTheme.accentBlue, fontWeight: FontWeight.w700)),
            subtitle: Text(item.subtitle),
            onTap: () {
              widget.onPick(item);
              setState(() {
                _items = [];
                _ctrl.clear();
              });
            },
          ),
        if (_ctrl.text.trim().isEmpty &&
            !_showAll &&
            _sectorPool.length > widget.initialVisible)
          TextButton(
            onPressed: () => setState(() => _showAll = true),
            child: const Text('Show more positions'),
          ),
      ],
    );
  }
}
