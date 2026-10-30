# SchoolLab 2.5.0 — bộ cài offline phòng tin học

## Chức năng chính

- Cài Dev-C++ nếu thiếu; tận dụng MinGW, cấu hình compiler/debugger.
- Cài Java JDK, Python/pip, VS Code Stable; cấu hình PATH, JAVA_HOME và extension/workspace C++/Java/Python.
- Giữ nguyên tất cả profile Chrome cũ. Tạo profile mới **OLBDB**, cài SFIT vào đó, bỏ ghim extension trong OLBDB; không sửa dữ liệu/shortcut của profile cũ.
- Tạo shortcut **OLBDB** trên Desktop để mở đúng profile và **https://utcoj.info/**. Chạy lại dùng lại profile SchoolLab đã tạo, không tạo trùng/reset.
- Thi **01/11/2026, 13:00–17:00 giờ Việt Nam**. SFIT tự áp dụng/hết giờ tự ngừng; **không nhập code vào thi** hoặc tạo phiên.
- Kiểm tra phần mềm, ghi log, bỏ qua thành phần đã đúng khi chạy lại và xử lý mã khởi động lại.

## Vị trí

| Nội dung | Vị trí |
| --- | --- |
| Bộ cài dùng để chép nguyên thư mục sang USB/LAN | `school-lab\dist\SchoolLab-2.5.0-20261030` trong repo |
| Installer và extension offline | `Files\` trong bộ cài |
| SFIT được cài trên máy trạm | `%ProgramFiles%\SchoolLab\ChromeExtension\OLBDB` |
| Profile OLBDB | Một thư mục riêng `SchoolLab-OLBDB-...` trong `%LOCALAPPDATA%\Google\Chrome\User Data`; dùng shortcut Desktop để mở |
| Log phần mềm | `%ProgramData%\SchoolLab\Logs\<Tên máy>` |
| Log SFIT và thông tin profile/shortcut | `%LOCALAPPDATA%\SchoolLab\Chrome` |

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
3. Để máy yên trong lúc script mở OLBDB, kiểm tra Profile Path và tự Load unpacked. Chỉ đạt khi có **SFIT DA XAC NHAN**, mã **0**. Mã **3010** cần restart và làm theo thông báo.
4. Ngày thi, mở shortcut **OLBDB** trên Desktop. Không cần USB hoặc nhập mã vào thi; kiểm tra đồng hồ máy trước buổi thi.

SFIT chỉ kiểm soát OLBDB, không khóa profile/trình duyệt khác. Không tự đổi policy quản trị bên ngoài hoặc ghi đè shortcut OLBDB không thuộc bộ cài này.
