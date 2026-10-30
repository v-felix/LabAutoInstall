const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const root = path.resolve(__dirname,'../../1-sfit-tracker');
const core = require(path.join(root,'core.js'));
const box = vm.createContext({}); vm.runInContext(fs.readFileSync(path.join(root,'config.js'),'utf8'),box);
const sample = JSON.parse(JSON.stringify(box.SFIT_CONFIG));
const base = core.validate(sample);
test('explicit Vietnam timezone; exact start inclusive / end exclusive', () => {
  assert.equal(core.parseTime('2026-11-01T08:00:00+07:00'),Date.parse('2026-11-01T01:00:00Z'));
  assert.equal(core.phase(base,base.startMs-1),'WAITING'); assert.equal(core.phase(base,base.startMs),'ACTIVE');
  assert.equal(core.phase(base,base.endMs-1),'ACTIVE'); assert.equal(core.phase(base,base.endMs),'ENDED');
  assert.equal(core.phase({...base,enabled:false},base.startMs),'DISABLED');
});
for (const value of ['2026-02-30T08:00:00+07:00','2026-11-01T25:00:00+07:00','2026-11-01 08:00:00','2026-11-01T08:00:00','2026-11-01T08:00:00+15:00']) {
  test('reject malformed schedule: '+value, () => assert.throws(()=>core.parseTime(value)));
}
test('reject reversed time and unknown / credentialed exam URL', () => {
  assert.throws(()=>core.validate({...sample,endAt:sample.startAt}));
  assert.throws(()=>core.validate({...sample,examUrl:'https://evil.test/'}));
  assert.throws(()=>core.validate({...sample,examUrl:'https://password@utcoj.info/'}));
  assert.throws(()=>core.validate({...sample,allowedHosts:['*.utcoj.info']}));
});
test('exact host allowlist rejects suffix attacks / embedded credentials / script URL', () => {
  for (const u of ['https://utcoj.info.evil.test/','https://utcoj.info@evil.test/','javascript:alert(1)','file:///tmp','chrome://extensions/']) assert.equal(core.allowedUrl(u,base.allowedHosts),false);
  assert.equal(core.allowedUrl('https://utcoj.info/contest/',base.allowedHosts),true);
});
test('network rules allow exact OJ only and strict CDN cannot become navigation allow', () => {
  const rules = core.rules(core.validate({...sample,networkMode:'strict',resourceHosts:['cdn.test']}));
  const main = rules.find(r=>r.id===10002), resource = rules.find(r=>r.id===10004);
  assert.equal(new RegExp(main.condition.regexFilter).test('https://utcoj.info.evil/'),false);
  assert.equal(new RegExp(main.condition.regexFilter).test('https://cdn.test/'),false);
  assert.equal(new RegExp(resource.condition.regexFilter).test('https://cdn.test/a.js'),true);
});

