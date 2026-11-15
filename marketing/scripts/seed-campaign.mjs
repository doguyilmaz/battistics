import { readFile, writeFile } from 'node:fs/promises';

const file = new URL('../app-store-screenshots.json', import.meta.url);
const project = JSON.parse(await readFile(file, 'utf8'));
const ink = '#17191B', paper = '#EEEAE2', orange = '#FF793B';
const tr = (x,y,width,height,rotation=0,zIndex=5) => ({x,y,width,height,rotation,zIndex});
const text = (id,en,turkish,x,y,w,h,size,color,rotation=0) => ({id,text:{en,tr:turkish},transform:tr(x,y,w,h,rotation),fontSize:size,fontWeight:800,color,align:'left'});
const art = (id,src,x,y,w,h,rotation=0,z=3) => ({id,src:`/artwork/on-duty/${src}`,transform:tr(x,y,w,h,rotation,z),fit:'contain'});
const panel = (id,x,y,w,h,rotation=0) => art(id,`{locale}/${id}.svg`,x,y,w,h,rotation,8);
const slide = (id,labelEn,labelTr,en,turkish,inverted=false,extra={}) => ({
  id,layout:'no-device',label:{en:labelEn,tr:labelTr},headline:{en,tr:turkish},screenshot:'',inverted,
  typography:{headlineScale:1.8,labelScale:1},
  transforms:{caption:tr(96,160,1130,650,0,12)},...extra,
});

project.themeId = 'battistics-on-duty';
project.fontId = 'self-hosted';
project.importedFont = {src:'/fonts/imported/724c9c25952d5f4a.ttf',format:'truetype',name:'Barlow Condensed ExtraBold'};
project.connectedCanvas = true;
project.device = 'iphone';
project.locale = 'en';
project.locales = ['en','tr'];
project.scene = {backdrop:'solid',span:false,decoration:'none',shadow:48,glow:0,tilt:0,headlineWeight:800,headlineScale:1.1,headlineCase:'as-typed',captionAlign:'left'};
project.slidesByDevice.iphone = [
  slide('still-on','BATTISTICS REMOTE / MAC + IPHONE','BATTISTICS REMOTE / MAC + IPHONE','YOUR MAC.\n*STILL ON.*','SEN UZAKTA.\n*MAC UYANIK.*',false,{
    imageElements:[art('signal','signal.svg',0,0,1320,2868,0,1),art('power','power-key.png',0,700,1320,885,0,4),panel('session',70,1610,1180,765,-3)],
    textElements:[text('benefit','KEEP AWAKE. FROM YOUR IPHONE.','IPHONE’UNDAN UYANIK TUT.',100,2490,1140,100,65,paper),text('requirement','Requires Battistics on your Mac.','Mac’inde Battistics gerektirir.',100,2640,1100,110,42,'#A9ACAD')],
  }),
  slide('one-more-tap','LIVE ACTIVITIES','CANLI ETKİNLİKLER','ONE TAP.\n*MORE TIME.*','DOKUN.\n*SÜRE EKLE.*',true,{
    imageElements:[art('timer','timer.svg',0,1050,1320,1500,0,2),panel('activity',70,1620,1180,545,-5),art('pointer','pointer.svg',690,2170,400,250,-6,10)],
    textElements:[text('30','+30','+30',80,700,1070,680,660,ink),text('minutes','MINUTES','DAKİKA',720,1230,470,150,100,'#A9360A'),text('live-actions','ADD TIME. OR STOP.\nRIGHT FROM YOUR LOCK SCREEN.','SÜRE EKLE. YA DA DURDUR.\nKİLİT EKRANINDAN.',100,2570,1120,190,60,ink)],
  }),
  slide('your-rules','KEEP AWAKE','UYANIK TUT','YOUR HOURS.\nYOUR RULES.','SÜRE SENİN.\nMOD SENİN.',true,{
    layout:'hero',backgroundColor:orange,screenshot:'/screenshots/apple/iphone/{locale}/03.png',
    transforms:{caption:tr(96,160,1130,640,0,12),device:tr(460,920,760,1652,4,6)},
    textElements:[text('times','15m\n1h\n∞','15dk\n1sa\n∞',80,1250,310,860,170,ink),text('modes','SCREEN ON. SCREEN OFF. LID CLOSED.','EKRAN AÇIK. EKRAN KAPALI. KAPAK KAPALI.',96,2660,1120,130,52,ink)],
  }),
  slide('behind-charge','BATTERY DETAILS','PİLİN AYRINTILARI','BEHIND THE\n*PERCENTAGE.*','YÜZDENİN\n*ÖTESİNİ GÖR.*',false,{
    imageElements:[panel('battery-gauge',55,800,760,790,-8),panel('battery-metrics',30,1550,1260,235,-3),panel('capacity',100,1890,1120,510,4)],
    textElements:[text('beyond','W\n°C\nmAh','W\n°C\nmAh',900,860,330,650,170,orange),text('battery-proof','CHARGE. HEALTH. WATTS. TEMPERATURE.','ŞARJ. SAĞLIK. GÜÇ. SICAKLIK.',100,2570,1140,170,61,paper)],
  }),
  slide('whole-desk','ACCESSORIES + APPS','AKSESUARLAR + UYGULAMALAR','ALL YOUR\n*BATTERIES.*','TÜM PİLLER.\n*TEK BAKIŞ.*',true,{
    imageElements:[art('accessory-lines','accessory-lines.svg',0,850,1320,900,0,2),panel('accessories',50,1500,1220,840,-4)],
    textElements:[text('apps','SEE WHAT’S\nUSING ENERGY.','ENERJİYİ NEYİN\nKULLANDIĞINI GÖR.',100,2440,1140,210,88,ink)],
  }),
  slide('your-connection','YOUR DEVICES. YOUR CONNECTION.','SENİN CİHAZLARIN. SENİN BAĞLANTIN.','NEAR.\nFAR.\n*YOURS.*','YAKINDA.\nUZAKTA.\n*SENİN.*',false,{
    typography:{headlineScale:2.4,labelScale:.92},transforms:{caption:tr(96,160,1130,1090,0,12)},
    imageElements:[art('routes','routes.svg',0,0,1320,2868,0,2)],
    textElements:[text('lan','WI-FI + ETHERNET','WI-FI + ETHERNET',220,1170,970,150,88,orange),text('ble','BLUETOOTH NEARBY','YAKINDA BLUETOOTH',220,1560,970,150,88,paper),text('cloud','PRIVATE ICLOUD AWAY','UZAKTA ÖZEL ICLOUD',220,1930,970,150,88,'#A9CBD5'),text('account','MAC + IPHONE. SAME APPLE ACCOUNT.\nBACKGROUND UPDATES DEPEND ON IOS.','MAC + IPHONE. AYNI APPLE HESABI.\nARKA PLAN GÜNCELLEMELERİ IOS’A BAĞLIDIR.',100,2590,1140,170,45,paper)],
  }),
];
await writeFile(file, JSON.stringify(project,null,2)+'\n');
console.log('Updated the English/Turkish iPhone campaign; other device decks preserved.');
