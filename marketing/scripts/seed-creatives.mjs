import {readFile,writeFile} from 'node:fs/promises';

// Adapt the accepted campaign inside Apple's measured art-safe areas.
// The existing editor owns rendering, phone frames, fonts and export.
const file=new URL('../app-store-screenshots.json',import.meta.url);
const project=JSON.parse(await readFile(file,'utf8'));
const rect=(x,y,width,height,zIndex=5)=>({x,y,width,height,rotation:0,zIndex});
const text=(id,value,x,y,w,h,size,color='#F3F0E7',weight=620)=>({id,text:value,transform:rect(x,y,w,h),fontSize:size,fontWeight:weight,lineHeight:1.06,letterSpacing:-2,color,align:'left'});
const art=(id,src,x,y,w,h,z=3)=>({id,src:`/artwork/companion/${src}`,transform:rect(x,y,w,h,z),fit:'contain'});
const slide=(id,extra)=>({id,layout:'no-device',label:{en:'',tr:''},headline:{en:'',tr:''},screenshot:'',backgroundColor:'#002D30',inverted:false,transforms:{caption:rect(0,0,1,1)},...extra});
const line={en:'Within reach.',tr:'Elinin altında.'};
const hero={en:'Your Mac.\nWithin reach.',tr:'Mac’in\nelinin altında.'};

project.slidesByDevice['creative-universal']=[slide('companion-universal',{
  textElements:[text('message',line,1970,690,1300,180,142)],
  imageElements:[art('nightwatch','nightwatch-cutout.png',2000,905,1240,700)],
})];
project.slidesByDevice['creative-header']=[slide('companion-header',{
  textElements:[text('message',hero,1130,600,790,400,118)],
  imageElements:[art('nightwatch','nightwatch-cutout.png',1925,515,790,615)],
})];
project.slidesByDevice['creative-search']=[slide('companion-search',{
  screenshot:'/screenshots/apple/iphone/{locale}/01-nearby.png',
  transforms:{caption:rect(0,0,1,1),device:rect(2420,790,435,945,7)},
  textElements:[text('message',hero,900,830,1120,440,162),text('detail',{en:'Battery. Keep Awake.',tr:'Pil. Uyanık Tut.'},910,1350,1060,130,70,'#BED4C9',420)],
  imageElements:[art('mascot','mascot-wave.png',1770,1215,640,560,8)],
})];
await writeFile(file,JSON.stringify(project,null,2)+'\n');
console.log('Seeded localized universal/header/search decks; accepted iPhone deck preserved.');
