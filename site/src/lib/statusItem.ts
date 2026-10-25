// The menu bar item as MenuBarIconRenderer composes it: glyph, readings,
// a bolt beside a percentage drawn inside, and the Keep Awake cup.

import { glyphSVG } from "./glyph";
import { symbolHTML } from "./symbols";
import { readingText, statusTint, type SimState } from "./sim";

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
    if (inside && state.charging) html += symbolHTML("bolt.fill", 11, "si-bolt");
  }
  if (texts.length) html += `<span class="si-text">${texts.join(" ")}</span>`;
  if (c.awakeIcon && state.session) html += symbolHTML("cup.and.saucer.fill", 12, "si-cup");
  return html;
}

/** Sets the tint class in place, keeping the element's other classes. */
export function applyTint(element: HTMLElement, state: SimState) {
  const tint = statusTint(state);
  for (const name of ["blue", "red", "orange", "green"]) element.classList.toggle(`tint-${name}`, tint === name);
}
