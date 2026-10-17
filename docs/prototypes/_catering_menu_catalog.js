/** Fixed 13-module catering catalogue (seed items for owner selection). */
const CAT_PKG_LEVELS = ['Basic', 'Standard', 'Premium', 'Custom'];

const FOOD_MODULE_GRADIENTS = [
  'linear-gradient(145deg,#0EA5E9,#0284C7)',
  'linear-gradient(145deg,#F97316,#EA580C)',
  'linear-gradient(145deg,#22C55E,#16A34A)',
  'linear-gradient(145deg,#EF4444,#DC2626)',
  'linear-gradient(145deg,#EAB308,#CA8A04)',
  'linear-gradient(145deg,#A855F7,#7C3AED)',
  'linear-gradient(145deg,#F43F5E,#E11D48)',
  'linear-gradient(145deg,#6366F1,#4F46E5)',
  'linear-gradient(145deg,#14B8A6,#0D9488)',
  'linear-gradient(145deg,#84CC16,#65A30D)',
  'linear-gradient(145deg,#FB923C,#F97316)',
  'linear-gradient(145deg,#D97706,#B45309)',
  'linear-gradient(145deg,#EC4899,#DB2777)',
];

function foodMasterKey(moduleId, subcatId, name) {
  return moduleId + '::' + subcatId + '::' + String(name || '').toLowerCase().replace(/\s+/g, '-');
}

