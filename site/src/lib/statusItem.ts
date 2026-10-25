// The menu bar item as MenuBarIconRenderer composes it: glyph, readings,
// a bolt beside a percentage drawn inside, and the Keep Awake cup.

import { glyphSVG } from "./glyph";
import { readingText, statusTint, type SimState } from "./sim";

export const CUP_SVG =
  '<svg viewBox="0 0 20 16" aria-hidden="true"><path d="M3 3.2h10.6v4.6a4.4 4.4 0 0 1-4.4 4.4H7.4A4.4 4.4 0 0 1 3 7.8zM13.6 4.6h1.3a2.3 2.3 0 0 1 0 4.6h-1.6" fill="currentColor" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/><path d="M1.5 14h15.4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>';

const BOLT_SVG =
  '<svg viewBox="0 0 8 12" aria-hidden="true"><path d="M5 0 0 7h3l-1 5 5-7H4z" fill="currentColor"/></svg>';

export function statusItemHTML(state: SimState): string {
  const c = state.config;
  const texts = [c.primary, c.secondary]
    .filter((kind) => kind !== "none" && !(c.percentInside && c.showGlyph && kind === "charge"))
    .map((kind) => readingText(kind, state));
  const showGlyph = c.showGlyph || texts.length === 0;
  const inside = c.percentInside && showGlyph;
  let html = "";
  if (showGlyph) {
    html += glyphSVG(
      {
        shape: c.style,
        fraction: state.charge / 100,
        charging: state.charging,
        percentage: inside ? state.charge : undefined,
      },
      `class="si-glyph${inside ? " si-inside" : ""}"`,
    );
    if (inside && state.charging) html += `<span class="si-bolt">${BOLT_SVG}</span>`;
  }
  if (texts.length) html += `<span class="si-text">${texts.join(" ")}</span>`;
  if (c.awakeIcon && state.session) html += `<span class="si-cup">${CUP_SVG}</span>`;
  return html;
}

/** Sets the tint class in place, keeping the element's other classes. */
export function applyTint(element: HTMLElement, state: SimState) {
  const tint = statusTint(state);
  for (const name of ["blue", "red", "orange", "green"]) element.classList.toggle(`tint-${name}`, tint === name);
}
