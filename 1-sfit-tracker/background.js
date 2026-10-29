"use strict";
importScripts("config.js", "core.js");
let config, configError = "", currentPhase = "INITIALIZING", examTabId = null;
let initialized = false, serial = Promise.resolve(), lastReport = 0, digest = "", deployment = null;
let lastNow = Date.now(), recentEvents = new Map(), nativeError = "";
try { config = SfitCore.validate(SFIT_CONFIG); } catch (error) { configError = error.message; }

function run(task) {
  const result = serial.catch(() => {}).then(task);
  serial = result.catch(async error => {
    console.error(error);
    await log("ERROR", String(error.message || error));
    currentPhase = "ERROR";
    try { await replaceRules([]); await broadcast(); await report(true); } catch (e) { console.error(e); }
    initialized = false; // Retry reconciliation on the next event.
  });
  return result;
}
async function log(type, detail = "") {
  const now = Date.now(), key = type + ":" + detail;
  if (now - (recentEvents.get(key) || 0) < 3000) return;
  recentEvents.set(key, now);
  if (recentEvents.size > 100) recentEvents = new Map([[key, now]]);
  const {events = []} = await chrome.storage.local.get("events");
  events.push({at:new Date(now).toISOString(), type, detail:String(detail).slice(0,180)});
  await chrome.storage.local.set({events:events.slice(-(config?.maxLogEntries || 300))});
}
async function replaceRules(addRules) {
  const old = await chrome.declarativeNetRequest.getSessionRules();
  await chrome.declarativeNetRequest.updateSessionRules({removeRuleIds:old.map(r => r.id), addRules});
}
function snapshot(tabId, url) {
  return {version:chrome.runtime.getManifest().version, phase:currentPhase, error:configError,
    startAt:SFIT_CONFIG.startAt, endAt:SFIT_CONFIG.endAt, now:new Date().toISOString(),
    examUrl:config?.examUrl || "", hideChatbox:!!config?.hideChatbox,
    singleExamTab:!!config?.singleExamTab, isExamTab:tabId === examTabId, isAllowedPage:!!config && SfitCore.allowedUrl(url,config.allowedHosts), examTabId,
    nativeError, scope:"Only the Chrome profile loading this extension"};
}
async function broadcast() {
  for (const tab of await chrome.tabs.query({})) {
    if (typeof tab.id !== "number") continue;
    try { await chrome.tabs.sendMessage(tab.id, {type:"SFIT_STATE", state:snapshot(tab.id,tab.url)}); } catch { /* internal pages / not injected yet */ }
  }
}
async function ensureExamTab() {
  if (!config || currentPhase !== "ACTIVE") return;
  if (examTabId !== null) {
    try { await chrome.tabs.get(examTabId); return; } catch { examTabId = null; }
  }
  const existing = (await chrome.tabs.query({})).find(t => SfitCore.allowedUrl(t.url, config.allowedHosts));
  if (existing) examTabId = existing.id;
  else if (config.autoOpenExam) examTabId = (await chrome.tabs.create({url:config.examUrl, active:true})).id;
  if (examTabId !== null) await chrome.storage.session.set({examTabId});
}
async function report(force = false) {
  if (!force && Date.now() - lastReport < 60000) return;
  lastReport = Date.now();
  try {
    if (!digest) {
      const bytes = await (await fetch(chrome.runtime.getURL("config.js"))).arrayBuffer();
      digest = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)), b => b.toString(16).padStart(2,"0")).join("");
    }
    if (deployment === null) {
      const r = await fetch(chrome.runtime.getURL("deployment.json")); deployment = r.ok ? await r.json() : {};
    }
    if (!deployment.token) return; // Standalone Load unpacked needs no native host.
    const r = await chrome.runtime.sendNativeMessage("vn.schoollab.sfit", {
      ...snapshot(), token:deployment.token, packageId:deployment.packageId, configSha256:digest
    });
    if (!r.ok) throw new Error(r.error || "Native host rejected status");
    nativeError = "";
  } catch (error) { nativeError = String(error.message || error); }
}
async function reconcile() {
  const now = Date.now();
  if (now < lastNow - 5000) await log("CLOCK_BACKWARD", "Local clock moved backwards; offline timing is not tamper-proof.");
  lastNow = now;
  if (!initialized) {
    const old = await chrome.storage.session.get("examTabId"); examTabId = Number.isInteger(old.examTabId) ? old.examTabId : null;
    await chrome.alarms.create("sfit-watch", {periodInMinutes:0.5});
  }
  const next = configError ? "INVALID_CONFIG" : SfitCore.phase(config, now);
  if (!initialized || next !== currentPhase) {
    await replaceRules(next === "ACTIVE" ? SfitCore.rules(config) : []);
    currentPhase = next; initialized = true;
    await chrome.alarms.clear("sfit-boundary");
    const boundary = next === "WAITING" ? config.startMs : next === "ACTIVE" ? config.endMs : null;
    if (boundary) await chrome.alarms.create("sfit-boundary", {when:boundary});
    await chrome.action.setBadgeText({text:{ACTIVE:"THI",WAITING:"CHỜ",ENDED:"XONG",DISABLED:"OFF"}[next] || "LỖI"});
    await chrome.action.setBadgeBackgroundColor({color:next === "ACTIVE" ? "#b91c1c" : "#25633e"});
    await log("STATE", next);
    if (next === "ACTIVE") await ensureExamTab();
    else { examTabId = null; await chrome.storage.session.remove("examTabId"); }
    await broadcast(); await report(true);
  } else { await ensureExamTab(); await report(); }
}
async function focusExam() {
  await ensureExamTab();
  if (examTabId !== null) {
    const tab = await chrome.tabs.get(examTabId).catch(() => null);
    const update = {active:true};
    if (tab && !SfitCore.allowedUrl(tab.url,config.allowedHosts)) update.url = config.examUrl;
    await chrome.tabs.update(examTabId,update).catch(() => {});
  }
}
chrome.runtime.onInstalled.addListener(() => { run(reconcile); });
chrome.runtime.onStartup.addListener(() => { run(reconcile); });
chrome.alarms.onAlarm.addListener(() => { run(reconcile); });
chrome.tabs.onCreated.addListener(tab => { run(async () => {
  await reconcile();
  if (currentPhase === "ACTIVE" && config.singleExamTab && examTabId !== null && tab.id !== examTabId) {
    // Only close newly-created tabs; never bulk-close existing work.
    await chrome.tabs.remove(tab.id).catch(() => {}); await log("NEW_TAB_BLOCKED"); await focusExam();
  }
}); });
chrome.tabs.onActivated.addListener(info => { run(async () => {
  await reconcile();
  if (currentPhase === "ACTIVE" && config.singleExamTab && examTabId !== null && info.tabId !== examTabId) {
    await log("TAB_SWITCH"); await focusExam();
  }
}); });
chrome.tabs.onRemoved.addListener(id => { run(async () => {
  if (id === examTabId) { examTabId = null; await reconcile(); }
}); });
chrome.tabs.onUpdated.addListener((id, change) => { if (change.url) run(async () => {
  await reconcile();
  try { await chrome.tabs.sendMessage(id,{type:"SFIT_STATE",state:snapshot(id,change.url)}); } catch {}
}); });
chrome.windows.onFocusChanged.addListener(id => { run(async () => {
  await reconcile();
  if (currentPhase === "ACTIVE" && id === chrome.windows.WINDOW_ID_NONE) await log("BROWSER_FOCUS_LOST", "Signal only; not a cheating verdict.");
}); });
chrome.webNavigation.onBeforeNavigate.addListener(info => { run(async () => {
  await reconcile();
  if (currentPhase !== "ACTIVE" || info.frameId !== 0 || !/^https?:/i.test(info.url)) return;
  if (!SfitCore.allowedUrl(info.url, config.allowedHosts)) {
    let host = "invalid URL"; try { host = new URL(info.url).hostname; } catch {}
    await log("NAVIGATION_BLOCKED", host); // No query strings, passwords or code.
  }
}); });
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (sender.id !== chrome.runtime.id) return false;
  const ownPage = sender.url?.startsWith(chrome.runtime.getURL(""));
  if (!["SFIT_GET_STATE","SFIT_FOCUS","SFIT_LOGS","SFIT_VERIFY"].includes(message?.type)) return false;
  if (message.type !== "SFIT_GET_STATE" && !ownPage) return false;
  run(async () => {
    await reconcile();
    if (message.type === "SFIT_FOCUS" && currentPhase === "ACTIVE") await focusExam();
    if (message.type === "SFIT_VERIFY") await report(true);
    const extra = message.type === "SFIT_LOGS" ? await chrome.storage.local.get("events") : {};
    reply({...snapshot(sender.tab?.id,sender.url), ...extra});
  }).catch(error => reply({phase:"ERROR",error:String(error)}));
  return true;
});
run(reconcile);
