// Game icon generator: draws the launcher icon as SVG layers on the 432x432
// Android adaptive canvas (108dp; launchers show the centre 72dp, the safe
// circle is 66dp) and renders them with Chromium via Playwright.
//
//   node tools/icon/make_icon.js            -> writes the chosen icon (DEFAULT) into the project
//   node tools/icon/make_icon.js pick=spire -> writes another design
//   node tools/icon/make_icon.js out=/tmp/x -> writes every design's layers to /tmp/x for review
//
// Project outputs: icon.png (512, full bleed), assets/icon/foreground.png,
// background.png and monochrome.png (432, Android adaptive / themed icon).
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const OUT = process.argv[2] || 'out';
fs.mkdirSync(OUT, { recursive: true });
const S = 432; // adaptive canvas; visible ~ center 288, safe circle r=132

const C = {
  top: '#0b1830', bottom: '#020308', cyan: '#2ef2ff', mag: '#ff2bd6',
  white: '#eafcff', green: '#39ff9e', gold: '#ffd23a', card: '#0a1122',
};

function rng(seed) {
  let s = seed >>> 0;
  return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
}

// Voronoi cells by half-plane clipping (small n, fine).
function clip(poly, a, b, c) { // keep a*x+b*y <= c
  const out = [];
  for (let i = 0; i < poly.length; i++) {
    const p = poly[i], q = poly[(i + 1) % poly.length];
    const fp = a * p[0] + b * p[1] - c, fq = a * q[0] + b * q[1] - c;
    if (fp <= 0) out.push(p);
    if ((fp < 0) !== (fq < 0) && fp !== fq) {
      const t = fp / (fp - fq);
      out.push([p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])]);
    }
  }
  return out;
}
function voronoi(seeds, x0, y0, x1, y1) {
  return seeds.map((s, i) => {
    let poly = [[x0, y0], [x1, y0], [x1, y1], [x0, y1]];
    seeds.forEach((o, j) => {
      if (i === j) return;
      const a = o[0] - s[0], b = o[1] - s[1];
      const c = (o[0] * o[0] + o[1] * o[1] - s[0] * s[0] - s[1] * s[1]) / 2;
      poly = clip(poly, a, b, c);
    });
    return poly;
  });
}
const pts = (p) => p.map((q) => q[0].toFixed(1) + ',' + q[1].toFixed(1)).join(' ');

function glassBackground(seed, opts = {}) {
  const r = rng(seed);
  const n = opts.cells || 16;
  const seeds = [];
  for (let i = 0; i < n; i++) seeds.push([r() * (S + 60) - 30, r() * (S + 60) - 30]);
  const cells = voronoi(seeds, -10, -10, S + 10, S + 10);
  const fills = ['#0b2a3a', '#0a1d33', '#2a0d33', '#0c3340', '#1a0f2e', '#081a2a', '#300a2c'];
  let g = '';
  cells.forEach((poly, i) => {
    const f = fills[Math.floor(r() * fills.length)];
    g += `<polygon points="${pts(poly)}" fill="${f}" fill-opacity="${(0.55 + r() * 0.4).toFixed(2)}"/>`;
  });
  // neon leading: cyan or magenta edges, glowing
  let lines = '';
  cells.forEach((poly) => {
    const col = r() < 0.6 ? C.cyan : C.mag;
    lines += `<polygon points="${pts(poly)}" fill="none" stroke="${col}" stroke-opacity="${(0.25 + r() * 0.35).toFixed(2)}" stroke-width="2"/>`;
  });
  return `
  <defs>
    <linearGradient id="bgG" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${C.top}"/><stop offset="1" stop-color="${C.bottom}"/></linearGradient>
    <radialGradient id="bgGlow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="${opts.glow || C.cyan}" stop-opacity="0.28"/>
      <stop offset="1" stop-color="${opts.glow || C.cyan}" stop-opacity="0"/></radialGradient>
    <filter id="bgBlur" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="3"/></filter>
  </defs>
  <rect width="${S}" height="${S}" fill="url(#bgG)"/>
  <g>${g}</g>
  <g filter="url(#bgBlur)">${lines}</g>
  <g stroke="#01030a" stroke-width="3" fill="none">${cells.map((p) => `<polygon points="${pts(p)}"/>`).join('')}</g>
  <g>${lines}</g>
  <circle cx="216" cy="216" r="200" fill="url(#bgGlow)"/>`;
}

const glowDefs = `
  <defs>
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur in="SourceGraphic" stdDeviation="6" result="b"/>
      <feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
    <filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="10"/></filter>
  </defs>`;

