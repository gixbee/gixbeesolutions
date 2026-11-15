/** All-India decoration catalogue — 14 categories for packages & individual services. */
const DECORATION_PKG_LEVELS = ['Basic', 'Standard', 'Premium'];
const DECORATION_EVENT_CATEGORIES = [
  { id: 'wedding', label: 'Wedding & Related Functions', hint: 'Wedding, Engagement, Reception, Haldi, Mehendi, Nikah, Walima & more' },
  { id: 'other', label: 'Other Functions', hint: 'Birthday, Housewarming, Corporate, Baptism, Navjote & more' },
];
const DECORATION_EVENT_TYPES = {
  wedding: ['Wedding','Engagement','Reception','Haldi','Mehendi / Mailanchi','Sangeet','Nikah','Walima','Betrothal','Roka','Chunni Ceremony','Anand Karaj','Bridal Shower','Wedding Eve','Pre-wedding','Post-wedding','Other wedding functions'],
  other: ['Birthday','First Birthday','Baby Shower','Naming Ceremony','Baptism','First Holy Communion','Confirmation','Housewarming','Anniversary','Retirement','Inauguration','Corporate Event','Cultural Event','Festival Celebration','Navjote','Other'],
};
const DECORATION_TRADITIONS = ['Hindu','Muslim','Christian','Others'];
const DECORATION_STYLES = ['Traditional','Modern','Floral','Royal','Minimal','Luxury','Theme Based','Custom'];
const DECORATION_CEREMONY_SETUP = ['Traditional Mandapam','Church Ceremony Setup','Nikah Setup','Reception Stage','Engagement Stage','General Stage','Custom'];
const DECORATION_UNITS = ['Per Event','Per Set','Per Unit','Per Item','Per Hour','Custom Quotation'];
const DECORATION_GST = ['Included','Additional','Not Applicable'];

