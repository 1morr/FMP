/* FMP design-draft kit: icons, source marks, synthetic data, components,
 * phone/desktop shells and the review harness. Every page in docs/design
 * composes its screens from these builders so the system stays in one place.
 * All covers, titles, artists and account names are synthetic demo data. */
(function () {
  const FMP = (window.FMP = {});

  /* ---------------------------------------------------------------- */
  /* Icons: one stroke family, 24-unit grid, round caps                 */
  /* ---------------------------------------------------------------- */
  function gearPath() {
    const cx = 12, cy = 12, ro = 9, ri = 6.9, n = 8;
    let d = '';
    for (let i = 0; i < n; i++) {
      const a0 = (i / n) * Math.PI * 2;
      const a1 = a0 + (Math.PI * 2) / n * 0.22;
      const a2 = a0 + (Math.PI * 2) / n * 0.5;
      const a3 = a0 + (Math.PI * 2) / n * 0.72;
      const p = (r, a) => (cx + r * Math.cos(a)).toFixed(2) + ' ' + (cy + r * Math.sin(a)).toFixed(2);
      d += (i === 0 ? 'M' : 'L') + p(ri, a0) + 'L' + p(ro, a1) + 'L' + p(ro, a2) + 'L' + p(ri, a3);
    }
    return d + 'Z';
  }
  const P = {
    search: '<circle cx="10.8" cy="10.8" r="6.3"/><path d="M15.6 15.6 20 20"/>',
    library: '<rect x="3.5" y="7.5" width="13" height="13" rx="3"/><path d="M8 3.5h9.5a3 3 0 0 1 3 3V16"/><circle cx="8.6" cy="16.6" r="1.7"/><path d="M10.3 16.6v-5.2l3.2-.9"/>',
    queue: '<path d="M4 6.5h16M4 12h10M4 17.5h7"/><path d="M15.5 14.6v6l4.9-3z" fill="currentColor" stroke-width="1.2"/>',
    settings: '<path d="' + gearPath() + '"/><circle cx="12" cy="12" r="2.8"/>',
    play: '<path d="M8 5.2v13.6c0 .6.7 1 1.2.7l10.6-6.8c.5-.3.5-1 0-1.4L9.2 4.5C8.7 4.2 8 4.6 8 5.2z" fill="currentColor" stroke="none"/>',
    pause: '<rect x="6.2" y="4.8" width="4.2" height="14.4" rx="1.3" fill="currentColor" stroke="none"/><rect x="13.6" y="4.8" width="4.2" height="14.4" rx="1.3" fill="currentColor" stroke="none"/>',
    next: '<path d="M4.5 6.6v10.8c0 .6.6.9 1.1.6l7.8-5.4c.4-.3.4-.9 0-1.2L5.6 6c-.5-.3-1.1 0-1.1.6zM12.5 6.6v10.8c0 .6.6.9 1.1.6l7.8-5.4c.4-.3.4-.9 0-1.2L13.6 6c-.5-.3-1.1 0-1.1.6z" fill="currentColor" stroke="none"/>',
    prev: '<path d="M19.5 6.6v10.8c0 .6-.6.9-1.1.6l-7.8-5.4a.7.7 0 0 1 0-1.2L18.4 6c.5-.3 1.1 0 1.1.6zM11.5 6.6v10.8c0 .6-.6.9-1.1.6l-7.8-5.4a.7.7 0 0 1 0-1.2L10.4 6c.5-.3 1.1 0 1.1.6z" fill="currentColor" stroke="none"/>',
    shuffle: '<path d="M3 7h3.2c2 0 3.2 1 4.3 2.6l2.6 4C14.2 15.2 15.5 16.5 17.6 16.5H21"/><path d="M3 16.5h3.2c1.5 0 2.5-.6 3.4-1.6M14 8.7c.9-1 2-1.7 3.6-1.7H21"/><path d="M18.6 4.6 21 7l-2.4 2.4M18.6 14.1 21 16.5l-2.4 2.4"/>',
    repeat: '<path d="M4 11.5V9.8A3.3 3.3 0 0 1 7.3 6.5H19.5"/><path d="M17 4 19.5 6.5 17 9"/><path d="M20 12.5v1.7a3.3 3.3 0 0 1-3.3 3.3H4.5"/><path d="M7 20 4.5 17.5 7 15"/>',
    repeat1: '<path d="M4 11.5V9.8A3.3 3.3 0 0 1 7.3 6.5H19.5"/><path d="M17 4 19.5 6.5 17 9"/><path d="M20 12.5v1.7a3.3 3.3 0 0 1-3.3 3.3H4.5"/><path d="M7 20 4.5 17.5 7 15"/><path d="M11.2 10.6 12.6 9.8v4.6" stroke-width="1.6"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    minus: '<path d="M5 12h14"/>',
    link: '<path d="M10.2 13.8a4 4 0 0 0 5.6 0l3-3a4 4 0 0 0-5.6-5.6l-1.1 1.1"/><path d="M13.8 10.2a4 4 0 0 0-5.6 0l-3 3a4 4 0 0 0 5.6 5.6l1.1-1.1"/>',
    more: '<circle cx="5.5" cy="12" r="1.7" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.7" fill="currentColor" stroke="none"/><circle cx="18.5" cy="12" r="1.7" fill="currentColor" stroke="none"/>',
    chevR: '<path d="m9 5 7 7-7 7"/>',
    chevL: '<path d="m15 5-7 7 7 7"/>',
    chevD: '<path d="m5 9 7 7 7-7"/>',
    chevU: '<path d="m5 15 7-7 7 7"/>',
    close: '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>',
    check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
    drag: '<path d="M5 8.5h14M5 12h14M5 15.5h14"/>',
    select: '<circle cx="12" cy="12" r="8.5"/><path d="m8.3 12.2 2.6 2.6 5-5.2"/>',
    sort: '<path d="M7.5 4v16M4 16.5 7.5 20l3.5-3.5M16.5 20V4M13 7.5 16.5 4 20 7.5"/>',
    refresh: '<path d="M19.5 12a7.5 7.5 0 1 1-2.2-5.3"/><path d="M19.8 4.5v4.6h-4.6"/>',
    lyrics: '<path d="M5.2 5h13.6c.9 0 1.7.8 1.7 1.7v9c0 .9-.8 1.7-1.7 1.7H13l-4.4 3.3v-3.3H5.2c-.9 0-1.7-.8-1.7-1.7v-9C3.5 5.8 4.3 5 5.2 5z"/><path d="M7.5 9.5h9M7.5 13h6"/>',
    addlist: '<path d="M4 6.5h11M4 11.5h11M4 16.5h6.5"/><path d="M17.5 13v7.5M13.8 16.75h7.4"/>',
    trash: '<path d="M4.5 7h15M9.5 7V5.2c0-.7.5-1.2 1.2-1.2h2.6c.7 0 1.2.5 1.2 1.2V7"/><path d="m6.5 7 1 12.2c.1.8.7 1.3 1.5 1.3h6c.8 0 1.4-.5 1.5-1.3l1-12.2M10 11v6M14 11v6"/>',
    info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5"/><circle cx="12" cy="7.9" r="1.1" fill="currentColor" stroke="none"/>',
    copy: '<rect x="8.5" y="8.5" width="11.5" height="11.5" rx="2.6"/><path d="M15.5 5.6v-.3c0-1-.8-1.8-1.8-1.8H5.3c-1 0-1.8.8-1.8 1.8v8.4c0 1 .8 1.8 1.8 1.8h.3"/>',
    external: '<path d="M14 4h6v6M20 4l-8.5 8.5"/><path d="M18 14v4.3c0 1-.8 1.7-1.7 1.7H5.7c-1 0-1.7-.8-1.7-1.7V7.7C4 6.8 4.8 6 5.7 6H10"/>',
    qr: '<rect x="4" y="4" width="6.5" height="6.5" rx="1.4"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="1.4"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="1.4"/><path d="M13.5 13.5h2.5v2.5M20 13.5v.1M13.5 20h.1M17 17h3v3h-3z"/>',
    globe: '<circle cx="12" cy="12" r="8.5"/><ellipse cx="12" cy="12" rx="3.6" ry="8.5"/><path d="M3.5 12h17"/>',
    key: '<circle cx="8" cy="15.5" r="3.8"/><path d="m10.8 12.8 8.7-8.7M16.2 7.4l2.6 2.6M13.9 9.7l2.1 2.1"/>',
    plugin: '<path d="M9.2 4.6a2.3 2.3 0 0 1 4.6 0V6H17c.6 0 1 .4 1 1v3.2h-1.4a2.3 2.3 0 0 0 0 4.6H18V18c0 .6-.4 1-1 1h-3.2v-1.4a2.3 2.3 0 0 0-4.6 0V19H6c-.6 0-1-.4-1-1v-3.2h1.4a2.3 2.3 0 0 0 0-4.6H5V7c0-.6.4-1 1-1h3.2z"/>',
    shield: '<path d="M12 3.5 19 6.3v5.3c0 4.2-2.9 7.6-7 8.9-4.1-1.3-7-4.7-7-8.9V6.3z"/><path d="m9 12 2.1 2.1L15.2 10"/>',
    user: '<circle cx="12" cy="8.5" r="3.6"/><path d="M5 19.5c1.2-3.2 3.8-4.8 7-4.8s5.8 1.6 7 4.8"/>',
    warn: '<path d="M10.6 4.7 3.3 17.6c-.6 1.1.2 2.4 1.4 2.4h14.6c1.2 0 2-1.3 1.4-2.4L13.4 4.7c-.6-1.1-2.2-1.1-2.8 0z"/><path d="M12 10v4"/><circle cx="12" cy="16.9" r="1" fill="currentColor" stroke="none"/>',
    volume: '<path d="M4 9.5h3.2L11.5 6v12l-4.3-3.5H4z"/><path d="M15 9.2a4 4 0 0 1 0 5.6M17.6 6.6a7.6 7.6 0 0 1 0 10.8"/>',
    volumeLow: '<path d="M4 9.5h3.2L11.5 6v12l-4.3-3.5H4z"/>',
    appearance: '<circle cx="12" cy="12" r="8.5"/><path d="M12 3.5a8.5 8.5 0 0 1 0 17z" fill="currentColor"/>',
    language: '<path d="M4 6h9M8.5 4v2c0 4-2 7-4.5 8.5M6.5 10c1.2 2 3 3.6 5 4.5"/><path d="m12.5 20 3.8-9 3.7 9M13.8 17h5"/>',
    note: '<path d="M9 17.5V6.5l10.5-2.2v11"/><circle cx="6.8" cy="17.5" r="2.2"/><circle cx="17.3" cy="15.3" r="2.2"/>',
    wave: '<path d="M4 12v.01M7.5 8.5v7M11 5v14M14.5 9v6M18 7v10M21 12v.01"/>',
    clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
    doc: '<path d="M7 3.5h6.5L18 8v11.5c0 .6-.4 1-1 1H7c-.6 0-1-.4-1-1v-15c0-.6.4-1 1-1z"/><path d="M13.5 3.5V8H18"/>',
    importBox: '<path d="M4 14v4.5c0 .8.7 1.5 1.5 1.5h13c.8 0 1.5-.7 1.5-1.5V14"/><path d="M12 4v11M7.5 10.5 12 15l4.5-4.5"/>',
    exportBox: '<path d="M4 14v4.5c0 .8.7 1.5 1.5 1.5h13c.8 0 1.5-.7 1.5-1.5V14"/><path d="M12 15V4M7.5 8.5 12 4l4.5 4.5"/>',
    pulse: '<path d="M3 12h4l2.2-5.5 4.1 11 2.2-5.5H21"/>',
    edit: '<path d="M14.5 5.5 18.5 9.5 9 19H5v-4z"/><path d="m12.5 7.5 4 4"/>',
    cloud: '<path d="M7.2 18h10.3a4 4 0 0 0 .6-7.9 6 6 0 0 0-11.5-1A4.5 4.5 0 0 0 7.2 18z"/>',
    cloudUp: '<path d="M7.2 18h10.3a4 4 0 0 0 .6-7.9 6 6 0 0 0-11.5-1A4.5 4.5 0 0 0 7.2 18z"/><path d="M12 16v-5.5M9.6 12.6 12 10.2l2.4 2.4"/>',
    offset: '<path d="M4 12h16M8 8l-4 4 4 4M16 8l4 4-4 4"/>',
    sidebar: '<rect x="3.5" y="5" width="17" height="14" rx="2.8"/><path d="M9.5 5v14"/>',
    sidebarR: '<rect x="3.5" y="5" width="17" height="14" rx="2.8"/><path d="M14.5 5v14"/>',
    nextUp: '<path d="M4 6.5h10M4 11.5h10M4 16.5h6"/><path d="M16.5 13v7l4.5-3.5z" fill="currentColor" stroke-width="1.2"/>',
    lock: '<rect x="5" y="10.5" width="14" height="9.5" rx="2.4"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5"/>',
    lockOpen: '<rect x="5" y="10.5" width="14" height="9.5" rx="2.4"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 6.8-1.2"/>',
    trial: '<circle cx="12" cy="12" r="8"/><path d="M12 4a8 8 0 0 1 0 16z" fill="currentColor"/>',
    crown: '<path d="M4 8l4 4 4-6.5 4 6.5 4-4-1.6 10.5H5.6z" fill="currentColor" stroke="none"/>',
    coin: '<circle cx="12" cy="12" r="8"/><path d="M12 7.5v9M14.5 9.4c-.5-.8-1.5-1.2-2.6-1.2-1.4 0-2.4.7-2.4 1.8 0 2.6 5.3 1.4 5.3 4.1 0 1.1-1.1 1.9-2.6 1.9-1.2 0-2.2-.5-2.8-1.3"/>',
    signal: '<path d="M4 18v-2M8.5 18v-5M13 18v-8M17.5 18V6" stroke-width="2.6"/>',
    wifi: '<path d="M4.5 10a11 11 0 0 1 15 0M7.5 13.2a6.6 6.6 0 0 1 9 0" stroke-width="2.2"/><circle cx="12" cy="16.8" r="1.6" fill="currentColor" stroke="none"/>',
    battery: '<rect x="2.5" y="7" width="17" height="10" rx="3" stroke-width="1.3" opacity=".45"/><rect x="4.2" y="8.7" width="13.6" height="6.6" rx="1.7" fill="currentColor" stroke="none"/><path d="M21.2 10.3v3.4" stroke-width="1.6" opacity=".45"/>',
    grid: '<rect x="4" y="4" width="7" height="7" rx="2"/><rect x="13" y="4" width="7" height="7" rx="2"/><rect x="4" y="13" width="7" height="7" rx="2"/><rect x="13" y="13" width="7" height="7" rx="2"/>',
    list: '<path d="M8.5 6.5h11.5M8.5 12h11.5M8.5 17.5h11.5"/><circle cx="4.6" cy="6.5" r="1" fill="currentColor" stroke="none"/><circle cx="4.6" cy="12" r="1" fill="currentColor" stroke="none"/><circle cx="4.6" cy="17.5" r="1" fill="currentColor" stroke="none"/>',
    filter: '<path d="M4 6h16M7 12h10M10 18h4"/>',
    history: '<path d="M4.5 12a7.5 7.5 0 1 0 2.2-5.3"/><path d="M4.2 4.5v4.6h4.6"/><path d="M12 8v4.2l2.8 1.6"/>',
    target: '<circle cx="12" cy="12" r="7.5"/><circle cx="12" cy="12" r="2.5"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3"/>',
    quote: '<path d="M6 17.5c-1.3 0-2.5-1.2-2.5-3 0-3.5 2-6.5 5.5-8M14 17.5c-1.3 0-2.5-1.2-2.5-3 0-3.5 2-6.5 5.5-8"/><circle cx="6.5" cy="14.5" r="2.5"/><circle cx="14.5" cy="14.5" r="2.5"/>',
    diag: '<path d="M8 3.5h8M9.5 3.5v5.2L4.8 17.6c-.7 1.3.3 2.9 1.8 2.9h10.8c1.5 0 2.5-1.6 1.8-2.9L14.5 8.7V3.5"/><path d="M7 14h10"/>',
    broom: '<path d="M14.5 3.5 11 10M6.5 10.5h9l2 9.5h-13z"/><path d="M9 14.5 8.5 20M12.5 14.5V20"/>',
    hash: '<path d="M9.5 4 8 20M16 4l-1.5 16M4.5 9h15M4 15h15"/>',
    down: '<path d="M12 4v16M6 14l6 6 6-6"/>',
    up: '<path d="M12 20V4M6 10l6-6 6 6"/>',
    airplay: '<path d="M6.5 17H5a1.5 1.5 0 0 1-1.5-1.5v-9A1.5 1.5 0 0 1 5 5h14a1.5 1.5 0 0 1 1.5 1.5v9A1.5 1.5 0 0 1 19 17h-1.5"/><path d="M12 14.5 16.5 20h-9z" fill="currentColor"/>',
  };
  FMP.icon = (name, cls) => '<svg class="i ' + (cls || '') + '" viewBox="0 0 24 24" aria-hidden="true">' + (P[name] || '') + '</svg>';
  FMP.icons = Object.keys(P);

  /* ---------------------------------------------------------------- */
  /* Source marks: simplified symbols, never the official logos         */
  /* ---------------------------------------------------------------- */
  const SRC = {
    bilibili: { name: 'Bilibili', short: 'B站', color: 'var(--src-bilibili)',
      svg: '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M5 1.8 6.6 3.9M11 1.8 9.4 3.9" stroke="var(--src-bilibili)" stroke-width="1.5" stroke-linecap="round" fill="none"/><rect x="1.4" y="3.9" width="13.2" height="10" rx="3" fill="var(--src-bilibili)"/><path d="M5.6 7.6v1.8M10.4 7.6v1.8" stroke="#fff" stroke-width="1.5" stroke-linecap="round"/></svg>' },
    youtube: { name: 'YouTube', short: 'YouTube', color: 'var(--src-youtube)',
      svg: '<svg viewBox="0 0 16 16" aria-hidden="true"><rect x=".8" y="2.8" width="14.4" height="10.4" rx="3.4" fill="var(--src-youtube)"/><path d="M6.5 5.6v4.8L10.6 8z" fill="#fff"/></svg>' },
    netease: { name: '網易雲音樂', short: '網易雲', color: 'var(--src-netease)',
      svg: '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="7.2" fill="var(--src-netease)"/><path d="M9.3 4.2c-.9-.3-2.6.1-3.5 1.3-1.2 1.6-.6 4 1.3 4.6 1.6.5 3.1-.6 3-2.1-.1-1.2-1.1-1.9-2.1-1.6M8.4 6.4l.8 3" stroke="#fff" stroke-width="1.25" stroke-linecap="round" fill="none"/></svg>' },
    lrclib: { name: 'lrclib', short: 'lrclib', color: 'var(--src-lrclib)',
      svg: '<svg viewBox="0 0 16 16" aria-hidden="true"><rect x="1" y="1" width="14" height="14" rx="4" fill="var(--src-lrclib)"/><path d="M4.5 5.5h7M4.5 8h7M4.5 10.5h4" stroke="#fff" stroke-width="1.3" stroke-linecap="round"/></svg>' },
  };
  FMP.SRC = SRC;
  FMP.srcMark = (s) => SRC[s].svg;
  FMP.src = (s, withName) => '<span class="src" title="' + SRC[s].name + '">' + SRC[s].svg + (withName ? '<span class="src-name">' + (withName === 'full' ? SRC[s].name : SRC[s].short) + '</span>' : '') + '</span>';
  FMP.srcChip = (s, full) => '<span class="src-chip">' + SRC[s].svg + (full ? SRC[s].name : SRC[s].short) + '</span>';

  /* access level: free and unknown show nothing; the three that limit listening do */
  FMP.acc = (lvl, big) => {
    if (!lvl) return '';
    const c = big ? ' acc-lg' : '';
    if (lvl === 'vip') return '<span class="acc acc-vip' + c + '" title="需要會員">會員</span>';
    if (lvl === 'paid') return '<span class="acc acc-paid' + c + '" title="需要單曲付費">付費</span>';
    if (lvl === 'trial') return '<span class="acc acc-trial' + c + '" title="只有試聽片段">' + FMP.icon('trial') + '試聽</span>';
    return '';
  };

  /* ---------------------------------------------------------------- */
  /* Synthetic covers                                                   */
  /* ---------------------------------------------------------------- */
  const PALETTES = [
    ['#1B1F3B', '#F25F5C', '#FFE066'], ['#0B3D2E', '#7BD389', '#F2F7F2'], ['#FFD6E0', '#6D28D9', '#1E1B4B'],
    ['#F4A261', '#264653', '#E9C46A'], ['#111418', '#FEE715', '#F5F5F5'], ['#E8E1D4', '#C1440E', '#2E2A24'],
    ['#3A0CA3', '#F72585', '#4CC9F0'], ['#F1FAEE', '#457B9D', '#1D3557'], ['#2B2D42', '#EF233C', '#EDF2F4'],
    ['#FFCDB2', '#B5838D', '#6D6875'], ['#0F172A', '#38BDF8', '#F0ABFC'], ['#FAF3DD', '#2A9D8F', '#E76F51'],
    ['#14213D', '#FCA311', '#E5E5E5'], ['#D8F3DC', '#40916C', '#081C15'], ['#FF9F1C', '#2EC4B6', '#011627'],
    ['#E0AFA0', '#463F3A', '#F4F3EE'], ['#5F0F40', '#FB8B24', '#E36414'], ['#CAF0F8', '#0077B6', '#03045E'],
    ['#22223B', '#C9ADA7', '#F2E9E4'], ['#FFE5EC', '#FF8FAB', '#590D22'],
  ];
  function rng(seed) {
    let h = 2166136261;
    for (const ch of String(seed)) { h ^= ch.charCodeAt(0); h = Math.imul(h, 16777619); }
    return () => { h += 0x6D2B79F5; let t = h; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  }
  function lum(hex) {
    const n = parseInt(hex.slice(1), 16);
    const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
    return 0.2126 * f((n >> 16) & 255) + 0.7152 * f((n >> 8) & 255) + 0.0722 * f(n & 255);
  }
  const coverCache = {};
  FMP.cover = function (seed, opts) {
    opts = opts || {};
    const key = seed + '|' + (opts.glyph || '') + '|' + (opts.kind ?? '');
    if (coverCache[key]) return coverCache[key];
    const r = rng(seed);
    const pal = PALETTES[opts.pal ?? Math.floor(r() * PALETTES.length)];
    const [a, b, c] = pal;
    const kind = opts.kind ?? Math.floor(r() * 8);
    const S = 200;
    let g = '<rect width="200" height="200" fill="' + a + '"/>';
    if (kind === 0) {
      const x = 60 + r() * 80, y = 60 + r() * 80;
      g += '<circle cx="' + x + '" cy="' + y + '" r="' + (62 + r() * 30) + '" fill="' + b + '"/><circle cx="' + (200 - x) + '" cy="' + (220 - y) + '" r="' + (18 + r() * 16) + '" fill="' + c + '"/>';
    } else if (kind === 1) {
      const w = 22 + r() * 16;
      for (let i = -4; i < 12; i++) g += '<rect x="' + (i * w * 2) + '" y="-60" width="' + w + '" height="340" fill="' + (i % 3 === 0 ? c : b) + '" transform="rotate(' + (24 + r() * 20) + ' 100 100)"/>';
    } else if (kind === 2) {
      for (let y = 0; y < 5; y++) for (let x = 0; x < 5; x++) g += '<circle cx="' + (20 + x * 40) + '" cy="' + (20 + y * 40) + '" r="' + (4 + r() * 15) + '" fill="' + (r() > 0.78 ? c : b) + '"/>';
    } else if (kind === 3) {
      const ch = opts.glyph || '音';
      g += '<rect x="14" y="14" width="172" height="172" fill="none" stroke="' + c + '" stroke-width="1.5" opacity=".6"/><text x="100" y="138" text-anchor="middle" font-family="PingFang TC, Noto Serif TC, serif" font-weight="700" font-size="118" fill="' + b + '">' + ch + '</text>';
    } else if (kind === 4) {
      g = '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="' + a + '"/><stop offset="1" stop-color="' + b + '"/></linearGradient></defs><rect width="200" height="200" fill="url(#g)"/><circle cx="' + (70 + r() * 60) + '" cy="118" r="38" fill="' + c + '"/><rect y="132" width="200" height="68" fill="' + a + '" opacity=".92"/>';
      for (let i = 0; i < 4; i++) g += '<rect x="' + (20 + r() * 140) + '" y="' + (142 + i * 12) + '" width="' + (20 + r() * 30) + '" height="2" fill="' + c + '" opacity=".6"/>';
    } else if (kind === 5) {
      for (let i = 0; i < 9; i++) {
        const y = 30 + i * 18, amp = 6 + r() * 14;
        g += '<path d="M-10 ' + y + ' C 40 ' + (y - amp) + ', 80 ' + (y + amp) + ', 120 ' + y + ' S 190 ' + (y - amp) + ', 220 ' + y + '" stroke="' + (i % 4 === 1 ? c : b) + '" stroke-width="' + (3 + r() * 5) + '" fill="none" stroke-linecap="round"/>';
      }
    } else if (kind === 6) {
      g += '<rect x="0" y="0" width="100" height="200" fill="' + b + '"/><rect x="' + (52 + r() * 30) + '" y="' + (48 + r() * 40) + '" width="72" height="72" fill="' + c + '"/>';
    } else {
      const x = 40 + r() * 120, y = 40 + r() * 120;
      for (let i = 7; i > 0; i--) g += '<circle cx="' + x + '" cy="' + y + '" r="' + i * 22 + '" fill="' + (i % 2 ? b : a) + '"/>';
      g += '<circle cx="' + x + '" cy="' + y + '" r="9" fill="' + c + '"/>';
    }
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + S + ' ' + S + '">' + g + '</svg>';
    const out = { url: 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg), tone: lum(a) > 0.32 ? 'light' : 'dark', colors: pal };
    coverCache[key] = out;
    return out;
  };
  FMP.coverEl = function (cv, size, cls, style) {
    const c = typeof cv === 'string' ? FMP.cover(cv) : cv;
    const s = typeof size === 'number' ? 'width:' + size + 'px;height:' + size + 'px;' : '';
    return '<span class="cover ' + (cls || '') + '" data-tone="' + c.tone + '" style="' + s + (style || '') + '"><img alt="" src="' + c.url + '"></span>';
  };

  /* ---------------------------------------------------------------- */
  /* Synthetic library                                                  */
  /* ---------------------------------------------------------------- */
  const T = [
    // id, title, artist, src, dur, acc, extra
    ['t01', '夜行列車', '鹿野青', 'netease', '4:12', 'vip', { g: '夜' }],
    ['t02', 'Glass Harbor', 'Mira Ochoa', 'youtube', '3:44', null, {}],
    ['t03', '【中文翻唱】群青の街', '栗子Kuri', 'bilibili', '4:18', null, { plays: '38.2萬' }],
    ['t04', '海岸線', '許晴川', 'netease', '4:31', 'trial', { g: '海' }],
    ['t05', '【4K】「夏夜漫遊」全曲 Live', '星野町樂團', 'bilibili', '38:40', 'vip', { parts: 6, plays: '12.7萬' }],
    ['t06', 'Northbound (Live at Hollow Hall)', 'The Lanterns', 'youtube', '5:58', null, {}],
    ['t07', '白晝之詩', '林以澄', 'netease', '3:48', null, { g: '晝' }],
    ['t08', '【鋼琴】千年之後 即興改編', '琴鍵上的鯨', 'bilibili', '5:44', null, { plays: '6.1萬' }],
    ['t09', '不眠的城', '夏目透', 'netease', '3:55', 'paid', { g: '城' }],
    ['t10', 'Paper Moons', 'Juno Vale', 'youtube', '3:12', null, {}],
    ['t11', '【初音未來】ネオンの海', 'ねこじゃらしP', 'bilibili', '3:58', null, { plays: '91.4萬' }],
    ['t12', '霧中燈塔', '鹿野青', 'netease', '5:10', 'vip', { g: '霧' }],
    ['t13', 'Satellite Hearts', 'Kite & Comet', 'youtube', '4:20', null, {}],
    ['t14', '晚風告白', '陳一禾', 'netease', '3:37', null, { g: '風' }],
    ['t15', '【合唱】春風十里 十人版', '青木社', 'bilibili', '4:46', null, { plays: '3.3萬' }],
    ['t16', 'Slow Tide', 'Oren Lake', 'youtube', '6:02', null, {}],
    ['t17', '雨天的貓', '白芷', 'netease', '3:21', 'trial', { g: '雨' }],
    ['t18', '【純享】燈火闌珊 舞台版', '柏原', 'bilibili', '12:06', null, { parts: 3, plays: '22.8萬' }],
    ['t19', 'City Lights — lofi mix', 'lofi atlas', 'youtube', '1:02:15', null, {}],
    ['t20', '春日遲遲', '林以澄', 'netease', '4:02', null, { g: '春' }],
    ['t21', '讀書用 BGM 三小時', '安靜的午後', 'bilibili', '3:00:12', null, { plays: '140萬' }],
    ['t22', 'Lanterns on the Water', 'Mira Ochoa', 'youtube', '4:48', null, {}],
    ['t23', '星屑ランデブー', '藍井ほたる', 'netease', '4:09', 'vip', { g: '星' }],
    ['t24', '月光海峽', '許晴川', 'netease', '4:26', null, { g: '月' }],
  ];
  FMP.T = {};
  FMP.tracks = T.map(([id, title, artist, src, dur, acc, x], i) => {
    const t = { id, title, artist, src, dur, acc, parts: x.parts || 0, plays: x.plays || '', cv: FMP.cover(id + title, x.g ? { glyph: x.g, kind: i % 3 === 0 ? 3 : undefined } : undefined) };
    FMP.T[id] = t;
    return t;
  });
  FMP.partsOf = (t) => {
    const names = {
      t05: ['開場：夏夜序曲', '漫遊者', '晚霞與你', '十字路口（新編）', 'Encore：夏夜漫遊', 'Encore：謝幕'],
      t18: ['燈火闌珊（舞台純享）', '幕後花絮', '燈火闌珊（伴奏版）'],
    }[t.id] || [];
    const durs = { t05: ['6:12', '5:48', '7:02', '6:31', '8:10', '4:57'], t18: ['4:36', '3:12', '4:18'] }[t.id] || [];
    return names.map((n, i) => ({ n: i + 1, title: n, dur: durs[i] }));
  };

  FMP.PL = {
    commute: { id: 'commute', name: '通勤路上', kind: 'local', count: 42, dur: '2 小時 51 分', cv: FMP.cover('pl-commute', { pal: 0, kind: 4 }), desc: '早上八點的捷運，從家到公司剛好一張歌單。' },
    code: { id: 'code', name: '深夜寫程式', kind: 'local', count: 128, dur: '9 小時 14 分', cv: FMP.cover('pl-code', { pal: 10, kind: 5 }) },
    weekend: { id: 'weekend', name: '週末慢活', kind: 'local', count: 23, dur: '1 小時 32 分', cv: FMP.cover('pl-weekend', { pal: 11, kind: 0 }) },
    learn: { id: 'learn', name: '想學的歌', kind: 'local', count: 9, dur: '38 分', cv: FMP.cover('pl-learn', { pal: 5, kind: 3, glyph: '練' }) },
    covers: { id: 'covers', name: '翻唱精選', kind: 'imported', src: 'bilibili', own: true, count: 214, dur: '17 小時 8 分', cv: FMP.cover('pl-covers', { pal: 19, kind: 7 }), refresh: '每 6 小時', last: '12 分鐘前', owner: '自己的收藏夾' },
    lofi: { id: 'lofi', name: 'Lo-fi Focus', kind: 'imported', src: 'youtube', own: false, count: 86, dur: '5 小時 40 分', cv: FMP.cover('pl-lofi', { pal: 17, kind: 2 }), refresh: '每天', last: '3 小時前', owner: 'lofi atlas' },
    cpop: { id: 'cpop', name: '華語私藏 2026', kind: 'imported', src: 'netease', own: true, count: 157, dur: '10 小時 22 分', cv: FMP.cover('pl-cpop', { pal: 2, kind: 3, glyph: '藏' }), refresh: '每 12 小時', last: '1 小時前', owner: '自己的歌單' },
    live: { id: 'live', name: '星野町 Live 合集', kind: 'imported', src: 'bilibili', own: false, count: 31, dur: '4 小時 2 分', cv: FMP.cover('pl-live', { pal: 16, kind: 1 }), refresh: '每週', last: '2 天前', owner: '星野町樂團' },
  };
  FMP.playlists = Object.values(FMP.PL);

  FMP.now = FMP.T.t01; // the track playing across the drafts

  /* ---------------------------------------------------------------- */
  /* Components                                                         */
  /* ---------------------------------------------------------------- */
  const I = FMP.icon;
  FMP.esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');

  /* one track row. opts: playing, check(bool|null), drag, more, dim, num, sub, desk, size, cls, trailing */
  FMP.trackRow = function (t, o) {
    o = o || {};
    const size = o.size || (o.desk ? 36 : 48);
    const lead = o.check !== undefined && o.check !== null ? '<span class="check' + (o.check ? ' on' : '') + '">' + I('check') + '</span>' : '';
    const num = o.num !== undefined ? '<span class="num c3" style="width:22px;text-align:right;font-size:13px;flex:none">' + o.num + '</span>' : '';
    const cover = o.noCover ? '' : FMP.coverEl(t.cv, size, 'thumb');
    const playing = o.playing ? '<span class="eq" aria-label="正在播放"><i></i><i></i><i></i></span>' : '';
    const sub = o.sub !== undefined ? o.sub : FMP.esc(t.artist);
    const part = t.parts > 1 ? '<span class="part">' + t.parts + 'P</span>' : '';
    const more = o.more === false ? '' : '<button class="ibtn" aria-label="更多" style="color:var(--label-2);margin-right:-10px">' + I('more', 's20') + '</button>';
    const drag = o.drag ? '<span class="c3" style="display:grid;place-items:center;width:28px;margin-right:-6px">' + I('drag', 's20') + '</span>' : '';
    const dur = o.noDur ? '' : '<span class="dur num">' + t.dur + '</span>';
    return '<div class="row ' + (o.playing ? 'playing ' : '') + (o.dim ? 'dim ' : '') + (o.cls || '') + '" style="' + (o.style || '') + '">' + lead + num + cover +
      '<div class="meta"><div class="t1">' + playing + '<span class="tt">' + FMP.esc(t.title) + '</span>' + FMP.acc(t.acc) + '</div>' +
      '<div class="t2">' + FMP.src(t.src) + part + '<span class="tt">' + sub + '</span></div></div>' + (o.trailing || '') + dur + (o.chev ? '<span class="c3">' + I(o.chev, 's20') + '</span>' : '') + drag + more + '</div>';
  };

  FMP.playlistCard = function (p, o) {
    o = o || {};
    const sub = p.kind === 'imported'
      ? FMP.src(p.src) + '<span>' + p.count + ' 首</span>'
      : '<span>' + p.count + ' 首</span>';
    const sel = o.check !== undefined ? '<span class="check' + (o.check ? ' on' : '') + '" style="position:absolute;right:8px;bottom:8px;background:' + (o.check ? '' : 'rgba(0,0,0,.25)') + ';box-shadow:inset 0 0 0 1.6px #fff">' + I('check') + '</span>' : '';
    const refreshing = o.refreshing ? '<span style="position:absolute;inset:0;display:grid;place-items:center;background:rgba(0,0,0,.35)"><span class="spinner" style="border-color:rgba(255,255,255,.35);border-top-color:#fff;width:26px;height:26px"></span></span>' : '';
    return '<div class="plc" style="display:flex;flex-direction:column;gap:7px;min-width:0">' +
      '<div style="position:relative">' + FMP.coverEl(p.cv, null, '', 'width:100%;aspect-ratio:1;border-radius:' + (o.desk ? '10px' : '12px')) + refreshing + sel + '</div>' +
      '<div style="min-width:0"><div class="ell" style="font-size:' + (o.desk ? '13' : '15') + 'px;line-height:1.3;font-weight:500">' + FMP.esc(p.name) + '</div>' +
      '<div class="c2" style="font-size:' + (o.desk ? '12' : '13') + 'px;display:flex;align-items:center;gap:5px;margin-top:1px">' + sub + '</div></div></div>';
  };

  /* status bar for the phone frame */
  FMP.statusBar = () => '<div class="status"><span>9:41</span><span class="sr">' + I('signal', 's18') + I('wifi', 's18') + '<svg class="i" viewBox="0 0 24 24" style="width:27px;height:22px">' + P.battery + '</svg></span></div><div class="island"></div>';

  /* phone mini player (spine: the capsule fills as it plays; owner picked it 2026-11-11). o: paused, progress (0-100), time ('1:36') */
  FMP.mini = function (t, o) {
    o = o || {};
    t = t || FMP.now;
    const pct = o.progress ?? 38;
    return '<div class="lg mini" data-adapt data-act="open-player" role="button" aria-label="打開播放頁">' +
      '<span class="played" style="width:' + pct + '%"></span>' +
      FMP.coverEl(t.cv, 40) +
      '<div class="mi"><b><span class="tt">' + FMP.esc(t.title) + '</span>' + FMP.acc(t.acc) + '</b><span>' + FMP.src(t.src) + '<span class="ell">' + FMP.esc(t.artist) + '</span><span class="tm">· ' + (o.time || '1:36') + ' / ' + t.dur + '</span></span></div>' +
      '<button class="ibtn" aria-label="' + (o.paused ? '播放' : '暫停') + '">' + I(o.paused ? 'play' : 'pause', 's24') + '</button>' +
      '<button class="ibtn" aria-label="下一首">' + I('next', 's24') + '</button></div>';
  };

  const TABS = [
    ['library', '音樂庫', 'library', 'library.html'],
    ['queue', '佇列', 'queue', 'queue.html'],
    ['settings', '設定', 'settings', 'settings.html'],
  ];
  FMP.dock = function (o) {
    o = o || {};
    const tab = o.tab || 'library';
    const cls = ['dock'];
    if (o.track === false) cls.push('no-mini');
    const tabs = TABS.map(([k, label, icon, href]) => '<button class="tab' + (k === tab ? ' on' : '') + '" data-href="' + href + '" data-tab="' + k + '">' + I(icon) + '<span>' + label + '</span></button>').join('');
    return '<div class="' + cls.join(' ') + '">' +
      (o.track === false ? '' : FMP.mini(o.track, o)) +
      '<nav class="lg tabbar" data-adapt aria-label="主導覽"><span class="tab-ind"></span>' + tabs + '</nav>' +
      '<button class="lg search-orb' + (tab === 'search' ? ' on' : '') + '" data-adapt data-href="search.html" aria-label="搜尋">' + I('search') + '</button>' +
      '</div>';
  };

  /* phone frame. o: content, top, dock (object|false), overlay, onMedia, bg, scrollCls */
  FMP.phone = function (ctx, o) {
    const dock = o.dock === false ? '' : FMP.dock(o.dock || {});
    return '<div class="phone scr t-' + ctx.theme + (o.onMedia ? ' on-media' : '') + '" data-tone="' + ctx.theme + '" style="' + (o.bg ? 'background:' + o.bg : '') + '">' +
      '<div class="content">' + (o.raw ? o.content : '<div class="page scroll ' + (o.scrollCls || '') + '">' + o.content + '</div>') + '</div>' +
      (o.noEdge ? '' : '<div class="edge-top"></div>') +
      (o.top || '') + dock + (o.overlay || '') + FMP.statusBar() + '<div class="homebar"></div></div>';
  };

  /* top bar with an inline title that appears once the large title scrolls away */
  FMP.ptop = function (title, left, right, inset) {
    return '<div class="ptop"' + (inset ? ' style="--pt-inset:' + inset + 'px"' : '') + '>' + (left || '') + '<span class="ptitle">' + title + '</span><span class="sp"></span>' + (right || '') + '</div>';
  };
  FMP.gbtn = (icon, label, extra) => '<button class="lg gbtn" data-adapt aria-label="' + label + '" ' + (extra || '') + '>' + I(icon) + '</button>';
  FMP.gpill = (items) => '<div class="lg gpill" data-adapt>' + items.map(([icon, label]) => '<button class="ibtn" aria-label="' + label + '">' + I(icon, 's20') + '</button>').join('') + '</div>';

  /* ---------------- desktop ---------------- */
  FMP.side = function (ctx, o) {
    o = o || {};
    const nav = o.nav || 'library';
    const item = (k, icon, label, cnt) => '<button class="nav-i' + (nav === k ? ' on' : '') + '" data-href="' + k + '.html">' + I(icon) + '<span>' + label + '</span>' + (cnt ? '<span class="cnt">' + cnt + '</span>' : '') + '</button>';
    const pls = FMP.playlists.map((p) => '<button class="nav-pl' + (o.pl === p.id ? ' on' : '') + '" data-href="playlist.html">' + FMP.coverEl(p.cv, 20) + '<span class="ell">' + FMP.esc(p.name) + '</span>' + (p.kind === 'imported' ? FMP.src(p.src) : '') + '</button>').join('');
    return '<aside class="lg side" data-lg-blur="6">' +
      '<div class="lights"><i></i><i></i><i></i></div>' +
      '<div class="sfield' + (nav === 'search' ? ' on' : '') + '" data-href="search.html">' + I('search') + '<span>' + (o.query ? FMP.esc(o.query) : '搜尋三個音源') + '</span><kbd>⌘K</kbd></div>' +
      item('library', 'library', '音樂庫') + item('queue', 'queue', '佇列', '64') +
      '<div class="nav-h"><span>歌單</span><button class="ibtn" aria-label="新建歌單">' + I('plus') + '</button></div>' +
      '<div class="scroll" style="flex:1;min-height:0;display:flex;flex-direction:column;gap:1px;margin:0 -4px;padding:0 4px">' + pls + '</div>' +
      '<div class="sfoot">' + item('settings', 'settings', '設定') + '</div></aside>';
  };

  /* desktop transport capsule (spine, same as the phone mini player). o: left, right, shuffle, repeat, paused, progress */
  FMP.transport = function (t, o) {
    o = o || {};
    t = t || FMP.now;
    const left = o.left ?? 280, right = o.right ?? 344;
    const pct = o.progress ?? 38;
    return '<div class="lg transport" data-adapt style="left:' + left + 'px;right:' + right + 'px">' +
      '<span class="played" style="width:' + pct + '%"></span>' +
      '<div class="ti" data-act="open-player" role="button">' + FMP.coverEl(t.cv, 44) + '<div style="min-width:0;display:flex;flex-direction:column;gap:2px"><b><span class="tt">' + FMP.esc(t.title) + '</span>' + FMP.acc(t.acc) + '</b><span>' + FMP.src(t.src) + '<span class="tt">' + FMP.esc(t.artist) + '</span></span></div></div>' +
      '<div class="row-c">' +
      '<button class="ibtn' + (o.shuffle ? ' on' : '') + '" aria-label="隨機">' + I('shuffle', 's18') + '</button>' +
      '<button class="ibtn" aria-label="上一首">' + I('prev', 's20') + '</button>' +
      '<button class="ibtn big" aria-label="暫停">' + I(o.paused ? 'play' : 'pause', 's24') + '</button>' +
      '<button class="ibtn" aria-label="下一首">' + I('next', 's20') + '</button>' +
      '<button class="ibtn' + (o.repeat ? ' on' : '') + '" aria-label="循環">' + I(o.repeat === 'one' ? 'repeat1' : 'repeat', 's18') + '</button></div>' +
      '<div class="tr"><span class="tm">1:36 / ' + t.dur + '</span><button class="ibtn" aria-label="歌詞">' + I('lyrics', 's18') + '</button><button class="ibtn" aria-label="佇列">' + I('queue', 's18') + '</button><button class="ibtn" aria-label="音量">' + I('volume', 's18') + '</button></div></div>';
  };

  FMP.detailPanel = function (ctx, o) {
    o = o || {};
    const t = o.track || FMP.now;
    const glass = document.documentElement.dataset.reach === 'B';
    const next = ['t02', 't03', 't04'].map((id) => FMP.trackRow(FMP.T[id], { desk: true, size: 32, more: false, style: 'padding:0 6px;min-height:44px' })).join('');
    return '<aside class="detail' + (glass ? ' lg' : '') + '"' + (glass ? ' data-adapt data-lg-blur="10"' : '') + '>' +
      '<div class="dhead"><span>正在播放</span><span class="sp"></span>' +
      '<button class="ibtn" aria-label="加入歌單">' + I('addlist', 's18') + '</button>' +
      '<div class="seg" style="margin:0 2px"><button class="on" style="height:24px;padding:0 9px">' + I('info', 's16') + '</button><button style="height:24px;padding:0 9px">' + I('lyrics', 's16') + '</button></div>' +
      '<button class="ibtn" aria-label="收起面板">' + I('sidebarR', 's18') + '</button></div>' +
      '<div class="dbody scroll">' +
      FMP.coverEl(t.cv, null, '', 'width:100%;aspect-ratio:1;border-radius:12px;box-shadow:0 12px 30px rgba(0,0,0,.25)') +
      '<div style="margin-top:14px;font-size:17px;line-height:22px;font-weight:700">' + FMP.esc(t.title) + '</div>' +
      '<div class="c2" style="font-size:13px;margin-top:2px">' + FMP.esc(t.artist) + '</div>' +
      '<div style="display:flex;flex-wrap:wrap;gap:6px;margin-top:10px;align-items:center">' + FMP.srcChip(t.src, true) + FMP.acc(t.acc, true) + (t.id === 't01' ? '<span class="src-chip">' + I('wave', 's16') + '無損 · 會員</span>' : '') + '</div>' +
      (t.id === 't01'
        ? '<div style="display:flex;gap:18px;margin-top:14px" class="c2"><span style="font-size:12px"><b class="num" style="color:var(--label);font-size:13px">8,214</b> 則評論</span><span style="font-size:12px">專輯《<span style="color:var(--label)">夜行</span>》</span></div>'
        : (t.plays ? '<div style="margin-top:14px;font-size:12px" class="c2"><b class="num" style="color:var(--label);font-size:13px">' + t.plays + '</b> 次播放</div>' : '')) +
      '<div style="margin:22px 0 4px;font-size:12px;font-weight:700;color:var(--label-2)">下一首</div>' + next +
      '<div style="margin:20px 0 6px;font-size:12px;font-weight:700;color:var(--label-2)">簡介</div>' +
      (t.id === 't01' ? '<div class="c2" style="font-size:12.5px;line-height:1.55">收錄於 2026 年專輯《夜行》。錄音在台北一間舊公寓完成，鋼琴是房東留下的老琴，最後一段的雜音是窗外的末班車。</div>' : '<div class="c3" style="font-size:12.5px">這個音源沒有提供簡介。</div>') +
      '</div></aside>';
  };

  /* desktop window. o: nav, pl, content, top, detail(bool), transport(bool|track), overlay, query */
  FMP.desktop = function (ctx, o) {
    const detail = o.detail !== false;
    const right = detail ? 344 : 24; // 24 clear of the detail panel (320) or the window edge; left is 24 clear of the sidebar (ends at 256)
    const scrollStyle = 'padding-right:' + (detail ? 320 : 0) + 'px;' + (o.scrollStyle || '');
    return '<div class="win scr desk t-' + ctx.theme + '" data-tone="' + ctx.theme + '">' +
      (o.ambient ? FMP.ambient(o.ambient) : '') +
      (detail && document.documentElement.dataset.reach === 'B' ? '<div class="amb-r">' + FMP.ambient(((o.detailOpts && o.detailOpts.track) || FMP.now).cv) + '</div>' : '') +
      '<div class="wcontent">' + (o.raw ? o.content : '<div class="scroll" style="' + scrollStyle + '">' + o.content + '</div>') + '</div>' +
      '<div class="edge-top" style="left:0;right:' + (detail ? 320 : 0) + 'px"></div>' +
      (o.top ? '<div class="wtop" style="left:248px;right:' + (detail ? 328 : 8) + 'px">' + o.top + '</div>' : '') +
      FMP.side(ctx, { nav: o.nav, pl: o.pl, query: o.query }) +
      (detail ? FMP.detailPanel(ctx, o.detailOpts) : '') +
      (o.transport === false ? '' : FMP.transport(o.transport && o.transport !== true ? o.transport : null, { right, ...(o.transportOpts || {}) })) +
      (o.overlay || '') + '</div>';
  };

  /* desktop settings window: app sidebar + a category column + one pane (macOS System Settings).
   * o: cat (id in FMP.SETTINGS_CATS), content (pane html), overlay,
   *    updates (plugin updates from the last manual check, default 2; 0 hides), expiring (membership warning dot, default true) */
  const SX_DISK = '<svg class="i" viewBox="0 0 24 24" aria-hidden="true"><ellipse cx="12" cy="6.5" rx="7.5" ry="2.8"/><path d="M4.5 6.5v11c0 1.5 3.4 2.8 7.5 2.8s7.5-1.3 7.5-2.8v-11M4.5 12c0 1.5 3.4 2.8 7.5 2.8s7.5-1.3 7.5-2.8"/></svg>';
  FMP.SETTINGS_CATS = [
    ['account', 'user', '帳號'], ['plugins', 'plugin', '插件'], '-',
    ['appearance', 'appearance', '外觀'], ['playback', 'wave', '播放'], ['lyrics', 'lyrics', '歌詞'],
    ['imported', 'refresh', '匯入歌單'], ['storage', 'disk', '儲存空間'], ['data', 'importBox', '資料'], '-',
    ['about', 'info', '關於'],
  ];
  FMP.settingsShell = function (ctx, o) {
    const updates = o.updates ?? 2;
    const badge = (id) => id === 'account' && o.expiring !== false ? '<span class="dot" title="會員快到期"></span>'
      : id === 'plugins' && updates ? '<span class="cnt">' + updates + '</span>' : '';
    const cats = FMP.SETTINGS_CATS.map((c) => c === '-' ? '<div class="sx-sep"></div>' :
      '<button class="sx-i' + (o.cat === c[0] ? ' on' : '') + '"><span class="gicon">' + (c[1] === 'disk' ? SX_DISK : I(c[1])) + '</span><span>' + c[2] + '</span><span class="sp"></span>' + badge(c[0]) + '</button>').join('');
    const content = '<div class="sx"><nav class="sx-cats" aria-label="設定分類"><div class="field">' + I('search') + '<span class="ph">搜尋設定</span></div>' + cats + '</nav>' +
      '<div class="sx-pane scroll">' + o.content + '</div></div>';
    return FMP.desktop(ctx, {
      nav: 'settings', raw: true, content, detail: false,
      top: '<span class="sx-wt">設定</span><span class="sp"></span>' + FMP.gbtn('sidebarR', '顯示詳情面板'),
      overlay: o.overlay,
    });
  };

  FMP.ambient = function (cv, strength) {
    const [a, b, c] = cv.colors;
    const s = strength || 1;
    return '<div class="ambient" style="background:' + a + '">' +
      '<i style="left:-10%;top:-15%;width:70%;height:75%;background:' + b + ';opacity:' + (0.85 * s) + '"></i>' +
      '<i style="right:-15%;top:20%;width:65%;height:70%;background:' + c + ';opacity:' + (0.55 * s) + '"></i>' +
      '<i style="left:20%;bottom:-25%;width:70%;height:60%;background:' + b + ';opacity:' + (0.6 * s) + '"></i>' +
      '<span style="position:absolute;inset:0;background:rgba(0,0,0,.28)"></span></div>';
  };

  /* phone: a track's "more" sheet. items: [icon, label, hint, cls], '-' (thin), '=' (thick, before actions that change data) or raw html */
  FMP.trackSheet = function (t, items, o) {
    o = o || {};
    const head = '<div class="th">' + FMP.coverEl(t.cv, 52) + '<div class="m"><b><span class="tt">' + FMP.esc(t.title) + '</span>' + FMP.acc(t.acc) + '</b><span>' + FMP.src(t.src, true) + '<span>·</span><span class="tt">' + FMP.esc(o.sub || t.artist) + '</span></span></div></div>';
    const body = items.map((it) => it === '-' ? '<div class="ts"></div>' : it === '=' ? '<div class="ts thick"></div>' : typeof it === 'string' ? it
      : '<button class="ti ' + (it[3] || '') + '" role="menuitem">' + I(it[0]) + '<span class="l">' + it[1] + '</span>' + (it[2] ? '<small>' + it[2] + '</small>' : '') + '</button>').join('');
    return '<div class="sheet-wrap"' + (o.wrapStyle ? ' style="' + o.wrapStyle + '"' : '') + '><div class="lg sheet tsheet" role="menu" aria-label="' + FMP.esc(t.title) + ' 的動作"><div class="grab"></div>' + head + '<div class="ts"></div>' + body + '</div></div>';
  };

  /* centered confirm with the tracks it acts on (covers included).
   * o: who (html chip), title, body, tracks (ids or track objects), more (extra count), ok, okCls, cancel, style, wrapStyle */
  FMP.confirm = function (o) {
    const list = (o.tracks || []).map((x) => typeof x === 'string' ? FMP.T[x] : x);
    const rows = list.length ? '<div class="cf-list">' + list.map((t) => '<div class="cf-t">' + FMP.coverEl(t.cv, 36) + '<div class="m"><b><span class="tt">' + FMP.esc(t.title) + '</span>' + FMP.acc(t.acc) + '</b><span>' + FMP.src(t.src) + '<span class="tt">' + FMP.esc(t.artist) + '</span></span></div><span class="num">' + t.dur + '</span></div>').join('') +
      (o.more ? '<div class="cf-more">還有 ' + o.more + ' 首</div>' : '') + '</div>' : '';
    return '<div class="dialog-wrap"' + (o.wrapStyle ? ' style="' + o.wrapStyle + '"' : '') + '><div class="lg alert cf" role="alertdialog"' + (o.style ? ' style="' + o.style + '"' : '') + '>' + (o.who ? '<span class="cf-who">' + o.who + '</span>' : '') +
      '<h4>' + o.title + '</h4>' + (o.body ? '<p>' + o.body + '</p>' : '') + rows +
      '<div class="acts"><button class="btn btn-gray">' + (o.cancel || '取消') + '</button><button class="btn ' + (o.okCls || 'btn-danger') + '">' + o.ok + '</button></div></div></div>';
  };

  /* refresh status row. o: state 'busy' | 'err', text, pct, action (button html) */
  FMP.refreshLine = function (o) {
    const icon = o.state === 'err' ? I('warn') : '<span class="spinner"></span>';
    return '<div class="rfs ' + (o.state || 'busy') + '" role="status"><span class="tx">' + icon + '<span>' + o.text + '</span></span>' + (o.action || '') +
      (o.pct !== undefined ? '<span class="rline" style="width:' + o.pct + '%"></span>' : '') + '</div>';
  };

  FMP.toast = (html, o) => '<div class="lg toast" data-adapt style="' + ((o && o.style) || 'bottom:112px') + '">' + html + '</div>';

  /* ---------------------------------------------------------------- */
  /* Review harness                                                     */
  /* ---------------------------------------------------------------- */
  const PAGES = [
    ['index.html', '總覽'], ['system.html', '設計系統'], ['shell.html', '外殼與迷你播放器'], ['search.html', '搜尋'],
    ['library.html', '音樂庫'], ['playlist.html', '歌單詳情'], ['queue.html', '佇列'], ['player.html', '播放頁'],
    ['add-to-playlist.html', '加入歌單'], ['account.html', '帳號與登入'], ['plugins.html', '插件'],
    ['settings.html', '設定'], ['backup-import.html', '匯入舊版備份'],
  ];
  FMP.PAGES = PAGES;
  const PREFS = { theme: 'both', glass: 'refract', reach: 'A', accent: 'none' };
  try { Object.assign(PREFS, JSON.parse(localStorage.getItem('fmp-draft-prefs') || '{}')); } catch (e) { /* ignore broken storage */ }
  FMP.ACCENTS = [['none', '無', null], ['violet', '堇紫', '#5E4BFF'], ['indigo', '靛藍', '#3D5BD9'], ['teal', '青綠', '#00786F']];
  // drafts before 2026-11-10 stored accent 'on'/'none' for the old A/B toggle; the owner then made "none" the default
  if (!FMP.ACCENTS.some(([k]) => k === PREFS.accent)) PREFS.accent = 'none';
  FMP.prefs = PREFS;
  function applyPrefs() {
    const h = document.documentElement;
    h.dataset.glass = PREFS.glass;
    h.dataset.reach = PREFS.reach;
    h.dataset.accent = PREFS.accent;
  }
  applyPrefs();

  function bar(current) {
    const g = (key, label, opts) => '<span class="grp">' + label + '<span class="opts">' + opts.map(([v, l]) => '<button data-pref="' + key + '" data-v="' + v + '" class="' + (PREFS[key] === v ? 'on' : '') + '">' + l + '</button>').join('') + '</span></span>';
    return '<div class="rv-bar"><a class="home" href="index.html">FMP · D 設計稿 B</a>' +
      '<nav>' + PAGES.slice(1).map(([h, l]) => '<a href="' + h + '" class="' + (h === current ? 'on' : '') + '">' + l + '</a>').join('') + '</nav><span class="sp"></span>' +
      g('theme', '外觀', [['both', '並排'], ['dark', '深'], ['light', '淺']]) +
      g('glass', '玻璃', [['refract', '折射'], ['standard', '標準'], ['minimal', '最低']]) +
      g('reach', '玻璃範圍', [['A', 'A 控制層'], ['B', 'B 延伸']]) +
      g('accent', '強調色', FMP.ACCENTS.map(([k, l]) => [k, k === 'none' ? '無（預設）' : l])) + '</div>';
  }

  FMP.page = function (spec) {
    const current = location.pathname.split('/').pop() || 'index.html';
    document.body.classList.add('rv');
    function render() {
      applyPrefs();
      const themes = PREFS.theme === 'both' ? ['dark', 'light'] : [PREFS.theme];
      let h = bar(current) + '<main class="rv-main"><div class="rv-intro"><h1>' + spec.title + '</h1>' + (spec.intro || '') + (spec.noSynthetic ? '' : '<p style="color:#6A6775;font-size:13px">封面、曲名、歌手、帳號名稱都是虛構的示範資料。</p>') + '</div>';
      let n = 0;
      (spec.sections || []).forEach((sec) => {
        h += '<section class="rv-sec">' + (sec.title ? '<h2>' + sec.title + '</h2>' : '') + (sec.desc ? '<p class="d">' + sec.desc + '</p>' : '');
        if (sec.html) h += sec.html;
        const frames = sec.frames || [];
        const phones = frames.filter((f) => f.kind === 'phone' || f.kind === 'panel');
        const desks = frames.filter((f) => f.kind === 'desktop');
        if (phones.length) {
          h += '<div class="rv-row">';
          phones.forEach((f) => themes.forEach((th) => {
            h += '<div class="rv-frame"><div class="cap"><b>' + f.label + '</b>' + (themes.length > 1 ? (th === 'dark' ? '深色' : '淺色') : '') + '</div><div class="' + (f.kind === 'panel' ? 'pad-panel' : 'pad-phone') + '" data-frame="' + (n++) + '" data-th="' + th + '"></div></div>';
          }));
          h += '</div>';
        }
        desks.forEach((f) => themes.forEach((th) => {
          h += '<div class="rv-frame" style="margin-top:36px"><div class="cap"><b>' + f.label + '</b>' + (themes.length > 1 ? (th === 'dark' ? '深色' : '淺色') : '') + '</div><div class="desk-slot" data-frame="' + (n++) + '" data-th="' + th + '"></div></div>';
        }));
        if (sec.notes) h += '<div class="rv-notes">' + sec.notes + '</div>';
        h += '</section>';
      });
      h += '</main>';
      document.body.innerHTML = h;
      // mount
      let k = 0;
      const all = [];
      (spec.sections || []).forEach((sec) => {
        const frames = sec.frames || [];
        const ordered = frames.filter((f) => f.kind === 'phone' || f.kind === 'panel').concat(frames.filter((f) => f.kind === 'desktop'));
        ordered.forEach((f) => themes.forEach((th) => all.push([f, th])));
      });
      all.forEach(([f, th]) => {
        const slot = document.querySelector('[data-frame="' + (k++) + '"]');
        const ctx = { theme: th, uid: 'f' + k };
        slot.innerHTML = f.render(ctx);
        const root = slot.firstElementChild;
        if (f.kind === 'desktop') fitDesktop(slot, root);
        wire(root, ctx);
        if (f.after) f.after(root, ctx);
      });
      document.querySelectorAll('[data-pref]').forEach((b) => b.addEventListener('click', () => {
        PREFS[b.dataset.pref] = b.dataset.v;
        localStorage.setItem('fmp-draft-prefs', JSON.stringify(PREFS));
        const y = scrollY;
        render();
        scrollTo(0, y);
      }));
      requestAnimationFrame(() => { window.FMPGlass && FMPGlass.scan(document); FMPGlass && FMPGlass.updateTones(); });
      setTimeout(() => window.FMPGlass && FMPGlass.updateTones(), 300);
    }
    function fitDesktop(slot, root) {
      const avail = Math.min(slot.parentElement.parentElement.clientWidth || 1280, 1600);
      const sc = Math.min(1, avail / 1280);
      slot.style.width = 1280 * sc + 'px';
      slot.style.height = 800 * sc + 'px';
      root.classList.add('rv-scale');
      root.style.transform = sc < 1 ? 'scale(' + sc + ')' : '';
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', render); else render();
    let rt;
    window.addEventListener('resize', () => { clearTimeout(rt); rt = setTimeout(() => document.querySelectorAll('.desk-slot').forEach((s) => fitDesktop(s, s.firstElementChild)), 150); });
  };

  /* behaviours shared by every frame */
  function wire(root, ctx) {
    // scroll edge only: the dock keeps its shape while scrolling (owner, 2026-11-10)
    const sc = root.querySelector('.page.scroll, .wcontent > .scroll');
    if (sc) sc.addEventListener('scroll', () => root.classList.toggle('scrolled', sc.scrollTop > 12), { passive: true });
    // tab indicator: a capsule that slides and stretches between tabs
    root.querySelectorAll('.tabbar').forEach((bar) => {
      const ind = bar.querySelector('.tab-ind');
      const place = (tab, animate) => {
        if (!tab || !ind) return;
        if (!animate) ind.style.transition = 'none';
        ind.style.left = tab.offsetLeft + 'px';
        ind.style.width = tab.offsetWidth + 'px';
        if (!animate) requestAnimationFrame(() => (ind.style.transition = ''));
      };
      requestAnimationFrame(() => place(bar.querySelector('.tab.on'), false));
      bar.querySelectorAll('.tab').forEach((tab) => tab.addEventListener('click', (e) => {
        e.stopPropagation();
        bar.querySelectorAll('.tab').forEach((x) => x.classList.toggle('on', x === tab));
        bar.classList.add('pressing');
        place(tab, true);
        setTimeout(() => bar.classList.remove('pressing'), 240);
        const href = tab.dataset.href;
        if (href && !location.pathname.endsWith(href)) setTimeout(() => (location.href = href), 560);
      }));
    });
    root.querySelectorAll('[data-href]:not(.tab)').forEach((n) => n.addEventListener('click', (e) => {
      e.stopPropagation();
      const href = n.dataset.href;
      if (href && !location.pathname.endsWith(href)) location.href = href;
    }));
    root.querySelectorAll('[data-act="open-player"]').forEach((n) => n.addEventListener('click', (e) => {
      if (e.target.closest('.ibtn')) return;
      if (!location.pathname.endsWith('player.html')) location.href = 'player.html';
    }));
    // generic toggles for demo controls
    root.querySelectorAll('.switch, .tog[data-toggle], .check[data-toggle]').forEach((n) => n.addEventListener('click', () => n.classList.toggle('on')));
  }
  FMP.wire = wire;
})();
