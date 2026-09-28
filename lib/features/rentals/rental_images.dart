/// Max photos on a rental listing (WhatsApp-style gallery, not a square crop).
const kMaxRentalPhotos = 6;

/// Cover (`imageUrl`) first, then extra `imageUrls`, de-duplicated.
List<String> rentalImageUrls(Map<String, dynamic>? item) {
  if (item == null) return <String>[];
  final out = <String>[];
  void add(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty || out.contains(s) || out.length >= kMaxRentalPhotos) return;
    out.add(s);
  }

  add(item['imageUrl'] as String?);
  final extra = item['imageUrls'];
  if (extra is List) {
    for (final e in extra) {
      add(e?.toString());
    }
  }
  return out;
}

/// Catalog distance from GET /rentals (`distanceKm`).
String? rentalDistanceLabel(Map<String, dynamic>? item) {
  if (item == null) return null;
  final raw = item['distanceKm'];
  final km = raw is num ? raw.toDouble() : double.tryParse('$raw');
  if (km == null || !km.isFinite || km < 0) return null;
  if (km < 0.1) return 'Nearby';
  if (km < 1) return '${(km * 1000).round()} m away';
  return '${km.toStringAsFixed(1)} km away';
}
