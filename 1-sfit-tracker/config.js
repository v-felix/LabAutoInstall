/* SỬA LỊCH Ở ĐÂY trước khi chạy Build-OfflinePackage.ps1.
 * Giờ Việt Nam: giữ đuôi +07:00. Dưới đây là lịch MẪU, cần thay.
 * Test: startAt trước hiện tại 1 phút, endAt sau hiện tại 2 phút.
 * Load unpacked: sửa rồi bấm Reload extension. Không tính giờ từ lúc cài.
 * networkMode=navigation: chỉ chặn mở web ngoài; strict chặn cả API/tài nguyên.
 * strict: điền đủ CDN/API thực tế vào resourceHosts. Giữ object bên dưới là JSON.
 */
globalThis.SFIT_CONFIG = Object.freeze({
  "enabled": true,
  "startAt": "2026-11-01T08:00:00+07:00",
  "endAt":   "2026-11-01T11:00:00+07:00",
  "examUrl": "https://www.laptrinhonline.club/",
  "allowedHosts": ["laptrinhonline.club", "www.laptrinhonline.club"],
  "networkMode": "navigation",
  "resourceHosts": [],
  "singleExamTab": true,
  "autoOpenExam": true,
  "hideChatbox": true,
  "maxLogEntries": 300
});
