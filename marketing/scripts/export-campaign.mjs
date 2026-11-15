import { chromium } from 'playwright';
import { mkdir, writeFile, readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import JSZip from 'jszip';
import sharp from 'sharp';
import assert from 'node:assert/strict';

// Drive the existing editor exporter; keep its font, paint and RGB checks.
// Example: node scripts/export-campaign.mjs http://127.0.0.1:3116 ../.build/app-store-still-on
const base = process.argv[2] || 'http://127.0.0.1:3116';
const root = fileURLToPath(new URL('../', import.meta.url));
const out = path.resolve(root, process.argv[3] || '../.build/app-store-still-on');
await mkdir(out, { recursive: true });
const projectRaw = await readFile(path.join(root, 'app-store-screenshots.json'), 'utf8');
const browser = await chromium.launch({ channel:'chrome', headless:true });
try {
  const page = await browser.newPage({ viewport:{width:1600,height:1100}, acceptDownloads:true });
  const failures = [];
  page.on('pageerror', e => failures.push(e.message));
  page.on('console', msg => { if (msg.type() === 'error' && /Export failed/.test(msg.text())) failures.push(msg.text()); });
  // Rendering must never autosave a browser's stale project into the workspace.
  await page.route('**/api/project', route => route.fulfill({json:{ok:true,state:JSON.parse(projectRaw)},headers:{ETag:'"campaign-export"'}}));
  await page.goto(base);
  await page.getByRole('button',{name:'Export bundle',exact:true}).waitFor();
  await page.waitForFunction(() => document.body.textContent.includes('YOUR MAC.'), { timeout:30000 });
  await page.evaluate(async()=>{await document.fonts.ready;});
  const font = JSON.parse(projectRaw).importedFont;
  if(font) assert.equal((await page.request.get(base+font.src)).status(),200,'Imported font must be served before export.');
  const download = page.waitForEvent('download',{timeout:240000});
  await page.getByRole('button',{name:'Export bundle',exact:true}).click();
  console.log('Rendering the English/Turkish campaign with the editor exporter.');
  const bundle = await download;
  const zipPath = path.join(out,'battistics-remote-still-on-en-tr.zip');
  await bundle.saveAs(zipPath);
  assert.deepEqual(failures,[]);
  const zip = await JSZip.loadAsync(await readFile(zipPath));
  const pngs = Object.values(zip.files).filter(f=>!f.dir&&f.name.endsWith('.png'));
  assert.equal(pngs.length,48);
  const report=[];
  for(const f of pngs){
    const bytes=await f.async('nodebuffer');
    const target=path.resolve(out,f.name);
    assert.ok(target.startsWith(out+path.sep));
    await mkdir(path.dirname(target),{recursive:true});
    await writeFile(target,bytes);
    const meta=await sharp(bytes).metadata();
    const [w,h]=f.name.split('/')[2].split('x').map(Number);
    assert.equal(meta.width,w);assert.equal(meta.height,h);assert.equal(meta.hasAlpha,false);assert.equal(meta.channels,3);
    report.push({file:f.name,width:w,height:h,channels:meta.channels,hasAlpha:meta.hasAlpha});
  }
  for(const locale of ['en','tr']){
    const folder=path.join(out,'ios/iphone/1320x2868',locale);
    const files=(await readdir(folder)).filter(f=>f.endsWith('.png')).sort();
    for(const width of [360,160]){
      const height=Math.round(width*2868/1320),gap=20;
      const parts=await Promise.all(files.map(async(f,i)=>({input:await sharp(path.join(folder,f)).resize({width}).png().toBuffer(),left:gap+(i%3)*(width+gap),top:gap+Math.floor(i/3)*(height+gap)})));
      await sharp({create:{width:width*3+gap*4,height:height*2+gap*3,channels:3,background:'#B9B9B3'}}).composite(parts).png().toFile(path.join(out,`${width===360?'contact-sheet':'thumbnail-sheet'}-${locale}.png`));
    }
  }
  const toasts=await page.locator('[data-sonner-toast]').allTextContents();
  assert.ok(!toasts.some(t=>/missing|failed|placeholder/i.test(t)),toasts.join('\n'));
  await writeFile(path.join(out,'export-validation.json'),JSON.stringify({pngs:report,toasts,errors:failures},null,2)+'\n');
  assert.equal(await readFile(path.join(root,'app-store-screenshots.json'),'utf8'),projectRaw);
  console.log(`Validated ${pngs.length} opaque RGB PNGs, all configured sizes, and both localized contact sheets: ${out}`);
} finally { await browser.close(); }
