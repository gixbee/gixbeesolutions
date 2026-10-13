/** Full owner-wizard-shaped payloads for customer demo (Blue Lens Studio). */

function ownerPkgBlueStandard() {
  return {
    id: 'standard',
    name: 'Standard Christian Wedding Package',
    level: 'Standard',
    desc:
      'Full-day wedding and reception coverage with candid + traditional photo team, cinematic highlight film, online gallery, and premium album. Designed for Christian ceremonies in Pathanamthitta & Kottayam.',
    listPrice: 100000,
    discountYes: 'yes',
    discountPct: 10,
    price: 90000,
    functions: ['Wedding & Reception', 'Engagement'],
    ceremonyTypes: ['Christian'],
    coverageByFunction: {
      'Wedding & Reception': {
        coverageSide: 'both',
        duration: 'Full Day',
        extraHour: 2500,
        photoTypes: {
          'Candid Photographer': { on: true, qty: 2 },
          'Traditional Photographer': { on: true, qty: 1 },
          'Candid + Traditional Photographer': { on: false, qty: 0 },
        },
        videoTypes: {
          'Cinematic Videographer': { on: true, qty: 1 },
          'Candid Videographer': { on: false, qty: 0 },
        },
      },
      Engagement: {
        coverageSide: 'single',
        duration: 'Up to 5 Hours',
        extraHour: 2000,
        photoTypes: {
          'Candid Photographer': { on: true, qty: 2 },
          'Traditional Photographer': { on: false, qty: 0 },
        },
        videoTypes: {
          'Cinematic Videographer': { on: false, qty: 0 },
        },
      },
    },
    deliverPhoto: ['Edited Photos', 'Colour-Graded Photos'],
    deliverVideo: ['Highlight Video', 'Cinematic Video'],
    deliverDigital: ['Online Gallery', 'Photo Selection App', 'Google Drive Link'],
    photoDetails: {
      'Edited Photos': { qty: 500, format: 'JPG (High Resolution)', delivery: '21 Working Days' },
      'Colour-Graded Photos': { qty: 120, format: 'JPG (High Resolution)', delivery: '21 Working Days' },
    },
    videoDetails: {
      'Highlight Video': { qty: 1, duration: '8-10 Minutes', format: 'MP4 (Full HD)', delivery: '21 Working Days' },
      'Cinematic Video': { qty: 1, duration: '12-15 Minutes', format: 'MP4 (4K)', delivery: '30 Working Days' },
    },
    albumPrints: {
      'Photo Album': {
        on: true,
        size: '12 x 30 inch',
        pages: 30,
        cover: 'Premium',
        paper: 'Matte',
        copies: 1,
      },
      Calendar: { on: true, size: 'A3', copies: 2 },
      'Photo Frame': { on: false },
    },
    deliveryMap: {
      'Edited Photos': '21 Working Days',
      'Colour-Graded Photos': '21 Working Days',
      'Highlight Video': '21 Working Days',
      'Cinematic Video': '30 Working Days',
      'Online Gallery': '7 Working Days',
      'Photo Selection App': '7 Working Days',
      'Google Drive Link': '21 Working Days',
      'Photo Album': '45 Working Days',
    },
    extras: {
      'Drone / Helicam': { mode: 'extra', price: 10000, basis: 'Per Event' },
      'Live Streaming': {
        mode: 'included',
        price: 0,
        basis: 'Per Event',
        hourlyLimit: true,
        includedHours: 4,
        extraHour: 2000,
        includedCameras: 2,
      },
      'Extra Photographer': { mode: 'extra', price: 5000, basis: 'Per Hour' },
      'Extra Videographer': { mode: 'extra', price: 6000, basis: 'Per Hour' },
      'Photo Booth': { mode: 'extra', price: 12000, basis: 'Per Event' },
    },
    paymentStages: [
      { label: 'Booking advance', pct: 25 },
      { label: 'Before wedding day', pct: 45 },
      { label: 'After online gallery', pct: 20 },
      { label: 'Album delivery', pct: 10 },
    ],
    cancelRules: [
      { days: '30+ days before event', pct: 10 },
      { days: '15–29 days', pct: 25 },
      { days: '7–14 days', pct: 50 },
      { days: 'Under 7 days', pct: 100 },
    ],
    rescheduleRules: [
      { days: 'Reschedule once, 15+ days before', pct: 0 },
      { days: 'Within 14 days', pct: 15 },
    ],
    policyValues: {
      'Cancellation Policy': {
        noticeDays: 30,
        refundPct: 50,
        notes: 'Advance is non-refundable if cancelled within 7 days of the event.',
      },
      'Rescheduling Policy': {
        noticeDays: 14,
        fee: 0,
        notes: 'One free reschedule with 14+ days notice; studio availability applies.',
      },
      'Photo Selection Deadline': { days: 45, notes: 'Album design starts after selection is locked.' },
      'Data Retention': { days: 365, notes: 'Online gallery retained 12 months; extensions on request.' },
    },
    policies: ['Cancellation Policy', 'Rescheduling Policy', 'Photo Selection Deadline', 'Data Retention'],
    requirements: [
      'Customer provides SSD / hard disk (optional backup)',
      'Electricity / power at venue for charging',
      'Meals for team on events over 8 hours',
      'Venue access 30 minutes before ceremony',
    ],
    equipmentNote: 'Backup bodies and lenses carried on wedding day.',
    qualityNote: 'Colour grading included for all delivered photos.',
  };
}

