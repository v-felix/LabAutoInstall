# LabAutoInstall

**Offline Classroom Setup Toolkit — SchoolLab 2.6.1**

Bộ cài offline cho phòng thực hành Windows 10/11 x64, chạy bằng Administrator từ USB hoặc LAN.

## Chức năng chính

- Cài Dev-C++, Java JDK, Python/pip và VS Code Stable; cấu hình PATH, JAVA_HOME, extension và workspace C++/Java/Python.
- **Giữ nguyên mọi profile và dữ liệu Chrome đang có.** Tạo một profile riêng tên **Olympic Đặc Biệt 2026**, cài SFIT vào đó và bỏ ghim extension trên profile Olympic Đặc Biệt 2026. Không cài/bỏ ghim trên các profile cũ.
- Tạo shortcut **Olympic Đặc Biệt 2026** trên Desktop, mở đúng profile thi và **https://utcoj.info/**. **Mỗi lần cài SFIT đều tạo profile mới**; shortcut thi trỏ sang profile vừa tạo. Giữ các profile cũ để quản trị viên tự xóa, không phụ thuộc thông tin profile còn sót lại từ lần cài trước.
- SFIT tự áp dụng từ **13:00 đến 17:00 ngày 01/11/2026, giờ Việt Nam**. Không nhập mã vào thi, không tạo phiên. Hết giờ tự ngừng giới hạn.
- Kiểm tra phần mềm, ghi log; bỏ qua phần mềm đã đúng khi chạy lại. Nếu cần restart, **cài xong toàn bộ mới đếm ngược 60 giây rồi restart**, không restart giữa các bước.

## Hai file chạy ngoài cùng

- **[Install-Lab.cmd](Install-Lab.cmd)**: cài toàn bộ phần mềm và chuẩn bị Olympic Đặc Biệt 2026/SFIT.
- **[Install-ChromeExtension.cmd](Install-ChromeExtension.cmd)**: chỉ chuẩn bị/cập nhật Olympic Đặc Biệt 2026, SFIT và shortcut.

Chuột phải → **Run as administrator**. Hai file gọi bộ cài tại `school-lab\dist\SchoolLab-2.6.1-20261031`; cần build trước hoặc chép nguyên bộ cài đã có vào đúng vị trí đó. Chrome Stable 120+ cần có sẵn. Có thể giữ Chrome cũ đang mở; để máy yên khi script tự mở và cấu hình cửa sổ Olympic Đặc Biệt 2026. Đóng VS Code nếu cài toàn bộ.

Nếu có yêu cầu restart (mã **3010**), script vẫn cài VS Code/SFIT xong trước, sau đó đếm ngược **60 giây**. Lưu công việc; **Ctrl+C** hủy đếm ngược. Sau restart, đăng nhập lại **đúng tài khoản Windows đã cài**; script tự kiểm tra kết quả từ ổ máy, không cần USB hoặc mở lại bộ cài. Không tự đăng nhập Windows, không restart lặp. Lỗi cài đặt thật sẽ dừng và ghi log, không tự restart. Ứng dụng còn tài liệu chưa lưu có thể giữ máy ở màn hình xác nhận restart.

Khi kết quả đã đạt và hoàn tất restart nếu có, ngày thi chỉ cần mở shortcut **Olympic Đặc Biệt 2026** trên Desktop. Không cần cắm USB hoặc nhập mã kích hoạt. SFIT chỉ áp dụng trong profile Olympic Đặc Biệt 2026; không khóa các profile/trình duyệt khác.

## Vị trí và sửa lịch

| Nội dung | Vị trí |
| --- | --- |
| Script nguồn | `school-lab/package/` |
| Nguồn SFIT, sửa trước khi build | [1-sfit-tracker/config.js](1-sfit-tracker/config.js) |
| Bộ cài hoàn chỉnh, chép nguyên thư mục sang USB | `school-lab/dist/SchoolLab-2.6.1-20261031/` |
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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-OfflinePackage.ps1 -OutputDirectory .\dist\SchoolLab-2.6.1-20261031
```

Git chứa mã nguồn, không chứa các installer/VSIX dung lượng lớn, `dist` hoặc log thử nghiệm. Máy trạm dùng nguyên bộ cài đã build để cài offline.

Hướng dẫn chạy và log: [school-lab/README.vi.md](school-lab/README.vi.md).

Mỗi lần chạy cài SFIT sẽ tạo một profile mới; profile cũ được giữ nguyên để quản trị viên tự xóa khi cần. Shortcut thi do SchoolLab tạo được cập nhật sang profile mới, kể cả khi profile cũ đã bị xóa tay.
