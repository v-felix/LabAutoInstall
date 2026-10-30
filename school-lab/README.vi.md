# SchoolLab 2.4.0 — bộ cài offline phòng tin học

## Chức năng chính

- Cài Dev-C++ nếu chưa có; tận dụng MinGW hiện có để build/debug C++.
- Cài và cấu hình Java JDK, Python/pip, VS Code Stable; thiết lập JAVA_HOME và PATH.
- Cài extension C++, Java, Python offline cho VS Code; tạo workspace mẫu và shortcut thực hành.
- Giữ nguyên tất cả profile, lịch sử, bookmark và dữ liệu Chrome; không sửa shortcut hay khóa tạo profile.
- Tự chọn profile của cửa sổ Chrome đang mở/gần nhất, xác minh bằng `chrome://version/`, đến `chrome://extensions/` để Load unpacked SFIT và bỏ ghim các extension trên profile đó, bao gồm SFIT. SFIT tự kiểm soát tab/trang web trong lịch đã đặt và ngừng kiểm soát khi hết giờ; chỉ áp dụng trong profile đã cài.
- Kiểm tra phần mềm, chạy thử Java/Python/C++, ghi log và cho phép chạy lại, bỏ qua thành phần đã đúng.

## Vị trí bộ cài và dữ liệu

| Nội dung | Vị trí |
| --- | --- |
| Bộ cài dùng để chép sang USB/LAN | `school-lab\dist\SchoolLab-2.4.0-20261030` trong thư mục dự án — chép **nguyên thư mục** |
| Installer và extension offline | `Files\` trong thư mục bộ cài |
| SFIT sau khi cài trên máy trạm | `%ProgramFiles%\SchoolLab\ChromeExtension\1-sfit-tracker` |
| Workspace thực hành | `Documents\SchoolLab\<PackageId>` của tài khoản lớp |
| Log cài phần mềm | `%ProgramData%\SchoolLab\Logs\<Tên máy>` |
| Log cài SFIT | `%LOCALAPPDATA%\SchoolLab\Chrome` |

## Sửa ngày giờ áp dụng SFIT

**Trước khi mang đi cài**, mở `Files\ChromeExtension\config.js` trong bộ cài/USB và sửa:

```javascript
"startAt": "2026-11-01T08:00:00+07:00",
"endAt":   "2026-11-01T11:00:00+07:00",
```

Giữ đuôi `+07:00` (giờ Việt Nam); giờ kết thúc phải sau giờ bắt đầu. Đây là lịch mẫu, cần thay theo buổi thi. Giữ `enabled: true`; đổi trang thi tại `examUrl` và danh sách tên miền tại `allowedHosts` nếu cần. Máy trạm phải có ngày giờ đúng.

Chỉ sửa `config.js`; bộ cài tự kiểm tra và cập nhật mã gói, không cần build lại. Sửa trên USB không tự cập nhật máy đã cài: mở đúng profile Chrome rồi chạy lại `Install-ChromeExtension.cmd` trên máy đó. Khi phát triển và build gói mới, sửa nguồn extension tại `1-sfit-tracker\config.js` trong thư mục dự án.

## Cách chạy

1. Đăng nhập tài khoản Windows dùng cho lớp; Chrome Stable 120+ phải có sẵn. Đóng VS Code, **mở đúng profile Chrome cần cài** rồi chạy script; nên chỉ để một cửa sổ Chrome. Nếu Chrome đang đóng, script mở profile dùng gần nhất.
2. Chuột phải `Install-Lab.cmd` → **Run as administrator** để cài toàn bộ. Nếu chỉ cần cài/cập nhật SFIT, chạy `Install-ChromeExtension.cmd` bằng Administrator.
3. Chờ hoàn tất, để máy yên khi Chrome tự thao tác. SFIT thành công khi hiện **SFIT DA XAC NHAN**, mã **0**. Nếu báo **3010**, khởi động lại và chạy tiếp theo thông báo.

Sau khi cài, dữ liệu SFIT nằm trên máy trạm; không cần giữ USB cắm vào để lịch hoạt động.

Lần cài chỉ áp dụng cho profile đã chọn. Các profile khác giữ nguyên extension/ghim của chúng. Ghim bị quản trị ép bằng policy sẽ báo lỗi để xử lý, không tự thay policy bên ngoài. Nếu không xác định được profile hoặc không xác nhận được trạng thái bỏ ghim, script báo lỗi thay vì chọn profile khác.