function event() { const handlers=[]; return {handlers,addListener:f=>handlers.push(f),fire:(...a)=>handlers.map(f=>f(...a))}; }
async function worker(raw=sample, now=base.startMs-1000, shared={}, session={}, deployment={}) {
  const data = shared, sessionData = session, alarms = {}, tabs = new Map([[1,{id:1,url:'https://utcoj.info/',active:true}],[2,{id:2,url:'https://outside.test/',active:false}]]);
  const messages=[], removed=[], native=[], state={now,rules:[]};
  class Clock extends Date { constructor(...a){ super(...(a.length?a:[state.now])); } static now(){ return state.now; } }
  const store = target => ({get:async key=>({[key]:target[key]}),set:async values=>Object.assign(target,values),remove:async key=>{delete target[key];}});
  const chrome = {
    runtime:{id:'test-id',getManifest:()=>({version:'2.0.0'}),getURL:f=>'chrome-extension://test-id/'+f,onInstalled:event(),onStartup:event(),onMessage:event(),sendNativeMessage:async(_h,m)=>{native.push(m);return {ok:true};}},
    storage:{local:store(data),session:store(sessionData)},
    alarms:{create:async(n,a)=>{alarms[n]=a;},clear:async n=>{delete alarms[n];},onAlarm:event()},
    action:{setBadgeText:async()=>{},setBadgeBackgroundColor:async()=>{}},
    declarativeNetRequest:{getSessionRules:async()=>state.rules,updateSessionRules:async u=>{state.rules=u.addRules;}},
    tabs:{onCreated:event(),onActivated:event(),onRemoved:event(),onUpdated:event(),query:async()=>[...tabs.values()],get:async id=>{if(!tabs.has(id))throw Error('closed');return tabs.get(id);},
      create:async options=>{const t={id:Math.max(...tabs.keys())+1,...options};tabs.set(t.id,t);return t;},
      update:async(id,opts)=>{Object.assign(tabs.get(id),opts);},remove:async id=>{removed.push(id);tabs.delete(id);},sendMessage:async(id,m)=>{messages.push({id,m});}},
    windows:{onFocusChanged:event(),WINDOW_ID_NONE:-1},webNavigation:{onBeforeNavigate:event()}
  };
  const c = vm.createContext({console,chrome,Date:Clock,URL,crypto:require('node:crypto').webcrypto,SFIT_CONFIG:raw,
    fetch:async url=>url.endsWith('config.js')?{arrayBuffer:async()=>new TextEncoder().encode('config').buffer}:{ok:true,json:async()=>deployment}});
  c.importScripts=(...files)=>{for(const f of files)if(f!=='config.js')vm.runInContext(fs.readFileSync(path.join(root,f),'utf8'),c);};
  vm.runInContext(fs.readFileSync(path.join(root,'background.js'),'utf8'),c);
  const flush = async()=>{for(let i=0;i<4;i++)await vm.runInContext('serial',c);};
  await flush();
  const value = expression=>vm.runInContext(expression,c);
  const request=async(type,sender={id:'test-id',url:'chrome-extension://test-id/status.html'})=>{
    let result; chrome.runtime.onMessage.fire({type},sender,r=>{result=r;}); await flush(); return result;
  };
  return {state,chrome,alarms,tabs,messages,removed,data,native,flush,value,request};
}
test('worker schedule transitions, removes all restrictions at end and keeps existing work', async()=>{
  const w=await worker(); assert.equal(w.value('currentPhase'),'WAITING'); assert.equal(w.state.rules.length,0);
  w.state.now=base.startMs;w.chrome.alarms.onAlarm.fire({name:'sfit-boundary'});await w.flush();
  assert.equal(w.value('currentPhase'),'ACTIVE');assert.equal(w.state.rules.length,2);assert.equal(w.value('examTabId'),1);
  assert.equal(w.tabs.has(2),true);assert.equal(w.removed.length,0);
  w.state.now=base.endMs;w.chrome.alarms.onAlarm.fire({name:'sfit-boundary'});await w.flush();
  assert.equal(w.state.rules.length,0);assert.equal(w.value('currentPhase'),'ENDED');assert.equal(w.tabs.has(1),true);
  assert(w.messages.some(x=>x.m.state.phase==='ENDED'));
});
test('restart inside interval resumes fixed deadline; restart afterwards stays ended', async()=>{
  const a=await worker(sample,base.startMs+1000); assert.equal(a.value('currentPhase'),'ACTIVE');
  const b=await worker(sample,base.endMs+1000,a.data,{});assert.equal(b.value('currentPhase'),'ENDED');assert.equal(b.state.rules.length,0);
});
test('new tabs rejected only during active schedule; preexisting tabs retained',async()=>{
  const w=await worker(sample,base.startMs);w.tabs.set(3,{id:3,url:'about:blank'});w.chrome.tabs.onCreated.fire({id:3});await w.flush();
  assert.deepEqual(w.removed,[3]);assert.equal(w.tabs.has(2),true);
  w.state.now=base.endMs;w.tabs.set(4,{id:4,url:'about:blank'});w.chrome.tabs.onCreated.fire({id:4});await w.flush();assert.equal(w.tabs.has(4),true);
});
test('focus signal is logged without browser-killing; no URLs with secrets logged',async()=>{
  const w=await worker(sample,base.startMs);w.chrome.windows.onFocusChanged.fire(-1);w.chrome.webNavigation.onBeforeNavigate.fire({frameId:0,url:'https://outside.test/?password=secret'});await w.flush();
  assert(w.data.events.some(e=>e.type==='BROWSER_FOCUS_LOST'));assert(!JSON.stringify(w.data.events).includes('secret'));assert.equal(w.tabs.size,2);
});
test('invalid schedule stays unrestricted and reports explicit configuration error',async()=>{
  const w=await worker({...sample,endAt:'invalid'});assert.equal(w.value('currentPhase'),'INVALID_CONFIG');assert.equal(w.state.rules.length,0);
});
test('status restricted to own extension page; content cannot export logs',async()=>{
  const w=await worker();const result=await w.request('SFIT_LOGS',{id:'test-id',url:'https://utcoj.info/',tab:{id:1}});assert.equal(result,undefined);
  assert.equal((await w.request('SFIT_VERIFY')).phase,'WAITING');
});
test('return from blocked page restores exam URL without resetting deadline',async()=>{
  const w=await worker(sample,base.startMs);w.tabs.get(1).url='chrome-extension://test-id/block.html';
  await w.request('SFIT_FOCUS');assert.equal(w.tabs.get(1).url,sample.examUrl);assert.equal(w.alarms['sfit-boundary'].when,base.endMs);
});
test('alarm delayed: next navigation still expires rules; iframe never redirects main tab',async()=>{
  const w=await worker(sample,base.startMs);w.chrome.webNavigation.onBeforeNavigate.fire({frameId:7,url:'https://outside.test/'});await w.flush();assert.equal(w.tabs.get(1).url,sample.examUrl);
  w.state.now=base.endMs+500;w.chrome.webNavigation.onBeforeNavigate.fire({frameId:0,url:'https://outside.test/'});await w.flush();assert.equal(w.state.rules.length,0);
});
test('native status carries exact deployment nonce, package and config bytes hash',async()=>{
  const w=await worker(sample,base.startMs-1,{},{},{token:'install-nonce',packageId:'lab-package'});
  assert(w.native.length>0);assert.equal(w.native[0].token,'install-nonce');assert.equal(w.native[0].packageId,'lab-package');
  assert.equal(w.native[0].configSha256,require('node:crypto').createHash('sha256').update('config').digest('hex'));
  assert.equal((await w.request('SFIT_VERIFY')).nativeError,'');
});

test('exam activates on schedule without an entry code or join form',async()=>{
  const w=await worker(sample,base.startMs);
  assert.equal((await w.request('SFIT_VERIFY')).phase,'ACTIVE');
  assert(w.state.rules.length>0);
  for(const file of ['status.html','block.html']){
    assert.doesNotMatch(fs.readFileSync(path.join(root,file),'utf8'),/<(?:input|form)\b|(?:exam|join|session|access)[-_]?code/i);
  }
  assert.equal(sample.examUrl,'https://utcoj.info/');
  assert.deepEqual(sample.allowedHosts,['utcoj.info']);
  assert.equal(sample.startAt,'2026-11-01T13:00:00+07:00');
  assert.equal(sample.endAt,'2026-11-01T17:00:00+07:00');
});
