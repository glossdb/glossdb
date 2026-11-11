// <gl-graph nodes="frames/…" edges="frames/…" empty="…"> draws a graph
// of boxes with their columns over two stored frames.
//
// The nodes frame is one row per column: `node`, `kind` (`source` |
// `table` | `view`), `col` (empty for a node with no columns), `ord`,
// and optionally `role`, `detail` (shown at the column's right, and
// enough to keep the column unfolded), `sub` (a line under the node's
// name) and `link` (the node's page).
//
// The edges frame is one row per edge: `src`, `dst`, `kind`.
//   `m2o` | `o2o`: a declared key between two columns (`table.col`, a
//     composite endpoint as `table.(a, b)`); the parent is placed left
//     of the table that points at it.
//   `reads`: a column to the view column that descends from it.
//   `loads`: a source to the table its load query produces, node to
//     node.
//
// dagre places the nodes left to right along the edges. A column an
// edge touches, or one with a detail, shows; the rest fold under a
// count and open on click. Hover follows a column through its edges.
// Click puts it in the URL as `focus`, so the picture is a link.
(function () {
  'use strict';

  const NODE_W = 190;
  const SUB = 14;
  const HEAD = 30;
  const ROW = 17;
  const FOLD = 17;
  const PAD = 6;
  const NS = 'http://www.w3.org/2000/svg';

  function el(tag, attrs, text) {
    const e = document.createElementNS(NS, tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (text != null) e.textContent = text;
    return e;
  }

  // `t.(a, b)` is one edge per member column; the tuple is the key,
  // the columns are where it lands.
  function endpoints(path) {
    const m = path.match(/^(.*?)\.\((.*)\)$/);
    if (!m) return [path];
    return m[2].split(',').map((c) => m[1] + '.' + c.trim());
  }

  function nodeOf(id) {
    return id.slice(0, id.lastIndexOf('.'));
  }

  class GlGraph extends HTMLElement {
    constructor() {
      super();
      this.open = new Set();
    }

    connectedCallback() {
      this._written = () => this.load();
      document.addEventListener('glossql:written', this._written);
      this.load();
    }

    disconnectedCallback() {
      document.removeEventListener('glossql:written', this._written);
    }

    async load() {
      const nodes = glStore.rows(this.getAttribute('nodes'));
      const edges = glStore.rows(this.getAttribute('edges'));
      if (nodes === this._nodes && edges === this._edges) return;
      this._nodes = nodes;
      this._edges = edges;
      this.setAttribute('aria-busy', 'true');
      try {
        const [nodeRows, edgeRows] = await Promise.all([nodes, edges]);
        if (!this.isConnected || nodes !== this._nodes) return;
        this.rows = { nodes: nodeRows, edges: edgeRows };
        this.draw();
      } catch (e) {
        this._nodes = null;
        this._edges = null;
        this.replaceChildren(glStore.errorBox(e.message || String(e)));
      } finally {
        this.removeAttribute('aria-busy');
      }
    }

    draw() {
      const W = Number(this.getAttribute('node-width')) || NODE_W;
      if (!window.dagre) {
        this.replaceChildren(glStore.errorBox('dagre did not load — the graph cannot lay out'));
        return;
      }
      const { nodes: nodeRows, edges: edgeRows } = this.rows;
      if (nodeRows.length === 0) {
        const stated = this.getAttribute('empty');
        const note = document.createElement('p');
        note.className = 'rows-empty';
        note.textContent = stated || 'nothing here';
        this.replaceChildren(note);
        return;
      }
      const focus = new URLSearchParams(document.location.search).get('focus');

      // The nodes, in the frame's order, each with its columns in
      // ordinal order.
      const byNode = new Map();
      for (const r of nodeRows) {
        if (!byNode.has(r.node)) {
          byNode.set(r.node, { name: r.node, kind: r.kind, sub: r.sub || '', link: r.link || '', columns: [] });
        }
        if (r.col) byNode.get(r.node).columns.push([r.col, r.role || '', r.detail || '']);
      }
      const NODES = [...byNode.values()];

      const touched = new Set();
      const edges = [];
      for (const r of edgeRows) {
        if (r.kind === 'loads') {
          edges.push({ from: r.src, to: r.dst, kind: r.kind });
          continue;
        }
        const from = endpoints(r.src);
        const to = endpoints(r.dst);
        for (let i = 0; i < from.length; i++) {
          const e = { from: from[i], to: to[i] || to[0], kind: r.kind };
          edges.push(e);
          touched.add(e.from);
          touched.add(e.to);
        }
      }

      const shown = new Map();
      for (const n of NODES) {
        const keep = n.columns.filter(
          ([c, role, detail]) => touched.has(n.name + '.' + c) || role || detail || this.open.has(n.name)
        );
        shown.set(n.name, { cols: keep, hidden: n.columns.length - keep.length });
      }
      const head = (n) => HEAD + (n.sub ? SUB : 0);
      const height = (n) => {
        const s = shown.get(n.name);
        return head(n) + s.cols.length * ROW + (s.hidden ? FOLD : 0) + PAD;
      };

      const g = new dagre.graphlib.Graph();
      g.setGraph({ rankdir: 'LR', nodesep: 22, ranksep: 70, marginx: 8, marginy: 8 });
      g.setDefaultEdgeLabel(() => ({}));
      for (const n of NODES) g.setNode(n.name, { width: W, height: height(n) });
      const seen = new Set();
      for (const e of edges) {
        // a key points from the child to its parent; the data flows
        // from the parent, so the parent ranks first
        const key = e.kind === 'm2o' || e.kind === 'o2o';
        const first = e.kind === 'loads' ? e.from : nodeOf(key ? e.to : e.from);
        const then = e.kind === 'loads' ? e.to : nodeOf(key ? e.from : e.to);
        const pair = first + '>' + then;
        if (first !== then && g.hasNode(first) && g.hasNode(then) && !seen.has(pair)) {
          g.setEdge(first, then);
          seen.add(pair);
        }
      }
      dagre.layout(g);
      const pos = new Map();
      for (const n of NODES) pos.set(n.name, g.node(n.name));
      const totalW = g.graph().width + 8;
      const totalH = g.graph().height + 8;

      const svg = el('svg', {
        width: totalW,
        height: totalH,
        viewBox: `0 0 ${totalW} ${totalH}`,
        role: 'img',
        'aria-label': this.getAttribute('label') || 'column lineage',
      });
      // A graph a little wider than the section scales down to fit —
      // the whole picture beats a scrollbar as long as the type stays
      // readable; past that floor the section scrolls, as wide rows do.
      const FIT_FLOOR = 0.78;
      const room = this.clientWidth || this.parentElement?.clientWidth || 0;
      if (room && totalW > room && totalW * FIT_FLOOR <= room) {
        svg.setAttribute('width', room);
        svg.setAttribute('height', Math.round((totalH * room) / totalW));
      }
      const anchors = new Map();
      const layerE = el('g', {});
      const layerN = el('g', {});
      svg.append(layerE, layerN);

      for (const n of NODES) {
        const p = pos.get(n.name);
        const s = shown.get(n.name);
        const x = p.x - p.width / 2;
        const y = p.y - p.height / 2;
        const grp = el('g', { class: 'node', transform: `translate(${x},${y})` });
        grp.append(el('rect', { class: 'n-box ' + n.kind, width: p.width, height: p.height, rx: 2 }));
        const name = el('text', { class: 'n-head', x: 10, y: 19 }, n.name);
        if (n.link) {
          const a = el('a', { href: n.link });
          a.append(name);
          grp.append(a);
        } else {
          grp.append(name);
        }
        if (n.sub) {
          // About 6px a character at the subtitle's size: trim to the
          // box, the whole line on hover.
          const fit = Math.floor((p.width - 20) / 6);
          const line = n.sub.length > fit ? n.sub.slice(0, fit - 1) + '…' : n.sub;
          const t = el('text', { class: 'n-sub', x: 10, y: 33 }, line);
          if (line !== n.sub) t.append(el('title', {}, n.sub));
          grp.append(t);
        }
        const top = head(n);
        if (s.cols.length || s.hidden) {
          grp.append(el('line', { class: 'n-rule', x1: 0, x2: p.width, y1: top - 4, y2: top - 4 }));
        }
        s.cols.forEach(([c, role, detail], i) => {
          const id = n.name + '.' + c;
          const cy = top + i * ROW;
          const col = el('g', { class: 'col' + (touched.has(id) ? ' keyed' : ''), 'data-id': id });
          col.append(el('rect', { x: 1, y: cy - 1, width: p.width - 2, height: ROW }));
          col.append(el('text', { x: 10, y: cy + 11 }, c));
          if (role || detail) {
            col.append(el('text', { class: 'role ' + role, x: p.width - 10, y: cy + 11, 'text-anchor': 'end' }, detail || role));
          }
          grp.append(col);
          anchors.set(id, { x0: x, x1: x + p.width, y: y + cy + ROW / 2 });
        });
        anchors.set('node:' + n.name, { x0: x, x1: x + p.width, y: y + 15 });
        if (s.hidden) {
          const fold = el('g', { class: 'fold', 'data-node': n.name });
          fold.append(el('text', { x: 10, y: top + s.cols.length * ROW + 11 }, '+ ' + s.hidden + ' more'));
          grp.append(fold);
        }
        layerN.append(grp);
      }

      for (const e of edges) {
        const whole = e.kind === 'loads';
        const a = anchors.get(whole ? 'node:' + e.from : e.from);
        const b = anchors.get(whole ? 'node:' + e.to : e.to);
        if (!a || !b) continue;
        const ltr = a.x1 <= b.x0;
        const x0 = ltr ? a.x1 : a.x0;
        const x1 = ltr ? b.x0 : b.x1;
        const dx = Math.max(30, Math.abs(x1 - x0) / 2) * (ltr ? 1 : -1);
        const d = `M${x0},${a.y} C${x0 + dx},${a.y} ${x1 - dx},${b.y} ${x1},${b.y}`;
        layerE.append(el('path', { class: 'e ' + e.kind, d, 'data-from': e.from, 'data-to': e.to }));
        if (e.kind === 'm2o' || e.kind === 'o2o') {
          const tip = e.kind === 'o2o' ? '↔' : '→';
          layerE.append(
            el('text', {
              class: 'e-tip',
              x: (x0 + x1) / 2,
              y: (a.y + b.y) / 2 - 3,
              'text-anchor': 'middle',
              'data-from': e.from,
              'data-to': e.to,
            }, tip)
          );
        }
      }
      const line = document.createElement('p');
      line.className = 'focus-line';
      this.replaceChildren(svg, line);
      // Past the fit floor the section scrolls: say so, since the views
      // are the right-hand end and would otherwise sit out of sight.
      const wrap = this.closest('.graph-wrap');
      if (wrap) wrap.classList.toggle('overflows', wrap.scrollWidth > wrap.clientWidth + 1);

      const lit = (id) => {
        const marks = svg.querySelectorAll('.e, .e-tip');
        if (!id) {
          for (const m of marks) m.classList.remove('lit', 'dim');
          for (const c of svg.querySelectorAll('.col.lit')) c.classList.remove('lit');
          line.textContent = '';
          return;
        }
        const near = new Set();
        for (const m of marks) {
          const hit = m.dataset.from === id || m.dataset.to === id;
          m.classList.toggle('lit', hit);
          m.classList.toggle('dim', !hit);
          if (hit) {
            near.add(m.dataset.from);
            near.add(m.dataset.to);
          }
        }
        for (const c of svg.querySelectorAll('.col')) c.classList.toggle('lit', near.has(c.dataset.id));
        const others = [...near].filter((t) => t !== id);
        line.replaceChildren();
        const b = document.createElement('b');
        b.textContent = id;
        line.append(b, ' — ' + (others.length ? others.join(' · ') : 'nothing attached'));
      };
      svg.addEventListener('mouseover', (ev) => {
        const c = ev.target.closest('.col');
        if (c) lit(c.dataset.id);
      });
      svg.addEventListener('mouseout', (ev) => {
        const c = ev.target.closest('.col');
        if (c) lit(focus);
      });
      svg.addEventListener('click', (ev) => {
        const f = ev.target.closest('.fold');
        if (f) {
          this.open.add(f.dataset.node);
          this.draw();
          return;
        }
        const c = ev.target.closest('.col');
        if (!c) return;
        // The focus rides the URL: the same view is a link, and the
        // frames keep their cache — nothing about them changed.
        const url = new URL(document.location.href);
        if (url.searchParams.get('focus') === c.dataset.id) {
          url.searchParams.delete('focus');
        } else {
          url.searchParams.set('focus', c.dataset.id);
        }
        document.location.assign(url.toString());
      });
      if (focus) lit(focus);
    }
  }

  customElements.define('gl-graph', GlGraph);
})();
