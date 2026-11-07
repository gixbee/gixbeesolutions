/** Nine-group dish library for Kerala catering, plus the Indian buffet dishes owners also serve. */
const CAT_PKG_LEVELS = ['Basic', 'Standard', 'Premium'];
const CAT_PKG_LEVEL_HINTS = {
  Basic: 'Simple and affordable menu',
  Standard: 'Popular menu with variety',
  Premium: 'Grand menu with special dishes',
};

const FOOD_MODULE_GRADIENTS = ["linear-gradient(145deg,#0EA5E9,#0284C7)", "linear-gradient(145deg,#F97316,#EA580C)", "linear-gradient(145deg,#22C55E,#16A34A)", "linear-gradient(145deg,#EF4444,#DC2626)", "linear-gradient(145deg,#EAB308,#CA8A04)", "linear-gradient(145deg,#A855F7,#7C3AED)", "linear-gradient(145deg,#F43F5E,#E11D48)", "linear-gradient(145deg,#6366F1,#4F46E5)", "linear-gradient(145deg,#14B8A6,#0D9488)", "linear-gradient(145deg,#84CC16,#65A30D)", "linear-gradient(145deg,#FB923C,#F97316)", "linear-gradient(145deg,#D97706,#B45309)", "linear-gradient(145deg,#EC4899,#DB2777)"];

function foodMasterKey(moduleId, subcatId, name) {
  return moduleId + '::' + subcatId + '::' + String(name || '').toLowerCase().replace(/\s+/g, '-');
}

function inferCatalogDiet(subcatName, itemName) {
  const sc = String(subcatName || '').toLowerCase();
  const nm = String(itemName || '').toLowerCase();
  const meat = /\b(chicken|mutton|beef|prawn|fish|crab|lobster|squid|calamari|seafood|chemmeen|duck|pork|meen)\b/;
  if (/\begg\b/.test(nm) && !/vegetable/.test(nm)) return 'non_veg';
  if (meat.test(nm)) return 'non_veg';
  if (/\b(rice|biryani|biriyani)\b/.test(nm)) return 'veg';
  if (
    sc.indexOf('non-vegetarian') >= 0 ||
    sc.indexOf('non vegetarian') >= 0 ||
    sc.indexOf('chicken & meat') >= 0 ||
    sc.indexOf('chicken, meat') >= 0 ||
    sc.indexOf('chicken dishes') >= 0 ||
    sc.indexOf('mutton') >= 0 ||
    sc.indexOf('beef') >= 0 ||
    sc.indexOf('duck') >= 0 ||
    sc.indexOf('pork') >= 0 ||
    sc.indexOf('fish & seafood') >= 0 ||
    sc.indexOf('seafood') >= 0 ||
    sc.indexOf('grill') >= 0
  ) {
    return 'non_veg';
  }
  if (sc.indexOf('paneer & egg') >= 0 && /\begg\b/.test(nm)) return 'non_veg';
  return 'veg';
}

