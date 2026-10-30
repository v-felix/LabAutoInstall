# LabAutoInstall

**Offline Classroom Setup Toolkit — SchoolLab 2.5.0**

Bộ cài offline cho phòng thực hành Windows 10/11 x64, chạy bằng Administrator từ USB hoặc LAN.

## Chức năng chính

- Cài Dev-C++, Java JDK, Python/pip và VS Code Stable; cấu hình PATH, JAVA_HOME, extension và workspace C++/Java/Python.
- **Giữ nguyên mọi profile và dữ liệu Chrome đang có.** Tạo một profile riêng tên **OLBDB**, cài SFIT vào đó và bỏ ghim extension trên profile OLBDB. Không cài/bỏ ghim trên các profile cũ.
- Tạo shortcut **OLBDB** trên Desktop, mở đúng profile thi và **https://utcoj.info/**. Chạy lại bộ cài sẽ dùng lại profile OLBDB do SchoolLab tạo, không tạo trùng hoặc reset.
- SFIT tự áp dụng từ **13:00 đến 17:00 ngày 01/11/2026, giờ Việt Nam**. Không nhập mã vào thi, không tạo phiên. Hết giờ tự ngừng giới hạn.
- Kiểm tra phần mềm, ghi log và xử lý yêu cầu khởi động lại; bỏ qua phần mềm đã đúng khi chạy lại.

## Hai file chạy ngoài cùng

- **[Install-Lab.cmd](Install-Lab.cmd)**: cài toàn bộ phần mềm và chuẩn bị OLBDB/SFIT.
- **[Install-ChromeExtension.cmd](Install-ChromeExtension.cmd)**: chỉ chuẩn bị/cập nhật OLBDB, SFIT và shortcut.

Chuột phải → **Run as administrator**. Hai file gọi bộ cài tại `school-lab\dist\SchoolLab-2.5.0-20261030`; cần build trước hoặc chép nguyên bộ cài đã có vào đúng vị trí đó. Chrome Stable 120+ cần có sẵn. Có thể giữ Chrome cũ đang mở; để máy yên khi script tự mở và cấu hình cửa sổ OLBDB. Đóng VS Code nếu cài toàn bộ.

Sau khi có **SFIT DA XAC NHAN**, mã **0**, ngày thi chỉ cần mở shortcut **OLBDB** trên Desktop. Không cần cắm USB hoặc nhập mã kích hoạt. SFIT chỉ áp dụng trong profile OLBDB; không khóa các profile/trình duyệt khác.

## Vị trí và sửa lịch

| Nội dung | Vị trí |
| --- | --- |
| Script nguồn | `school-lab/package/` |
| Nguồn SFIT, sửa trước khi build | [1-sfit-tracker/config.js](1-sfit-tracker/config.js) |
| Bộ cài hoàn chỉnh, chép nguyên thư mục sang USB | `school-lab/dist/SchoolLab-2.5.0-20261030/` |
| Sửa lịch trên USB, không cần build lại | `Files/ChromeExtension/config.js` bên trong bộ cài |
| Phiên bản/URL/hash của installer và VSIX | `school-lab/sources-lock.json` |

```javascript
"enabled": true,
"startAt": "2026-11-01T13:00:00+07:00",
"endAt":   "2026-11-01T17:00:00+07:00",
"examUrl": "https://utcoj.info/",
"allowedHosts": ["utcoj.info"],
```

Giữ đuôi `+07:00`, dùng giờ 24 tiếng, `endAt` phải sau `startAt`. Đồng hồ máy trạm phải đúng. Sửa **nguồn SFIT** thì build gói mới; sửa `config.js` **trong bộ cài/USB** thì lưu và chạy lại `Install-ChromeExtension.cmd` trên từng máy cần cập nhật. Sửa trên USB không tự đổi lịch ở máy đã cài. Shortcut sẽ được cập nhật theo `examUrl` của gói.

Test nhanh: đặt bắt đầu trước hiện tại 1 phút, kết thúc sau hiện tại 2 phút. Với Load unpacked thủ công, sửa file trong thư mục đã nạp rồi Reload tại `chrome://extensions/`.

## Dựng bộ cài

Máy chuẩn bị cần Internet, Windows PowerShell 5.1 x64 và Node.js trong PATH. Từ thư mục repo:

```powershell
Set-Location .\school-lab
New-Item -ItemType Directory -Path .\downloads\current -Force | Out-Null
if (-not (Test-Path .\downloads\current\sources-lock.json)) {
    Copy-Item .\sources-lock.json .\downloads\current\sources-lock.json
}
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-OfflinePayloads.ps1
# Chạy sau khi tải thành công; output phải là thư mục chưa tồn tại.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-OfflinePackage.ps1 -OutputDirectory .\dist\SchoolLab-2.5.0-20261030
```

Git chứa mã nguồn, không chứa các installer/VSIX dung lượng lớn, `dist` hoặc log thử nghiệm. Máy trạm dùng nguyên bộ cài đã build để cài offline.

Hướng dẫn chạy và log: [school-lab/README.vi.md](school-lab/README.vi.md).
