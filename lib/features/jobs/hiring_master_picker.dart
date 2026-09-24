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

  void _search(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(value.trim(), reset: true));
  }

  Future<void> _load(String value, {required bool reset}) async {
    if (value.length < 2) {
      setState(() {
        _items = [];
        _hasMore = false;
        _error = null;
        _query = value;
      });
      return;
    }
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
            value,
            offset: reset ? 0 : _items.length,
          );
      if (!mounted) return;
      final parsed = _parse(page);
      setState(() {
        _items = reset ? parsed : [..._items, ...parsed];
        _hasMore = parsed.length == 20;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
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
        if (!_loading && _ctrl.text.trim().length >= 2 && _items.isEmpty && _error == null)
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
              widget.onPick(item);
              setState(() {
                _ctrl.text = item.label;
                _items = [];
              });
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
  const HiringPositionSearch({super.key, this.sectorId, this.selectedLabel, required this.onPick});

  @override
  ConsumerState<HiringPositionSearch> createState() => _HiringPositionSearchState();
}

class _HiringPositionSearchState extends ConsumerState<HiringPositionSearch> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<HiringPositionPick> _items = [];
  bool _loading = false;
  String? _error;

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
      _ctrl.clear();
    }
  }

  void _search(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final page = await ref.read(matchingRepositoryProvider).searchHiringPositions(
              query: value.trim(),
              sectorId: widget.sectorId,
            );
        if (!mounted) return;
        setState(() {
          _items = page.map((row) => HiringPositionPick(
                id: '${row['id']}',
                label: '${row['label'] ?? ''}',
                subtitle: '${row['subtitle'] ?? ''}',
              )).toList();
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Unable to search positions';
        });
      }
    });
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
        for (final item in _items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.label, style: const TextStyle(color: GixbeeTheme.accentBlue, fontWeight: FontWeight.w700)),
            subtitle: Text(item.subtitle),
            onTap: () {
              widget.onPick(item);
              setState(() => _items = []);
            },
          ),
      ],
    );
  }
}