const DECORATION_CATALOG_DEFS = [
  {
    "id": "d01",
    "name": "Stage / Mandapam",
    "emoji": "\ud83c\udfaa",
    "items": [
          "Wedding Stage Backdrop (Fabric)",
          "Wedding Stage Backdrop (LED)",
          "Traditional Wooden Mandapam",
          "Floral Mandapam",
          "Crystal / Acrylic Stage Arch",
          "Stage Carpet / Runners",
          "Stage Steps with Floral Trim",
          "Couple Throne / Stage Seating",
          "Name Board / LED Monogram",
          "Reception Stage (Full Setup)",
          "Engagement Stage",
          "Nikah Stage & Seating",
          "Church-Style Floral Altar Backdrop",
          "Sangeet / Mehendi Stage",
          "Haldi Ceremony Stage Setup",
          "Minimal Stage (Corporate)",
          "Outdoor Stage Canopy Frame",
          "Stage Side Pillars (Floral)",
          "LED Wall Backdrop",
          "Photo-Frame Stage Panel"
    ],
  },
  {
    "id": "d02",
    "name": "Entrance & Welcome",
    "emoji": "\ud83d\udeaa",
    "items": [
          "Floral Entrance Arch",
          "Balloon Entrance Arch",
          "Fabric Drape Entrance",
          "Welcome Board (Printed)",
          "LED Welcome Sign",
          "Couple Name Entrance Board",
          "Direction / Parking Signage",
          "Floral Entrance Pillars (Pair)",
          "Welcome Table Arrangement",
          "Entrance Red Carpet",
          "Traditional Toran / Main Door Décor",
          "Nikah Entrance Arch",
          "Church Entrance Floral Arch",
          "Gate / Compound Entrance Draping",
          "Photo Welcome Stand",
          "Guest Registration Desk Décor",
          "Entrance Fairy Light Tunnel",
          "Marquee Entrance Framing"
    ],
  },
  {
    "id": "d03",
    "name": "Pathway Decoration",
    "emoji": "\ud83d\udee4\ufe0f",
    "items": [
          "Central Aisle Red Carpet",
          "White / Ivory Aisle Carpet",
          "Floral Aisle Markers",
          "Petal Pathway",
          "Candle Aisle (Indoor)",
          "Outdoor Walkway Lanterns",
          "Garden Pathway Urns",
          "Mandapam Walkway Draping",
          "Church Pew Aisle Flowers",
          "Reception Entry Path Lights",
          "Bridal Entry Path (Traditional)",
          "Royal Carpet with Borders",
          "Mirror / Reflective Aisle Panels",
          "Outdoor Tent Walkway"
    ],
  },
  {
    "id": "d04",
    "name": "Floral Decoration",
    "emoji": "\ud83d\udc90",
    "items": [
          "Fresh Flower Ceiling Hangings",
          "Artificial Flower Ceiling",
          "Marigold Garlands (Bulk)",
          "Jasmine / Malli Strings",
          "Rose Floral Walls",
          "Mixed South Indian Flower Arrangements",
          "North Indian Floral Backdrop",
          "Orchid & Exotic Flower Décor",
          "Pooja Room Floral Setup",
          "Centre Table Floral (Reception)",
          "Haldi Marigold Setup",
          "Church Altar Flowers",
          "Bridal Car Flower Garland (Separate)",
          "Garland for Mala / Exchange",
          "Floral Pillars (Indoor)",
          "Wedding Eve Floral Installations",
          "Baby Shower Floral Corner",
          "Corporate Floral Branding",
          "Hanging Floral Chandeliers",
          "Tropical Flower Theme (Goa / Coastal)"
    ],
  },
  {
    "id": "d05",
    "name": "Lighting & Sound",
    "emoji": "\ud83d\udca1",
    "items": [
          "Fairy / String Lights (Warm)",
          "LED Strip Lighting",
          "Par / Focus Lights for Stage",
          "Moving Head Lights",
          "Uplighters (Wall Wash)",
          "Outdoor Flood Lights",
          "Chandeliers (Rental)",
          "Pathway Bollard Lights",
          "Sound System (Basic PA)",
          "Sound System (Reception / DJ Ready)",
          "Wireless Microphones",
          "LED Dance Floor Lighting",
          "Name GOBO Projection",
          "Stage Truss Lighting",
          "Emergency Backup Lighting",
          "Generator / Power Distribution (Decorator)"
    ],
  },
  {
    "id": "d06",
    "name": "Seating & Furniture",
    "emoji": "\ud83e\ude91",
    "items": [
          "Couple Sofa (White)",
          "Couple Diwan / Traditional Seating",
          "Royal Chairs (Pair)",
          "Guest Plastic / Banquet Chairs",
          "Chiavari Chairs",
          "Cushions & Covers",
          "VIP Seating Section",
          "Mehendi Low Seating",
          "Sangeet Stage Seating",
          "Bridal Green Room Sofa",
          "Bench Seating (Outdoor)",
          "Traditional Wooden Chairs",
          "Hospitality Counter Table",
          "Side Tables (Stage)"
    ],
  },
  {
    "id": "d07",
    "name": "Dining & Table",
    "emoji": "\ud83c\udf7d\ufe0f",
    "items": [
          "Buffet Table Skirting & Décor",
          "Dessert Counter Décor",
          "Cake Table Setup",
          "Welcome Drink Counter",
          "Table Centrepieces",
          "Table Runners & Linen",
          "Chair Bow / Sash Decoration",
          "Menu Display Board",
          "Live Counter Framing",
          "Corporate Buffet Branding",
          "South Indian Banana Leaf Station Décor",
          "High-Tea Table Styling"
    ],
  },
  {
    "id": "d08",
    "name": "Photo & Display",
    "emoji": "\ud83d\udcf8",
    "items": [
          "Photo Booth Backdrop",
          "Selfie Point / Ring Light",
          "Couple Portrait Backdrop",
          "Family Photo Wall",
          "Polaroid / Guest Message Wall",
          "Hashtag LED Board",
          "Memory Lane Photo Line",
          "Instagram Frame Prop",
          "360° Spin Booth Space Décor",
          "Baby Shower Photo Corner",
          "Corporate Step-and-Repeat",
          "Gift Display Table"
    ],
  },
  {
    "id": "d09",
    "name": "Special Effects",
    "emoji": "\u2728",
    "items": [
          "Cold Pyro / Cold Fire (Permit Required)",
          "Low-Lying Fog",
          "Smoke Machine",
          "Confetti Blast",
          "CO₂ Jet Effects",
          "Bubble Machine",
          "Projection Mapping (Basic)",
          "Drone Show Coordination (Third Party)",
          "Fireworks Synchronization (Where Permitted)",
          "Sparkler Entry Package",
          "Indoor Safe Confetti"
    ],
  },
  {
    "id": "d10",
    "name": "Vehicle & Personal Flowers",
    "emoji": "\ud83d\ude97",
    "items": [
          "Wedding Car Floral Decoration (Full)",
          "Wedding Car Bonnet Garland",
          "Car Door Floral Handles",
          "Car Roof Floral (South Indian Style)",
          "Luxury Car Décor (Premium Flowers)",
          "Vintage Car Flower Drape",
          "Bike / Two-Wheeler Wedding Décor",
          "Car Ribbon & Bow Package",
          "Bridal Bouquet (Hand-Tied)",
          "Bridal Bouquet (Cascading)",
          "Bridesmaid Bouquets",
          "Boutonniere (Groom)",
          "Boutonniere (Groomsmen Set)",
          "Mother / Family Corsage",
          "Flower Basket (Petal Shower)",
          "Garland for Groom Entry",
          "Marigold Car Toran",
          "Christian Bridal Bouquet (White Roses)",
          "Muslim Groom Flower Pin",
          "Reception Car Send-Off Décor",
          "Corporate Guest Welcome Bouquet",
          "Housewarming Door Flower Hangings"
    ],
  },
  {
    "id": "d11",
    "name": "Traditional / Ceremony Setup",
    "emoji": "\ud83e\ude94",
    "items": [
          "Banana Stem Traditional Mandapam Elements",
          "Mango Leaf Thoranam",
          "Coconut Leaf Toran",
          "Nilavilakku / Brass Lamps (Set)",
          "Kalash & Traditional Vessels",
          "Pooja Backdrop (Traditional)",
          "Pookalam / Rangoli Support Décor",
          "Haldi Plate & Seating Corner",
          "Mehendi / Mailanchi Seating Décor",
          "Nikah Signing Table Setup",
          "Islamic Geometric Backdrop Panel",
          "Walima Stage Floral (Green / Gold Theme)",
          "Church Pew Ends & Altar Florals",
          "Baptism / Communion Backdrop",
          "Anand Karaj Floral (Gurdwara Approved)",
          "Navjote Traditional Setup Elements",
          "Roka / Engagement Traditional Platform",
          "Chunni Ceremony Seating",
          "Jain Minimal Mandap Elements",
          "Interfaith Neutral Ceremony Backdrop"
    ],
  },
  {
    "id": "d12",
    "name": "Other Items",
    "emoji": "\ud83d\udce6",
    "items": [
          "Ceiling Draping (Full Hall)",
          "Wall Draping / Masking",
          "Pillar Wrapping",
          "Partition Screens",
          "Home Décor (Housewarming)",
          "Garden / Lawn Tent Décor",
          "Weather Protection Sidewalls",
          "Green Room Makeover",
          "Signage Package (Event)",
          "Custom Theme Props",
          "Balloon Ceiling",
          "Kids Birthday Balloon Arch",
          "Corporate Stage Branding",
          "Festival Ganesh / Onam Installations",
          "Repairs & Touch-Up Kit (Day Of)"
    ],
  },
];

function buildDecorationModules() {
  return DECORATION_CATALOG_DEFS.map(function (m, idx) {
    const items = (m.items || []).map(function (name) {
      return {
        id: m.id + '::' + String(name).toLowerCase().replace(/[^a-z0-9]+/g, '-').slice(0, 48),
        name: name,
      };
    });
    return { id: m.id, num: idx + 1, name: m.name, emoji: m.emoji, items: items };
  });
}
const DECORATION_MODULES = buildDecorationModules();

function findDecorationModule(moduleId) {
  return DECORATION_MODULES.find(function (m) { return m.id === moduleId; });
}

function defaultDecorationStore() {
  return {
    hubTab: 'packages',
    pkgFilter: 'all',
    pkgCategoryFilter: 'wedding',
    pkgSort: 'name',
    pkgSearch: '',
    catPackages: [],
    individualServices: [],
  };
}