const CATERING_CATALOG_DEFS = [
  {
    "id": "g01",
    "name": "Welcome drinks",
    "emoji": "🥤",
    "subcats": [
      {
        "id": "juices",
        "name": "Juices",
        "items": [
          "Fresh Lime Juice",
          "Ginger Lime",
          "Lemon Mint Juice",
          "Orange Juice",
          "Watermelon Juice",
          "Pineapple Juice",
          "Mango Juice",
          "Guava Juice",
          "Papaya Juice",
          "Muskmelon Juice",
          "Tender Coconut Water",
          "Mixed Fruit Juice"
        ]
      },
      {
        "id": "traditional",
        "name": "Traditional drinks",
        "items": [
          "Tea",
          "Masala Tea",
          "Sulaimani",
          "Coffee",
          "Sambharam / Spiced Buttermilk",
          "Plain Buttermilk",
          "Rose Milk",
          "Badam Milk",
          "Pista Milk",
          "Nannari Sarbath"
        ]
      },
      {
        "id": "cold",
        "name": "Cold drinks",
        "items": [
          "Soft Drinks",
          "Jaljeera",
          "Aam Panna",
          "Virgin Mojito",
          "Blue Lagoon (Mocktail)",
          "Mango Lassi",
          "Sweet Lassi",
          "Chocolate Milkshake",
          "Strawberry Milkshake",
          "Mineral Water"
        ]
      }
    ]
  },
  {
    "id": "g02",
    "name": "Starters and snacks",
    "emoji": "🥟",
    "subcats": [
      {
        "id": "veg-snacks",
        "name": "Vegetarian snacks",
        "items": [
          "Vegetable Cutlet",
          "Hara Bhara Kebab",
          "Paneer Tikka",
          "Tandoori Mushroom",
          "Crispy Corn",
          "Gobi 65",
          "Samosa",
          "Veg Pakoda",
          "Vegetable Spring Roll",
          "French Fries",
          "Baby Corn Fry",
          "Veg Momos"
        ]
      },
      {
        "id": "non-veg-snacks",
        "name": "Non-vegetarian snacks",
        "items": [
          "Chicken 65",
          "Chicken Lollipop",
          "Chicken Tikka",
          "Chicken Malai Tikka",
          "Chicken Fry",
          "Chicken Pepper Fry",
          "Fish Fry",
          "Fish Finger",
          "Prawn Fry",
          "Prawn Pepper Fry",
          "Crab Ball",
          "Mutton Kebab",
          "Mutton Seekh Kebab",
          "Beef Cutlet",
          "Beef Fry",
          "Egg Pakoda"
        ]
      },
      {
        "id": "kerala-snacks",
        "name": "Kerala tea-time",
        "items": [
          "Pazham Pori",
          "Banana Boli",
          "Parippu Vada",
          "Uzhunnu Vada",
          "Bonda",
          "Unniyappam",
          "Ela Ada",
          "Achappam",
          "Kuzhalappam",
          "Sukhiyan",
          "Kappa Cutlet"
        ]
      },
      {
        "id": "chaat-rolls",
        "name": "Chaat and rolls",
        "items": [
          "Vegetable Puff",
          "Chicken Puff",
          "Veg Grill Sandwich",
          "Chicken Kathi Roll",
          "Aloo Tikki Chaat",
          "Papdi Chaat",
          "Dahi Bhalla",
          "Bhel Puri",
          "Pav Bhaji"
        ]
      },
      {
        "id": "soups",
        "name": "Soups",
        "items": [
          "Tomato Soup",
          "Sweet Corn Vegetable Soup",
          "Hot and Sour Vegetable Soup",
          "Chicken Clear Soup",
          "Chicken Sweet Corn Soup",
          "Mutton Soup",
          "Mulligatawny Soup"
        ]
      }
    ]
  },
  {
    "id": "g03",
    "name": "Rice, biryani and mandi",
    "emoji": "🍚",
    "subcats": [
      {
        "id": "biryani",
        "name": "Biryani",
        "items": [
          "Chicken Biriyani",
          "Mutton Biriyani",
          "Beef Biriyani",
          "Fish Biriyani",
          "Prawn Biriyani",
          "Egg Biriyani",
          "Duck Biriyani",
          "Vegetable Biriyani",
          "Paneer Biriyani"
        ]
      },
      {
        "id": "regional-biryani",
        "name": "Regional biryani",
        "items": [
          "Malabar Chicken Biriyani",
          "Thalassery Chicken Biriyani",
          "Hyderabadi Chicken Dum Biriyani",
          "Ambur Mutton Biriyani",
          "Kacchi Mutton Dum Biriyani",
          "Jeerakasala Fish Biriyani"
        ]
      },
      {
        "id": "rice",
        "name": "Rice and noodles",
        "items": [
          "Kerala Matta Rice",
          "Steamed Rice",
          "Ghee Rice",
          "Jeera Rice",
          "Vegetable Pulao",
          "Coconut Rice",
          "Lemon Rice",
          "Curd Rice",
          "Tomato Rice",
          "Vegetable Fried Rice",
          "Chicken Fried Rice",
          "Vegetable Hakka Noodles",
          "Chicken Hakka Noodles"
        ]
      },
      {
        "id": "mandi-grills",
        "name": "Mandi and grills",
        "items": [
          "Chicken Mandi",
          "Mutton Mandi",
          "Fish Mandi",
          "Al Faham Chicken",
          "Chicken Shawarma Roll",
          "Chicken Shawarma Plate",
          "Grilled Chicken",
          "Mixed Grill",
          "Arabic Rice"
        ]
      }
    ]
  },
  {
    "id": "g04",
    "name": "Breads",
    "emoji": "🫓",
    "subcats": [
      {
        "id": "indian-breads",
        "name": "Indian breads",
        "items": [
          "Chapati",
          "Phulka",
          "Poori",
          "Bhatura",
          "Tandoori Roti",
          "Naan",
          "Butter Naan",
          "Garlic Naan",
          "Kulcha",
          "Lachha Paratha",
          "Missi Roti",
          "Rumali Roti"
        ]
      },
      {
        "id": "kerala-breads",
        "name": "Kerala breads",
        "items": [
          "Porotta",
          "Malabar Porotta",
          "Nool Porotta",
          "Coin Porotta",
          "Appam",
          "Kallappam",
          "Idiyappam",
          "Pathiri",
          "Neypathal",
          "Puttu",
          "Pidi"
        ]
      },
      {
        "id": "other-breads",
        "name": "Other breads",
        "items": [
          "Pita Bread",
          "Kuboos",
          "Pav",
          "Garlic Bread",
          "Cheese Garlic Bread"
        ]
      }
    ]
  },
  {
    "id": "g05",
    "name": "Curries and gravies",
    "emoji": "🥘",
    "subcats": [
      {
        "id": "kerala-curries",
        "name": "Kerala curries",
        "items": [
          "Sambar",
          "Rasam",
          "Avial",
          "Parippu Curry",
          "Theeyal",
          "Ulli Theeyal",
          "Pulissery",
          "Moru Curry",
          "Kalan",
          "Olan",
          "Erissery",
          "Koottu Curry",
          "Kichadi",
          "Kadala Curry",
          "Vegetable Stew",
          "Mango Curry"
        ]
      },
      {
        "id": "veg-curries",
        "name": "Other vegetarian gravies",
        "items": [
          "Vegetable Kurma",
          "Mixed Vegetable Curry",
          "Dal Tadka",
          "Dal Makhani",
          "Chana Masala",
          "Rajma Masala",
          "Paneer Butter Masala",
          "Kadai Paneer",
          "Palak Paneer",
          "Malai Kofta",
          "Mushroom Masala",
          "Aloo Gobi"
        ]
      },
      {
        "id": "non-veg-curries",
        "name": "Kerala chicken, meat and seafood",
        "items": [
          "Chicken Curry",
          "Chicken Stew",
          "Chicken Mappas",
          "Chicken Roast",
          "Chicken Varutharacha Curry",
          "Mutton Curry",
          "Mutton Stew",
          "Mutton Roast",
          "Beef Curry",
          "Beef Roast",
          "Beef Varattiyathu",
          "Duck Curry",
          "Duck Roast",
          "Kerala Fish Curry",
          "Fish Molee",
          "Fish Pollichathu",
          "Prawn Curry",
          "Crab Curry",
          "Pork Varattiyathu"
        ]
      },
      {
        "id": "other-gravies",
        "name": "Other gravies",
        "items": [
          "Butter Chicken",
          "Chicken Chettinad",
          "Mutton Rogan Josh"
        ]
      },
      {
        "id": "egg",
        "name": "Egg",
        "items": [
          "Egg Curry",
          "Egg Roast",
          "Egg Masala"
        ]
      }
    ]
  },
  {
    "id": "g06",
    "name": "Dry vegetables and thoran",
    "emoji": "🥬",
    "subcats": [
      {
        "id": "thoran",
        "name": "Thoran",
        "items": [
          "Cabbage Thoran",
          "Beans Thoran",
          "Carrot Thoran",
          "Beetroot Thoran",
          "Long Beans Thoran",
          "Raw Banana Thoran"
        ]
      },
      {
        "id": "mezhukkupuratti",
        "name": "Mezhukkupuratti and fry",
        "items": [
          "Potato Mezhukkupuratti",
          "Beans Mezhukkupuratti",
          "Raw Banana Mezhukkupuratti",
          "Potato Fry",
          "Bitter Gourd Fry",
          "Kovakka Fry"
        ]
      },
      {
        "id": "kappa",
        "name": "Kappa",
        "items": [
          "Kappa Puzhukku",
          "Boiled Kappa"
        ]
      }
    ]
  },
  {
    "id": "g07",
    "name": "Chutney, pickle, salad and pappadam",
    "emoji": "🥙",
    "subcats": [
      {
        "id": "chutney",
        "name": "Chutneys",
        "items": [
          "Coconut Chammanthi",
          "Mango Chammanthi",
          "Puthina Chutney",
          "Coriander Chutney",
          "Tomato Chutney",
          "Mulaku Chutney",
          "Onion Chutney",
          "Inji Curry",
          "Puli Inji"
        ]
      },
      {
        "id": "pickle",
        "name": "Pickles",
        "items": [
          "Mango Pickle",
          "Tender Mango Pickle",
          "Lime Pickle",
          "Mixed Pickle",
          "Green Chilli Pickle",
          "Gooseberry Pickle",
          "Vadukapuli Pickle"
        ]
      },
      {
        "id": "salad",
        "name": "Salads and raita",
        "items": [
          "Green Salad",
          "Kachumber Salad",
          "Russian Salad",
          "Cucumber Salad",
          "Onion Salad",
          "Coconut Salad",
          "Cucumber Raita",
          "Boondi Raita",
          "Onion Raita",
          "Mint Raita",
          "Pineapple Pachadi",
          "Beetroot Pachadi",
          "Mango Pachadi",
          "Curd"
        ]
      },
      {
        "id": "crunch",
        "name": "Pappadam and chips",
        "items": [
          "Pappadam",
          "Banana Chips",
          "Jackfruit Chips",
          "Chena Chips",
          "Sharkara Upperi",
          "Chilli Kondattam",
          "Ripe Nendran Banana"
        ]
      }
    ]
  },
  {
    "id": "g08",
    "name": "Payasam and desserts",
    "emoji": "🍮",
    "subcats": [
      {
        "id": "payasam",
        "name": "Payasam and pradhaman",
        "items": [
          "Palada Payasam",
          "Ada Pradhaman",
          "Pazham Pradhaman",
          "Semiya Payasam",
          "Parippu Payasam",
          "Paal Payasam",
          "Chakka Pradhaman",
          "Kadala Parippu Pradhaman",
          "Ari Payasam",
          "Gothambu Payasam"
        ]
      },
      {
        "id": "sweets",
        "name": "Sweets",
        "items": [
          "Gulab Jamun",
          "Rasmalai",
          "Jalebi",
          "Mysore Pak",
          "Laddu",
          "Peda",
          "Kaju Katli",
          "Milk Burfi",
          "Carrot Halwa",
          "Wheat Halwa"
        ]
      },
      {
        "id": "chilled",
        "name": "Chilled desserts",
        "items": [
          "Ice Cream",
          "Kulfi",
          "Caramel Custard",
          "Falooda",
          "Tender Coconut Pudding",
          "Fresh Fruit Platter"
        ]
      },
      {
        "id": "cakes",
        "name": "Cakes",
        "items": [
          "Vanilla Sponge Cake (Sliced)",
          "Black Forest Cake (Sliced)",
          "Brownie",
          "Cupcakes"
        ]
      }
    ]
  },
  {
    "id": "g09",
    "name": "Live counters",
    "emoji": "🔥",
    "subcats": [
      {
        "id": "kerala-live",
        "name": "Kerala counters",
        "items": [
          "Appam Counter",
          "Dosa Counter",
          "Puttu Counter",
          "Porotta Counter",
          "Idiyappam Counter",
          "Thattukada Live Station",
          "Payasam Counter"
        ]
      },
      {
        "id": "hot-live",
        "name": "Grill and hot food",
        "items": [
          "Al Faham Counter",
          "BBQ Counter",
          "Shawarma Counter",
          "Seafood Grill Counter",
          "Live Biriyani Counter"
        ]
      },
      {
        "id": "street-live",
        "name": "Street food and tandoor",
        "items": [
          "Chaat Counter",
          "Pani Puri Counter",
          "French Fries Counter",
          "Tandoor Counter",
          "Pasta Counter"
        ]
      },
      {
        "id": "sweet-live",
        "name": "Dessert counters",
        "items": [
          "Ice Cream Scooping",
          "Jalebi Counter",
          "Coffee Bar",
          "Samavar Tea Counter",
          "Tender Coconut Counter",
          "Paan Counter"
        ]
      }
    ]
  }
];

