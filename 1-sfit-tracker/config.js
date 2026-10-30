/* SỬA LỊCH Ở ĐÂY trước khi chạy Build-OfflinePackage.ps1.
 * Lịch Olympic Đặc Biệt 2026: 01/11/2026, 13:00-17:00 giờ Việt Nam (+07:00).
 * Test: startAt trước hiện tại 1 phút, endAt sau hiện tại 2 phút.
 * Load unpacked: sửa rồi bấm Reload extension. Không tính giờ từ lúc cài.
 * networkMode=navigation: chỉ chặn mở web ngoài; strict chặn cả API/tài nguyên.
 * strict: điền đủ CDN/API thực tế vào resourceHosts. Giữ object bên dưới là JSON.
 */
globalThis.SFIT_CONFIG = Object.freeze({
  "enabled": true,
  "startAt": "2026-11-01T13:00:00+07:00",
  "endAt":   "2026-11-01T17:00:00+07:00",
  "examUrl": "https://utcoj.info/",
  "allowedHosts": ["utcoj.info"],
  "networkMode": "navigation",
  "resourceHosts": [],
  "singleExamTab": true,
  "autoOpenExam": true,
  "hideChatbox": true,
  "maxLogEntries": 300
});
