function cateringIcon(name) {
  const c = ' class="p-ico" aria-hidden="true"';
  const icons = {
    pin: '<svg' + c + ' viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 21s6-5.2 6-10a6 6 0 1 0-12 0c0 4.8 6 10 6 10z"/><circle cx="12" cy="11" r="2.5"/></svg>',
  };
  return icons[name] || '';
}
