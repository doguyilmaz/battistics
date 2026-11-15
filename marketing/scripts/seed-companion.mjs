import {readFile,writeFile} from 'node:fs/promises';

const file=new URL('../app-store-screenshots.json',import.meta.url);
const project=JSON.parse(await readFile(file,'utf8'));
const copy=JSON.parse(await readFile(new URL('../copy/companion.json',import.meta.url),'utf8'));
const ink='#163E42',paper='#F3F0E7',night='#002D30',lime='#D5EF80';
const rect=(x,y,width,height,rotation=0,zIndex=5)=>({x,y,width,height,rotation,zIndex});
const text=(id,value,x,y,w,h,size,color,weight=400,lineHeight=1.22,letterSpacing=-.4)=>({id,text:value,transform:rect(x,y,w,h),fontSize:size,fontWeight:weight,lineHeight,letterSpacing,color,align:'left'});
const image=(id,src,x,y,w,h,rotation=0,zIndex=3,fade)=>({id,src:`/artwork/companion/${src}`,transform:rect(x,y,w,h,rotation,zIndex),fit:'contain',...(fade?{fade}:{})});
const panel=(name,x,y,w,h,rotation=0)=>image(name,`{locale}/${name}.svg`,x,y,w,h,rotation,9);
function page(key,layout,background,options={}){
  const dark=background===night;
  const {headlineRect=rect(90,180,1140,560),headlineSize=160,bodyRect=rect(100,720,1120,190),brand=true,...rest}=options;
  const elements=[
    ...(brand?[text('brand',{en:'Battistics Remote',tr:'Battistics Remote'},100,65,1100,115,39,dark?lime:ink,600,1.1,0)]:[]),
    text('headline',copy[key].headline,headlineRect.x,headlineRect.y,headlineRect.width,headlineRect.height,headlineSize,dark?paper:ink,620,1.04,-5),
    text('body',copy[key].body,bodyRect.x,bodyRect.y,bodyRect.width,bodyRect.height,52,dark?'#BED4C9':'#426568',420,1.24,-.3),
  ];
  return{id:`companion-${key}`,layout,label:{en:'',tr:''},headline:{en:'',tr:''},screenshot:'',backgroundColor:background,inverted:!dark,
    transforms:{caption:rect(0,0,1,1)},textElements:elements,...rest};
}

project.themeId='battistics-companion';
project.fontId='self-hosted';
project.importedFont={src:'/fonts/imported/b24f181258481695.ttf',format:'truetype',name:'Instrument Sans',weightRange:[400,700]};
project.connectedCanvas=false;project.device='iphone';project.orientation='portrait';project.locale='tr';project.locales=['en','tr'];
project.scene={backdrop:'solid',span:false,decoration:'none',shadow:40,glow:0,tilt:0,headlineWeight:620,headlineScale:1,headlineCase:'as-typed',captionAlign:'left'};
const hero=page('hero','no-device',night,{
  imageElements:[image('night-scene','night-scene.svg',-20,990,1360,1255,0,2,{edge:'top',amount:15}),panel('activity',65,2225,1190,545)],
});
hero.textElements.push(text('requirement',copy.hero.note,100,915,1120,100,38,'#BED4C9',400,1.15,0));

project.slidesByDevice.iphone=[
  hero,
  page('pocket','hero',paper,{
    headlineSize:156,bodyRect:rect(100,765,1120,180),screenshot:'/screenshots/apple/iphone/{locale}/01-nearby.png',
    transforms:{caption:rect(0,0,1,1),device:rect(500,1080,740,1609,5,7)},
    imageElements:[image('pocket','pocket.png',-160,1070,1450,1812,0,2,{edge:'top',amount:20})],
  }),
  page('keepAwake','device-top','#EAF1EE',{
    screenshot:'/screenshots/apple/iphone/{locale}/03.png',bodyRect:rect(100,690,1120,180),
    transforms:{caption:rect(0,0,1,1),device:rect(110,900,780,1696,-5,6)},
    imageElements:[image('arc','mint-arc.svg',0,0,1320,2868,0,1),panel('keep-awake',275,1890,1010,605,5)],
  }),
  page('journey','no-device',paper,{
    headlineSize:153,bodyRect:rect(100,700,1120,190),
    imageElements:[image('window','journey-window.svg',60,920,1200,1500),panel('activity',85,2240,1150,535,-2)],
  }),
  page('battery','hero',night,{
    screenshot:'/screenshots/apple/iphone/{locale}/05.png',headlineSize:150,
    transforms:{caption:rect(0,0,1,1),device:rect(455,930,750,1630,5,6)},
    imageElements:[panel('battery-gauge',55,1120,390,410,-6),panel('battery-power',50,1620,430,218,-3),panel('battery-health',50,1865,430,218,-3),panel('battery-temperature',50,2110,430,218,-3)],
  }),
  page('accessories','device-top','#EAF1EE',{
    brand:false,headlineSize:145,headlineRect:rect(90,1860,1140,485),bodyRect:rect(100,2380,1120,230),
    screenshot:'/screenshots/apple/iphone/{locale}/04.png',
    transforms:{caption:rect(0,0,1,1),device:rect(140,-100,820,1783,-4,6)},
    imageElements:[panel('accessories',375,1040,915,620,5)],
  }),
  page('connection','no-device',night,{
    headlineSize:150,bodyRect:rect(100,2250,1120,210),screenshot:'/screenshots/apple/iphone/{locale}/01-nearby.png',
    transforms:{caption:rect(0,0,1,1),device:rect(100,865,650,1413,-4,6)},
    imageElements:[image('mascot','mascot-wave.png',620,1120,740,970,0,8)],
  }),
];
const last=project.slidesByDevice.iphone.at(-1);
last.textElements.push(text('account-note',copy.connection.note,100,2590,1120,180,37,'#BED4C9',400,1.24,0));
await writeFile(file,JSON.stringify(project,null,2)+'\n');
console.log('Seeded seven EN/TR companion compositions; other decks preserved.');