// Shatter a polygon into shards around a point (for glass-pane fills).
function shards(poly, cx, cy, n, seed) {
  const r = rng(seed);
  const seeds = [];
  for (let i = 0; i < n; i++) {
    const a = r() * Math.PI * 2, d = Math.pow(r(), 0.7) * 120;
    seeds.push([cx + Math.cos(a) * d, cy + Math.sin(a) * d]);
  }
  const cells = voronoi(seeds, 0, 0, S, S);
  return cells.map((c) => {
    let p = c;
    // clip to convex poly
    for (let i = 0; i < poly.length; i++) {
      const A = poly[i], B = poly[(i + 1) % poly.length];
      // inside = left side for clockwise in screen coords; compute line
      const a = B[1] - A[1], b = A[0] - B[0];
      const cc = a * A[0] + b * A[1];
      // pick orientation so centroid is inside
      const gx = poly.reduce((s, q) => s + q[0], 0) / poly.length;
      const gy = poly.reduce((s, q) => s + q[1], 0) / poly.length;
      const sign = a * gx + b * gy - cc <= 0 ? 1 : -1;
      p = clip(p, sign * a, sign * b, sign * cc);
      if (p.length < 3) break;
    }
    return p;
  }).filter((p) => p.length >= 3);
}

function paneFill(poly, cx, cy, n, seed, palette) {
  const r = rng(seed + 7);
  return shards(poly, cx, cy, n, seed).map((p) => {
    const f = palette[Math.floor(r() * palette.length)];
    return `<polygon points="${pts(p)}" fill="${f}" fill-opacity="${(0.6 + r() * 0.35).toFixed(2)}" stroke="#01030a" stroke-width="3.5" stroke-linejoin="round"/>`;
  }).join('');
}

// ---------- Candidates (foreground layers, transparent) ----------
const FG = {};

// A: Ghost Sigil — the hub's triangle eye, filled with stained-glass shards.
FG.sigil = () => {
  const tri = [[216, 318], [104, 128], [328, 128]]; // pointing down like the hub mark
  const fill = paneFill(tri, 216, 196, 13, 11, ['#0f7f95', '#1450a8', '#6a1490', '#0aa0a8', '#a01a8a', '#1d3c8c']);
  return `${glowDefs}
  <polygon points="${pts(tri)}" fill="${C.cyan}" opacity="0.35" filter="url(#soft)"/>
  ${fill}
  <polygon points="${pts(tri)}" fill="none" stroke="${C.cyan}" stroke-width="9" stroke-linejoin="round" filter="url(#glow)"/>
  <polygon points="${pts(tri)}" fill="none" stroke="${C.white}" stroke-width="3" stroke-linejoin="round"/>
  <path d="M152 186 Q216 138 280 186 Q216 234 152 186 Z" fill="#01030a" stroke="${C.cyan}" stroke-width="5" filter="url(#glow)"/>
  <circle cx="216" cy="186" r="20" fill="${C.mag}" filter="url(#glow)"/>
  <circle cx="216" cy="186" r="8" fill="${C.white}"/>
  <circle cx="300" cy="300" r="6" fill="${C.mag}" filter="url(#glow)"/>
  <circle cx="132" cy="300" r="4" fill="${C.cyan}" filter="url(#glow)"/>`;
};

// B: Glass Spire — a faceted tower of stained glass with neon leading.
FG.spire = () => {
  const L = [[216, 82], [176, 330], [216, 350]];
  const R = [[216, 82], [256, 330], [216, 350]];
  const lf = paneFill(L, 200, 220, 8, 21, ['#0f7f95', '#0aa0a8', '#1450a8', '#0b5f86']);
  const rf = paneFill(R, 232, 220, 8, 23, ['#a01a8a', '#6a1490', '#c0207a', '#4a1478']);
  const traces = [
    'M176 330 L140 330 L120 350 L96 350', 'M256 330 L292 330 L312 350 L336 350',
    'M186 270 L150 270 L136 256', 'M246 270 L282 270 L296 256',
  ].map((d) => `<path d="${d}" fill="none" stroke="${C.cyan}" stroke-width="4" stroke-linecap="round" filter="url(#glow)"/>`).join('');
  const nodes = [[96, 350], [336, 350], [136, 256], [296, 256]].map(([x, y], i) =>
    `<circle cx="${x}" cy="${y}" r="6" fill="${i % 2 ? C.mag : C.cyan}" filter="url(#glow)"/>`).join('');
  return `${glowDefs}
  <ellipse cx="216" cy="350" rx="110" ry="14" fill="${C.mag}" opacity="0.5" filter="url(#soft)"/>
  <polygon points="216,82 176,330 216,350 256,330" fill="${C.cyan}" opacity="0.35" filter="url(#soft)"/>
  ${traces}${nodes}
  ${lf}${rf}
  <polyline points="216,82 216,350" stroke="${C.white}" stroke-width="3" fill="none"/>
  <polygon points="216,82 176,330 216,350 256,330" fill="none" stroke="${C.cyan}" stroke-width="8" stroke-linejoin="round" filter="url(#glow)"/>
  <polygon points="216,82 176,330 216,350 256,330" fill="none" stroke="${C.white}" stroke-width="2.5" stroke-linejoin="round"/>
  <circle cx="216" cy="82" r="10" fill="${C.white}" filter="url(#glow)"/>
  <path d="M216 52 L216 66 M190 64 L198 74 M242 64 L234 74" stroke="${C.cyan}" stroke-width="4" stroke-linecap="round" filter="url(#glow)"/>`;
};

