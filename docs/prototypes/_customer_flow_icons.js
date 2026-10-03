/** Inline SVG icons (mock-aligned). Included in customer flow app bundle. */
function svgIcon(name, cls) {
  const classes = ['flow-ico'];
  if (cls) classes.push(cls);
  const c = ' class="' + classes.join(' ') + '" aria-hidden="true"';
  const icons = {
    logo:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="11" fill="#ECFDF3"/><path d="M12 19s-5.5-3.5-5.5-8a3.5 3.5 0 0 1 7 0c0 4.5-5.5 8-5.5 8z" fill="#12B76A"/></svg>',
    pin:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#12B76A" stroke-width="2"><path d="M12 21s6-5.2 6-10a6 6 0 1 0-12 0c0 4.8 6 10 6 10z"/><circle cx="12" cy="11" r="2.5"/></svg>',
    pinBlue:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="#2563EB"><path d="M12 2C8.1 2 5 5.1 5 9c0 5.2 7 13 7 13s7-7.8 7-13c0-3.9-3.1-7-7-7zm0 9.5a2.5 2.5 0 1 1 0-5 2.5 2.5 0 0 1 0 5z"/></svg>',
    cal:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#12B76A" stroke-width="2"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M8 3v4M16 3v4M3 10h18"/></svg>',
    people:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#12B76A" stroke-width="2"><circle cx="9" cy="8" r="3"/><path d="M3 20c0-3.3 2.7-6 6-6"/><circle cx="17" cy="9" r="2.5"/><path d="M14 20c0-2.8 2.2-5 5-5"/></svg>',
    snow:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#2563EB" stroke-width="2"><path d="M12 2v20M4 6l16 12M20 6L4 18M2 12h20"/></svg>',
    house:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 10.5L12 4l8 6.5V20a1 1 0 0 1-1 1h-5v-6H10v6H5a1 1 0 0 1-1-1v-9.5z"/></svg>',
    tree:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#12B76A" stroke-width="2"><path d="M12 3L8 10h3l-2 4h6l-2-4h3L12 3z"/><path d="M8 18h8v3H8z"/></svg>',
    search:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/></svg>',
    bell:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#1B2559" stroke-width="2"><path d="M18 16H6l1.5-2V10a5.5 5.5 0 0 1 11 0v4L18 16z"/><path d="M10 19a2 2 0 0 0 4 0"/></svg>',
    menu:
      '<svg' + c + ' viewBox="0 0 24 24" fill="#1B2559"><path d="M4 7h16v2H4V7zm0 5h16v2H4v-2zm0 5h16v2H4v-2z"/></svg>',
    heart:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#2563EB" stroke-width="2"><path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2 4 4 0 0 1 7 2c0 5.5-7 10-7 10z"/></svg>',
    heartFill:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="#2563EB"><path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2 4 4 0 0 1 7 2c0 5.5-7 10-7 10z"/></svg>',
    share:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#2563EB" stroke-width="2"><path d="M16 8l-4-4-4 4M12 4v12M6 16v2a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2v-2"/></svg>',
    star:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="#FBBF24"><path d="M12 2l3 7h7l-5.5 4.5 2 7L12 17l-6.5 3.5 2-7L2 9h7l3-7z"/></svg>',
    check:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3"><path d="M5 13l4 4L19 7"/></svg>',
    sun:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#12B76A" stroke-width="2"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4 12H2M22 12h-2M5 5l1.5 1.5M17.5 17.5L19 19M19 5l-1.5 1.5M5 19l1.5-1.5"/></svg>',
    moon:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#6366F1" stroke-width="2"><path d="M21 14.5A8.5 8.5 0 1 1 9.5 3 7 7 0 0 0 21 14.5z"/></svg>',
    fan:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#64748B" stroke-width="2"><path d="M12 12v-9M12 12c-3 0-5 2-5 5M12 12c3 0 5 2 5 5M12 12L5 19M12 12l7 7"/></svg>',
    car:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#12B76A" stroke-width="2"><path d="M5 17h14l-1.5-6H6.5L5 17zM7 17a1.5 1.5 0 1 0 0 .01M17 17a1.5 1.5 0 1 0 0 .01M6 11l1-4h10l1 4"/></svg>',
    bike:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#12B76A" stroke-width="2"><circle cx="6" cy="17" r="3"/><circle cx="18" cy="17" r="3"/><path d="M6 17l4-7h4l2 3h3"/></svg>',
    dine:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#12B76A" stroke-width="2"><path d="M8 3v8a3 3 0 0 0 6 0V3M11 11v10M6 3v5M14 3v5"/></svg>',
    seat:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#12B76A" stroke-width="2"><circle cx="12" cy="8" r="3"/><path d="M6 20v-2a4 4 0 0 1 8 0v2"/></svg>',
    plane:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2"><path d="M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z"/></svg>',
    warn:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="#EA580C"><path d="M12 3L2 21h20L12 3zm0 6v6m0 3h.01" stroke="#fff" stroke-width="2"/></svg>',
    chev:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#94A3B8" stroke-width="2"><path d="M9 6l6 6-6 6"/></svg>',
    info:
      '<svg' +
      c +
      ' viewBox="0 0 24 24" fill="none" stroke="#12B76A" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 10v6M12 7h.01"/></svg>',
  };
  return icons[name] || '';
}
