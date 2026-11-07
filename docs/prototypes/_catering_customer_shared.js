/** Shared catering customer helpers — aligned with owner menu & packages (nine groups, serve style). */

const CC_SERVE_FILTERS = [
  { id: 'all', label: 'All', hint: 'Every serving style' },
  { id: 'table', label: 'Table service', hint: 'We serve each course at the table' },
  { id: 'buffet', label: 'Buffet', hint: 'Counters; guests help themselves' },
  { id: 'both', label: 'Table & buffet', hint: 'Table service plus buffet counters' },
];

function ccPackageServeStyle(p) {
  p = p || {};
  if (p.serveStyle === 'table' || p.serveStyle === 'buffet' || p.serveStyle === 'both') return p.serveStyle;
  if (p.serveAtTable && p.serveAtCounter) return 'both';
  if (p.serveAtCounter) return 'buffet';
  if (p.serveAtTable) return 'table';
  const legacy = p.menuStyle || '';
  if (legacy === 'sadhya') return 'table';
  if (legacy === 'buffet' || legacy === 'arabian') return 'buffet';
  return '';
}

function ccServeStyleLabel(id) {
  if (id === 'table') return 'Table service';
  if (id === 'buffet') return 'Buffet';
  if (id === 'both') return 'Table & buffet';
  return '';
}

function ccServeFilterLabel(id) {
  const hit = CC_SERVE_FILTERS.filter(function (s) {
    return s.id === id;
  })[0];
  return hit ? hit.label : 'All';
}

function ccCustomerModuleLabel(mod) {
  const id = mod && mod.id;
  const labels = {
    g01: 'Welcome Drinks',
    g02: 'Starters & Snacks',
    g03: 'Rice, Biriyani & Mandi',
    g04: 'Breads & Rotis',
    g05: 'Curries & Gravies',
    g06: 'Vegetables & Thoran',
    g07: 'Accompaniments',
    g08: 'Desserts & Sweets',
    g09: 'Live Counters',
  };
  if (id && labels[id]) return labels[id];
  return (mod && mod.name) || '';
}

function ccCustomerFoodGroups() {
  if (typeof FOOD_MODULES !== 'undefined' && FOOD_MODULES.length) {
    return FOOD_MODULES.map(function (m) {
      return { id: m.id, label: ccCustomerModuleLabel(m) };
    });
  }
  return [
    { id: 'g01', label: 'Welcome Drinks' },
    { id: 'g02', label: 'Starters & Snacks' },
    { id: 'g03', label: 'Rice, Biriyani & Mandi' },
    { id: 'g04', label: 'Breads & Rotis' },
    { id: 'g05', label: 'Curries & Gravies' },
    { id: 'g06', label: 'Vegetables & Thoran' },
    { id: 'g07', label: 'Accompaniments' },
    { id: 'g08', label: 'Desserts & Sweets' },
    { id: 'g09', label: 'Live Counters' },
  ];
}

function ccMenuGroupsForPackage(pkg) {
  if (!pkg) return [];
  if (pkg.menuModules && pkg.menuModules.length) {
    return pkg.menuModules.map(function (row) {
      const mod = typeof findFoodModule === 'function' ? findFoodModule(row.moduleId) : null;
      return {
        moduleId: row.moduleId,
        name: ccCustomerModuleLabel(mod) || String(row.moduleId || 'Menu'),
        emoji: (mod && mod.emoji) || '',
        items: row.items || [],
      };
    });
  }
  if (pkg.groups && pkg.groups.length) {
    return pkg.groups.map(function (g) {
      return { name: g.name, items: g.items || [], emoji: '' };
    });
  }
  return [];
}

function ccGuestSlabsLikeOwner(base) {
  const mid = Math.max(80, Math.round(+base || 300));
  return [
    { from: 1, to: 25, price: mid + 100 },
    { from: 26, to: 50, price: mid + 50 },
    { from: 51, to: 100, price: mid },
    { from: 101, to: 200, price: Math.max(80, mid - 50) },
    { from: 201, to: 500, price: Math.max(80, mid - 80) },
  ];
}

