// The app's menu bar glyphs (Sources/BattisticsApp/Theme/BatGlyph.swift),
// drawn as SVG with the same geometry. Coordinates are y-up like AppKit and
// flipped once by the wrapping group.

export type GlyphShape = "bat" | "classic" | "gauge" | "stats" | "wings";

export interface GlyphState {
  shape: GlyphShape;
  /** 0...1 */
  fraction: number;
  charging: boolean;
  /** Drawn inside the glyph in place of the level, as "percentage inside". */
  percentage?: number;
}

const W = 34;
const H = 20;

const f = (v: number) => +v.toFixed(3);
const pt = (x: number, y: number) => `${f(x)} ${f(y)}`;

function roundedRect(x: number, y: number, w: number, h: number, r: number) {
  r = Math.min(r, w / 2, h / 2);
  return (
    `M${pt(x + r, y)}H${f(x + w - r)}A${f(r)} ${f(r)} 0 0 1 ${pt(x + w, y + r)}` +
    `V${f(y + h - r)}A${f(r)} ${f(r)} 0 0 1 ${pt(x + w - r, y + h)}` +
    `H${f(x + r)}A${f(r)} ${f(r)} 0 0 1 ${pt(x, y + h - r)}V${f(y + r)}A${f(r)} ${f(r)} 0 0 1 ${pt(x + r, y)}Z`
  );
}

function bolt(cx: number, cy: number, s: number) {
  return (
    `M${pt(cx + s * 0.18, cy + s * 0.95)}L${pt(cx - s * 0.45, cy - s * 0.1)}` +
    `L${pt(cx - s * 0.05, cy - s * 0.1)}L${pt(cx - s * 0.18, cy - s * 0.95)}` +
    `L${pt(cx + s * 0.45, cy + s * 0.1)}L${pt(cx + s * 0.05, cy + s * 0.1)}Z`
  );
}

function metrics(batShaped: boolean) {
  const stroke = Math.max(H * 0.075, 1.2);
  const earHeight = batShaped ? H * 0.2 : 0;
  const wingHeight = batShaped ? H * 0.16 : 0;
  const bodyWidth = W * 0.87;
  const left = stroke / 2;
  const right = left + bodyWidth;
  const top = H - earHeight - stroke / 2;
  const bottom = wingHeight + stroke / 2;
  const radius = (top - bottom) * 0.24;
  return { stroke, earHeight, wingHeight, bodyWidth, left, right, top, bottom, radius, midX: (left + right) / 2 };
}

type M = ReturnType<typeof metrics>;

function batOutline(m: M) {
  const c = (x1: number, y1: number, x2: number, y2: number, x: number, y: number) =>
    `C${pt(x1, y1)} ${pt(x2, y2)} ${pt(x, y)}`;
  let d = `M${pt(m.left, m.bottom + m.radius)}L${pt(m.left, m.top - m.radius)}`;
  d += c(m.left, m.top - m.radius * 0.45, m.left + m.radius * 0.45, m.top, m.left + m.radius, m.top);
  for (const earCenter of [m.left + m.bodyWidth * 0.3, m.left + m.bodyWidth * 0.62]) {
    const half = m.bodyWidth * 0.095;
    const peak = H;
    d += `L${pt(earCenter - half, m.top)}`;
    d += c(earCenter - half * 0.6, m.top + m.earHeight * 0.5, earCenter - half * 0.25, peak - m.earHeight * 0.1, earCenter - half * 0.1, peak);
    d += c(earCenter + half * 0.15, peak - m.earHeight * 0.3, earCenter + half * 0.6, m.top + m.earHeight * 0.4, earCenter + half, m.top);
  }
  d += `L${pt(m.right - m.radius, m.top)}`;
  d += c(m.right - m.radius * 0.45, m.top, m.right, m.top - m.radius * 0.45, m.right, m.top - m.radius);
  d += `L${pt(m.right, m.bottom + m.radius)}`;
  d += c(m.right, m.bottom + m.radius * 0.45, m.right - m.radius * 0.45, m.bottom, m.right - m.radius, m.bottom);
  d += c(m.left + m.bodyWidth * 0.68, m.bottom - m.wingHeight * 0.1, m.left + m.bodyWidth * 0.58, m.wingHeight * 0.25, m.midX, 0);
  d += c(m.left + m.bodyWidth * 0.42, m.wingHeight * 0.25, m.left + m.bodyWidth * 0.32, m.bottom - m.wingHeight * 0.1, m.left + m.radius, m.bottom);
  d += c(m.left + m.radius * 0.45, m.bottom, m.left, m.bottom + m.radius * 0.45, m.left, m.bottom + m.radius);
  return d + "Z";
}

