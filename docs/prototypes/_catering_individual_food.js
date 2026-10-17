/** À la carte singles for "Add individual food item" (one pick → rate slabs). */
const INDIVIDUAL_FOOD_PICKER_SECTIONS = [
  {
    section: 'Biriyani & rice',
    names: [
      'Chicken Biriyani',
      'Mutton Biriyani',
      'Fish Biriyani',
      'Prawn / Chemmeen Biriyani',
      'Vegetable Biriyani',
      'Malabar Biriyani',
      'Thalassery Biriyani',
      'Ghee Rice',
      'Steamed Rice',
    ],
  },
  {
    section: 'Arabian & grills',
    names: [
      'Al Faham Chicken',
      'Chicken Mandi',
      'Mutton Mandi',
      'Shawarma Roll',
      'Grilled Chicken',
      'Mixed Grill',
      'Arabian Rice',
    ],
  },
  {
    section: 'Curries & mains',
    names: [
      'Chicken Curry',
      'Beef Roast',
      'Beef Fry',
      'Mutton Pepper Fry',
      'Fish Fry',
      'Fish Molee',
      'Prawn Roast',
      'Duck Curry',
      'Paneer Butter Masala',
      'Vegetable Kurma',
    ],
  },
  {
    section: 'Breads & sides',
    names: ['Appam', 'Porotta', 'Malabar Porotta', 'Idiyappam', 'Chapati', 'Naan', 'Pappadam'],
  },
  {
    section: 'Beverages',
    names: [
      'Tea',
      'Coffee',
      'Masala Chai',
      'Fresh Lime Juice',
      'Tender Coconut Water',
      'Rose Milk',
      'Plain Buttermilk',
    ],
  },
];

function findCatalogItemByName(dishName) {
  const q = String(dishName || '').trim().toLowerCase();
  if (!q) return null;
  for (let mi = 0; mi < FOOD_MODULES.length; mi++) {
    const mod = FOOD_MODULES[mi];
    for (let si = 0; si < mod.subcats.length; si++) {
      const sc = mod.subcats[si];
      for (let ii = 0; ii < sc.items.length; ii++) {
        const it = sc.items[ii];
        if (String(it.name).toLowerCase() === q) {
          return { module: mod, subcat: sc, item: it };
        }
      }
    }
  }
  return null;
}

function buildIndividualPickerRows() {
  const rows = [];
  INDIVIDUAL_FOOD_PICKER_SECTIONS.forEach(function (sec) {
    (sec.names || []).forEach(function (name) {
      const hit = findCatalogItemByName(name);
      if (hit) {
        rows.push({
          section: sec.section,
          name: hit.item.name,
          masterKey: hit.item.masterKey,
          diet: hit.item.diet,
          moduleId: hit.module.id,
        });
      } else {
        rows.push({
          section: sec.section,
          name: name,
          masterKey: null,
          diet: 'veg',
          moduleId: 'm09',
        });
      }
    });
  });
  return rows;
}
