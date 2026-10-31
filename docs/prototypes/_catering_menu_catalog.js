/** Fixed 13-module catering catalogue — generated from gixbee-catering-almostfinal.docx */
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
  if (/\begg\b/.test(nm) && !/vegetable/.test(nm)) return 'non_veg';
  if (
    sc.indexOf('non-vegetarian') >= 0 ||
    sc.indexOf('non vegetarian') >= 0 ||
    sc.indexOf('chicken & meat') >= 0 ||
    sc.indexOf('chicken dishes') >= 0 ||
    sc.indexOf('mutton') >= 0 ||
    sc.indexOf('beef') >= 0 ||
    sc.indexOf('fish & seafood') >= 0 ||
    sc.indexOf('seafood') >= 0 ||
    sc.indexOf('grill') >= 0
  ) {
    return 'non_veg';
  }
  if (/\b(chicken|mutton|beef|prawn|fish|crab|lobster|squid|seafood|chemmeen)\b/.test(nm)) return 'non_veg';
  if (sc.indexOf('paneer & egg') >= 0 && /\begg\b/.test(nm)) return 'non_veg';
  if (sc.indexOf('vegetarian') >= 0) return 'veg';
  return 'veg';
}

/** @type {Array<{id:string,name:string,emoji:string,subcats:Array<{id:string,name:string,items:string[]}>}>} */
const CATERING_CATALOG_DEFS = 
[
  {
    "id": "m01",
    "name": "Welcome Drinks",
    "emoji": "🥤",
    "subcats": [
      {
        "id": "juices-fresh-drinks",
        "name": "Juices & Fresh Drinks",
        "items": [
          "Fresh Lime Juice",
          "Lemon Mint Juice",
          "Orange Juice",
          "Watermelon Juice",
          "Pineapple Juice",
          "Mango Juice",
          "Grape Juice",
          "Apple Juice",
          "Mixed Fruit Juice",
          "Tender Coconut Water"
        ]
      },
      {
        "id": "traditional-dairy-drinks",
        "name": "Traditional & Dairy Drinks",
        "items": [
          "Sambharam / Spiced Buttermilk",
          "Plain Buttermilk",
          "Rose Milk",
          "Badam Milk",
          "Pista Milk",
          "Cold Coffee",
          "Tea",
          "Coffee"
        ]
      },
      {
        "id": "cold-special-drinks",
        "name": "Cold & Special Drinks",
        "items": [
          "Soft Drinks",
          "Packaged Fruit Drinks",
          "Mocktails",
          "Smoothies",
          "Milkshakes",
          "Mojito (Non-Alcoholic)",
          "Iced Tea",
          "Flavoured Water",
          "Mineral Water"
        ]
      }
    ]
  },
  {
    "id": "m02",
    "name": "Starters & Snacks",
    "emoji": "🥟",
    "subcats": [
      {
        "id": "vegetarian-snacks",
        "name": "Vegetarian Snacks",
        "items": [
          "Vegetable Cutlet",
          "Paneer Cutlet",
          "Samosa",
          "Vegetable Spring Roll",
          "Veg Pakoda",
          "Onion Pakoda",
          "Gobi 65",
          "Chilli Gobi",
          "Paneer Tikka",
          "Baby Corn Fry",
          "French Fries",
          "Potato Wedges",
          "Cheese Balls",
          "Veg Fingers"
        ]
      },
      {
        "id": "non-vegetarian-snacks",
        "name": "Non-Vegetarian Snacks",
        "items": [
          "Chicken Cutlet",
          "Chicken 65",
          "Chilli Chicken",
          "Chicken Lollipop",
          "Chicken Fry",
          "Chicken Tikka",
          "Chicken Kebab",
          "Chicken Pakoda",
          "Fish Fingers",
          "Fish Cutlet",
          "Fish Fry Bites",
          "Prawn Fry",
          "Prawn Tempura",
          "Beef Cutlet",
          "Mutton Kebab",
          "Egg Pakoda"
        ]
      },
      {
        "id": "kerala-tea-time-snacks",
        "name": "Kerala & Tea-Time Snacks",
        "items": [
          "Pazham Pori",
          "Unniyappam",
          "Sukhiyan",
          "Parippu Vada",
          "Uzhunnu Vada",
          "Ela Ada",
          "Kozhukatta",
          "Neyyappam",
          "Achappam",
          "Kuzhalappam",
          "Kallappam Bites",
          "Banana Fritters"
        ]
      },
      {
        "id": "other-snack-types",
        "name": "Other Snack Types",
        "items": [
          "Patties",
          "Puffs",
          "Sandwiches",
          "Rolls",
          "Wraps",
          "Mini Burgers",
          "Finger Foods",
          "Chaat Items",
          "Kids' Snacks"
        ]
      }
    ]
  },
  {
    "id": "m03",
    "name": "Salads",
    "emoji": "🥗",
    "subcats": [
      {
        "id": "fresh-vegetable-salads",
        "name": "Fresh & Vegetable Salads",
        "items": [
          "Green Salad",
          "Cucumber Salad",
          "Onion Salad",
          "Tomato Salad",
          "Carrot Salad",
          "Beetroot Salad",
          "Cabbage Salad",
          "Corn Salad",
          "Sprout Salad",
          "Crispy Vegetable Salad"
        ]
      },
      {
        "id": "fruit-specialty-salads",
        "name": "Fruit & Specialty Salads",
        "items": [
          "Fresh Fruit Salad",
          "Creamy Fruit Salad",
          "Pineapple Salad",
          "Apple Salad",
          "Russian Salad",
          "Coleslaw",
          "Pasta Salad",
          "Macaroni Salad",
          "Potato Salad",
          "Mayonnaise Salad"
        ]
      },
      {
        "id": "yogurt-based",
        "name": "Yogurt-Based",
        "items": [
          "Plain Curd",
          "Cucumber Raita",
          "Boondi Raita",
          "Mixed Vegetable Raita",
          "Pineapple Raita",
          "Specialty Raita"
        ]
      }
    ]
  },
  {
    "id": "m04",
    "name": "Soups",
    "emoji": "🍲",
    "subcats": [
      {
        "id": "vegetarian-soups",
        "name": "Vegetarian Soups",
        "items": [
          "Tomato Soup",
          "Sweet Corn Vegetable Soup",
          "Hot and Sour Vegetable Soup",
          "Manchow Vegetable Soup",
          "Clear Vegetable Soup",
          "Cream of Mushroom Soup",
          "Cream of Tomato Soup",
          "Vegetable Noodle Soup",
          "Lentil Soup"
        ]
      },
      {
        "id": "non-vegetarian-soups",
        "name": "Non-Vegetarian Soups",
        "items": [
          "Chicken Clear Soup",
          "Chicken Sweet Corn Soup",
          "Chicken Hot and Sour Soup",
          "Chicken Manchow Soup",
          "Cream of Chicken Soup",
          "Seafood Soup",
          "Prawn Soup",
          "Fish Soup"
        ]
      },
      {
        "id": "specialty",
        "name": "Specialty",
        "items": [
          "Pepper Soup",
          "Mulligatawny Soup"
        ]
      }
    ]
  },
  {
    "id": "m05",
    "name": "Sadhya",
    "emoji": "🍛",
    "subcats": [
      {
        "id": "rice-dal",
        "name": "Rice & Dal",
        "items": [
          "Kerala Matta Rice",
          "Parippu Curry",
          "Ghee",
          "Sambar",
          "Rasam",
          "Pulissery",
          "Moru Curry"
        ]
      },
      {
        "id": "vegetable-dishes",
        "name": "Vegetable Dishes",
        "items": [
          "Avial",
          "Thoran",
          "Olan",
          "Kalan",
          "Erissery",
          "Koottu Curry",
          "Mezhukkupuratti",
          "Theeyal",
          "Cabbage Thoran",
          "Beans Thoran",
          "Pumpkin Erissery"
        ]
      },
      {
        "id": "pachadi-pickles",
        "name": "Pachadi & Pickles",
        "items": [
          "Pineapple Pachadi",
          "Beetroot Pachadi",
          "Cucumber Pachadi",
          "Pineapple Kichadi",
          "Beetroot Kichadi",
          "Inji Curry",
          "Puli Inji",
          "Mango Pickle",
          "Lime Pickle"
        ]
      },
      {
        "id": "crunchy-sides-desserts",
        "name": "Crunchy Sides & Desserts",
        "items": [
          "Pappadam",
          "Banana Chips",
          "Sharkara Upperi",
          "Upperi",
          "Ada Pradhaman",
          "Palada Payasam",
          "Parippu Payasam",
          "Paal Payasam",
          "Semiya Payasam",
          "Chakka Pradhaman"
        ]
      },
      {
        "id": "sadhya-packages",
        "name": "Sadhya Packages",
        "items": [
          "Kerala Sadhya",
          "Wedding Sadhya",
          "Vegetarian Sadhya",
          "Special Sadhya",
          "Banana Leaf Sadhya",
          "Festival Sadhya"
        ]
      }
    ]
  },
  {
    "id": "m06",
    "name": "Biriyani",
    "emoji": "🍚",
    "subcats": [
      {
        "id": "chicken-meat",
        "name": "Chicken & Meat",
        "items": [
          "Chicken Biriyani",
          "Mutton Biriyani",
          "Beef Biriyani",
          "Egg Biriyani"
        ]
      },
      {
        "id": "vegetarian",
        "name": "Vegetarian",
        "items": [
          "Vegetable Biriyani",
          "Paneer Biriyani",
          "Mushroom Biriyani"
        ]
      },
      {
        "id": "seafood",
        "name": "Seafood",
        "items": [
          "Fish Biriyani",
          "Prawn / Chemmeen Biriyani",
          "Seafood Biriyani"
        ]
      },
      {
        "id": "regional-styles",
        "name": "Regional & Styles",
        "items": [
          "Malabar Biriyani",
          "Thalassery Biriyani",
          "Kozhikode Biriyani",
          "Hyderabadi Biriyani",
          "Kacchi Biriyani",
          "Dum Biriyani",
          "Special Dum Biriyani",
          "Kaima / Jeerakasala Rice Biriyani"
        ]
      },
      {
        "id": "common-sides-optional",
        "name": "Common Sides (optional)",
        "items": [
          "Raita",
          "Pickle",
          "Pappadam",
          "Chammanthi",
          "Boiled Egg"
        ]
      }
    ]
  },
  {
    "id": "m07",
    "name": "Arabian",
    "emoji": "🧆",
    "subcats": [
      {
        "id": "rice-mandi",
        "name": "Rice & Mandi",
        "items": [
          "Chicken Mandi",
          "Al Faham Mandi",
          "Mutton Mandi",
          "Beef Mandi",
          "Fish Mandi",
          "Prawn Mandi",
          "Vegetable Mandi",
          "Kuzhi Mandi",
          "Arabic Rice"
        ]
      },
      {
        "id": "grilled-roasted",
        "name": "Grilled & Roasted",
        "items": [
          "Al Faham Chicken",
          "Shawaya / Shawarma Chicken",
          "Grilled Chicken",
          "Madhbi Chicken",
          "Madfoon",
          "Kabsa Chicken",
          "Peri-Peri Chicken",
          "Mixed Grill"
        ]
      },
      {
        "id": "wraps-sides",
        "name": "Wraps & Sides",
        "items": [
          "Shawarma Roll",
          "Shawarma Plate",
          "Hummus",
          "Mutabbal",
          "Pita Bread",
          "Garlic Sauce",
          "Arabic Salad",
          "French Fries"
        ]
      },
      {
        "id": "combos",
        "name": "Combos",
        "items": [
          "Half Chicken Combo",
          "Full Chicken Combo",
          "Family Mandi Combo"
        ]
      }
    ]
  },
  {
    "id": "m08",
    "name": "Main Course",
    "emoji": "🍽️",
    "subcats": [
      {
        "id": "chicken-dishes",
        "name": "Chicken Dishes",
        "items": [
          "Chicken Roast",
          "Chicken Kondattam",
          "Chicken Pepper Fry",
          "Butter Chicken",
          "Chicken Tikka Masala",
          "Chilli Chicken",
          "Chicken Stew",
          "Chicken Kurma",
          "Chicken Varutharacha Curry"
        ]
      },
      {
        "id": "mutton-beef",
        "name": "Mutton & Beef",
        "items": [
          "Mutton Roast",
          "Mutton Kurma",
          "Mutton Pepper Fry",
          "Beef Roast",
          "Beef Ularthiyathu",
          "Beef Fry",
          "Beef Curry"
        ]
      },
      {
        "id": "fish-seafood",
        "name": "Fish & Seafood",
        "items": [
          "Fish Fry",
          "Fish Molee",
          "Fish Pollichathu",
          "Fish Masala",
          "Prawn Roast",
          "Prawn Masala",
          "Crab Roast",
          "Squid Roast",
          "Mussels Roast"
        ]
      },
      {
        "id": "vegetarian-paneer",
        "name": "Vegetarian & Paneer",
        "items": [
          "Vegetable Kurma",
          "Paneer Butter Masala",
          "Kadai Paneer",
          "Palak Paneer",
          "Mushroom Masala",
          "Mixed Vegetable Curry",
          "Dal Tadka",
          "Chana Masala"
        ]
      },
      {
        "id": "rice-noodles",
        "name": "Rice & Noodles",
        "items": [
          "Steamed Rice",
          "Ghee Rice",
          "Jeera Rice",
          "Vegetable Pulao",
          "Fried Rice",
          "Chicken Fried Rice",
          "Egg Fried Rice",
          "Noodles",
          "Pasta"
        ]
      },
      {
        "id": "other",
        "name": "Other",
        "items": [
          "Regional Speciality",
          "Chef's Special"
        ]
      }
    ]
  },
  {
    "id": "m09",
    "name": "Curries & Gravies",
    "emoji": "🥘",
    "subcats": [
      {
        "id": "vegetarian-curries",
        "name": "Vegetarian Curries",
        "items": [
          "Vegetable Curry",
          "Vegetable Kurma",
          "Mixed Vegetable Curry",
          "Avial",
          "Sambar",
          "Rasam",
          "Dal Curry",
          "Dal Tadka",
          "Chana Masala",
          "Green Peas Curry",
          "Mushroom Curry"
        ]
      },
      {
        "id": "regional-specialty",
        "name": "Regional & Specialty",
        "items": [
          "Theeyal",
          "Pulissery",
          "Moru Curry",
          "Kalan",
          "Salna",
          "Pepper Gravy",
          "Chef's Special Curry"
        ]
      },
      {
        "id": "paneer-egg",
        "name": "Paneer & Egg",
        "items": [
          "Paneer Butter Masala",
          "Kadai Paneer",
          "Palak Paneer",
          "Egg Curry",
          "Egg Roast",
          "Egg Masala"
        ]
      },
      {
        "id": "chicken-meat",
        "name": "Chicken & Meat",
        "items": [
          "Chicken Curry",
          "Chicken Roast Gravy",
          "Butter Chicken Gravy",
          "Chicken Kurma",
          "Mutton Curry",
          "Mutton Kurma",
          "Beef Curry",
          "Beef Roast Gravy"
        ]
      },
      {
        "id": "fish-seafood",
        "name": "Fish & Seafood",
        "items": [
          "Kerala Fish Curry",
          "Fish Molee",
          "Fish Masala",
          "Prawn Curry",
          "Prawn Masala",
          "Crab Curry",
          "Lobster Curry",
          "Kallumakkaya (Mussels) Curry",
          "Squid Curry",
          "Seafood Curry"
        ]
      }
    ]
  },
  {
    "id": "m10",
    "name": "Accompaniments",
    "emoji": "🥙",
    "subcats": [
      {
        "id": "chutneys-chammanthi",
        "name": "Chutneys & Chammanthi",
        "items": [
          "Coconut Chammanthi",
          "Puthina Chutney",
          "Tomato Chutney",
          "Mulaku Chutney",
          "Podi Chutney",
          "Edi Chammanthi",
          "Chemmeen Chammanthi",
          "Chemmeen Podi",
          "Fish Chutney"
        ]
      },
      {
        "id": "pickles",
        "name": "Pickles",
        "items": [
          "Mango Pickle",
          "Lime Pickle",
          "Mixed Pickle",
          "Green Chilli Pickle",
          "Uppilithathu",
          "Vattal Mulaku"
        ]
      },
      {
        "id": "salads-curd-pachadi",
        "name": "Salads, Curd & Pachadi",
        "items": [
          "Curd",
          "Raita",
          "Vinegar Salad",
          "Cucumber Salad",
          "Onion Salad",
          "Green Salad",
          "Beetroot Salad",
          "Carrot Salad",
          "Pineapple Pachadi",
          "Beetroot Pachadi",
          "Cucumber Pachadi"
        ]
      },
      {
        "id": "pappadam-crunchy-sides",
        "name": "Pappadam & Crunchy Sides",
        "items": [
          "Pappadam",
          "Banana Chips",
          "Sharkara Upperi",
          "Fried Chilli"
        ]
      },
      {
        "id": "sauces-condiments",
        "name": "Sauces & Condiments",
        "items": [
          "Garlic Sauce",
          "Mayonnaise",
          "Ketchup",
          "Salsa",
          "Aioli",
          "Mint Sauce",
          "Chilli Sauce",
          "Mustard Sauce"
        ]
      },
      {
        "id": "traditional-sides",
        "name": "Traditional Sides",
        "items": [
          "Thoran",
          "Mezhukkupuratti",
          "Olan",
          "Kalan",
          "Erissery",
          "Koottu Curry",
          "Inji Curry",
          "Puli Inji",
          "Salna"
        ]
      }
    ]
  },
  {
    "id": "m11",
    "name": "Special Live Counters",
    "emoji": "🔥",
    "subcats": [
      {
        "id": "kerala-live-counters",
        "name": "Kerala Live Counters",
        "items": [
          "Thattukada",
          "Appam Counter",
          "Dosa Counter",
          "Idiyappam Counter",
          "Puttu Counter",
          "Kallappam Counter",
          "Pathiri Counter",
          "Porotta Counter",
          "Kallumakkaya Counter"
        ]
      },
      {
        "id": "grill-hot-food",
        "name": "Grill & Hot Food",
        "items": [
          "Al Faham Counter",
          "BBQ Counter",
          "Tandoori Counter",
          "Shawarma Counter",
          "Live Biriyani Counter",
          "Noodles Counter",
          "Pasta Counter",
          "Pizza Counter",
          "Burger Counter",
          "Sandwich Counter",
          "Bread Counter"
        ]
      },
      {
        "id": "street-food-snacks",
        "name": "Street Food & Snacks",
        "items": [
          "Pani Puri Counter",
          "Chaat Counter",
          "Jalebi Counter",
          "Popcorn Counter",
          "French Fries Counter",
          "Live Fry Counter"
        ]
      },
      {
        "id": "dessert-beverage-counters",
        "name": "Dessert & Beverage Counters",
        "items": [
          "Chocolate Fountain",
          "Ice Cream Scooping",
          "Kulfi Counter",
          "Falooda Counter",
          "Waffle Counter",
          "Pancake Counter",
          "Milkshake Bar",
          "Mojito Bar (Non-Alcoholic)",
          "Coffee Bar",
          "Samavar Tea Counter"
        ]
      }
    ]
  },
  {
    "id": "m12",
    "name": "Breads & Rotis",
    "emoji": "🫓",
    "subcats": [
      {
        "id": "indian-breads",
        "name": "Indian Breads",
        "items": [
          "Chapati",
          "Phulka",
          "Roti",
          "Tandoori Roti",
          "Rumali Roti",
          "Naan",
          "Butter Naan",
          "Garlic Naan",
          "Kulcha",
          "Butter Kulcha"
        ]
      },
      {
        "id": "kerala-breads",
        "name": "Kerala Breads",
        "items": [
          "Porotta",
          "Malabar Porotta",
          "Coin Porotta",
          "Pathiri",
          "Appam",
          "Kallappam",
          "Idiyappam",
          "Puttu",
          "Vattayappam"
        ]
      },
      {
        "id": "other-breads",
        "name": "Other Breads",
        "items": [
          "Pita Bread",
          "Dinner Rolls",
          "Bread Slices",
          "Pav",
          "Specialty Bread"
        ]
      }
    ]
  },
  {
    "id": "m13",
    "name": "Desserts & Sweets",
    "emoji": "🍮",
    "subcats": [
      {
        "id": "payasam-pradhaman",
        "name": "Payasam & Pradhaman",
        "items": [
          "Ada Pradhaman",
          "Palada Payasam",
          "Semiya Payasam",
          "Parippu Payasam",
          "Paal Payasam",
          "Carrot Payasam",
          "Pineapple Payasam",
          "Chakka Pradhaman",
          "Gothambu Payasam",
          "Dates Payasam"
        ]
      },
      {
        "id": "traditional-sweets",
        "name": "Traditional Sweets",
        "items": [
          "Gulab Jamun",
          "Rasmalai",
          "Jalebi",
          "Laddu",
          "Mysore Pak",
          "Halwa",
          "Mithai",
          "Unniyappam",
          "Neyyappam"
        ]
      },
      {
        "id": "puddings-chilled-desserts",
        "name": "Puddings & Chilled Desserts",
        "items": [
          "Caramel Custard",
          "Chocolate Pudding",
          "Fruit Pudding",
          "Jelly",
          "Falooda",
          "Cassata",
          "Ice Cream",
          "Kulfi",
          "Fruit Salad",
          "Fresh Fruit Platter"
        ]
      },
      {
        "id": "cakes-baked-desserts",
        "name": "Cakes & Baked Desserts",
        "items": [
          "Cake",
          "Cheesecake",
          "Brownie",
          "Chocolate Mousse",
          "Pastry",
          "Tart",
          "Cookies",
          "Cupcakes",
          "Waffles",
          "Pancakes"
        ]
      },
      {
        "id": "specialty",
        "name": "Specialty",
        "items": [
          "Kids' Special Dessert",
          "Seasonal Dessert",
          "Chef's Special Dessert"
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
      key: foodMasterKey('m06', 'chicken-meat', 'Chicken Biriyani'),
      slabs: [
        { from: 1, to: 25, price: 200 },
        { from: 26, to: 50, price: 180 },
        { from: 51, to: 100, price: 165 },
      ],
    },
    {
      key: foodMasterKey('m07', 'grilled-roasted', 'Al Faham Chicken'),
      slabs: [
        { from: 1, to: 25, price: 220 },
        { from: 26, to: 50, price: 200 },
      ],
    },
    {
      key: foodMasterKey('m01', 'traditional-dairy-drinks', 'Tea'),
      slabs: [{ from: 1, to: 25, price: 15 }],
    },
    {
      key: foodMasterKey('m01', 'traditional-dairy-drinks', 'Coffee'),
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

