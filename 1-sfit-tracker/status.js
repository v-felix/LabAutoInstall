"use strict";
async function verify() {
  try {
    const s = await chrome.runtime.sendMessage({type:"SFIT_VERIFY"});
    document.getElementById("phase").textContent = ({WAITING:"CHỜ ĐẾN GIỜ",ACTIVE:"ĐANG ÁP DỤNG BỘ LỌC",ENDED:"ĐÃ HẾT GIỜ — KHÔNG CHẶN",DISABLED:"ĐÃ TẮT TRONG CẤU HÌNH"})[s.phase] || s.phase;
    document.getElementById("details").textContent = JSON.stringify(s,null,2);
  } catch (e) { document.getElementById("phase").textContent = String(e); }
}
document.getElementById("verify").addEventListener("click", verify);
document.getElementById("logs").addEventListener("click", async () => {
  const report = await chrome.runtime.sendMessage({type:"SFIT_LOGS"});
  const url = URL.createObjectURL(new Blob([JSON.stringify(report,null,2)], {type:"application/json"}));
  const a = document.createElement("a"); a.href = url; a.download = "sfit-log.json"; a.click();
  setTimeout(() => URL.revokeObjectURL(url),10000);
});
verify();
