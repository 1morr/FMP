/* FMP Liquid Glass engine for the static design drafts.
 *
 * Every element with the `lg` class gets a backdrop filter that bends the
 * content behind it: an SVG displacement map shaped like a convex bezel,
 * light chromatic dispersion at the rim, then blur and saturation.
 * Chromium supports SVG filters inside `backdrop-filter`; other engines
 * fall back to the "standard" tier (blur + saturation) automatically.
 *
 * Tiers (html[data-glass]): refract | standard | minimal
 *   refract  = Flutter "premium" (Impeller shader)
 *   standard = Flutter "standard" (light shader); Windows tops out here
 *   minimal  = BackdropFilter only / Reduce Transparency: near-opaque fill
 */
(function () {
  const SVGNS = 'http://www.w3.org/2000/svg';
  let defs = null;
  let uid = 0;
  const supportsUrlBackdrop = (() => {
    const ua = navigator.userAgent;
    return /Chrome\//.test(ua) && !/Edg\/1[0-7]\./.test(ua);
  })();

  function ensureDefs() {
    if (defs) return defs;
    const svg = document.createElementNS(SVGNS, 'svg');
    svg.setAttribute('width', '0');
    svg.setAttribute('height', '0');
    svg.setAttribute('aria-hidden', 'true');
    svg.style.position = 'absolute';
    svg.style.pointerEvents = 'none';
    defs = document.createElementNS(SVGNS, 'defs');
    svg.appendChild(defs);
    document.body.appendChild(svg);
    return defs;
  }

  // Signed distance to a rounded rectangle centred at the origin.
  function sdRoundRect(px, py, hw, hh, r) {
    const qx = Math.abs(px) - (hw - r);
    const qy = Math.abs(py) - (hh - r);
    const ox = Math.max(qx, 0), oy = Math.max(qy, 0);
    return Math.hypot(ox, oy) + Math.min(Math.max(qx, qy), 0) - r;
  }

  // Displacement map: outward normal * refraction strength of a squircle bezel.
  function buildMap(w, h, r, bezel) {
    const s = 0.5; // half resolution is plenty; the filter upsamples
    const cw = Math.max(2, Math.round(w * s));
    const ch = Math.max(2, Math.round(h * s));
    const c = document.createElement('canvas');
    c.width = cw; c.height = ch;
    const ctx = c.getContext('2d');
    const img = ctx.createImageData(cw, ch);
    const d = img.data;
    const hw = w / 2, hh = h / 2;
    const rr = Math.min(r, hw, hh);
    const e = 0.75;
    for (let y = 0; y < ch; y++) {
      for (let x = 0; x < cw; x++) {
        const px = (x + 0.5) / s - hw;
        const py = (y + 0.5) / s - hh;
        const dist = -sdRoundRect(px, py, hw, hh, rr); // >0 inside
        let dx = 0, dy = 0;
        if (dist > 0 && dist < bezel) {
          const nx = sdRoundRect(px + e, py, hw, hh, rr) - sdRoundRect(px - e, py, hw, hh, rr);
          const ny = sdRoundRect(px, py + e, hw, hh, rr) - sdRoundRect(px, py - e, hw, hh, rr);
          const len = Math.hypot(nx, ny) || 1;
          const t = dist / bezel; // 0 at rim, 1 at the flat top
          // slope of a squircle profile y = (1-(1-t)^4)^(1/4): steep at the rim
          const m = Math.pow(1 - t, 2.2);
          // sample inward: the rim magnifies what sits under the glass
          // (sampling outward would read outside the backdrop and go black)
          dx = -(nx / len) * m;
          dy = -(ny / len) * m;
        }
        const i = (y * cw + x) * 4;
        d[i] = 128 + dx * 127;
        d[i + 1] = 128 + dy * 127;
        d[i + 2] = 128;
        d[i + 3] = 255;
      }
    }
    ctx.putImageData(img, 0, 0);
    return c.toDataURL();
  }

  function el(name, attrs) {
    const n = document.createElementNS(SVGNS, name);
    for (const k in attrs) n.setAttribute(k, attrs[k]);
    return n;
  }

  function buildFilter(id, w, h, r, opts) {
    const f = el('filter', {
      id, x: '0', y: '0', width: w, height: h,
      filterUnits: 'userSpaceOnUse', primitiveUnits: 'userSpaceOnUse',
      'color-interpolation-filters': 'sRGB',
    });
    const map = buildMap(w, h, r, opts.bezel);
    f.appendChild(el('feImage', { href: map, x: 0, y: 0, width: w, height: h, result: 'map', preserveAspectRatio: 'none' }));
    const pre = el('feGaussianBlur', { in: 'SourceGraphic', stdDeviation: opts.blur, result: 'src' });
    f.appendChild(pre);
    const k = opts.scale;
    // three slightly different scales = faint dispersion at the rim
    f.appendChild(el('feDisplacementMap', { in: 'src', in2: 'map', scale: k * 1.06, xChannelSelector: 'R', yChannelSelector: 'G', result: 'dr' }));
    f.appendChild(el('feDisplacementMap', { in: 'src', in2: 'map', scale: k, xChannelSelector: 'R', yChannelSelector: 'G', result: 'dg' }));
    f.appendChild(el('feDisplacementMap', { in: 'src', in2: 'map', scale: k * 0.94, xChannelSelector: 'R', yChannelSelector: 'G', result: 'db' }));
    f.appendChild(el('feColorMatrix', { in: 'dr', type: 'matrix', values: '1 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 1 0', result: 'r' }));
    f.appendChild(el('feColorMatrix', { in: 'dg', type: 'matrix', values: '0 0 0 0 0  0 1 0 0 0  0 0 0 0 0  0 0 0 1 0', result: 'g' }));
    f.appendChild(el('feColorMatrix', { in: 'db', type: 'matrix', values: '0 0 0 0 0  0 0 0 0 0  0 0 1 0 0  0 0 0 1 0', result: 'b' }));
    f.appendChild(el('feBlend', { in: 'r', in2: 'g', mode: 'screen', result: 'rg' }));
    f.appendChild(el('feBlend', { in: 'rg', in2: 'b', mode: 'screen', result: 'rgb' }));
    f.appendChild(el('feColorMatrix', { in: 'rgb', type: 'saturate', values: opts.saturate }));
    return f;
  }

  function radiusOf(node, w, h) {
    const cs = getComputedStyle(node);
    const r = parseFloat(cs.borderTopLeftRadius) || 0;
    return Math.min(r, w / 2, h / 2);
  }

  const states = new WeakMap();

  // surfaces that carry text get thick frost and no lens (menus, dialogs, sheets, alerts, toasts)
  const THICK = '.gmenu, .dlg, .sheet, .alert, .toast, [role="menu"], [role="dialog"], [class*="-menu"], [class*="-dlg"], [class*="-sheet"]';
  function refresh(node) {
    if (node.matches(THICK)) { node.classList.add('lg-thick'); node.style.removeProperty('--lg-filter'); return; }
    if (!supportsUrlBackdrop) return;
    const rect = node.getBoundingClientRect();
    // getBoundingClientRect includes ancestor transforms (frames are scaled)
    const w = Math.round(node.offsetWidth);
    const h = Math.round(node.offsetHeight);
    if (w < 4 || h < 4) return;
    const r = radiusOf(node, w, h);
    const key = w + 'x' + h + 'r' + r + (node.dataset.lgVariant || '');
    let st = states.get(node);
    if (st && st.key === key) return;
    const defsEl = ensureDefs();
    if (!st) { st = { id: 'lg' + (++uid) }; states.set(node, st); }
    const minSide = Math.min(w, h);
    const variant = node.dataset.lgVariant || 'regular';
    // the lens lives in the rim; the flat centre stays frosted so labels read
    const bezel = Math.min(minSide * 0.42, 22);
    const scale = variant === 'clear' ? Math.min(70, minSide * 0.75) : Math.min(56, minSide * 0.6);
    const blur = variant === 'clear' ? 0.6 : Math.max(Number(node.dataset.lgBlur) || 0, 5);
    const f = buildFilter(st.id, w, h, r, { bezel, scale, blur, saturate: variant === 'clear' ? 1.5 : 1.9 });
    const old = document.getElementById(st.id);
    if (old) old.replaceWith(f); else defsEl.appendChild(f);
    st.key = key;
    node.style.setProperty('--lg-filter', 'url(#' + st.id + ')');
    void rect;
  }

  const ro = new ResizeObserver((entries) => {
    for (const e of entries) refresh(e.target);
  });

  function scan(root) {
    (root || document).querySelectorAll('.lg').forEach((n) => {
      if (n.__lg) return;
      n.__lg = true;
      refresh(n);
      ro.observe(n);
    });
  }

  /* Adaptive tone: glass over light content turns lighter with dark glyphs,
   * over dark content darker with light glyphs. Content blocks declare their
   * tone with data-tone="light|dark"; otherwise the frame's theme decides. */
  function toneUnder(node) {
    const r = node.getBoundingClientRect();
    const pts = [[0.25, 0.5], [0.5, 0.5], [0.75, 0.5]];
    let light = 0, dark = 0;
    for (const [fx, fy] of pts) {
      const x = r.left + r.width * fx, y = r.top + r.height * fy;
      const stack = document.elementsFromPoint(x, y);
      let tone = null;
      for (const s of stack) {
        if (s === node || node.contains(s) || s.closest('.lg')) continue;
        const t = s.closest('[data-tone]');
        if (t) { tone = t.dataset.tone; break; }
      }
      if (tone === 'light') light++; else if (tone === 'dark') dark++;
    }
    if (!light && !dark) return null;
    return light > dark ? 'light' : 'dark';
  }

  function updateTones() {
    document.querySelectorAll('.lg[data-adapt]').forEach((n) => {
      const t = toneUnder(n);
      if (t && n.dataset.over !== t) n.dataset.over = t;
      if (!t && n.dataset.over) delete n.dataset.over;
    });
  }

  let toneQueued = false;
  function queueTones() {
    if (toneQueued) return;
    toneQueued = true;
    requestAnimationFrame(() => { toneQueued = false; updateTones(); });
  }

  window.FMPGlass = {
    scan,
    refresh,
    updateTones,
    queueTones,
    supportsRefraction: supportsUrlBackdrop,
  };

  document.addEventListener('scroll', queueTones, true);
  window.addEventListener('resize', queueTones);
  if (!supportsUrlBackdrop) document.documentElement.classList.add('no-refract');
})();