function buildFoodModules() {
  return CATERING_CATALOG_DEFS.map(function (m, idx) {
    const subcats = (m.subcats || []).map(function (sc) {
      const items = (sc.items || []).map(function (name) {
        const diet = inferCatalogDiet(sc.name, name);
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
    { from: 1, to: 25, price: 500 },
    { from: 26, to: 50, price: 450 },
    { from: 51, to: 100, price: 400 },
    { from: 101, to: 200, price: 350 },
    { from: 201, to: 500, price: 300 },
  ];
}

function defaultCateringMenuStore() {
  return {
    hubTab: 'packages',
    pkgFilter: 'all',
    pkgCategoryFilter: 'wedding',
    pkgSort: 'name',
    pkgSearch: '',
    foodSearch: '',
    foodItems: [],
    catPackages: [
      {
        id: 'cpkg-demo-1',
        name: 'Engagement Day Menu',
        level: 'Standard',
        packageCategory: 'wedding',
        description:
          'Balanced spread for engagement functions with welcome drinks, starters, mains and dessert.',
        subtitle: 'Standard tier · ~120 guests · per person',
        listPrice: 40000,
        price: 35000,
        status: 'live',
        pricingMode: 'per_person',
        dietType: 'mixed',
        serveAtCounter: true,
        serveAtTable: false,
        guestSlabs: defaultPackageGuestSlabs(),
        itemIds: [],
        imageEmoji: '🍽️',
      },
      {
        id: 'cpkg-demo-2',
        name: 'Wedding Premium',
        level: 'Premium',
        packageCategory: 'wedding',
        description:
          'Full-day premium wedding catering with live counters and extended dessert selection.',
        subtitle: 'Full day · premium spread',
        listPrice: 75000,
        price: 75000,
        status: 'live',
        pricingMode: 'per_person',
        dietType: 'mixed',
        serveAtCounter: true,
        serveAtTable: true,
        guestSlabs: defaultPackageGuestSlabs(),
        itemIds: [],
        imageEmoji: '💒',
      },
      {
        id: 'cpkg-demo-3',
        name: 'Reception Basic',
        level: 'Basic',
        packageCategory: 'other',
        description: 'Essential reception menu — starters, one main and dessert.',
        subtitle: 'Reception essentials',
        listPrice: 25000,
        price: 25000,
        status: 'draft',
        pricingMode: 'per_person',
        dietType: 'veg',
        serveAtCounter: false,
        serveAtTable: true,
        guestSlabs: defaultPackageGuestSlabs(),
        itemIds: [],
        imageEmoji: '🎉',
      },
    ],
  };
}

function seedDemoFoodItems() {
  const specs = [
    {
      key: foodMasterKey('g03', 'biryani', 'Chicken Biriyani'),
      slabs: [
        { from: 1, to: 25, price: 200 },
        { from: 26, to: 50, price: 180 },
        { from: 51, to: 100, price: 165 },
      ],
    },
    {
      key: foodMasterKey('g03', 'mandi-grills', 'Al Faham Chicken'),
      slabs: [
        { from: 1, to: 25, price: 220 },
        { from: 26, to: 50, price: 200 },
      ],
    },
    {
      key: foodMasterKey('g01', 'traditional', 'Tea'),
      slabs: [{ from: 1, to: 25, price: 15 }],
    },
    {
      key: foodMasterKey('g01', 'traditional', 'Coffee'),
      slabs: [{ from: 1, to: 25, price: 20 }],
    },
  ];
  return specs
    .map(function (spec) {
      const hit = findMasterItem(spec.key);
      if (!hit) return null;
      return {
        id: 'food-' + spec.key.replace(/::/g, '-'),
        masterKey: spec.key,
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
        individualListing: true,
        slabs: spec.slabs || defaultItemSlabs(),
        imageEmoji: hit.module.emoji,
      };
    })
    .filter(Boolean);
}

