import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';

import '../../repositories/matching_repository.dart';
import '../../services/location_service.dart';
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
  final String? selectedId;
  final ValueChanged<HiringLocationPick> onPick;
  final VoidCallback? onSelectionCleared;
  final bool enableGps;
  final bool embedded;

  const HiringLocationSearch({
    super.key,
    this.selectedLabel,
    this.selectedId,
    required this.onPick,
    this.onSelectionCleared,
    this.enableGps = false,
    this.embedded = false,
  });

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
  bool _gpsLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.selectedLabel != null) _ctrl.text = widget.selectedLabel!;
  }

  @override
  void didUpdateWidget(covariant HiringLocationSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedLabel != oldWidget.selectedLabel) {
      final next = widget.selectedLabel ?? '';
      if (_ctrl.text.trim() != next.trim()) {
        _ctrl.text = next;
      }
    }
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
    if (widget.selectedId != null) {
      final confirmed = (widget.selectedLabel ?? '').trim();
      if (trimmed != confirmed) {
        widget.onSelectionCleared?.call();
      }
    }
    _invalidatePendingLoads(query: trimmed);
    if (trimmed.length < 2) return;
    setState(() => _loading = true);
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _load(trimmed, reset: true),
    );
  }

  Future<void> _useGps() async {
    if (_gpsLoading) return;
    setState(() => _gpsLoading = true);
    try {
      final loc = ref.read(locationServiceProvider);
      final block = await loc.gpsBlockReason();
      if (block == 'service_off') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Turn on location services, then try again')),
          );
        }
        return;
      }
      if (block == 'denied_forever') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Allow location in app settings to use current location'),
              action: SnackBarAction(label: 'Settings', onPressed: loc.openAppSettings),
            ),
          );
        }
        return;
      }
      final pos = await loc.getCurrentPosition(fallbackToLastKnown: true);
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read GPS — search manually')),
          );
        }
        return;
      }
      var query = '';
      if (!kIsWeb) {
        try {
          final marks = await Geocoding()
              .placemarkFromCoordinates(pos.latitude, pos.longitude)
              .timeout(const Duration(seconds: 6));
          if (marks.isNotEmpty) {
            final p = marks.first;
            query = [
              p.locality,
              p.subAdministrativeArea,
              p.administrativeArea,
            ].where((s) => s != null && s.trim().isNotEmpty).map((s) => s!.trim()).join(' ');
          }
        } catch (_) {}
      }
      if (query.length < 2) {
        query = await loc.getAddressFromLatLng(pos);
      }
      query = query.trim();
      if (query.length < 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not resolve a place name — search manually')),
          );
        }
        return;
      }
      if (!mounted) return;
      _ctrl.text = query;
      widget.onSelectionCleared?.call();
      await _load(query, reset: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Confirm your job location from the list')),
        );
      }
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _confirmPick(HiringLocationPick item) async {
    if (item.needsConfirmation) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm location'),
          content: Text(
            'Use “${item.label}” as the job location?\n\n'
            'This is a suggested match — confirm only if it is correct.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
          ],
        ),
      );
      if (ok != true) return;
    }
    _invalidatePendingLoads(query: item.label);
    widget.onPick(item);
    if (mounted) setState(() => _ctrl.text = item.label);
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
    final field = TextField(
      controller: _ctrl,
      decoration: InputDecoration(
        hintText: 'Search city or town',
        prefixIcon: const Icon(Icons.location_on_outlined),
        suffixIcon: widget.enableGps
            ? _gpsLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Use current location',
                    icon: const Icon(Icons.my_location),
                    onPressed: _useGps,
                  )
            : null,
        border: widget.embedded ? OutlineInputBorder(borderRadius: BorderRadius.circular(12)) : null,
        filled: widget.embedded,
      ),
      onChanged: _search,
    );

    final suggestions = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            subtitle: Text(
              [item.districtName, item.stateName].where((p) => p.isNotEmpty).join(', '),
            ),
            trailing: item.needsConfirmation
                ? Text(
                    'Confirm',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.gx.accent,
                    ),
                  )
                : null,
            onTap: () => _confirmPick(item),
          ),
      ],
    );

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [field, suggestions],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [field, suggestions],
    );
  }
}

class HiringPositionSearch extends ConsumerStatefulWidget {
  final String? sectorId;
  final String? selectedId;
  final String? selectedLabel;
  final ValueChanged<HiringPositionPick> onPick;
  final int initialVisible;
  const HiringPositionSearch({
    super.key,
    this.sectorId,
    this.selectedId,
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

  void _select(HiringPositionPick item) {
    widget.onPick(item);
    setState(() {
      _items = [];
      _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = widget.selectedId;
    final visible = _visible;
    final selectedInList =
        selectedId != null && visible.any((p) => p.id == selectedId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedId != null &&
            widget.selectedLabel != null &&
            !selectedInList) ...[
          _PositionTile(
            item: HiringPositionPick(
              id: selectedId,
              label: widget.selectedLabel!,
              subtitle: 'Your selected position',
            ),
            selected: true,
            onTap: () {},
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _ctrl,
          decoration: const InputDecoration(
            hintText: 'Search position',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: _search,
        ),
        if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 8),
        for (final item in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PositionTile(
              item: item,
              selected: selectedId == item.id,
              onTap: () => _select(item),
            ),
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

class _PositionTile extends StatelessWidget {
  const _PositionTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final HiringPositionPick item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const selectedFill = Color(0xFFF0FDF4);
    final gx = context.gx;
    final border = selected ? GixbeeTheme.accentGreen : gx.border;
    final titleColor = selected ? GixbeeTheme.accentGreenDark : gx.ink;

    return Material(
      color: selected ? selectedFill : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: selected ? 2 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: titleColor,
                      ),
                    ),
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: gx.ink.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    color: GixbeeTheme.accentGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 16, color: Colors.white),
                )
              else
                Icon(
                  Icons.radio_button_unchecked,
                  size: 22,
                  color: gx.ink.withValues(alpha: 0.25),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
