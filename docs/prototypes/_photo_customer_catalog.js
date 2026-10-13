/** Customer-facing catalog — mirrors owner package/service wizard fields (demo data). */
const CUSTOMER_CATALOG = {
  blue: {
    id: 'blue',
    name: 'Blue Lens Studio',
    tagline: 'Sakthan Nagar, Thrissur',
    rating: 4.8,
    reviews: 56,
    km: 5,
    years: '5+',
    events: '200+',
    team: 'Professional Team',
    about:
      'Blue Lens Studio specialises in Christian and inter-faith weddings across Pathanamthitta and Kottayam. We deliver candid storytelling, traditional coverage, and cinematic films with clear deliverable timelines.',
    areas: ['Pathanamthitta', 'Kottayam', 'Ranni', 'Thiruvalla'],
    weddingFrom: 65000,
    serviceFrom: 8000,
    packages: [
      {
        id: 'basic',
        name: 'Basic Wedding Package',
        level: 'Basic',
        ceremonies: ['Christian', 'Hindu'],
        functions: ['Wedding & Reception'],
        price: 65000,
        listPrice: 65000,
        discountPct: 0,
        cardBullets: ['300 edited photos', '1 candid photographer', 'Online gallery', '8×8 album (20 pages)'],
        inclusions: [
          '300 edited high-resolution photos',
          '1 candid photographer (8 hours)',
          'Online gallery (password protected)',
          '8×8 flush-mount album · 20 pages',
          'Basic colour correction',
          'Travel within 25 km of Thrissur',
        ],
        coverage: [
          {
            fn: 'Wedding & Reception',
            side: 'Both',
            hours: 8,
            extraHour: 2000,
            photoTeam: '1 Candid Photographer',
            videoTeam: '—',
          },
        ],
        delivery: [
          { item: 'Online gallery', timeline: '7 days after event' },
          { item: 'Edited photos (full set)', timeline: '21 days' },
          { item: 'Album design proof', timeline: '30 days' },
          { item: 'Printed album', timeline: '45 days' },
        ],
        extras: [
          { id: 'drone', label: 'Drone photography', price: 10000 },
          { id: 'cine', label: 'Cinematography (highlight film)', price: 15000 },
          { id: 'live', label: 'Live streaming', price: 8000, cameras: 2 },
          { id: 'album-extra', label: 'Extra parent album copy', price: 5000 },
        ],
        paymentStages: [
          { label: 'Booking advance', pct: 30 },
          { label: 'Before event', pct: 40 },
          { label: 'On delivery of gallery', pct: 20 },
          { label: 'Final (album)', pct: 10 },
        ],
        optionalFunctions: ['Engagement', 'Reception only', 'Wedding Eve'],
      },
      {
        id: 'standard',
        name: 'Standard Wedding Package',
        level: 'Standard',
        ceremonies: ['Christian'],
        functions: ['Wedding & Reception', 'Reception'],
        price: 90000,
        listPrice: 100000,
        discountPct: 10,
        cardBullets: [
          '500 edited photos',
          '2 photographers',
          '12×12 album (30 pages)',
          'Pre-wedding shoot (4 hrs)',
        ],
        inclusions: [
          '500 edited photos',
          '2 candid photographers',
          'Pre-wedding shoot · 4 hours · 80 edited photos',
          '12×12 album · 30 pages',
          'Wedding highlight film · 8–10 min',
          'Online gallery + download',
          'Photo selection app for album',
        ],
        coverage: [
          {
            fn: 'Wedding & Reception',
            side: 'Both',
            hours: 10,
            extraHour: 2500,
            photoTeam: 'Candid + Traditional Photographer',
            videoTeam: '1 Cinematic Videographer',
          },
          {
            fn: 'Reception',
            side: 'Single',
            hours: 5,
            extraHour: 2000,
            photoTeam: '2 Candid Photographers',
            videoTeam: '—',
          },
        ],
        delivery: [
          { item: 'Pre-wedding gallery', timeline: '5 days after shoot' },
          { item: 'Wedding online gallery', timeline: '10 days' },
          { item: 'Highlight film', timeline: '21 days' },
          { item: 'Album print', timeline: '50 days' },
        ],
        extras: [
          { id: 'drone', label: 'Drone photography', price: 10000 },
          { id: 'cine', label: 'Full ceremony film', price: 18000 },
          { id: 'live', label: 'Live streaming (2 cameras)', price: 8000 },
          { id: 'album-extra', label: 'Extra album copy', price: 5500 },
        ],
        paymentStages: [
          { label: 'Booking advance', pct: 25 },
          { label: 'Before wedding', pct: 45 },
          { label: 'After gallery delivery', pct: 20 },
          { label: 'Final payment', pct: 10 },
        ],
        optionalFunctions: ['Engagement', 'Reception', 'Wedding Eve'],
      },
      {
        id: 'premium',
        name: 'Premium Wedding Package',
        level: 'Premium',
        ceremonies: ['All'],
        functions: ['Wedding & Reception', 'Engagement', 'Pre-Wedding Shoot'],
        price: 145000,
        listPrice: 145000,
        discountPct: 0,
        cardBullets: ['800+ photos', 'Photo + video team', 'Premium albums', 'Save-the-date reel'],
        inclusions: [
          '800+ edited photos',
          'Candid + traditional photo team',
          'Cinematic videography team',
          'Premium album set (couple + parents)',
          'Save-the-date reel',
          'Dedicated album designer',
        ],
        coverage: [
          {
            fn: 'Wedding & Reception',
            side: 'Both',
            hours: 12,
            extraHour: 3000,
            photoTeam: 'Candid + Traditional Photographer',
            videoTeam: 'Cinematic Videographer',
          },
        ],
        delivery: [
          { item: 'Teaser reel', timeline: '3 days' },
          { item: 'Full gallery', timeline: '14 days' },
          { item: 'Albums', timeline: '60 days' },
        ],
        extras: [
          { id: 'drone', label: 'Drone package', price: 12000 },
          { id: 'live', label: 'Live streaming (3 cameras)', price: 12000 },
        ],
        paymentStages: [
          { label: 'Advance', pct: 30 },
          { label: 'Mid', pct: 40 },
          { label: 'Balance', pct: 30 },
        ],
        optionalFunctions: ['Engagement', 'Reception', 'Wedding Eve', 'Post-wedding shoot'],
      },
    ],
    services: {
      funeral: {
        id: 'funeral-mem',
        name: 'Funeral / Memorial Photography',
        category: 'funeral',
        price: 8000,
        listPrice: 8000,
        pricingType: 'fixed',
        inclusions: [
          'Event coverage (2–3 hours)',
          'Professional photographer (1)',
          '100+ edited photos',
          'Online gallery',
          'Basic enhancement',
          'Travel within 20 km',
        ],
        coverage: [
          { k: 'Duration', v: '2–3 hours (included)' },
          { k: 'Stages covered', v: 'Family arrival · Prayer/rituals · Last respects · Procession · Cremation/Burial' },
          { k: 'Team', v: '1 respectful candid photographer' },
          { k: 'Delivery', v: '3–5 days · online gallery' },
        ],
        durationOptions: [
          { id: 'inc', label: '2–3 hours (Included)', add: 0 },
          { id: '3-5', label: '3–5 hours', add: 2000 },
          { id: '5-7', label: '5–7 hours', add: 4000 },
        ],
        extras: [
          { id: 'extra-photos', label: 'Extra edited photos pack', price: 1000 },
          { id: 'extend', label: 'Extended coverage (+1 hr)', price: 2000 },
          { id: 'stream', label: 'Live streaming for family abroad', price: 2000, cameras: 1 },
          { id: 'album', label: 'Memorial printed album', price: 4000 },
        ],
        delivery: [{ item: 'Online gallery', timeline: '3–5 days' }],
      },
      baptism: {
        id: 'baptism',
        name: 'Baptism Photography',
        category: 'event',
        price: 12000,
        inclusions: [
          'Church / venue coverage (3 hours)',
          '1 photographer',
          '150 edited photos',
          'Online gallery',
          'Group & family portraits',
        ],
        coverage: [{ k: 'Duration', v: '3 hours' }, { k: 'Delivery', v: '7 days' }],
        durationOptions: [{ id: 'inc', label: '3 hours (Included)', add: 0 }, { id: 'ext', label: '+1 hour', add: 1500 }],
        extras: [{ id: 'album', label: 'Small album', price: 3500 }],
        delivery: [{ item: 'Gallery', timeline: '7 days' }],
      },
      event: {
        id: 'event-gtg',
        name: 'Event / Get-togethers Photography',
        category: 'event',
        price: 18000,
        inclusions: ['4 hours coverage', '2 photographers', '250 edited photos', 'Online gallery'],
        coverage: [{ k: 'Duration', v: '4 hours' }, { k: 'Team', v: '2 candid photographers' }],
        durationOptions: [{ id: 'inc', label: '4 hours', add: 0 }, { id: 'ext', label: '6 hours', add: 4000 }],
        extras: [{ id: 'video', label: 'Event highlight video', price: 8000 }],
        delivery: [{ item: 'Photos', timeline: '10 days' }],
      },
      portrait: {
        id: 'portrait',
        name: 'Portrait Photography',
        category: 'portrait',
        price: 5000,
        inclusions: ['1 hour studio or outdoor', '30 edited photos', '2 outfit changes'],
        coverage: [{ k: 'Duration', v: '1 hour' }],
        durationOptions: [{ id: 'inc', label: '1 hour', add: 0 }],
        extras: [{ id: 'makeup', label: 'Makeup artist coordination', price: 3000 }],
        delivery: [{ item: 'Gallery', timeline: '5 days' }],
      },
      corporate: {
        id: 'corporate',
        name: 'Corporate Photography',
        category: 'corporate',
        price: 15000,
        inclusions: ['Half-day coverage', '1 photographer', 'Event & headshots', '200 edited photos'],
        coverage: [{ k: 'Duration', v: '4 hours' }],
        durationOptions: [{ id: 'inc', label: '4 hours', add: 0 }],
        extras: [{ id: 'video', label: 'Corporate reel', price: 12000 }],
        delivery: [{ item: 'Photos', timeline: '7 business days' }],
      },
    },
  },
  archana: {
    id: 'archana',
    name: 'Archana Photography',
    tagline: 'Peringara, Pathanamthitta',
    rating: 4.9,
    reviews: 128,
    km: 8,
    years: '8+',
    events: '350+',
    team: 'Professional Team',
    about:
      'Archana Photography is a full-service studio for Hindu and Christian weddings, with published work in Kerala wedding magazines. We operate with lead photographer Archana K. and trained associates.',
    areas: ['Pathanamthitta', 'Kozhencherry', 'Ranni', 'Thiruvalla'],
    weddingFrom: 72000,
    serviceFrom: 7500,
    packages: [
      {
        id: 'arch-standard',
        name: 'Classic Wedding Package',
        level: 'Standard',
        ceremonies: ['Hindu', 'Christian'],
        functions: ['Wedding & Reception'],
        price: 95000,
        listPrice: 105000,
        discountPct: 10,
        cardBullets: ['450 edited photos', '2 photographers', 'Traditional + candid', '10×10 album'],
        inclusions: ['450 edited photos', '2 photographers', 'Online gallery', '10×10 album · 25 pages'],
        coverage: [
          {
            fn: 'Wedding & Reception',
            side: 'Both',
            hours: 9,
            extraHour: 2200,
            photoTeam: 'Candid + Traditional Photographer',
            videoTeam: 'Optional add-on',
          },
        ],
        delivery: [{ item: 'Gallery', timeline: '14 days' }],
        extras: [{ id: 'drone', label: 'Drone', price: 9000 }],
        paymentStages: [{ label: 'Advance', pct: 30 }, { label: 'Balance', pct: 70 }],
        optionalFunctions: ['Engagement', 'Reception'],
      },
    ],
    services: {
      funeral: {
        id: 'arch-funeral',
        name: 'Funeral / Memorial Photography',
        category: 'funeral',
        price: 7500,
        inclusions: ['2–3 hours', '1 photographer', '80+ photos', 'Online gallery'],
        coverage: [{ k: 'Duration', v: '2–3 hours' }],
        durationOptions: [{ id: 'inc', label: '2–3 hours', add: 0 }],
        extras: [{ id: 'stream', label: 'Live stream', price: 1800 }],
        delivery: [{ item: 'Gallery', timeline: '4 days' }],
      },
    },
  },
};