// C: Cracked Card — one program card in the circuit frame, glass art window.
FG.card = () => {
  const x = 140, y = 92, w = 152, h = 248;
  const win = [[x + 18, y + 40], [x + w - 18, y + 40], [x + w - 18, y + 150], [x + 18, y + 150]];
  const art = paneFill(win, x + w / 2, y + 95, 10, 31, ['#0f7f95', '#1450a8', '#6a1490', '#0aa0a8', '#a01a8a']);
  return `${glowDefs}
  <g transform="rotate(-8 216 216)">
    <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="14" fill="${C.cyan}" opacity="0.35" filter="url(#soft)"/>
    <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="14" fill="${C.card}"/>
    ${art}
    <rect x="${x + 18}" y="${y + 40}" width="${w - 36}" height="110" fill="none" stroke="${C.cyan}" stroke-width="2.5"/>
    <polygon points="${x + w / 2},${y + 128} ${x + w / 2 - 28},${y + 66} ${x + w / 2 + 28},${y + 66}" fill="none" stroke="${C.white}" stroke-width="4" stroke-linejoin="round" filter="url(#glow)"/>
    <circle cx="${x + w / 2}" cy="${y + 84}" r="6" fill="${C.mag}" filter="url(#glow)"/>
    <circle cx="${x + 22}" cy="${y + 20}" r="12" fill="#01030a" stroke="${C.cyan}" stroke-width="3"/>
    <rect x="${x + 42}" y="${y + 15}" width="70" height="9" rx="4" fill="${C.white}" opacity="0.8"/>
    <rect x="${x + 22}" y="${y + 170}" width="${w - 44}" height="7" rx="3" fill="${C.white}" opacity="0.55"/>
    <rect x="${x + 22}" y="${y + 186}" width="${w - 64}" height="7" rx="3" fill="${C.white}" opacity="0.4"/>
    <path d="M${x + 6} ${y + 60} L${x + 6} ${y + 6} L${x + 60} ${y + 6} M${x + w - 6} ${y + h - 60} L${x + w - 6} ${y + h - 6} L${x + w - 60} ${y + h - 6}" fill="none" stroke="${C.cyan}" stroke-width="4" filter="url(#glow)"/>
    <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="14" fill="none" stroke="${C.cyan}" stroke-width="5" filter="url(#glow)"/>
    <path d="M${x + w} ${y + 70} L${x + w - 40} ${y + 110} L${x + w - 22} ${y + 140} L${x + w - 70} ${y + 210} L${x + w - 60} ${y + h}" fill="none" stroke="${C.mag}" stroke-width="5" stroke-linejoin="round" filter="url(#glow)"/>
    <path d="M${x + w} ${y + 70} L${x + w - 40} ${y + 110} L${x + w - 22} ${y + 140} L${x + w - 70} ${y + 210} L${x + w - 60} ${y + h}" fill="none" stroke="${C.white}" stroke-width="1.8" stroke-linejoin="round"/>
  </g>`;
};

// D: Card Spire — three fanned cards whose tops form a spire, glass faces.
FG.fan = () => {
  const card = (rot, pal, seed, edge, front) => {
    const x = 160, y = 96, w = 112, h = 196;
    const face = [[x + 10, y + 10], [x + w - 10, y + 10], [x + w - 10, y + h - 10], [x + 10, y + h - 10]];
    return `<g transform="rotate(${rot} 216 330)">
      <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="12" fill="${C.card}"/>
      ${paneFill(face, x + w / 2, y + h / 2 - 10, front ? 9 : 6, seed, pal)}
      <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="12" fill="none" stroke="${edge}" stroke-width="5" filter="url(#glow)"/>
      <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="12" fill="none" stroke="${C.white}" stroke-width="1.6" opacity="0.8"/>
      ${front ? `<polygon points="216,236 186,150 246,150" fill="none" stroke="${C.white}" stroke-width="4.5" stroke-linejoin="round" filter="url(#glow)"/>
      <circle cx="216" cy="172" r="7" fill="${C.mag}" filter="url(#glow)"/>` : ''}
    </g>`;
  };
  return `${glowDefs}
  <ellipse cx="216" cy="230" rx="130" ry="120" fill="${C.cyan}" opacity="0.18" filter="url(#soft)"/>
  ${card(-22, ['#a01a8a', '#6a1490', '#4a1478'], 41, C.mag, false)}
  ${card(22, ['#a01a8a', '#6a1490', '#4a1478'], 43, C.mag, false)}
  ${card(0, ['#0f7f95', '#1450a8', '#0aa0a8', '#6a1490'], 45, C.cyan, true)}`;
};