function ownerPkgBlueBasic() {
  const p = ownerPkgBlueStandard();
  p.id = 'basic';
  p.name = 'Basic Wedding Package';
  p.level = 'Basic';
  p.price = 65000;
  p.listPrice = 65000;
  p.discountPct = 0;
  p.desc = 'Essential wedding day coverage with one candid photographer and album.';
  p.functions = ['Wedding & Reception'];
  delete p.coverageByFunction.Engagement;
  const wed = p.coverageByFunction['Wedding & Reception'];
  wed.extraHour = 2000;
  wed.photoTypes = {
    'Candid Photographer': { on: true, qty: 1 },
    'Traditional Photographer': { on: false, qty: 0 },
    'Candid + Traditional Photographer': { on: false, qty: 0 },
  };
  wed.videoTypes = {
    'Cinematic Videographer': { on: false, qty: 0 },
    'Candid Videographer': { on: false, qty: 0 },
  };
  p.deliverVideo = [];
  p.videoDetails = {};
  p.photoDetails['Edited Photos'].qty = 300;
  p.albumPrints['Photo Album'] = { on: true, size: '10 x 12 inch', pages: 20, cover: 'Standard', paper: 'Matte', copies: 1 };
  return p;
}

function ownerPkgBluePremium() {
  const p = ownerPkgBlueStandard();
  p.id = 'premium';
  p.name = 'Premium Wedding Package';
  p.level = 'Premium';
  p.price = 145000;
  p.listPrice = 145000;
  p.discountPct = 0;
  p.desc = 'Premium team, save-the-date reel, parent albums, and extended cinematic deliverables.';
  p.functions = ['Wedding & Reception', 'Engagement', 'Pre-Wedding Shoot'];
  p.coverageByFunction = {
    'Wedding & Reception': {
      coverageSide: 'both',
      duration: 'Full Day',
      extraHour: 3000,
      photoTypes: {
        'Candid Photographer': { on: true, qty: 2 },
        'Traditional Photographer': { on: true, qty: 2 },
        'Candid + Traditional Photographer': { on: false, qty: 0 },
      },
      videoTypes: {
        'Cinematic Videographer': { on: true, qty: 2 },
        'Candid Videographer': { on: true, qty: 1 },
      },
    },
    Engagement: {
      coverageSide: 'single',
      duration: 'Up to 5 Hours',
      extraHour: 2500,
      photoTypes: {
        'Candid Photographer': { on: true, qty: 2 },
        'Traditional Photographer': { on: true, qty: 1 },
      },
      videoTypes: {
        'Cinematic Videographer': { on: true, qty: 1 },
      },
    },
    'Pre-Wedding Shoot': {
      coverageSide: 'single',
      duration: 'Up to 5 Hours',
      extraHour: 3000,
      photoTypes: {
        'Candid Photographer': { on: true, qty: 1 },
        'Traditional Photographer': { on: false, qty: 0 },
      },
      videoTypes: {
        'Cinematic Videographer': { on: true, qty: 1 },
      },
    },
  };
  p.deliverVideo = ['Save-the-date Reel', 'Highlight Video', 'Cinematic Video'];
  p.videoDetails = {
    'Save-the-date Reel': {
      qty: 1,
      duration: '60–90 Seconds',
      format: 'MP4 (Full HD)',
      delivery: '3 Working Days',
    },
    'Highlight Video': { qty: 1, duration: '10–12 Minutes', format: 'MP4 (4K)', delivery: '21 Working Days' },
    'Cinematic Video': { qty: 1, duration: '15–18 Minutes', format: 'MP4 (4K)', delivery: '30 Working Days' },
  };
  p.photoDetails['Edited Photos'].qty = 800;
  p.photoDetails['Colour-Graded Photos'].qty = 200;
  p.albumPrints['Photo Album'] = {
    on: true,
    size: '12 x 36 inch',
    pages: 40,
    cover: 'Luxury',
    paper: 'Lustre',
    copies: 3,
  };
  p.deliveryMap['Save-the-date Reel'] = '3 Working Days';
  p.deliveryMap['Highlight Video'] = '21 Working Days';
  p.deliveryMap['Cinematic Video'] = '30 Working Days';
  p.deliveryMap['Photo Album'] = '60 Working Days';
  return p;
}

