import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import sharp from 'sharp';

const root = fileURLToPath(new URL('../', import.meta.url));
const out = path.join(root, 'public/artwork/companion');
await mkdir(out, {recursive:true});
const svg = (w,h,body,viewBox=`0 0 ${w} ${h}`) => `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${w}" height="${h}" viewBox="${viewBox}">${body}</svg>`;

// Viewports enlarge real captured pixels. No interface or readings are redrawn.
for(const locale of ['en','tr']){
  const folder=path.join(out,locale);await mkdir(folder,{recursive:true});
  async function crop(name,file,sourceW,sourceH,x,y,w,h,radius){
    const bytes=await readFile(path.join(root,`public/screenshots/apple/iphone/${locale}/${file}.png`));
    const uri=`data:image/png;base64,${bytes.toString('base64')}`;
    const content=`<defs><clipPath id="clip"><rect width="${w}" height="${h}" rx="${radius}"/></clipPath><filter id="shadow" x="-25%" y="-35%" width="150%" height="180%"><feDropShadow dx="0" dy="16" stdDeviation="20" flood-color="#082F32" flood-opacity=".22"/></filter></defs><g transform="translate(45 35)" filter="url(#shadow)"><g clip-path="url(#clip)"><image xlink:href="${uri}" x="${-x}" y="${-y}" width="${sourceW}" height="${sourceH}"/></g></g>`;
    await writeFile(path.join(folder,`${name}.svg`),svg(w+90,h+100,content));
  }
  if(locale==='tr')await crop('activity','02',1320,2868,44,1999,1230,462,80);
  else await crop('activity','02',1320,2868,48,1943,1225,506,80);
  await crop('keep-awake','03',1320,2868,49,1140,1222,675,84);
  await crop('battery-gauge','03',1320,2868,66,454,260,260,130);
  await crop('battery-power','03',1320,2868,95,714,360,128,38);
  await crop('battery-health','03',1320,2868,480,714,360,128,38);
  await crop('battery-temperature','03',1320,2868,865,714,360,128,38);
  await crop('accessories','04',1320,2868,49,locale==='tr'?2034:1928,1222,790,84);
}

const night=await readFile(path.join(out,'nightwatch.png'));
const meta=await sharp(night).metadata();
const top=Math.round(meta.height*.23),height=Math.round(meta.height*.74);
await writeFile(path.join(out,'night-scene.svg'),svg(meta.width,height,
  `<image xlink:href="data:image/png;base64,${night.toString('base64')}" width="${meta.width}" height="${meta.height}"/>`,
  `0 ${top} ${meta.width} ${height}`));

const journey=await readFile(path.join(out,'journey.png'));
await writeFile(path.join(out,'journey-window.svg'),svg(1200,1500,
  `<defs><clipPath id="window"><path d="M0 600 A600 600 0 0 1 1200 600 V1460 Q1200 1500 1160 1500 H40 Q0 1500 0 1460 Z"/></clipPath></defs><image xlink:href="data:image/png;base64,${journey.toString('base64')}" width="1200" height="1500" preserveAspectRatio="xMidYMid slice" clip-path="url(#window)"/>`));

// Quiet background forms echo a battery's curved edges without imitating UI.
await writeFile(path.join(out,'mint-arc.svg'),svg(1320,2868,
  '<path d="M1320 960 C820 960 730 1280 730 1680 V2868 H1320 Z" fill="#DDE8D4"/><path d="M1320 1040 C900 1040 810 1340 810 1680 V2868" fill="none" stroke="#9BB9AC" stroke-width="2"/>'));
console.log('Built localized native viewports and the companion scene crops.');
