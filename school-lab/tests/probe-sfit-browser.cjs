// Local HEADLESS development probe. Never uses a real user profile or registry.
// Usage: node tests/probe-sfit-browser.cjs "path/to/msedge.exe-or-chrome.exe"
const fs=require('node:fs/promises'), path=require('node:path'), {spawn}=require('node:child_process'), http=require('node:http'), assert=require('node:assert/strict');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
  const root=path.resolve(__dirname,'..'), extSource=path.resolve(root,'../1-sfit-tracker');
  const work=path.join(root,'test-results','sfit-browser-'+Date.now()), ext=path.join(work,'extension'), profile=path.join(work,'profile');
  await fs.mkdir(ext,{recursive:true}); await fs.mkdir(profile,{recursive:true});
  const files=(await fs.readdir(extSource)).filter(n=>/\.(js|json|html|css|png)$/.test(n));
  for(const f of files)await fs.copyFile(path.join(extSource,f),path.join(ext,f));
  const server=http.createServer((req,res)=>{res.setHeader('Content-Type','text/html');res.end('<!doctype html><title>SFIT Local Probe</title><div id="chatbox">chat</div><textarea id="work">UNSAVED_WORK</textarea>');});
  await new Promise(r=>server.listen(0,'127.0.0.1',r)); const port=server.address().port;
  const c={enabled:true,startAt:new Date(Date.now()+5000).toISOString().replace(/\.\d{3}Z$/,'Z'),endAt:new Date(Date.now()+15000).toISOString().replace(/\.\d{3}Z$/,'Z'),examUrl:`http://127.0.0.1:${port}/`,allowedHosts:['127.0.0.1'],resourceHosts:[],networkMode:'strict',singleExamTab:false,autoOpenExam:true,hideChatbox:true,maxLogEntries:30};
  await fs.writeFile(path.join(ext,'config.js'),'globalThis.SFIT_CONFIG=Object.freeze('+JSON.stringify(c)+');');
  const log=await fs.open(path.join(work,'browser-stderr.log'),'w');
  const child=spawn(process.argv[2],['--headless=new','--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-component-update','--disable-sync',`--user-data-dir=${profile}`,'--remote-debugging-port=0','--remote-debugging-address=127.0.0.1',`--load-extension=${ext}`,`--disable-extensions-except=${ext}`,'about:blank'],{windowsHide:true,stdio:['ignore','ignore',log.fd]});
  let ws;
  try{
    let active;
    for(let i=0;i<60;i++){try{active=(await fs.readFile(path.join(profile,'DevToolsActivePort'),'utf8')).trim().split('\n');break;}catch{}await sleep(250);}
    if(!active)throw Error('No headless DevTools endpoint; see browser-stderr.log');
    ws=new WebSocket(`ws://127.0.0.1:${active[0]}${active[1]}`);await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});
    let sequence=0;const pending=new Map();
    ws.onmessage=event=>{const m=JSON.parse(event.data);if(m.id&&pending.has(m.id)){const p=pending.get(m.id);clearTimeout(p.timer);pending.delete(m.id);m.error?p.reject(Error(JSON.stringify(m.error))):p.resolve(m.result);}};
    const send=(method,params={},sessionId)=>new Promise((resolve,reject)=>{const id=++sequence;const timer=setTimeout(()=>{pending.delete(id);reject(Error('CDP timeout '+method));},10000);pending.set(id,{resolve,reject,timer});ws.send(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})}));});
    let worker;
    for(let i=0;i<60;i++){const targets=await send('Target.getTargets');worker=targets.targetInfos.find(t=>t.type==='service_worker'&&t.url.includes('/background.js'));if(worker)break;await sleep(250);}
    if(!worker)throw Error('No extension worker. This browser build may not support command-line loading.');
    const {sessionId}=await send('Target.attachToTarget',{targetId:worker.targetId,flatten:true});
    const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true},sessionId);if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
    let phase;
    for(let i=0;i<40;i++){phase=await evaluate('(()=>{try{return currentPhase}catch{return "BOOT"}})()');if(!['BOOT','INITIALIZING'].includes(phase))break;await sleep(50);}
    assert.equal(phase,'WAITING');
    for(let i=0;i<100;i++){phase=await evaluate('currentPhase');if(phase==='ACTIVE')break;await sleep(100);}
    assert.equal(phase,'ACTIVE');const rules=await evaluate('chrome.declarativeNetRequest.getSessionRules()');assert.equal(rules.length,4);
    const matches=await evaluate(`chrome.declarativeNetRequest.testMatchOutcome({url:'https://outside.test/',type:'main_frame'})`);
    assert(matches.matchedRules.some(r=>r.ruleId===10001));
    const apiMatch=await evaluate(`chrome.declarativeNetRequest.testMatchOutcome({url:'https://outside.test/api',type:'xmlhttprequest'})`);
    assert(apiMatch.matchedRules.some(r=>r.ruleId===10003));
    const targets=await send('Target.getTargets'), page=targets.targetInfos.find(t=>t.url===c.examUrl);assert(page);
    const pageSession=(await send('Target.attachToTarget',{targetId:page.targetId,flatten:true})).sessionId;
    const pageEval=async expression=>{const r=await send('Runtime.evaluate',{expression,returnByValue:true},pageSession);if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
    let hidden=false;
    for(let i=0;i<30;i++){hidden=await pageEval('!!document.querySelector("#chatbox") && getComputedStyle(document.querySelector("#chatbox")).display === "none"');if(hidden)break;await sleep(100);}
    assert.equal(hidden,true);assert.equal(await pageEval('document.querySelector("#work").value'),'UNSAVED_WORK');
    // Wait for the REAL scheduled end alarm, without mutating config or calling
    // reconcile ourselves. This checks boundary wake-up and DOM cleanup.
    for(let i=0;i<180;i++){phase=await evaluate('currentPhase');if(phase==='ENDED')break;await sleep(100);}
    assert.equal(phase,'ENDED');assert.equal((await evaluate('chrome.declarativeNetRequest.getSessionRules()')).length,0);
    for(let i=0;i<30;i++){hidden=await pageEval('getComputedStyle(document.querySelector("#chatbox")).display === "none"');if(!hidden)break;await sleep(100);}
    assert.equal(hidden,false);assert.equal(await pageEval('document.querySelector("#work").value'),'UNSAVED_WORK');
    await fs.writeFile(path.join(work,'result.json'),JSON.stringify({Passed:true,Browser:(await send('Browser.getVersion')),Checks:['real MV3 worker starts WAITING','real start alarm activates strict rules','outside navigation matches redirect','outside API matches block','chat hidden only while ACTIVE','real end alarm clears rules','chat restored and unsaved work retained'],Scope:'Headless isolated profile; not Chrome UI installer'},null,2));
    console.log('PASS real browser extension probe: '+work);
    await send('Browser.close').catch(()=>{});
  }finally{ws?.close();child.kill();server.close();await log.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