function ccDemoVegWeddingMenuModules() {
  return [
    { moduleId: 'g01', items: ['Fresh Lime Juice', 'Sambharam / Spiced Buttermilk'] },
    { moduleId: 'g02', items: ['Vegetable Samosa', 'Banana Fritters', 'Unnakaya'] },
    { moduleId: 'g03', items: ['Kerala Matta Rice', 'Ghee Rice', 'Nei Choru'] },
    { moduleId: 'g05', items: ['Sambar', 'Avial', 'Pulissery', 'Kaalan', 'Parippu'] },
    { moduleId: 'g06', items: ['Mixed Vegetable Thoran', 'Beans Thoran', 'Cabbage Thoran'] },
    { moduleId: 'g07', items: ['Pappadam', 'Pickle', 'Banana', 'Inji Curry'] },
    { moduleId: 'g08', items: ['Palada Payasam', 'Ada Pradhaman', 'Semiya Payasam'] },
  ];
}

function ccDemoCompactVegMenuModules() {
  return [
    { moduleId: 'g01', items: ['Fresh Lime Juice', 'Sambharam / Spiced Buttermilk'] },
    { moduleId: 'g03', items: ['Kerala Matta Rice', 'Ghee Rice'] },
    { moduleId: 'g05', items: ['Sambar', 'Avial', 'Parippu'] },
    { moduleId: 'g06', items: ['Mixed Vegetable Thoran', 'Beans Thoran'] },
    { moduleId: 'g07', items: ['Pappadam', 'Pickle', 'Banana'] },
    { moduleId: 'g08', items: ['Palada Payasam', 'Semiya Payasam'] },
  ];
}

function ccDemoArabianReceptionModules() {
  return [
    { moduleId: 'g01', items: ['Fresh Lime Juice', 'Mint Lime', 'Sambharam / Spiced Buttermilk'] },
    { moduleId: 'g02', items: ['Chicken Cutlet', 'Beef Fry', 'Hummus', 'Falafel'] },
    { moduleId: 'g03', items: ['Chicken Mandi', 'Mutton Mandi', 'Al Faham Chicken', 'Ghee Rice'] },
    { moduleId: 'g04', items: ['Kuboos', 'Rumali Roti', 'Sheermal'] },
    { moduleId: 'g08', items: ['Fresh Fruit Platter', 'Kunafa', 'Umm Ali'] },
  ];
}

function ccDemoWeddingMenuModules() {
  return [
    { moduleId: 'g01', items: ['Fresh Lime Juice', 'Tender Coconut Water', 'Sambharam / Spiced Buttermilk'] },
    {
      moduleId: 'g02',
      items: ['Vegetable Samosa', 'Banana Fritters', 'Chicken Cutlet', 'Beef Fry'],
    },
    {
      moduleId: 'g03',
      items: ['Kerala Matta Rice', 'Ghee Rice', 'Vegetable Biriyani', 'Chicken Biriyani'],
    },
    { moduleId: 'g04', items: ['Chappati', 'Kerala Porotta', 'Appam'] },
    {
      moduleId: 'g05',
      items: ['Sambar', 'Avial', 'Chicken Curry', 'Fish Molly', 'Beef Roast'],
    },
    { moduleId: 'g06', items: ['Mixed Vegetable Thoran', 'Beans Thoran', 'Cabbage Thoran'] },
    { moduleId: 'g07', items: ['Pappadam', 'Pickle', 'Banana', 'Onion Salad'] },
    {
      moduleId: 'g08',
      items: ['Palada Payasam', 'Ada Pradhaman', 'Gulab Jamun', 'Fresh Fruit Platter'],
    },
    { moduleId: 'g09', items: ['Dosa Counter', 'Chaat Counter', 'Payasam Counter'] },
  ];
}

function ccPackageMenuFromModules(rows) {
  return rows.map(function (row) {
    const mod = typeof findFoodModule === 'function' ? findFoodModule(row.moduleId) : null;
    return { name: ccCustomerModuleLabel(mod) || row.moduleId, items: row.items || [] };
  });
}

function ccFoodModuleId(item) {
  return item.moduleId || item.group || 'g05';
}
