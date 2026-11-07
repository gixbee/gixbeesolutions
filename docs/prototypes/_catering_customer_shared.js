/** Shared catering customer helpers — aligned with owner menu & packages (nine groups, serve style). */

const CC_SERVE_FILTERS = [
  { id: 'all', label: 'All', hint: 'Every serving style' },
  { id: 'table', label: 'Table service', hint: 'Sadhya on leaf; staff serve courses' },
  { id: 'buffet', label: 'Buffet', hint: 'Counters; guests help themselves' },
  { id: 'both', label: 'Table & buffet', hint: 'Leaf sadhya plus buffet counters' },
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

function ccCustomerFoodGroups() {
  if (typeof FOOD_MODULES !== 'undefined' && FOOD_MODULES.length) {
    return FOOD_MODULES.map(function (m) {
      return { id: m.id, label: m.name };
    });
  }
  return [
    { id: 'g01', label: 'Welcome drinks' },
    { id: 'g02', label: 'Starters and snacks' },
    { id: 'g03', label: 'Rice, biryani and mandi' },
    { id: 'g04', label: 'Breads' },
    { id: 'g05', label: 'Curries and gravies' },
    { id: 'g06', label: 'Dry vegetables and thoran' },
    { id: 'g07', label: 'Chutney, pickle, salad and pappadam' },
    { id: 'g08', label: 'Payasam and desserts' },
    { id: 'g09', label: 'Live counters' },
  ];
}

function ccMenuGroupsForPackage(pkg) {
  if (!pkg) return [];
  if (pkg.groups && pkg.groups.length) return pkg.groups;
  if (pkg.menuModules && pkg.menuModules.length) {
    return pkg.menuModules.map(function (row) {
      const mod = typeof findFoodModule === 'function' ? findFoodModule(row.moduleId) : null;
      return { name: (mod && mod.name) || String(row.moduleId || 'Menu'), items: row.items || [] };
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
    return { name: (mod && mod.name) || row.moduleId, items: row.items || [] };
  });
}

function ccFoodModuleId(item) {
  return item.moduleId || item.group || 'g05';
}
