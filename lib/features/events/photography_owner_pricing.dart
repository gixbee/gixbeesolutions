/// Photography catalogue monetary rules shared by owner editor and cards.
/// Rust validates the resulting price independently on every catalogue save.
class PhotographyOwnerPrice {
  const PhotographyOwnerPrice._();

  static int? discounted(int listPrice, int discountPercent) {
    if (listPrice < 1 || listPrice > 10000000 ||
        discountPercent < 0 || discountPercent > 90) {
      return null;
    }
    // Positive integer rupees: round half up, exactly like Rust.
    return (listPrice * (100 - discountPercent) + 50) ~/ 100;
  }

  static String? validate(Map<String, dynamic> item) {
    final name = (item['name'] ?? '').toString().trim();
    final kind = item['kind'];
    final amount = item['price'];
    if (name.isEmpty || name.length > 150 ||
        (kind != 'PACKAGE' && kind != 'ITEM') ||
        amount is! int || amount < 1 || amount > 10000000) {
      return 'Enter a name and price between ₹1 and ₹1,00,00,000.';
    }
    final original = item['listPrice'];
    final pct = item['discountPct'];
    if (original != null || pct != null) {
      if (original is! int || pct is! int ||
          discounted(original, pct) != amount) {
        return 'Check the list price, discount and customer-facing price.';
      }
    }
    if (kind == 'PACKAGE') {
      final stages = (item['paymentSplit'] as List? ?? const []);
      if (stages.isEmpty || stages.length > 6) {
        return 'Enter 1–6 payment stages.';
      }
      final names = <String>{};
      var sum = 0;
      for (final row in stages) {
        if (row is! Map) return 'Invalid payment stage.';
        final label = (row['label'] ?? '').toString().trim();
        final value = row['percent'];
        if (label.isEmpty || label.length > 150 ||
            !names.add(label.toLowerCase()) ||
            value is! int || value < 1 || value > 100) {
          return 'Check payment stage names and percentages.';
        }
        sum += value;
      }
      if (sum != 100) return 'Payment percentages must total 100%.';
      if ((item['functions'] as List? ?? const []).isEmpty) {
        return 'Select at least one function.';
      }
    }
    return null;
  }

  static List<Map<String, dynamic>> visible(
    List<Map<String, dynamic>> items, {
    required bool packages,
    String status = 'all',
    String level = 'all',
    String search = '',
  }) {
    final needle = search.trim().toLowerCase();
    return items.where((item) {
      if ((item['kind'] == 'PACKAGE') != packages) return false;
      if (status == 'live' && item['active'] == false) return false;
      if (status == 'draft' && item['active'] != false) return false;
      if (packages && level != 'all' &&
          item['packageLevel']?.toString() != level) return false;
      final text = '${item['name'] ?? ''} ${item['category'] ?? ''}'
          .toLowerCase();
      return text.contains(needle);
    }).toList();
  }
}
