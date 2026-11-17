const fs=require('fs'),path=require('path'),{stripTypeScriptTypes}=require('node:module');
const base=path.join(__dirname,'bot'),cache={};
function load(file){if(cache[file])return cache[file];const e=cache[file]={};let js=stripTypeScriptTypes(fs.readFileSync(file,'utf8'),{mode:'transform'});const exports=[];js=js.replace(/import\s*\{([\s\S]*?)\}\s*from\s*['"]([^'"]+)['"];?/g,(_,bindings,ref)=>`const {${bindings.replace(/\bas\b/g,':')}} = require(${JSON.stringify(ref)});`);js=js.replace(/export\s+(const|let|var|class|function)\s+(\w+)/g,(_,kind,name)=>{exports.push(name);return kind+' '+name;});js+='\nObject.assign(exports,{'+exports.join(',')+'});';new Function('require','exports',js)(ref=>load(path.resolve(path.dirname(file),ref+'.ts')),e);return e;}
const {BotEngine}=load(base+'/engine.ts'),{STATES}=load(base+'/states.ts'),{SHAPES}=load(base+'/skins.ts'),{EXPRESSIONS}=load(base+'/expressions.ts');
const {decalageDesYeux}=load(base+'/eyefit.ts');
const round=n=>Math.round(n*1000)/1000;
function native(f,def,t){
 const coords=[];const chunks=[...f.bodyPath.matchAll(/([MC])([^MCZ]+)/g)];for(const [_,op,s] of chunks){const v=s.trim().split(/[ ,]+/).map(Number);if(op==='M')coords.push(...v);else coords.push(...v.slice(-2));}coords.splice(-2);
 const eyes=f.eyes.map(e=>{const ends=[...e.d.matchAll(/([MLA])([^MLAZ]+)/g)].map(([_,op,s])=>{const v=s.trim().split(/[ ,]+/).map(Number);return op==='A'?v.slice(-2):v;});const xs=ends.map(v=>v[0]),ys=ends.map(v=>v[1]);return [Math.max(...xs)-Math.min(...xs),Math.max(...ys)-Math.min(...ys),...e.matrix.match(/[-+]?\d*\.?\d+(?:e[-+]?\d+)?/gi).map(Number),e.alpha,e.surface.x,e.surface.y,e.surface.offX,e.surface.offY].map(round);});
 const arcs=def.pose(t).arcs.map(a=>{const s=a.seed;return [s.a,s.k,s.tilt,s.speed,s.phase,s.sweep,s.width,s.cx,s.cy,a.t,a.opacity].map(round);});
 return {v:round(f.accessoryAlpha),b:coords.map(round),s:[f.silhouette.rot,f.silhouette.cx,f.silhouette.cy,f.silhouette.sx,f.silhouette.sy].map(round),a:round(f.bodyAlpha),e:eyes,r:arcs,d:f.dots.map(d=>[d.x,d.y,d.r||3,d.opacity,d.depth??1].map(round)),z:f.dotsBehind,n:f.notif?[f.notif.x,f.notif.y,f.notif.r].map(round):null,h:f.notch?[f.notch.x,f.notch.y,f.notch.r].map(round):null};
}
const shape=SHAPES.find(s=>s.id==='goutte'),expression=EXPRESSIONS.find(e=>e.id==='attentif');
const data={version:2,fps:24,duration:6,clips:{},rest:{},profiles:{},eyeFit:{}};
for(const shape of SHAPES){data.profiles[shape.id]=shape.radii.map(round);data.eyeFit[shape.id]={};for(const state of STATES){data.eyeFit[shape.id][state.id]={};for(const exp of EXPRESSIONS){const fit=decalageDesYeux(shape.radii,state.id,exp.id);data.eyeFit[shape.id][state.id][exp.id]=[round(fit.x*100),round(fit.y*100)];}}}
for(const state of STATES){const engine=new BotEngine(100,state.id,shape.radii,expression);data.clips[state.id]=Array.from({length:145},(_,i)=>native(engine.sample(i/24),state,i/24));}
for(const s of SHAPES){data.rest[s.id]={};for(const e of EXPRESSIONS){const engine=new BotEngine(100,'idle',s.radii,e);data.rest[s.id][e.id]=native(engine.sample(0),STATES.find(d=>d.id==='idle'),0);}}
for(const [id,frames] of Object.entries(data.clips))for(const f of frames){if(f.b.length!==128||!f.b.every(Number.isFinite))throw Error(id+' invalid contour');}
const dest=path.resolve(__dirname,'../../assets/mascot');fs.mkdirSync(dest,{recursive:true});fs.writeFileSync(dest+'/bloub-motion.json',JSON.stringify(data));console.log('Native vector atlas: '+fs.statSync(dest+'/bloub-motion.json').size+' bytes');
