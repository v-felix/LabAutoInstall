# LabAutoInstall

**Offline Classroom Setup Toolkit — SchoolLab 2.3.0**

Bộ script PowerShell dựa trên PSAppDeployToolkit để chuẩn bị máy thực hành Windows 10/11 x64. Chạy bằng Administrator từ USB hoặc thư mục chia sẻ LAN.

Hai file chạy nằm ngay ngoài cùng repo:

- **[Install-Lab.cmd](Install-Lab.cmd)**: cài toàn bộ phần mềm, môi trường và SFIT.
- **[Install-ChromeExtension.cmd](Install-ChromeExtension.cmd)**: chỉ cài/cập nhật SFIT.

Chuột phải → **Run as administrator**. Hai file gọi bộ cài tại `school-lab\dist\SchoolLab-2.3.0-20261029`; cần build trước theo hướng dẫn bên dưới hoặc chép nguyên bộ cài đã có vào đúng vị trí này. Nếu thiếu, cửa sổ sẽ báo rõ đường dẫn.

## Chức năng

- Cài Dev-C++, Java JDK, Python/pip và VS Code Stable; cấu hình PATH, JAVA_HOME.
- Cài extension C++, Java, Python offline cho VS Code; tạo workspace build/debug và kiểm tra môi trường.
- Xóa dữ liệu Chrome cũ của tài khoản hiện tại, không sao lưu; tạo một profile SchoolLab và tự nạp extension SFIT qua Load unpacked. Không chặn tạo profile mới.
- SFIT tự áp dụng giới hạn tab/trang thi theo ngày giờ trong cấu hình và ngừng kiểm soát khi hết giờ. Chỉ áp dụng cho profile đã nạp extension.
- Cho phép chạy lại, bỏ qua thành phần đã đúng; ghi log theo máy và xử lý yêu cầu khởi động lại.

## Vị trí quan trọng

| Nội dung | Vị trí |
| --- | --- |
| Script cài đặt | `school-lab/package/` |
| Nguồn extension SFIT, lịch áp dụng trước khi build | `1-sfit-tracker/config.js` |
| Danh sách phiên bản, URL và SHA-256 của bộ cài 2.3.0 | `school-lab/sources-lock.json` |
| Bộ cài sau khi build, chép nguyên thư mục sang USB | `school-lab/dist/SchoolLab-2.3.0-20261029/` |
| Lịch SFIT có thể sửa trên USB trước khi cài | `Files/ChromeExtension/config.js` trong bộ cài |

Sửa `startAt` và `endAt`, giữ múi giờ `+07:00`. Lịch mẫu: `2026-11-01T08:00:00+07:00` đến `2026-11-01T11:00:00+07:00`. Sửa trên USB không tự cập nhật máy đã cài; cần chạy lại bước cài SFIT trên máy đó.

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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-OfflinePackage.ps1 -OutputDirectory .\dist\SchoolLab-2.3.0-20261029
```

Repo chứa mã nguồn, không chứa installer/VSIX, thư mục `dist` hay log thử nghiệm. Máy trạm dùng nguyên bộ cài đã build và không cần tải lại các phần mềm đã đóng gói.

## Chạy trên máy lớp

Đăng nhập đúng tài khoản lớp, đóng Chrome/VS Code. Chrome Stable 120+ cần có sẵn. Chuột phải `Install-Lab.cmd` → **Run as administrator**. Nếu chỉ cần cài/cập nhật SFIT, chạy `Install-ChromeExtension.cmd` bằng Administrator. Để máy yên khi Chrome tự thao tác; hoàn tất SFIT khi hiện **SFIT DA XAC NHAN**, mã **0**.

Hướng dẫn ngắn và vị trí log: [school-lab/README.vi.md](school-lab/README.vi.md).
