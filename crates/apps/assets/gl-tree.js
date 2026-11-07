// <gl-tree frame="frames/tree"> — the console's tree. The frame serves
// one row per entry: `section`, `parent` (the table a column belongs
// to, empty otherwise), `name`, `label`, `link`. Sections and tables
// fold; which are open is kept per browser. The entry whose link is
// the current page is marked, and its section and table open.
(function () {
  'use strict';

  const KEY = 'glossdb.tree.open';

  // What the viewer left open; null on a first visit, when every
  // section opens and every table stays folded.
  function remembered() {
    try {
      const stored = localStorage.getItem(KEY);
      return stored == null ? null : new Set(JSON.parse(stored));
    } catch (e) {
      return null;
    }
  }

  function remember(open) {
    try {
      localStorage.setItem(KEY, JSON.stringify([...open]));
    } catch (e) {
      /* the choice lasts this page */
    }
  }

  // A link is the current page when its path and every one of its
  // params match the location; the location may carry more (a tab, a
  // grain), which still marks the object.
  function isCurrent(link) {
    const url = new URL(link, document.location.origin);
    if (url.pathname !== document.location.pathname) return false;
    const here = new URLSearchParams(document.location.search);
    for (const [k, v] of url.searchParams) {
      if (here.get(k) !== v) return false;
    }
    return url.searchParams.toString() !== '' || here.toString() === '';
  }

  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  function entry(row) {
    const a = el('a', 't-link', row.label);
    a.href = row.link;
    if (isCurrent(row.link)) {
      a.classList.add('current');
      a.setAttribute('aria-current', 'page');
    }
    return a;
  }

  function fold(id, summary, open, current) {
    const d = el('details', 't-fold');
    d.dataset.id = id;
    d.open = open.has(id) || current;
    d.append(summary);
    d.addEventListener('toggle', () => {
      if (d.open) open.add(id);
      else open.delete(id);
      remember(open);
    });
    return d;
  }

  class GlTree extends HTMLElement {
    connectedCallback() {
      this._written = () => this.load();
      document.addEventListener('glossql:written', this._written);
      this.load();
    }

    disconnectedCallback() {
      document.removeEventListener('glossql:written', this._written);
    }

    async load() {
      this.setAttribute('aria-busy', 'true');
      try {
        const rows = await glStore.rows(this.getAttribute('frame'));
        if (!this.isConnected) return;
        this.replaceChildren(this.draw(rows));
        if (window.htmx) window.htmx.process(this);
      } catch (e) {
        this.replaceChildren(glStore.errorBox(e.message || String(e)));
      } finally {
        this.removeAttribute('aria-busy');
      }
    }

    draw(rows) {
      const stored = remembered();
      const open = stored || new Set();
      const sections = new Map();
      for (const r of rows) {
        if (!sections.has(r.section)) sections.set(r.section, { tops: [], kids: new Map() });
        const s = sections.get(r.section);
        if (r.parent) {
          if (!s.kids.has(r.parent)) s.kids.set(r.parent, []);
          s.kids.get(r.parent).push(r);
        } else {
          s.tops.push(r);
        }
      }
      const nav = el('nav', 'tree');
      nav.setAttribute('aria-label', 'dataset');
      for (const [name, s] of sections) {
        const list = el('ul', 't-list');
        let sectionCurrent = false;
        for (const top of s.tops) {
          const li = el('li');
          const kids = s.kids.get(top.name) || [];
          const kidCurrent = kids.some((k) => isCurrent(k.link));
          if (kidCurrent || isCurrent(top.link)) sectionCurrent = true;
          if (kids.length) {
            const head = el('summary');
            head.append(entry(top));
            const sub = el('ul', 't-list t-sub');
            for (const k of kids) {
              const kl = el('li');
              kl.append(entry(k));
              sub.append(kl);
            }
            const d = fold(name + '/' + top.name, head, open, kidCurrent || isCurrent(top.link));
            d.append(sub);
            li.append(d);
          } else {
            li.append(entry(top));
          }
          list.append(li);
        }
        const head = el('summary', 't-head', name);
        head.append(el('span', 't-count', String(s.tops.length)));
        const d = fold(name, head, open, sectionCurrent || stored == null);
        d.append(list);
        nav.append(d);
      }
      if (sections.size === 0) nav.append(el('p', 'rows-empty', 'nothing loaded yet'));
      return nav;
    }
  }

  customElements.define('gl-tree', GlTree);
})();
