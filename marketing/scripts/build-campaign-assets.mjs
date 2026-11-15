import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// SVG viewports present unaltered native captures as enlarged UI details.
// No interface, measurement or control is redrawn or generated.
const root = fileURLToPath(new URL('../', import.meta.url));
const out = path.join(root, 'public/artwork/on-duty');
await mkdir(out, { recursive: true });
const svg = (w, h, body) => `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${body}</svg>`;
const save = (name, w, h, body) => writeFile(path.join(out, `${name}.svg`), svg(w, h, body));

for (const locale of ['en', 'tr']) {
  const folder = path.join(out, locale);
  await mkdir(folder, { recursive: true });
  async function crop(name, file, originalW, originalH, x, y, w, h, radius) {
    const bytes = await readFile(path.join(root, `public/screenshots/apple/iphone/${locale}/${file}.png`));
    const uri = `data:image/png;base64,${bytes.toString('base64')}`;
    const body = `<defs><clipPath id="clip"><rect width="${w}" height="${h}" rx="${radius}"/></clipPath><filter id="shadow" x="-20%" y="-30%" width="140%" height="170%"><feDropShadow dx="0" dy="18" stdDeviation="22" flood-opacity=".24"/></filter></defs><g transform="translate(45 35)" filter="url(#shadow)"><g clip-path="url(#clip)"><image xlink:href="${uri}" x="${-x}" y="${-y}" width="${originalW}" height="${originalH}"/></g></g>`;
    await writeFile(path.join(folder, `${name}.svg`), svg(w + 90, h + 100, body));
  }
  await crop('session', '01-nearby', 1206, 2622, 48, 926, 1110, 679, 78);
  if (locale === 'tr') await crop('activity', '02', 1320, 2868, 44, 1999, 1230, 462, 80);
  else await crop('activity', '02', 1320, 2868, 48, 1943, 1225, 506, 80);
  await crop('battery-gauge', '03', 1320, 2868, 66, 454, 260, 260, 130);
  await crop('battery-metrics', '03', 1320, 2868, 95, 714, 1130, 128, 38);
  await crop('capacity', '05', 1320, 2868, 60, 1112, 1200, 467, 86);
  await crop('accessories', '04', 1320, 2868, 49, locale === 'tr' ? 2034 : 1928, 1222, 790, 84);
}

// Original vector campaign art, deliberately distinct from the app interface.
await save('timer', 1320, 1500, `<g transform="translate(660 720)"><circle r="505" fill="#F5D865"/><circle r="456" fill="none" stroke="#17191B" stroke-width="2" opacity=".18"/>${Array.from({length:60}, (_,i)=>`<path d="M 0 -430 v ${i%5===0?52:22}" transform="rotate(${i*6})" stroke="#17191B" stroke-width="${i%5===0?6:3}" opacity=".5"/>`).join('')}<path d="M0 -505 A505 505 0 0 1 505 0" fill="none" stroke="#FF793B" stroke-width="30"/><circle r="12" fill="#17191B"/><path d="M0 0 L-120 -240 M0 0 L260 -80" stroke="#17191B" stroke-width="12" stroke-linecap="round"/></g>`);
await save('pointer', 400, 250, `<path d="M25 20 C30 170 220 220 350 115 M300 115 L355 110 L342 170" fill="none" stroke="#FF793B" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>`);
await save('signal', 1320, 2868, `<path d="M-60 2370 H210 Q270 2370 270 2310 V2140 Q270 2080 330 2080 H890 Q950 2080 950 2020 V1900 Q950 1840 1010 1840 H1400" stroke="#FF793B" stroke-width="9" fill="none"/><g fill="#FF793B"><circle cx="270" cy="2310" r="16"/><circle cx="950" cy="2020" r="16"/></g><g stroke="#EEEAE2" opacity=".12" stroke-width="2"><path d="M0 2420 H230 Q320 2420 320 2330 V2200 Q320 2140 380 2140 H940 Q1010 2140 1010 2080 V1980 Q1010 1920 1070 1920 H1320"/><path d="M0 2470 H280 Q370 2470 370 2380 V2260 Q370 2200 430 2200 H990 Q1070 2200 1070 2140 V2060 Q1070 2000 1130 2000 H1320"/></g>`);
await save('accessory-lines', 1320, 900, `<g fill="none" stroke="#17191B" stroke-width="11" stroke-linecap="round" stroke-linejoin="round"><g transform="translate(110 170) rotate(-14 170 220)"><rect x="20" y="0" width="270" height="420" rx="132"/><path d="M155 0 V140 M20 140 H290"/><rect x="135" y="50" width="40" height="60" rx="18" fill="#FF793B" stroke="none"/></g><g transform="translate(700 140) rotate(16 160 250)"><path d="M30 250 V150 C30 -20 300 -20 300 150 V250" stroke-width="48"/><rect x="0" y="220" width="80" height="160" rx="38" fill="#FF793B" stroke="none"/><rect x="250" y="220" width="80" height="160" rx="38" fill="#FF793B" stroke="none"/><path d="M30 250 V150 C30 -20 300 -20 300 150 V250" stroke="#EEEAE2" stroke-width="16"/></g></g>`);
await save('routes', 1320, 2868, `<g fill="none" stroke-linecap="round" stroke-linejoin="round"><path d="M140 1240 V1400 H1040 Q1110 1400 1110 1470 V2360" stroke="#FF793B" stroke-width="12"/><path d="M140 1630 V1770 H960 Q1030 1770 1030 1840 V2360" stroke="#EEEAE2" stroke-width="8"/><path d="M140 2000 V2140 H870 Q940 2140 940 2210 V2360" stroke="#7BA8B6" stroke-width="8"/>${[1240,1630,2000].map((y,i)=>`<circle cx="140" cy="${y}" r="31" fill="${['#FF793B','#EEEAE2','#7BA8B6'][i]}" stroke="#17191B" stroke-width="12"/>`).join('')}<rect x="842" y="2310" width="340" height="180" rx="44" fill="#FF793B" stroke="#17191B" stroke-width="12"/><path d="M960 2380 h100 v55 H960 z M940 2440 h140" stroke="#17191B" stroke-width="10"/></g>`);
console.log('Built native capture viewports and original campaign vector art.');