function buildFoodModules() {
  const defs = [
    {
      id: 'm01',
      name: 'Welcome Drinks',
      emoji: '🥤',
      subcats: [
        {
          id: 'juices',
          name: 'Juices & Mocktails',
          items: ['Fresh Lime', 'Mango Juice', 'Watermelon Juice', 'Mint Lime', 'Buttermilk (Chaas)'],
        },
        {
          id: 'hot',
          name: 'Hot Beverages',
          items: ['Tea', 'Coffee', 'Masala Chai'],
        },
      ],
    },
    {
      id: 'm02',
      name: 'Starters & Snacks',
      emoji: '🥟',
      subcats: [
        {
          id: 'veg',
          name: 'Vegetarian',
          items: ['Vegetable Spring Roll', 'Paneer Tikka', 'Gobi Manchurian', 'Banana Fritters', 'Samosa'],
        },
        {
          id: 'nonveg',
          name: 'Non-Vegetarian',
          items: ['Chicken 65', 'Fish Fry', 'Prawn Tempura', 'Mutton Cutlet'],
        },
      ],
    },
    {
      id: 'm03',
      name: 'Salads',
      emoji: '🥗',
      subcats: [
        {
          id: 'fresh',
          name: 'Fresh Salads',
          items: ['Green Salad', 'Russian Salad', 'Fruit Salad', 'Coleslaw'],
        },
      ],
    },
    {
      id: 'm04',
      name: 'Soups',
      emoji: '🍲',
      subcats: [
        {
          id: 'veg',
          name: 'Vegetarian Soups',
          items: [
            'Tomato Soup',
            'Manchow Vegetable Soup',
            'Sweet Corn Vegetable Soup',
            'Mushroom Soup',
            'Hot & Sour Vegetable Soup',
          ],
        },
        {
          id: 'nonveg',
          name: 'Non-Vegetarian Soups',
          items: [
            'Chicken Clear Soup',
            'Chicken Manchow Soup',
            'Prawn Soup',
            'Mutton Soup',
            'Sweet Corn Chicken Soup',
          ],
        },
        {
          id: 'special',
          name: 'Specialty',
          items: ['Pepper Soup', 'Mulligatawny Soup', 'Custom Soup'],
        },
      ],
    },
    {
      id: 'm05',
      name: 'Sadhya',
      emoji: '🍛',
      subcats: [
        {
          id: 'items',
          name: 'Sadhya Items',
          items: ['Traditional Sadhya (per person)', 'Mini Sadhya', 'Onam Sadhya'],
        },
      ],
    },
    {
      id: 'm06',
      name: 'Biriyani',
      emoji: '🍚',
      subcats: [
        {
          id: 'veg',
          name: 'Vegetarian',
          items: ['Vegetable Biriyani', 'Paneer Biriyani', 'Mushroom Biriyani'],
        },
        {
          id: 'nonveg',
          name: 'Non-Vegetarian',
          items: ['Chicken Biriyani', 'Mutton Biriyani', 'Fish Biriyani', 'Prawn Biriyani'],
        },
      ],
    },
    {
      id: 'm07',
      name: 'Arabian',
      emoji: '🧆',
      subcats: [
        {
          id: 'grill',
          name: 'Grills & Rice',
          items: ['Chicken Mandi', 'Mutton Kabsa', 'Al Faham', 'Arabian Rice'],
        },
      ],
    },
    {
      id: 'm08',
      name: 'Main Course',
      emoji: '🍽️',
      subcats: [
        {
          id: 'veg',
          name: 'Vegetarian',
          items: ['Vegetable Stew', 'Paneer Butter Masala', 'Dal Tadka', 'Mixed Veg Curry'],
        },
        {
          id: 'nonveg',
          name: 'Non-Vegetarian',
          items: ['Chicken Roast', 'Fish Molly', 'Beef Fry', 'Mutton Pepper Fry'],
        },
      ],
    },
    {
      id: 'm09',
      name: 'Curries & Gravies',
      emoji: '🥘',
      subcats: [
        {
          id: 'veg',
          name: 'Vegetarian',
          items: ['Sambar', 'Avial', 'Erissery', 'Moru Curry'],
        },
        {
          id: 'nonveg',
          name: 'Non-Vegetarian',
          items: ['Chicken Curry', 'Fish Curry', 'Mutton Curry', 'Prawn Curry'],
        },
      ],
    },
    {
      id: 'm10',
      name: 'Accompaniments',
      emoji: '🥙',
      subcats: [
        {
          id: 'sides',
          name: 'Sides',
          items: ['Pickle', 'Pappadam', 'Chutney', 'Raitha', 'Ghee Rice'],
        },
      ],
    },
    {
      id: 'm11',
      name: 'Special Live Counters',
      emoji: '🔥',
      subcats: [
        {
          id: 'live',
          name: 'Live Stations',
          items: ['Appam Counter', 'Dosa Counter', 'Grill Counter', 'Chaat Counter', 'Payasam Counter'],
        },
      ],
    },
    {
      id: 'm12',
      name: 'Breads & Rotis',
      emoji: '🫓',
      subcats: [
        {
          id: 'bread',
          name: 'Breads',
          items: ['Appam', 'Idiyappam', 'Porotta', 'Naan', 'Chapati'],
        },
      ],
    },
    {
      id: 'm13',
      name: 'Desserts & Sweets',
      emoji: '🍮',
      subcats: [
        {
          id: 'sweet',
          name: 'Sweets',
          items: ['Payasam', 'Gulab Jamun', 'Ice Cream', 'Fruit Custard', 'Ada Pradhaman'],
        },
      ],
    },
  ];
  return defs.map(function (m, idx) {
    const subcats = (m.subcats || []).map(function (sc) {
      const items = (sc.items || []).map(function (name) {
        const diet =
          sc.id === 'nonveg' || /chicken|mutton|prawn|fish|beef|meat/i.test(name)
            ? 'non_veg'
            : sc.id === 'veg' || /vegetable|paneer|mushroom|dal|sambar|avial/i.test(name)
              ? 'veg'
              : 'veg';
        return {
          masterKey: foodMasterKey(m.id, sc.id, name),
          name: name,
          subcatId: sc.id,
          subcatName: sc.name,
          diet: diet,
        };
      });
      return { id: sc.id, name: sc.name, items: items };
    });
    return {
      id: m.id,
      num: idx + 1,
      name: m.name,
      emoji: m.emoji,
      gradient: FOOD_MODULE_GRADIENTS[idx] || FOOD_MODULE_GRADIENTS[0],
      subcats: subcats,
    };
  });
}

