# SFIT Tracker 2.0

## Sửa giờ áp dụng

Mở [config.js](config.js), giữ `"enabled": true` và sửa:

```javascript
"startAt": "2026-11-01T08:00:00+07:00",
"endAt":   "2026-11-01T11:00:00+07:00",
```

Ví dụ trên áp dụng ngày **01/11/2026, 08:00–11:00 giờ Việt Nam**. Dùng giờ 24 tiếng, giữ đuôi `+07:00`; giờ kết thúc phải sau giờ bắt đầu. Không tạo phiên.

Trước giờ: WAITING; trong giờ: ACTIVE; hết giờ: ENDED, tự gỡ giới hạn. Máy cần có đồng hồ đúng; thời gian không tính từ lúc cài.

Load unpacked: sửa file rồi Reload extension. Với USB SchoolLab: sửa
Files/ChromeExtension/config.js trong gói và chạy Install-Lab.cmd hoặc Install-ChromeExtension.cmd.
Script tự chuẩn bị lại lock của riêng cấu hình; sửa mã logic khác phải build lại.

Nếu sửa nguồn trong repo, cần build gói mới. Máy đã cài cần chạy lại bước cài SFIT để nhận lịch mới; sửa trên USB không tự cập nhật các máy đó. Test nhanh: bắt đầu trước hiện tại 1 phút, kết thúc sau hiện tại 2 phút.

Mô tả đầy đủ: [SFIT-2.0.vi.md](../school-lab/SFIT-2.0.vi.md).
Chỉ kiểm soát profile đã nạp; không khóa profile/trình duyệt/ứng dụng khác hoặc chống quyền admin.
