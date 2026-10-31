# SchoolLab 2.6.3 — bộ cài offline phòng tin học

## Chức năng chính

- Cài Dev-C++ nếu thiếu; tận dụng MinGW, cấu hình compiler/debugger.
- Cài Java JDK, Python/pip, VS Code Stable; cấu hình PATH, JAVA_HOME và extension/workspace C++/Java/Python.
- Giữ nguyên tất cả profile Chrome cũ. **Mỗi lần cài SFIT đều tạo profile mới** tên **Olympic Đặc Biệt 2026**, cài SFIT vào đó và bỏ ghim extension trong profile mới. Quản trị viên có thể tự xóa profile cũ.
- Shortcut **Olympic Đặc Biệt 2026** trên Desktop được cập nhật để mở profile vừa tạo và **https://utcoj.info/**. Thiếu file đánh dấu của profile cũ hoặc đã xóa profile cũ không chặn lượt cài mới.
- Thi **01/11/2026, 13:00–17:00 giờ Việt Nam**. SFIT tự áp dụng/hết giờ tự ngừng; **không nhập code vào thi** hoặc tạo phiên.
- Kiểm tra phần mềm, ghi log, bỏ qua thành phần đã đúng khi chạy lại. **Chỉ tự restart cuối cùng nếu cần**, sau khi phần mềm, VS Code và SFIT đều cài thành công.

## Vị trí

| Nội dung | Vị trí |
| --- | --- |
| Bộ cài dùng để chép nguyên thư mục sang USB/LAN | `school-lab\dist\SchoolLab-2.6.3-20261031` trong repo |
| Installer và extension offline | `Files\` trong bộ cài |
| SFIT được cài trên máy trạm | `%ProgramFiles%\SchoolLab\ChromeExtension\OLBDB` |
| Profile Olympic Đặc Biệt 2026 | Một thư mục riêng `SchoolLab-OLBDB-...` trong `%LOCALAPPDATA%\Google\Chrome\User Data`; dùng shortcut Desktop để mở |
| Log phần mềm | `%ProgramData%\SchoolLab\Logs\<Tên máy>` |
| Log SFIT và thông tin profile/shortcut | `%LOCALAPPDATA%\SchoolLab\Chrome` |
| Kết quả xác minh tài khoản Desktop/SID khi cài SFIT | `%LOCALAPPDATA%\SchoolLab\Chrome\classroom-context.json` |
| Trạng thái kiểm tra sau restart | `%ProgramFiles%\SchoolLab\Resume\*.json` |
| Log kiểm tra sau restart | `%ProgramData%\SchoolLab\Logs\<Tên máy>\Bootstrap\after-restart-*.log` |

## Sửa giờ/trang thi

Mở `Files\ChromeExtension\config.js` trong bộ cài/USB:

```javascript
"startAt": "2026-11-01T13:00:00+07:00",
"endAt":   "2026-11-01T17:00:00+07:00",
"examUrl": "https://utcoj.info/",
"allowedHosts": ["utcoj.info"],
```

Giữ `enabled: true`, múi giờ `+07:00`, giờ 24 tiếng và kết thúc sau bắt đầu. Lưu rồi chạy lại `Install-ChromeExtension.cmd` trên máy cần cập nhật, không cần build lại. Sửa USB không tự cập nhật máy đã cài. Nếu sửa nguồn `1-sfit-tracker\config.js` trong repo, cần build gói mới.

## Chạy trên máy lớp

1. Đăng nhập tài khoản Windows dùng cho lớp; Chrome Stable 120+ cần có sẵn. Đóng VS Code nếu cài toàn bộ; không cần đóng/xóa các profile Chrome cũ.
2. Chuột phải `Install-Lab.cmd` → **Run as administrator**, hoặc `Install-ChromeExtension.cmd` nếu chỉ chuẩn bị/cập nhật SFIT.
3. Để máy yên trong lúc script mở Olympic Đặc Biệt 2026, kiểm tra Profile Path và tự Load unpacked. Sau đó script mở **Chi tiết SFIT** để bỏ ghim, tự cuộn nếu cần và đọc lại trạng thái. Chỉ đạt khi có **SFIT DA XAC NHAN**, mã **0** ở bước cài SFIT.
4. Nếu cần restart (mã **3010**), script cài xong mọi bước rồi đếm ngược **60 giây** và restart. Lưu công việc; **Ctrl+C** hủy đếm ngược. Đăng nhập lại **đúng tài khoản Windows đã cài**, script tự kiểm tra từ ổ máy, không cần USB/chạy lại bộ cài. Không cần restart thì kết thúc mã **0**.
5. Ngày thi, mở shortcut **Olympic Đặc Biệt 2026** trên Desktop. Không cần USB hoặc nhập mã vào thi; kiểm tra đồng hồ máy trước buổi thi.

Bản 2.6.3 xác minh SID trực tiếp bằng token Desktop và phiên đăng nhập Windows, không phụ thuộc WMI của Explorer. Trường hợp một tài khoản Admin dùng trực tiếp sẽ được đối chiếu đúng SID. Nếu không xác minh được, script chờ tối đa 15 giây và lưu `classroom-context.json`; không tự kết luận là có admin khác. Nếu UAC dùng tài khoản khác với Desktop thật, cần đăng nhập trực tiếp tài khoản admin dùng cho lớp rồi chạy lại.

Không tự đăng nhập Windows hoặc tự restart thêm lần nữa sau kiểm tra. Ứng dụng có tài liệu chưa lưu có thể chặn restart. Nếu còn lỗi/còn yêu cầu restart, xem log và chạy `Check-LabReady.cmd` sau khi xử lý. Lỗi cài đặt thật sẽ dừng, không bị bỏ qua để restart. Chế độ không có Desktop/tài khoản lớp đang đăng nhập chỉ cài phần mềm và báo các bước còn thiếu, không tự restart.

Trong **nguồn** `school-lab/package/LabConfig.psd1`, `AutomaticRestart = $false` tắt tự restart; `RestartCountdownSeconds = 60` chỉnh thời gian đợi. Thay cấu hình này cần build gói mới. `Install-ChromeExtension.cmd` chạy riêng không tự restart máy.

SFIT chỉ kiểm soát Olympic Đặc Biệt 2026, không khóa profile/trình duyệt khác. Không tự đổi policy quản trị bên ngoài hoặc ghi đè shortcut Olympic Đặc Biệt 2026 không thuộc bộ cài này.

Mỗi lần chạy cài SFIT sẽ tạo một profile mới; profile cũ được giữ nguyên để quản trị viên tự xóa khi cần. Shortcut thi do SchoolLab tạo được cập nhật sang profile mới, kể cả khi profile cũ đã bị xóa tay.
