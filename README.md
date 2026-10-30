# LabAutoInstall

**Offline Classroom Setup Toolkit — SchoolLab 2.4.0**

Bộ script PowerShell dựa trên PSAppDeployToolkit để chuẩn bị máy thực hành Windows 10/11 x64. Chạy bằng Administrator từ USB hoặc thư mục chia sẻ LAN.

Hai file chạy nằm ngay ngoài cùng repo:

- **[Install-Lab.cmd](Install-Lab.cmd)**: cài toàn bộ phần mềm, môi trường và SFIT.
- **[Install-ChromeExtension.cmd](Install-ChromeExtension.cmd)**: chỉ cài/cập nhật SFIT.

Chuột phải → **Run as administrator**. Hai file gọi bộ cài tại `school-lab\dist\SchoolLab-2.4.0-20261030`; cần build trước theo hướng dẫn bên dưới hoặc chép nguyên bộ cài đã có vào đúng vị trí này. Nếu thiếu, cửa sổ sẽ báo rõ đường dẫn.

## Chức năng

- Cài Dev-C++, Java JDK, Python/pip và VS Code Stable; cấu hình PATH, JAVA_HOME.
- Cài extension C++, Java, Python offline cho VS Code; tạo workspace build/debug và kiểm tra môi trường.
- Giữ nguyên tất cả profile và dữ liệu Chrome. Cài SFIT vào profile của cửa sổ Chrome đang mở/gần nhất và bỏ ghim các extension trong profile đó, bao gồm SFIT. Không đổi shortcut hoặc chặn tạo profile mới.
- SFIT tự áp dụng giới hạn tab/trang thi theo ngày giờ trong cấu hình và ngừng kiểm soát khi hết giờ. Chỉ áp dụng cho profile đã nạp extension.
- Cho phép chạy lại, bỏ qua thành phần đã đúng; ghi log theo máy và xử lý yêu cầu khởi động lại.

## Vị trí quan trọng

| Nội dung | Vị trí |
| --- | --- |
| Script cài đặt | `school-lab/package/` |
| Nguồn extension SFIT, lịch áp dụng trước khi build | `1-sfit-tracker/config.js` |
| Danh sách phiên bản, URL và SHA-256 của bộ cài 2.4.0 | `school-lab/sources-lock.json` |
| Bộ cài sau khi build, chép nguyên thư mục sang USB | `school-lab/dist/SchoolLab-2.4.0-20261030/` |
| Lịch SFIT có thể sửa trên USB trước khi cài | `Files/ChromeExtension/config.js` trong bộ cài |

## Cách sửa ngày giờ SFIT

1. Mở đúng file `config.js` bằng Notepad hoặc VS Code:
   - **Trước khi build:** [1-sfit-tracker/config.js](1-sfit-tracker/config.js).
   - **Đã có bộ cài/USB:** `school-lab\dist\SchoolLab-2.4.0-20261030\Files\ChromeExtension\config.js`, hoặc `Files\ChromeExtension\config.js` nếu mở ngay trong thư mục bộ cài.
2. Sửa ba dòng dưới đây trong cấu hình, rồi lưu file. Ví dụ thi **ngày 01/11/2026, từ 08:00 đến 11:00 giờ Việt Nam**:

   ```javascript
   "enabled": true,
   "startAt": "2026-11-01T08:00:00+07:00",
   "endAt":   "2026-11-01T11:00:00+07:00",
   ```

   Định dạng: `YYYY-MM-DDTHH:mm:ss+07:00`, dùng giờ 24 tiếng. Giữ dấu ngoặc kép, dấu phẩy và đuôi `+07:00`; `endAt` phải sau `startAt`.
3. Nếu sửa **mã nguồn**, build gói mới theo phần dưới. Nếu sửa **bộ cài/USB**, không cần build lại: mở đúng profile Chrome rồi chạy `Install-ChromeExtension.cmd` bằng Administrator trên từng máy cần cập nhật. Bộ cài tự kiểm tra và cập nhật mã gói cho lịch mới. Hai file chạy ngoài cùng repo dùng lịch trong **bộ cài đã build**, không đọc trực tiếp file nguồn.

Trước `startAt`, SFIT chờ; từ `startAt` đến trước `endAt`, SFIT kiểm soát; đến `endAt`, SFIT tự ngừng kiểm soát, không cần gỡ extension hoặc restore. Lịch tính theo ngày giờ của máy, không tính từ lúc cài; kiểm tra đồng hồ máy trạm. Sửa file trên USB không tự đổi lịch ở các máy đã cài.

**Test nhanh:** đặt `startAt` trước giờ hiện tại 1 phút và `endAt` sau giờ hiện tại 2 phút, rồi cài/cập nhật SFIT. Với extension được Load unpacked thủ công khi phát triển, sửa file trong chính thư mục đã nạp rồi bấm **Reload** tại `chrome://extensions/`.

## Dựng bộ cài

Trên máy Windows chuẩn bị có Internet, dùng **Windows PowerShell 5.1 x64** và có Node.js trong PATH. Từ thư mục repo:

```powershell
Set-Location .\school-lab
New-Item -ItemType Directory -Path .\downloads\current -Force | Out-Null
# Chỉ cần chép lock lần đầu; giữ lock hiện có khi tải tiếp.
if (-not (Test-Path .\downloads\current\sources-lock.json)) {
    Copy-Item .\sources-lock.json .\downloads\current\sources-lock.json
}
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-OfflinePayloads.ps1
# Chạy sau khi tải thành công; thư mục output phải chưa tồn tại.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-OfflinePackage.ps1 -OutputDirectory .\dist\SchoolLab-2.4.0-20261030
```

Repo chứa mã nguồn, không chứa installer/VSIX, thư mục `dist` hay log thử nghiệm. Bản 2.4.0 giữ nguyên phiên bản phần mềm và lịch mẫu của 2.3.0; chỉ đổi cách cài Chrome/SFIT. Máy trạm dùng nguyên bộ cài đã build và không cần tải lại các phần mềm đã đóng gói.

## Chạy trên máy lớp

Đăng nhập đúng tài khoản lớp, đóng VS Code và **mở sẵn đúng profile Chrome cần cài SFIT**. Nếu đang mở nhiều cửa sổ Chrome, đưa cửa sổ cần cài lên trước rồi chạy script; nên chỉ để một cửa sổ khi cài. Chrome Stable 120+ cần có sẵn. Nếu Chrome đang đóng, script mở profile dùng gần nhất. Chuột phải `Install-Lab.cmd` → **Run as administrator**. Nếu chỉ cần cài/cập nhật SFIT, chạy `Install-ChromeExtension.cmd` bằng Administrator. Script mở tab cài đặt riêng, xác định Profile Path qua `chrome://version/`, tự đến `chrome://extensions/` để Load unpacked và bỏ ghim extension bằng giao diện Chrome. Để máy yên khi Chrome tự thao tác; hoàn tất SFIT khi hiện **SFIT DA XAC NHAN**, mã **0**.

Hướng dẫn ngắn và vị trí log: [school-lab/README.vi.md](school-lab/README.vi.md).