const FOOD_MODULES = buildFoodModules();

function findFoodModule(moduleId) {
  return FOOD_MODULES.find(function (m) {
    return m.id === moduleId;
  });
}

function findMasterItem(masterKey) {
  for (let mi = 0; mi < FOOD_MODULES.length; mi++) {
    const mod = FOOD_MODULES[mi];
    for (let si = 0; si < mod.subcats.length; si++) {
      const sc = mod.subcats[si];
      for (let ii = 0; ii < sc.items.length; ii++) {
        if (sc.items[ii].masterKey === masterKey) return { module: mod, subcat: sc, item: sc.items[ii] };
      }
    }
  }
  return null;
}

function defaultItemSlabs() {
  return [
    { from: 1, to: 25, price: 70 },
    { from: 26, to: 50, price: 60 },
    { from: 51, to: 100, price: 55 },
    { from: 101, to: 200, price: 50 },
    { from: 201, to: 500, price: 45 },
  ];
}

function defaultPackageGuestSlabs() {
  return [
    { from: 25, to: 50, price: 300 },
    { from: 51, to: 100, price: 280 },
    { from: 101, to: 200, price: 260 },
    { from: 201, to: 300, price: 240 },
    { from: 301, to: 500, price: 220 },
  ];
}

function defaultCateringMenuStore() {
  return {
    hubTab: 'packages',
    pkgFilter: 'all',
    pkgSort: 'name',
    pkgSearch: '',
    foodSearch: '',
    foodItems: [],
    catPackages: [
      {
        id: 'cpkg-demo-1',
        name: 'Engagement Standard',
        level: 'Standard',
        description: 'Balanced spread for engagement functions with welcome drinks, starters, mains and dessert.',
        subtitle: '~120 guests · 10 modules · per person',
        listPrice: 40000,
        price: 35000,
        status: 'live',
        pricingMode: 'per_person',
        guestSlabs: defaultPackageGuestSlabs(),
        itemIds: [],
        imageEmoji: '🍽️',
      },
      {
        id: 'cpkg-demo-2',
        name: 'Wedding Premium',
        level: 'Premium',
        description: 'Full-day premium wedding catering with live counters and extended dessert selection.',
        subtitle: 'Full day · premium spread',
        listPrice: 75000,
        price: 75000,
        status: 'live',
        pricingMode: 'per_person',
        guestSlabs: defaultPackageGuestSlabs(),
        itemIds: [],
        imageEmoji: '💒',
      },
      {
        id: 'cpkg-demo-3',
        name: 'Reception Basic',
        level: 'Basic',
        description: 'Essential reception menu — starters, one main and dessert.',
        subtitle: 'Reception essentials',
        listPrice: 25000,
        price: 25000,
        status: 'draft',
        pricingMode: 'per_person',
        guestSlabs: defaultPackageGuestSlabs(),
        itemIds: [],
        imageEmoji: '🎉',
      },
    ],
  };
}

function seedDemoFoodItems() {
  const keys = [
    foodMasterKey('m04', 'veg', 'Tomato Soup'),
    foodMasterKey('m04', 'nonveg', 'Chicken Clear Soup'),
    foodMasterKey('m01', 'juices', 'Fresh Lime'),
    foodMasterKey('m02', 'veg', 'Paneer Tikka'),
  ];
  return keys
    .map(function (k) {
      const hit = findMasterItem(k);
      if (!hit) return null;
      return {
        id: 'food-' + k.replace(/::/g, '-'),
        masterKey: k,
        name: hit.item.name,
        moduleId: hit.module.id,
        subcatId: hit.subcat.id,
        subcatName: hit.subcat.name,
        description: '',
        diet: hit.item.diet,
        pricingMode: 'per_person',
        unitLabel: 'plate',
        quoteOnly: false,
        status: 'active',
        slabs: defaultItemSlabs(),
        imageEmoji: hit.module.emoji,
      };
    })
    .filter(Boolean);
}