const SCALE = { sigil: 0.86, spire: 0.84, card: 0.8, fan: 0.84 };
const fgOf = (n) => `<g transform="translate(216 216) scale(${SCALE[n]}) translate(-216 -216)">${FG[n]()}</g>`;
const BG = {
  sigil: () => glassBackground(5, { glow: C.cyan }),
  spire: () => glassBackground(9, { glow: C.mag }),
  card: () => glassBackground(13, { glow: C.cyan }),
  fan: () => glassBackground(17, { glow: C.cyan }),
};

const svg = (inner, vb = `0 0 ${S} ${S}`) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${vb}" width="100%" height="100%">${inner}</svg>`;

module.exports = { FG, BG, svg, S, fgOf };

const DEFAULT = 'sigil';

// Themed-icon layer (Android 13+): solid white where the foreground is bright
// (neon lines, white cores); dark glass fills and soft halos drop out.
const monoLayer = (fg) => {
  const inner = fg.replace(/ filter="url\(#glow\)"/g, '').replace(/<[^>]*filter="url\(#soft\)"[^>]*\/>/g, '');
  return `
  <defs><filter id="monoA" x="0" y="0" width="100%" height="100%">
    <feColorMatrix in="SourceGraphic" type="luminanceToAlpha"/>
    <feComponentTransfer result="a"><feFuncA type="discrete" tableValues="0 0 0 0 0 1 1 1 1 1"/></feComponentTransfer>
    <feFlood flood-color="#ffffff"/><feComposite in2="a" operator="in"/>
  </filter></defs>
  <g filter="url(#monoA)">${inner}</g>`;
};

if (require.main === module) {
  const args = Object.fromEntries(process.argv.slice(2).map((a) => a.split('=')));
  const ROOT = path.resolve(__dirname, '..', '..');
  (async () => {
    const browser = await chromium.launch();
    const page = await browser.newPage({ deviceScaleFactor: 1 });
    const shot = async (inner, px, file, transparent, vb) => {
      await page.setViewportSize({ width: px, height: px });
      await page.setContent(`<html><body style="margin:0;background:transparent">${svg(inner, vb)}</body></html>`);
      await page.screenshot({ path: file, omitBackground: transparent });
    };
    // Full-bleed legacy icon: the adaptive visible area (centre 72 of 108dp).
    const pad = S * 18 / 108;
    const legacyVb = `${pad} ${pad} ${S - 2 * pad} ${S - 2 * pad}`;
    if (args.out) {
      fs.mkdirSync(args.out, { recursive: true });
      for (const n of Object.keys(FG)) {
        const fg = fgOf(n), bg = BG[n]();
        await shot(fg, 432, path.join(args.out, `${n}_fg.png`), true);
        await shot(bg, 432, path.join(args.out, `${n}_bg.png`), false);
        await shot(bg + fg, 512, path.join(args.out, `${n}_icon.png`), false, legacyVb);
        await shot(bg + fg, 432, path.join(args.out, `${n}_full432.png`), false);
      }
    } else {
      const n = args.pick || DEFAULT;
      if (!FG[n]) throw new Error(`unknown design ${n}; one of ${Object.keys(FG)}`);
      const fg = fgOf(n), bg = BG[n]();
      const dir = path.join(ROOT, 'assets', 'icon');
      fs.mkdirSync(dir, { recursive: true });
      await shot(fg, 432, path.join(dir, 'foreground.png'), true);
      await shot(bg, 432, path.join(dir, 'background.png'), false);
      await shot(monoLayer(fg), 432, path.join(dir, 'monochrome.png'), true);
      await shot(bg + fg, 512, path.join(ROOT, 'icon.png'), false, legacyVb);
      console.log(`wrote ${n}: icon.png, assets/icon/{foreground,background,monochrome}.png`);
    }
    await browser.close();
  })();
}
