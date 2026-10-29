# SFIT Tracker 2.0

Sửa `startAt`, `endAt` với múi giờ `+07:00` trong config.js. Không tạo phiên.
Trước giờ: WAITING; trong giờ: ACTIVE; hết giờ: ENDED, tự gỡ giới hạn.

Load unpacked: sửa file rồi Reload extension. Với USB SchoolLab: sửa
Files/ChromeExtension/config.js trong gói và chạy Install-Lab.cmd hoặc Install-ChromeExtension.cmd.
Script tự chuẩn bị lại lock của riêng cấu hình; sửa mã logic khác phải build lại.

Mô tả đầy đủ: [SFIT-2.0.vi.md](../school-lab/SFIT-2.0.vi.md).
Chỉ kiểm soát profile đã nạp; không khóa profile/trình duyệt/ứng dụng khác hoặc chống quyền admin.
