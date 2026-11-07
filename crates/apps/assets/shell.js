// The bar's pickers: each option's value is the path it opens, and
// choosing one is navigation. The page carries no handler of its own
// — the door's content security policy runs the shell's assets and
// nothing inline. Delegated on the document, because hx-boost swaps
// the body and a listener on the picker would go with it.
(function () {
  'use strict';

  document.addEventListener('change', (event) => {
    const picker = event.target.closest('select[data-nav]');
    if (picker) location.assign(picker.value);
  });

  // The queries behind each section: hidden unless the viewer asked,
  // a class on <html> so a boosted swap of the body keeps it.
  const KEY = 'glossdb.showReads';
  const root = document.documentElement;
  function stored() {
    try { return localStorage.getItem(KEY) === '1'; } catch (e) { return false; }
  }
  function apply(on) {
    root.classList.toggle('show-reads', on);
    document.querySelectorAll('[data-reads-toggle]').forEach((b) => {
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
      b.textContent = on ? 'Hide queries' : 'Show queries';
    });
  }
  root.classList.toggle('show-reads', stored());
  document.addEventListener('DOMContentLoaded', () => apply(stored()));
  document.addEventListener('htmx:afterSwap', () => apply(root.classList.contains('show-reads')));
  document.addEventListener('click', (event) => {
    if (!event.target.closest('[data-reads-toggle]')) return;
    const on = !root.classList.contains('show-reads');
    try { localStorage.setItem(KEY, on ? '1' : '0'); } catch (e) { /* the choice lasts this page */ }
    apply(on);
  });
})();
