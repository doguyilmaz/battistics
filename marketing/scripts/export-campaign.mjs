import { chromium } from 'playwright';
import { mkdir, writeFile, readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import JSZip from 'jszip';
import sharp from 'sharp';
import assert from 'node:assert/strict';

// Drive the existing editor exporter; keep its font, paint and RGB checks.
// Example: node scripts/export-campaign.mjs http://127.0.0.1:3116 ../.build/app-store-companion
const base = process.argv[2] || 'http://127.0.0.1:3116';
const root = fileURLToPath(new URL('../', import.meta.url));
const out = path.resolve(root, process.argv[3] || '../.build/app-store-companion');
await mkdir(out, { recursive: true });
const projectRaw = await readFile(path.join(root, 'app-store-screenshots.json'), 'utf8');
const project = JSON.parse(projectRaw);
const browser = await chromium.launch({ channel:'chrome', headless:true });
try {
  const page = await browser.newPage({ viewport:{width:1600,height:1100}, acceptDownloads:true });
  const failures = [];
  page.on('pageerror', e => failures.push(e.message));
  page.on('console', msg => { if (msg.type() === 'error' && /Export failed/.test(msg.text())) failures.push(msg.text()); });
  // Rendering must never autosave a browser's stale project into the workspace.
  let displayLocale=project.locale;
  await page.route('**/api/project', route => route.fulfill({json:{ok:true,state:{...project,locale:displayLocale}},headers:{ETag:'"campaign-export"'}}));
  const layout=[];
  for(const locale of project.locales){
    displayLocale=locale;
    await page.goto(base);
    await page.getByRole('button',{name:'Export bundle',exact:true}).waitFor();
    await page.waitForSelector('[data-text-element]');
    await page.evaluate(async()=>{
      for(const weight of [400,420,600,620])await document.fonts.load(`${weight} 64px "ImportedScreenshotFont"`);
      await document.fonts.ready;
    });
    const measurements=await page.evaluate(()=>{
      const root=[...document.querySelectorAll('div')].find(el=>el.style.left==='-99999px'&&el.style.width==='1320px');
      if(!root)throw Error('Export canvas missing');
      return [...root.querySelectorAll('[data-text-element]')].map(owner=>{
        const content=owner.firstElementChild;
        const range=document.createRange();range.selectNodeContents(content);
        const bounds=owner.getBoundingClientRect();
        const rects=[...range.getClientRects()].filter(r=>r.width>0&&r.height>0);
        const lines=new Set(rects.map(r=>Math.round(r.top*2)/2)).size;
        const expected=(content.textContent||'').split('\n').length;
        const overflow=rects.some(r=>r.left<bounds.left-1||r.right>bounds.right+1||r.top<bounds.top-1||r.bottom>bounds.bottom+1);
        return{id:owner.dataset.textElement,text:content.textContent,lines,expected,overflow};
      });
    });
    const bad=measurements.filter(m=>m.overflow||m.lines>m.expected);
    await writeFile(path.join(out,`layout-${locale}.json`),JSON.stringify(measurements,null,2)+'\n');
    assert.deepEqual(bad,[],`${locale}: copy clipped or wrapped beyond its intentional line breaks`);
    layout.push({locale,measured:measurements.length,clipped:0,unexpectedWraps:0});
  }
  const font = project.importedFont;
  if(font) assert.equal((await page.request.get(base+font.src)).status(),200,'Imported font must be served before export.');
  const download = page.waitForEvent('download',{timeout:240000});
  await page.getByRole('button',{name:'Export bundle',exact:true}).click();
  console.log('Rendering the English/Turkish campaign with the editor exporter.');
  const bundle = await download;
  const zipPath = path.join(out,'battistics-remote-companion-en-tr.zip');
  await bundle.saveAs(zipPath);
  assert.deepEqual(failures,[]);
  const zip = await JSZip.loadAsync(await readFile(zipPath));
  const pngs = Object.values(zip.files).filter(f=>!f.dir&&f.name.endsWith('.png'));
  assert.equal(pngs.length,project.slidesByDevice.iphone.length*project.locales.length*4);
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
  for(const locale of project.locales){
    const folder=path.join(out,'ios/iphone/1320x2868',locale);
    const files=(await readdir(folder)).filter(f=>f.endsWith('.png')).sort();
    for(const width of [360,160]){
      const height=Math.round(width*2868/1320),gap=20;
      const parts=await Promise.all(files.map(async(f,i)=>({input:await sharp(path.join(folder,f)).resize({width}).png().toBuffer(),left:gap+(i%3)*(width+gap),top:gap+Math.floor(i/3)*(height+gap)})));
      const rows=Math.ceil(files.length/3);
      await sharp({create:{width:width*3+gap*4,height:height*rows+gap*(rows+1),channels:3,background:'#CDD8D3'}}).composite(parts).png().toFile(path.join(out,`${width===360?'contact-sheet':'thumbnail-sheet'}-${locale}.png`));
    }
  }
  const toasts=await page.locator('[data-sonner-toast]').allTextContents();
  assert.ok(!toasts.some(t=>/missing|failed|placeholder/i.test(t)),toasts.join('\n'));
  await writeFile(path.join(out,'export-validation.json'),JSON.stringify({pngs:report,layout,toasts,errors:failures},null,2)+'\n');
  assert.equal(await readFile(path.join(root,'app-store-screenshots.json'),'utf8'),projectRaw);
  console.log(`Validated ${pngs.length} opaque RGB PNGs, all configured sizes, and both localized contact sheets: ${out}`);
} finally { await browser.close(); }
