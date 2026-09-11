/// Parse timestamps from API JSON (ISO-8601 string, epoch ms, or DateTime).
DateTime? parseApiDateTime(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is String) {
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
  }
  if (raw is num) {
    return DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true);
  }
  return DateTime.tryParse(raw.toString());
}
