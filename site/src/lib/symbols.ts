// SF Symbols rendered from the system at build time of these assets
// (public/symbols), used as masks so they take the text colour.

const SIZES: Record<string, [number, number]> = {
  "bolt.batteryblock": [90, 62], terminal: [90, 66],
  "cup.and.saucer": [98, 69], "cup.and.saucer.fill": [98, 69], leaf: [79, 67], "leaf.fill": [80, 66],
  gearshape: [79, 75], pin: [73, 81], "bolt.fill": [63, 81], wifi: [85, 60], "switch.2": [76, 68],
  "chevron.down": [71, 39], "stop.fill": [67, 59], cellularbars: [96, 63], "battery.100percent": [109, 51],
  laptopcomputer: [107, 59], "gauge.with.dots.needle.67percent": [76, 72], "chart.xyaxis.line": [84, 66],
  "bolt.circle": [76, 72], keyboard: [95, 58], iphone: [65, 75], "menubar.rectangle": [90, 66],
  "bell.badge": [73, 78], internaldrive: [90, 62], "questionmark.circle": [76, 72], "thermometer.medium": [49, 78],
  "arrow.uturn.backward.circle": [76, 72], "battery.25percent": [109, 51], personalhotspot: [102, 59],
  "checkmark.seal.fill": [83, 81], "moon.zzz.fill": [73, 80], "sun.max.fill": [80, 76], "lock.fill": [61, 70],
  icloud: [91, 63], "person.crop.circle.badge.xmark": [86, 77], "arrow.down.circle": [76, 72],
};

/** An inline symbol `height` px tall, in the current text colour. */
export function symbolHTML(name: string, height = 14, extraClass = ""): string {
  const [w, h] = SIZES[name] ?? [1, 1];
  const width = +((height * w) / h).toFixed(2);
  return `<i class="sf ${extraClass}" aria-hidden="true" style="width:${width}px;height:${height}px;-webkit-mask-image:url(/symbols/${name}.png);mask-image:url(/symbols/${name}.png)"></i>`;
}
