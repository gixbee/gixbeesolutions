/// Builds a single saved-address line from the complete-address form.
/// Empty parts are skipped so "house, city" stays clean when landmark/PIN
/// are omitted.
String composeAddressLine({
  required String house,
  String landmark = '',
  String area = '',
  String city = '',
  String pincode = '',
}) {
  return [
    house.trim(),
    landmark.trim(),
    area.trim(),
    city.trim(),
    pincode.trim(),
  ].where((part) => part.isNotEmpty).join(', ');
}

/// Append [city] onto [address] when it is not already present.
String ensureCityInAddress(String address, String city) {
  final line = address.trim();
  final name = city.trim();
  if (name.isEmpty) return line;
  if (line.isEmpty) return name;
  if (line.toLowerCase().contains(name.toLowerCase())) return line;
  return '$line, $name';
}