function nub(m: M) {
  const h = (m.top - m.bottom) * 0.4;
  const w = W * 0.075;
  return roundedRect(m.right + m.stroke * 0.7, (m.top + m.bottom) / 2 - h / 2, w, h, w * 0.45);
}

function silhouette() {
  const p = (x: number, y: number) => pt(W * x, H * y);
  const c = (a: number[], b: number[], e: number[]) => `C${p(a[0], a[1])} ${p(b[0], b[1])} ${p(e[0], e[1])}`;
  return (
    `M${p(0.03, 0.6)}` +
    c([0.13, 0.86], [0.28, 0.84], [0.4, 0.8]) +
    c([0.41, 0.86], [0.41, 0.93], [0.43, 0.97]) +
    c([0.46, 0.92], [0.48, 0.86], [0.5, 0.84]) +
    c([0.52, 0.86], [0.54, 0.92], [0.57, 0.97]) +
    c([0.59, 0.93], [0.59, 0.86], [0.6, 0.8]) +
    c([0.72, 0.84], [0.87, 0.86], [0.97, 0.6]) +
    c([0.88, 0.44], [0.8, 0.36], [0.7, 0.36]) +
    c([0.64, 0.36], [0.6, 0.3], [0.56, 0.24]) +
    c([0.53, 0.18], [0.51, 0.1], [0.5, 0.06]) +
    c([0.49, 0.1], [0.47, 0.18], [0.44, 0.24]) +
    c([0.4, 0.3], [0.36, 0.36], [0.3, 0.36]) +
    c([0.2, 0.36], [0.12, 0.44], [0.03, 0.6]) +
    "Z"
  );
}

const strokeAttrs = (w: number) =>
  `fill="none" stroke="currentColor" stroke-width="${f(w)}" stroke-linejoin="round" stroke-linecap="round"`;

let maskSeed = 0;

/** Inner SVG markup in a 34×20 y-up box; wrap with `glyphSVG`. */
export function glyphBody({ shape, fraction, charging: chargingState, percentage }: GlyphState): string {
  const level = percentage === undefined ? Math.min(Math.max(fraction, 0), 1) : 0;
  // The percentage replaces the level and the bolt; the menu bar draws the bolt beside it.
  const charging = percentage === undefined && chargingState;
  if (shape === "bat" || shape === "classic") {
    const m = metrics(shape === "bat");
    const outline = shape === "bat" ? batOutline(m) : roundedRect(m.left, m.bottom, m.bodyWidth, m.top - m.bottom, m.radius);
    let out = `<path d="${outline}" ${strokeAttrs(m.stroke)}/><path d="${nub(m)}" fill="currentColor"/>`;
    if (charging) {
      out += `<path d="${bolt(m.midX, (m.top + m.bottom) / 2, (m.top - m.bottom) * 0.6)}" fill="currentColor"/>`;
    } else {
      const inset = m.stroke * 1.9;
      const ix = m.left + inset;
      const iy = m.bottom + inset * 0.8;
      const iw = m.bodyWidth - inset * 2;
      const ih = m.top - m.bottom - inset * 1.6;
      if (iw * level > 1) out += `<path d="${roundedRect(ix, iy, iw * level, ih, ih * 0.22)}" fill="currentColor" fill-opacity=".55"/>`;
    }
    return out;
  }
  if (shape === "gauge") {
    const stroke = Math.max(H * 0.09, 1.3);
    const cx = W / 2;
    const cy = H * 0.16;
    const r = Math.min(W / 2, H * 0.8) - stroke;
    let out = `<path d="M${pt(cx - r, cy)}A${f(r)} ${f(r)} 0 0 0 ${pt(cx + r, cy)}" ${strokeAttrs(stroke)}/>`;
    if (charging) return out + `<path d="${bolt(cx, cy + r * 0.42, r * 0.75)}" fill="currentColor"/>`;
    const angle = ((180 - 180 * level) * Math.PI) / 180;
    const len = r - stroke * 1.6;
    out += `<path d="M${pt(cx, cy)}L${pt(cx + Math.cos(angle) * len, cy + Math.sin(angle) * len)}" ${strokeAttrs(stroke)}/>`;
    return out + `<circle cx="${f(cx)}" cy="${f(cy)}" r="${f(stroke * 0.9)}" fill="currentColor"/>`;
  }
  if (shape === "stats") {
    const m = metrics(false);
    let out = `<path d="${roundedRect(m.left, m.bottom, m.bodyWidth, m.top - m.bottom, m.radius)}" ${strokeAttrs(m.stroke)}/><path d="${nub(m)}" fill="currentColor"/>`;
    if (charging) return out + `<path d="${bolt(m.midX, (m.top + m.bottom) / 2, (m.top - m.bottom) * 0.6)}" fill="currentColor"/>`;
    const inset = m.stroke * 2;
    const ix = m.left + inset;
    const iy = m.bottom + inset * 0.9;
    const iw = m.bodyWidth - inset * 2;
    const ih = m.top - m.bottom - inset * 1.8;
    const gap = iw * 0.06;
    const bw = (iw - gap * 4) / 5;
    const heights = [0.34, 0.5, 0.68, 0.84, 1];
    const lit = level <= 0 ? 0 : Math.max(Math.ceil(level * 5), 1);
    heights.forEach((h, i) => {
      out += `<path d="${roundedRect(ix + i * (bw + gap), iy, bw, ih * h, bw * 0.3)}" fill="currentColor" fill-opacity="${i < lit ? 1 : 0.25}"/>`;
    });
    return out;
  }
  const body = silhouette();
  const id = `wing${++maskSeed}`;
  let out = `<clipPath id="${id}c"><path d="${body}"/></clipPath>`;
  if (level > 0 || charging) {
    const fill = `<rect x="0" y="0" width="${W}" height="${f(charging ? H : H * level)}" fill="currentColor" fill-opacity="${charging ? 0.9 : 0.6}" clip-path="url(#${id}c)"/>`;
    if (charging) {
      out += `<mask id="${id}m"><rect width="${W}" height="${H}" fill="#fff"/><path d="${bolt(W / 2, (H / 2) * 1.05, H * 0.42)}" fill="#000"/></mask><g mask="url(#${id}m)">${fill}<path d="${body}" ${strokeAttrs(Math.max(H * 0.06, 1))}/></g>`;
      return out;
    }
    out += fill;
  }
  return out + `<path d="${body}" ${strokeAttrs(Math.max(H * 0.06, 1))}/>`;
}

