/// Shop and offer categories from the v147 Plan an Event and Today's Offers
/// screens. [id] is the stored category. [chip] is the home-tab label.
class OfferCategory {
  const OfferCategory(this.id, this.chip, this.kind);

  final String id;
  final String chip;

  /// `offers` filters the deal list. `gym` and `clinic` open an enquire-only
  /// directory. `shops` opens a shop list for that trade.
  final String kind;

  bool get isDirectory => kind != 'offers';
}

const offerCategories = <OfferCategory>[
  OfferCategory('Jewellery', '💍 Jewellery', 'offers'),
  OfferCategory('Textiles', '🥻 Textiles', 'offers'),
  OfferCategory('Beauty', '💆 Beauty', 'offers'),
  OfferCategory('Bridal', '👗 Bridal', 'offers'),
  OfferCategory('Electronics', '📱 Electronics', 'offers'),
  OfferCategory('Furniture', '🛋 Furniture', 'offers'),
  OfferCategory('Opticals', '👓 Opticals', 'offers'),
  OfferCategory('Fitness', '🏋 Fitness', 'gym'),
  OfferCategory('Dental', '🦷 Dental', 'clinic'),
  OfferCategory('Medical', '💊 Medical', 'shops'),
  OfferCategory('Paint', '🎨 Paint', 'shops'),
  OfferCategory('Hardware', '🔧 Hardware', 'shops'),
  OfferCategory('Study Abroad', '🎓 Study Abroad', 'shops'),
  OfferCategory('Auto', '🚗 Auto', 'shops'),
  OfferCategory('Tailoring', '🧵 Tailoring', 'shops'),
  OfferCategory('Labs', '🧪 Labs', 'shops'),
];

OfferCategory? offerCategoryByChip(String chip) {
  for (final category in offerCategories) {
    if (category.chip == chip || category.id == chip) return category;
  }
  return null;
}

/// A deal matches a chip when its category equals the chip id. The All chip
/// matches every deal.
bool matchesOfferCategory(String? category, String chip) {
  if (chip == 'All') return true;
  final selected = offerCategoryByChip(chip);
  if (selected == null || selected.isDirectory) return false;
  return (category ?? '').trim().toLowerCase() == selected.id.toLowerCase();
}
