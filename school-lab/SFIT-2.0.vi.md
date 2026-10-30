# SFIT Tracker 2.0 — tích hợp SchoolLab 2.4.0

SFIT kiểm soát tab và trang thi theo lịch cố định. Bản 2.4.0 thay đổi cách triển khai Chrome; mã runtime extension vẫn là 2.0.0.

## Cài vào Chrome

1. Mở sẵn đúng profile Chrome cần cài, nên chỉ để một cửa sổ. Đóng VS Code nếu cài cả bộ.
2. Chạy Install-ChromeExtension.cmd bằng Administrator, hoặc Install-Lab.cmd để cài toàn bộ.
3. Để máy yên: script tạo tab setup, xác minh Profile Path bằng chrome://version, mở chrome://extensions, bật Developer mode, bỏ ghim extension và Load unpacked SFIT.
4. Chỉ đạt khi có SFIT DA XAC NHAN và mã 0; script phải nhận native report mới và xác nhận SFIT không ghim trong profile đã chọn.

Giữ nguyên tất cả profile, bookmark, lịch sử, dữ liệu và shortcut Chrome. Chỉ cài/bỏ ghim trong profile đã chọn; không gỡ hoặc vô hiệu hóa các extension khác. Nếu Chrome đang đóng, script mở profile dùng gần nhất. Không xóa/restore dữ liệu hoặc khóa tạo profile. Hướng dẫn chi tiết: [CHROME-PROFILE-USB.vi.md](CHROME-PROFILE-USB.vi.md).

## Sửa ngày giờ

Trước khi build: sửa 1-sfit-tracker/config.js trong repo. Với bộ cài đã build/USB: sửa Files/ChromeExtension/config.js rồi chạy lại bước cài SFIT trên từng máy cần cập nhật, không cần build lại.

```javascript
"enabled": true,
"startAt": "2026-11-01T08:00:00+07:00",
"endAt":   "2026-11-01T11:00:00+07:00",
```

Đây là ví dụ ngày 01/11/2026, 08:00–11:00 giờ Việt Nam. Giữ múi giờ +07:00, giờ 24 tiếng và endAt sau startAt. Không tạo phiên hoặc tính thời gian từ lúc cài. Đồng hồ máy trạm phải đúng. Sửa trên USB không tự cập nhật các máy đã cài.

Test nhanh: startAt trước hiện tại 1 phút, endAt sau hiện tại 2 phút. Nếu Load unpacked thủ công khi phát triển, sửa file trong thư mục đã nạp rồi bấm Reload extension tại chrome://extensions.

## Hành vi runtime

- WAITING: trước lịch; chưa áp dụng giới hạn.
- ACTIVE: áp dụng allowedHosts, giữ một tab thi khi singleExamTab=true; autoOpenExam=true tự mở examUrl. hideChatbox=true ẩn chat trên trang được phép.
- ENDED hoặc DISABLED: tự gỡ giới hạn. Không phải đi gỡ extension/restore từng máy.
- networkMode=navigation chỉ giới hạn điều hướng; strict chặn thêm request mạng ngoài allowedHosts/resourceHosts. Điền đủ CDN/API khi dùng strict.
- Giữ bài đang làm khi hết giờ; chỉ đóng tab mới phát sinh trong giờ áp dụng, không xóa hàng loạt tab đã tồn tại.
- Chỉ kiểm soát profile nạp extension; không chống người có quyền Administrator, trình duyệt/profile khác hoặc chỉnh đồng hồ.

## Log và xác nhận

Log: %LOCALAPPDATA%/SchoolLab/Chrome gồm install.log, result.json, expected.json, heartbeat.json và profile-state.json. Lỗi UI có thêm uia-diagnostic.txt; mã lỗi Chrome là 69030.

Native bridge kiểm ID, SID, token của lượt cài, phiên bản/hash lịch và thời gian báo cáo. Chỉ một heartbeat từ profile khác chưa đủ để báo đạt; phải xác nhận trang chi tiết SFIT trong cửa sổ đã chọn. Không mở cổng mạng hoặc gửi log lên Internet.

Readiness dùng journal schema 3 và không yêu cầu chỉ tồn tại Default. Muốn Check-LabReady xác nhận toàn bộ gói, phần máy và tài khoản phải cùng PackageId; nếu chỉ cập nhật SFIT, dùng SFIT DA XAC NHAN/mã 0 để xác nhận bước riêng đó.