function catalogStudio(studioId) {
  return CUSTOMER_CATALOG[studioId] || CUSTOMER_CATALOG.blue;
}

function studioList() {
  return Object.keys(CUSTOMER_CATALOG).map(function (k) {
    return CUSTOMER_CATALOG[k];
  });
}

function packagesForStudio(studioId, filters) {
  const st = catalogStudio(studioId);
  let list = (st.packages || []).slice();
  if (filters && filters.level && filters.level !== 'All') {
    list = list.filter(function (p) {
      return p.level === filters.level;
    });
  }
  if (filters && filters.community && filters.community !== 'all') {
    const map = { hindu: 'Hindu', muslim: 'Muslim', christian: 'Christian', other: 'Others' };
    const want = map[filters.community] || '';
    list = list.filter(function (p) {
      return (p.ceremonies || []).indexOf('All') >= 0 || (p.ceremonies || []).indexOf(want) >= 0;
    });
  }
  return list.length ? list : st.packages || [];
}

function serviceForStudio(studioId, serviceKey) {
  const st = catalogStudio(studioId);
  const svc = (st.services || {})[serviceKey];
  if (svc) return svc;
  return CUSTOMER_CATALOG.blue.services.funeral;
}

function defaultPackageId(studioId) {
  const pkgs = packagesForStudio(studioId, {});
  return pkgs[0] ? pkgs[0].id : 'standard';
}
