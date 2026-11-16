import {chromium} from 'playwright';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import path from 'node:path';
import JSZip from 'jszip';
import sharp from 'sharp';
import assert from 'node:assert/strict';

const base=process.argv[2]||'http://127.0.0.1:3116';
const out=path.resolve('../.build/app-store-companion/creatives');await mkdir(out,{recursive:true});
const raw=await readFile('app-store-screenshots.json','utf8'),project=JSON.parse(raw);
const sizes={'creative-universal':[[5244,2950]],'creative-header':[[3840,1646]],'creative-search':[[3840,2560],[1920,1280]]};
const safe={'creative-universal':[1921,660,1402,962],'creative-header':[1097,493,1646,661],'creative-search':[836,765,2168,1030]};
const browser=await chromium.launch({channel:'chrome',headless:true});const report=[];
try{
  for(const [device,outputs] of Object.entries(sizes)){
    const page=await browser.newPage({viewport:{width:1600,height:1000},acceptDownloads:true});const errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    let locale='en';
    await page.route('**/api/project',r=>r.fulfill({json:{ok:true,state:{...project,device,orientation:'portrait',locale}},headers:{ETag:'"creative-export"'}}));
    for(locale of project.locales){
      await page.goto(base);await page.getByRole('button',{name:'Export bundle',exact:true}).waitFor();
      await page.waitForSelector('[data-text-element]');
      await page.evaluate(async()=>{for(const w of [420,620])await document.fonts.load(`${w} 64px "ImportedScreenshotFont"`);await document.fonts.ready;});
      const width=outputs[0][0];
      const measurements=await page.evaluate(({width})=>{
        const root=[...document.querySelectorAll('div')].find(e=>e.style.left==='-99999px'&&e.style.width===`${width}px`);
        if(!root)throw Error('Export canvas missing');
        return [...root.querySelectorAll('[data-text-element]')].map(owner=>{
          const content=owner.firstElementChild,range=document.createRange();range.selectNodeContents(content);const box=owner.getBoundingClientRect();
          const rects=[...range.getClientRects()].filter(r=>r.width>0&&r.height>0);
          const lines=new Set(rects.map(r=>Math.round(r.top*2)/2)).size;
          return {id:owner.dataset.textElement,text:content.textContent,lines,expected:content.textContent.split('\n').length,overflow:rects.some(r=>r.left<box.left-1||r.right>box.right+1||r.top<box.top-1||r.bottom>box.bottom+1)};
        });
      },{width});
      assert.deepEqual(measurements.filter(m=>m.overflow||m.lines>m.expected),[],`${device}/${locale}: text layout`);
      report.push({device,locale,text:measurements});
    }
    const [sx,sy,sw,sh]=safe[device];
    for(const slide of project.slidesByDevice[device])for(const item of [...slide.textElements||[],...slide.imageElements||[]]){
      const t=item.transform;assert.ok(t.x>=sx&&t.y>=sy&&t.x+t.width<=sx+sw&&t.y+t.height<=sy+sh,`${device}/${item.id}: outside art-safe area`);
    }
    const pending=page.waitForEvent('download',{timeout:240000});await page.getByRole('button',{name:'Export bundle',exact:true}).click();
    const zipPath=path.join(out,`${device}-en-tr.zip`);await(await pending).saveAs(zipPath);
    const zip=await JSZip.loadAsync(await readFile(zipPath));const pngs=Object.values(zip.files).filter(f=>!f.dir&&f.name.endsWith('.png'));
    assert.equal(pngs.length,outputs.length*project.locales.length);
    for(const file of pngs){
      const bytes=await file.async('nodebuffer'),dest=path.join(out,file.name);await mkdir(path.dirname(dest),{recursive:true});await writeFile(dest,bytes);
      const meta=await sharp(bytes).metadata(),[w,h]=file.name.split('/')[2].split('x').map(Number);
      assert.equal(meta.width,w);assert.equal(meta.height,h);assert.equal(meta.channels,3);assert.equal(meta.hasAlpha,false);
      report.push({file:file.name,width:w,height:h,channels:meta.channels});
    }
    const toasts=await page.locator('[data-sonner-toast]').allTextContents();assert.ok(!toasts.some(t=>/missing|failed|placeholder/i.test(t)),toasts.join('\n'));assert.deepEqual(errors,[]);
    await page.close();console.log(`Validated ${device}: ${pngs.length} RGB exports.`);
  }
  await writeFile(path.join(out,'validation.json'),JSON.stringify(report,null,2)+'\n');assert.equal(await readFile('app-store-screenshots.json','utf8'),raw);
}finally{await browser.close();}