/** The app's status ladder: charging blue, 10% red, 20% orange, 95% green. */
export function glyphTone(fraction: number, charging: boolean): "charging" | "critical" | "low" | "full" | "plain" {
  if (charging) return "charging";
  if (fraction <= 0.1) return "critical";
  if (fraction <= 0.2) return "low";
  if (fraction >= 0.95) return "full";
  return "plain";
}

/** Where each shape fits its digits, y-up, as in BatGlyph.drawPercentage. */
function percentBox(shape: GlyphShape): [number, number, number, number] {
  if (shape === "gauge") {
    const stroke = Math.max(H * 0.09, 1.3);
    const r = Math.min(W / 2, H * 0.8) - stroke;
    return [W / 2 - r * 0.7, H * 0.16 + stroke * 0.25, r * 1.4, r * 0.58];
  }
  if (shape === "wings") return [W * 0.24, H * 0.405, W * 0.52, H * 0.375];
  const m = metrics(shape === "bat");
  return [m.left + m.stroke, m.bottom + m.stroke / 2, m.bodyWidth - m.stroke * 2, m.top - m.bottom - m.stroke];
}

function percentText(shape: GlyphShape, value: number): string {
  const digits = String(Math.min(Math.max(Math.round(value), 0), 100));
  const [x, y, w, h] = percentBox(shape);
  // SF digits are about 0.6em wide and 0.72em tall.
  const size = Math.min(H * (11 / 17), w / (0.6 * digits.length), h / 0.72);
  return `<text x="${f(x + w / 2)}" y="${f(H - (y + h / 2))}" font-size="${f(size)}" font-weight="600" text-anchor="middle" dominant-baseline="central" fill="currentColor" font-family="-apple-system, BlinkMacSystemFont, system-ui, sans-serif" style="font-variant-numeric: tabular-nums">${digits}</text>`;
}

export function glyphSVG(state: GlyphState, attrs = ""): string {
  const text = state.percentage === undefined ? "" : percentText(state.shape, state.percentage);
  return `<svg viewBox="-1 -1 ${W + 2} ${H + 2}" ${attrs} aria-hidden="true"><g transform="translate(0 ${H}) scale(1 -1)">${glyphBody(state)}</g>${text}</svg>`;
}

export const GLYPH_SHAPES: { shape: GlyphShape; label: string }[] = [
  { shape: "bat", label: "Bat" },
  { shape: "classic", label: "Classic" },
  { shape: "gauge", label: "Gauge" },
  { shape: "stats", label: "Stats" },
  { shape: "wings", label: "Wings" },
];