function ownerSvcBlueFuneral() {
  return {
    id: 'funeral-mem',
    category: 'funeral',
    name: 'Funeral / Memorial Photography',
    blurb:
      'Respectful, unobtrusive coverage for funeral and memorial services with fast online delivery and optional live stream for family abroad.',
    pricingType: 'fixed',
    listPrice: 9000,
    discountYes: 'yes',
    discountPct: 11,
    price: 8000,
    durEnabled: true,
    duration: '2–3 Hours',
    extraHour: 2000,
    team: {
      photo: { 'Candid Photographer': { on: true, qty: 1 } },
      video: { 'Candid Videographer': { on: false, qty: 0 } },
    },
    deliverPhoto: ['Edited Photos'],
    deliverVideo: ['Live Streaming'],
    deliverDigital: ['Online Gallery', 'Google Drive Link'],
    photoDetails: {
      'Edited Photos': { qty: 100, format: 'JPG (High Resolution)', delivery: '3–5 Working Days' },
    },
    videoDetails: {
      'Live Streaming': {
        qty: 1,
        duration: 'Full Event',
        format: 'HD Stream',
        delivery: 'Same day',
        streamCameras: 1,
      },
    },
    albumPrints: {},
    deliveryMap: {
      'Edited Photos': '3–5 Working Days',
      'Online Gallery': '3 Working Days',
      'Google Drive Link': '5 Working Days',
      'Live Streaming': 'Same day',
    },
    extras: {
      'Extra edited photos': { mode: 'extra', price: 1000, basis: 'Per Event' },
      'Extended coverage (+1 hr)': { mode: 'extra', price: 2000, basis: 'Per Hour' },
      'Live streaming (extra camera)': { mode: 'extra', price: 1500, basis: 'Per Event' },
      'Printed memorial album': { mode: 'extra', price: 4000, basis: 'Per Event' },
    },
    paymentStages: [{ label: 'On booking', pct: 50 }, { label: 'After gallery', pct: 50 }],
    cancelRules: [{ days: 'Same day cancellation', pct: 100 }],
    rescheduleRules: [{ days: 'Date change', pct: 0 }],
    policyValues: {
      'Cancellation Policy': { notes: 'Memorial services: advance is non-refundable within 24 hours of service.' },
      'Data Retention': { days: 180, notes: 'Gallery available 6 months.' },
    },
    policies: ['Cancellation Policy', 'Data Retention'],
    requirements: ['Family liaison on arrival', 'Permission for indoor church / hall coverage'],
  };
}

function ownerSvcBlueBaptism() {
  return {
    id: 'baptism',
    category: 'event',
    name: 'Baptism Photography',
    blurb: 'Church and celebration coverage with family portraits.',
    pricingType: 'fixed',
    price: 12000,
    listPrice: 12000,
    discountPct: 0,
    duration: '3 Hours',
    extraHour: 1500,
    team: { photo: { 'Candid Photographer': { on: true, qty: 1 } }, video: {} },
    deliverPhoto: ['Edited Photos'],
    deliverDigital: ['Online Gallery'],
    photoDetails: { 'Edited Photos': { qty: 150, format: 'JPG (High Resolution)', delivery: '7 Working Days' } },
    deliveryMap: { 'Edited Photos': '7 Working Days', 'Online Gallery': '5 Working Days' },
    extras: { 'Small album': { mode: 'extra', price: 3500, basis: 'Per Event' } },
    policies: ['Cancellation Policy'],
    policyValues: { 'Cancellation Policy': { refundPct: 50, noticeDays: 7 } },
    requirements: ['Church photography permission if required'],
  };
}

function ownerPkgArchanaClassic() {
  const p = ownerPkgBlueStandard();
  p.id = 'arch-standard';
  p.name = 'Classic Wedding Package';
  p.level = 'Standard';
  p.price = 95000;
  p.listPrice = 105000;
  p.discountPct = 10;
  p.ceremonyTypes = ['Hindu', 'Christian'];
  p.desc = 'Archana Photography signature package for Hindu and Christian weddings in Pathanamthitta.';
  p.photoDetails['Edited Photos'].qty = 450;
  return p;
}

function ownerPayloadForPackage(studioId, pkgId) {
  if (studioId === 'archana') {
    return ownerPkgArchanaClassic();
  }
  if (studioId === 'blue') {
    if (pkgId === 'basic') return ownerPkgBlueBasic();
    if (pkgId === 'premium') return ownerPkgBluePremium();
    return ownerPkgBlueStandard();
  }
  return ownerPkgBlueStandard();
}

function ownerPayloadForService(studioId, serviceKey) {
  if (studioId === 'blue') {
    if (serviceKey === 'baptism') return ownerSvcBlueBaptism();
    return ownerSvcBlueFuneral();
  }
  return ownerSvcBlueFuneral();
}
