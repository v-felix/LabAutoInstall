"use strict";
(() => {
  let overlay = null, style = null, endTimer;
  function clear() { overlay?.remove(); style?.remove(); overlay = style = null; }
  function apply(next) {
    clear(); clearTimeout(endTimer);
    if (next.phase !== "ACTIVE") return;
    if (!next.isExamTab && next.singleExamTab) {
      overlay = document.createElement("div");
      Object.assign(overlay.style, {position:"fixed",inset:"0",zIndex:"2147483647",background:"#f1f5f9",color:"#0f172a",display:"grid",placeContent:"center",font:"20px system-ui",textAlign:"center"});
      const text = document.createElement("p"); text.textContent = "Đang trong giờ thi. Hãy sử dụng tab Online Judge chính.";
      overlay.append(text); document.documentElement.append(overlay);
    }
    if (next.hideChatbox && next.isAllowedPage) {
      style = document.createElement("style"); style.textContent = "#chatbox { display:none !important; }";
      document.documentElement.append(style);
    }
    // DOM deadline is also checked locally if a browser alarm is delayed.
    const remaining = Date.parse(next.endAt) - Date.now();
    if (remaining > 0) endTimer = setTimeout(() => { clear(); refresh(); }, Math.min(remaining,2147483647));
  }
  async function refresh() {
    try { apply(await chrome.runtime.sendMessage({type:"SFIT_GET_STATE"})); }
    catch { clear(); } // Extension reload/disable must not leave a stale overlay.
  }
  chrome.runtime.onMessage.addListener(m => { if (m?.type === "SFIT_STATE") apply(m.state); });
  document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
  refresh();
})();
