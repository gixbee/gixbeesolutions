import 'dart:collection';

/// In-memory app-side cache for master data and location search pages.
/// Does not replace on-device secure storage for tokens or private profiles.
class AppDataCache {
  AppDataCache._();
  static final AppDataCache instance = AppDataCache._();

  static const Duration locationPageTtl = Duration(hours: 24);
  static const Duration hiringSnapshotTtl = Duration(hours: 24);

  int? _hiringMasterVersion;
  int? _locationMasterVersion;

  Map<String, dynamic>? _hiringSnapshotActive;
  DateTime? _hiringSnapshotAt;

  final _locationPages = LinkedHashMap<String, _LocationPageEntry>();
  static const int _maxLocationPages = 32;

  void setServerVersions({
    int? hiringMaster,
    int? locationMaster,
  }) {
    if (hiringMaster != null && hiringMaster != _hiringMasterVersion) {
      _hiringMasterVersion = hiringMaster;
      _hiringSnapshotActive = null;
      _hiringSnapshotAt = null;
    }
    if (locationMaster != null && locationMaster != _locationMasterVersion) {
      _locationMasterVersion = locationMaster;
      _locationPages.clear();
    }
  }

  int? get hiringMasterVersion => _hiringMasterVersion;
  int? get locationMasterVersion => _locationMasterVersion;

  Map<String, dynamic>? get hiringSnapshotActive => _hiringSnapshotActive;

  bool hiringSnapshotFresh(int cacheVersion) {
    if (_hiringSnapshotActive == null || _hiringSnapshotAt == null) return false;
    if (_hiringMasterVersion != cacheVersion) return false;
    return DateTime.now().difference(_hiringSnapshotAt!) < hiringSnapshotTtl;
  }

  void putHiringSnapshot(Map<String, dynamic> body, int cacheVersion) {
    _hiringMasterVersion = cacheVersion;
    _hiringSnapshotActive = body;
    _hiringSnapshotAt = DateTime.now();
  }

  List<Map<String, dynamic>>? locationPage(String key) {
    final entry = _locationPages[key];
    if (entry == null) return null;
    if (_locationMasterVersion != null &&
        entry.locationMasterVersion != _locationMasterVersion) {
      _locationPages.remove(key);
      return null;
    }
    if (DateTime.now().difference(entry.fetchedAt) > locationPageTtl) {
      _locationPages.remove(key);
      return null;
    }
    return entry.items;
  }

  void putLocationPage(String key, List<Map<String, dynamic>> items) {
    _locationPages.remove(key);
    _locationPages[key] = _LocationPageEntry(
      items: items,
      locationMasterVersion: _locationMasterVersion ?? 0,
      fetchedAt: DateTime.now(),
    );
    while (_locationPages.length > _maxLocationPages) {
      _locationPages.remove(_locationPages.keys.first);
    }
  }

  void clearUserScoped() {
    // Reserved for per-user preference caches keyed by user id.
  }

  void clearHiringSnapshot() {
    _hiringSnapshotActive = null;
    _hiringSnapshotAt = null;
  }

  void clearAll() {
    clearHiringSnapshot();
    _locationPages.clear();
    _hiringMasterVersion = null;
    _locationMasterVersion = null;
  }
}

class _LocationPageEntry {
  final List<Map<String, dynamic>> items;
  final int locationMasterVersion;
  final DateTime fetchedAt;

  _LocationPageEntry({
    required this.items,
    required this.locationMasterVersion,
    required this.fetchedAt,
  });
}
