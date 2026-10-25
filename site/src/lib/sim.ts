// One simulated Mac shared by every interactive part of the page: the menu
// bar, the popover, the icon settings and the Keep Awake demo.

import type { GlyphShape } from "./glyph";

export type LowPowerPolicy = "never" | "always" | "battery" | "adapter";
export type AwakeMode = "displayOn" | "displayMaySleep" | "lidClosed";
export type MenuBarText = "none" | "charge" | "health" | "time" | "temperature" | "watts" | "mah";

export interface MenuBarConfig {
  style: GlyphShape;
  showGlyph: boolean;
  percentInside: boolean;
  primary: MenuBarText;
  secondary: MenuBarText;
  colorLow: boolean;
  lowThreshold: number;
  colorHigh: boolean;
  colorCharging: boolean;
  awakeIcon: boolean;
}

export interface Session {
  mode: AwakeMode;
  minutes: number;
  startedAt: number;
}

export interface SimState {
  charge: number;
  charging: boolean;
  onAdapter: boolean;
  lowPower: LowPowerPolicy;
  session: Session | null;
  config: MenuBarConfig;
}

export const defaultState: SimState = {
  charge: 82,
  charging: false,
  onAdapter: false,
  lowPower: "never",
  session: null,
  config: {
    style: "bat",
    showGlyph: true,
    percentInside: false,
    primary: "charge",
    secondary: "none",
    colorLow: true,
    lowThreshold: 20,
    colorHigh: false,
    colorCharging: false,
    awakeIcon: true,
  },
};

export const POLICY_LABELS: Record<LowPowerPolicy, string> = {
  never: "Never",
  always: "Always",
  battery: "Only on battery",
  adapter: "Only on power adapter",
};

export const MODE_LABELS: Record<AwakeMode, string> = {
  displayOn: "Keep the display on",
  displayMaySleep: "Let the display sleep",
  lidClosed: "Stay awake with the lid closed",
};

export const TEXT_LABELS: Record<MenuBarText, string> = {
  none: "Nothing",
  charge: "Charge %",
  health: "Health %",
  time: "Time remaining",
  temperature: "Temperature",
  watts: "Power (W)",
  mah: "Charge (mAh)",
};

/** Whether Low Power Mode applies to the source in use right now. */
export function lowPowerActive(state: SimState): boolean {
  switch (state.lowPower) {
    case "always": return true;
    case "battery": return !state.onAdapter;
    case "adapter": return state.onAdapter;
    default: return false;
  }
}

/** The app's charge ring colour: red at 10%, orange at 20%, yellow in Low Power. */
export function chargeTone(state: SimState): "red" | "orange" | "yellow" | "green" {
  if (state.charge <= 10) return "red";
  if (state.charge <= 20) return "orange";
  return lowPowerActive(state) ? "yellow" : "green";
}

/** The menu bar tint ladder, each rung switchable as in Settings › Menu Bar. */
export function statusTint(state: SimState): "blue" | "red" | "orange" | "green" | null {
  const c = state.config;
  if (c.colorCharging && state.charging) return "blue";
  if (c.colorLow && !state.onAdapter) {
    if (state.charge <= 10) return "red";
    if (state.charge <= c.lowThreshold) return "orange";
  }
  if (c.colorHigh && state.charge >= 95) return "green";
  return null;
}

export function readingText(kind: MenuBarText, state: SimState): string {
  const minutes = Math.round((state.charge / 100) * 420);
  switch (kind) {
    case "charge": return `${state.charge}%`;
    case "health": return "86%";
    case "time": return state.onAdapter ? "Full" : `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")}`;
    case "temperature": return "34°";
    case "watts": return state.onAdapter ? "+42 W" : "9.8 W";
    case "mah": return `${Math.round(state.charge * 51.49).toLocaleString("en-US")} mAh`;
    default: return "";
  }
}

let state: SimState = structuredClone(defaultState);
const listeners = new Set<(state: SimState) => void>();

export function getState(): SimState {
  return state;
}

export function update(change: (draft: SimState) => void) {
  const next = structuredClone(state);
  change(next);
  state = next;
  const root = document.documentElement;
  root.dataset.lowPower = String(lowPowerActive(state));
  root.dataset.awake = String(state.session !== null);
  for (const listener of listeners) listener(state);
}

export function subscribe(listener: (state: SimState) => void) {
  listeners.add(listener);
  listener(state);
  return () => listeners.delete(listener);
}

export function remainingSeconds(session: Session, now = Date.now()): number | null {
  if (session.minutes === 0) return null;
  return Math.max(0, Math.round((session.startedAt + session.minutes * 60_000 - now) / 1000));
}

export function startSession(mode: AwakeMode, minutes: number) {
  update((s) => (s.session = { mode, minutes, startedAt: Date.now() }));
}

export function stopSession() {
  update((s) => (s.session = null));
}
