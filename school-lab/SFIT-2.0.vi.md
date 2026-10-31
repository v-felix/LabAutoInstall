# SFIT Tracker 2.0 — SchoolLab 2.6.3

SFIT tự kiểm soát tab/trang thi theo lịch, không có ô nhập code vào thi hoặc tạo phiên.

- Trang thi: **https://utcoj.info/**; allowedHosts chỉ có **utcoj.info**.
- Lịch đã đặt: **01/11/2026, 13:00–17:00, giờ Việt Nam (+07:00)**.
- SchoolLab giữ nguyên profile cũ, **mỗi lần cài SFIT tạo profile mới** tên **Olympic Đặc Biệt 2026**, cài SFIT trên đó và cập nhật shortcut **Olympic Đặc Biệt 2026** trên Desktop sang profile mới nhất. Quản trị viên tự xóa profile cũ khi cần.
- Chạy Install-ChromeExtension.cmd bằng Administrator, để máy yên lúc tự cài. Chỉ đạt khi SFIT DA XAC NHAN, mã 0. Ngày thi mở shortcut Olympic Đặc Biệt 2026, không cần cắm USB.

## Chỉnh lịch

Sửa nguồn `1-sfit-tracker/config.js` trước khi build. Với bộ cài/USB đã có, sửa `Files/ChromeExtension/config.js` rồi chạy lại bước cài SFIT trên các máy cần cập nhật, không cần build lại:

```javascript
"enabled": true,
"startAt": "2026-11-01T13:00:00+07:00",
"endAt":   "2026-11-01T17:00:00+07:00",
"examUrl": "https://utcoj.info/",
"allowedHosts": ["utcoj.info"],
```

Giữ múi giờ +07:00, giờ 24 tiếng, endAt sau startAt và đồng hồ máy đúng. Không tính thời gian từ lúc cài. Sửa trên USB không tự thay đổi lịch máy đã cài. Test nhanh: bắt đầu trước hiện tại 1 phút, kết thúc sau hiện tại 2 phút. Load unpacked thủ công cần Reload sau khi sửa file đã nạp.

## Hành vi

- WAITING: trước lịch, chưa giới hạn.
- ACTIVE: áp dụng allowedHosts, một tab thi khi singleExamTab=true, mở examUrl khi autoOpenExam=true và ẩn chatbox khi hideChatbox=true.
- ENDED/DISABLED: tự gỡ giới hạn, không yêu cầu đi gỡ extension/restore từng máy.
- networkMode=navigation giới hạn điều hướng; strict chặn thêm request ngoài allowedHosts/resourceHosts, cần đủ CDN/API khi sử dụng.
- Giữ bài đang làm khi hết giờ. Chỉ đóng tab mới phát sinh trong giờ thi, không xóa hàng loạt tab đã tồn tại.
- Chỉ kiểm soát profile cài SFIT; không khóa các profile, trình duyệt, ứng dụng khác hoặc chống quyền Administrator.

Log: %LOCALAPPDATA%/SchoolLab/Chrome. Native bridge xác minh ID/SID/token/version/hash lịch và báo cáo mới; script phải xác nhận đúng profile Olympic Đặc Biệt 2026 và không ghim trước khi đạt. Không mở cổng mạng hoặc gửi log ra Internet.

Check-LabReady toàn bộ cần báo cáo cùng PackageId. Khi chỉ cập nhật SFIT, dùng SFIT DA XAC NHAN/mã 0 để xác nhận riêng bước này. Chi tiết: [README.vi.md](README.vi.md), [CHROME-PROFILE-USB.vi.md](CHROME-PROFILE-USB.vi.md).
