"use strict";
async function show() {
  try {
    const s = await chrome.runtime.sendMessage({type:"SFIT_GET_STATE"});
    document.getElementById("state").textContent = s.phase === "ACTIVE" ? "Đang thi đến " + s.endAt : "Bộ lọc đã ngừng. Bạn có thể nhập lại địa chỉ cần truy cập.";
    document.getElementById("exam").disabled = s.phase !== "ACTIVE";
  } catch (e) { document.getElementById("error").textContent = String(e); }
}
document.getElementById("exam").addEventListener("click", () => chrome.runtime.sendMessage({type:"SFIT_FOCUS"}));
chrome.runtime.onMessage.addListener(m => { if (m?.type === "SFIT_STATE") show(); });
show();
