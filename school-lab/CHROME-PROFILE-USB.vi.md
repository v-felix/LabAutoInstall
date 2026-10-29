# SchoolLab 2.3.0 — Một profile Chrome và tự cài SFIT từ USB

## Luồng cài đã đơn giản hóa

1. Kiểm tra quyền admin, đúng tài khoản Windows dùng trong lớp và Chrome đã đóng hoàn toàn.
2. Tự gỡ những giá trị policy do SchoolLab 2.2 đã đặt, dựa trên journal cũ. Không cần giáo viên đi sửa Registry hoặc chạy restore từng máy.
3. Lần đầu chạy 2.3, **xóa toàn bộ dữ liệu Chrome cũ** ở `%LOCALAPPDATA%\Google\Chrome\User Data`, gồm các profile, bookmark, cookie, đăng nhập và extension cũ. **Không sao lưu.** Tạo lại một profile `Default`, tên hiển thị `SchoolLab`; chuẩn bị thông tin mở lại đúng profile đó.
4. Đưa các shortcut Chrome thông thường ở Desktop/Start Menu/taskbar về `--profile-directory="Default"` để không tạo lại profile đã xóa khi mở shortcut cũ; tạo thêm **SchoolLab Chrome** trên Desktop. Shortcut dùng user-data-dir tùy chỉnh không bị sửa. Chép SFIT vào Program Files, đăng ký Native Messaging bridge, mở Chrome bằng tài khoản thường thông qua Explorer.
5. Tự chọn tab có sẵn hoặc nhập `chrome://extensions/` vào omnibox rồi Enter sau khi xác nhận đúng cửa sổ/focus. Đợi tài liệu Extensions thật tải xong, bật Developer mode, bấm Load unpacked, điền thư mục và chọn.
6. Chỉ báo **SFIT DA XAC NHAN / mã 0** khi có handshake mới đúng ID, version, cấu hình, PackageId và SID.

Đây là thao tác xóa dữ liệu dành cho máy thực hành đã được cho phép dọn sạch. Không chạy bước Chrome trên tài khoản cá nhân có dữ liệu cần giữ. Chỉ dọn Chrome của tài khoản Windows đang chạy bộ cài; không quét/xóa thư mục tài khoản Windows khác.

## Giáo viên chạy thế nào

- Chép nguyên thư mục `SchoolLab-2.3.0-20261029` vào USB hoặc thư mục chia sẻ.
- Nếu đã đổi lịch ở bản cũ, chép riêng `Files\ChromeExtension\config.js` sang gói mới; kiểm lại ngày giờ trước khi chạy.
- Đóng Chrome hoàn toàn, kể cả tiến trình nền. Không mở Chrome khác trong lúc bộ cài chạy.
- Máy đã đủ Java/Python/VS Code: chuột phải **Install-ChromeExtension.cmd → Run as administrator**. Máy mới triển khai cả bộ: **Install-Lab.cmd → Run as administrator**.
- Để máy yên, thả Ctrl/Alt/Shift. Script tự mở trang quản lý, không yêu cầu người cài bấm mở trang đó bằng tay.
- Chờ SFIT DA XAC NHAN và mã 0. Đóng/mở Chrome lại (có thể dùng SchoolLab Chrome trên Desktop) để kiểm tra chỉ có SchoolLab và lịch SFIT đúng.

Gói mới không có Restore-ChromeProfiles.cmd, không tạo backup Chrome, không đặt policy chặn thêm profile, Guest/Incognito, browser sign-in/Sync hoặc cài extension. Profile sạch bắt đầu với danh sách ghim rỗng; không tự ghim SFIT. Không triển khai khóa gỡ SFIT.

## Chạy lại và mở Chrome về sau

Journal `profile-state.json` schema 2 ghi nhận profile đã chuẩn bị. Chạy lại khi chỉ còn Default thì giữ nguyên profile và cài/kiểm lại SFIT. Nếu đã xuất hiện profile khác hoặc cache danh sách profile cũ, lần chạy bộ cài tiếp theo sẽ dọn sạch lại để trở về một Default/SchoolLab. Nếu bị ngắt giữa lúc xóa, trạng thái ResetPending cho phép chạy lại tiếp tục.

Chrome tự quản lý Local State/Secure Preferences sau khi mở; script không giả ID extension, vị trí force-installed hoặc mã bảo vệ. Khi vừa cài xong chỉ có một profile dùng để mở về sau. Người dùng vẫn được tạo profile mới vì đã bỏ cơ chế chặn; bộ cài không chạy tác vụ dọn profile ngầm mỗi lần mở Chrome.

## Tự sửa policy từ gói cũ

Các bản 2.2 đặt `ExtensionSettings.*.installation_mode=blocked` và cho phép riêng ID SFIT. Chromium kiểm mặc định chặn toàn bộ trước khi đọc extension unpacked, nên cấu hình đó vẫn có thể chặn Load unpacked. Đây là lỗi thiết kế của gói cũ; không cần xóa/cài lại Chrome.

2.3 đọc `%LOCALAPPDATA%\SchoolLab\Chrome\policy-state.json` cũ, hoàn tác phần do SchoolLab đã thay đổi và ghi trạng thái Removed. Các giá trị ban đầu và thay đổi mới của quản trị viên được giữ lại; không xóa cả nhánh Policies\Google\Chrome. Không bật lại các hạn chế sau khi SFIT cài xong.

Nếu một policy cấm thực sự tồn tại từ nguồn khác, script dừng trước khi xóa dữ liệu và ghi rõ policy. Nó không tự bỏ cấm của quản trị viên khác. Backup do bản cũ tạo trước đây không được dùng và không cần thao tác để hoàn tất gói mới; luồng cài mới không có bước backup/restore.

Nguồn xác minh hành vi chặn unpacked: [Chromium UnpackedInstaller::IsLoadingUnpackedAllowed](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/extensions/browser/unpacked_installer.cc).

## Log và kiểm thử

Log ở `%LOCALAPPDATA%\SchoolLab\Chrome`: result.json, install.log, profile-state.json, expected.json, heartbeat.json; uia-diagnostic.txt khi thất bại. Mã 69030 nghĩa là bước Chrome chưa đạt. Check-LabReady của gói mới cần toàn bộ báo cáo cùng PackageId; nếu mới thử riêng Chrome trên bộ phần mềm cũ, dùng dòng SFIT DA XAC NHAN/mã 0 để xác nhận riêng bước đó.

Đã kiểm thử xóa dữ liệu giả trong thư mục dự án và sửa policy cũ trong HKCU test key riêng; không xóa profile hay đổi policy Chrome thật của máy phát triển. Cần kiểm thử VM: chạy gói mới trên máy đã bị policy của 2.2 chặn, xác nhận tự dọn policy, tự mở trang, tự cài và mở Chrome lại chỉ có SchoolLab. Sau đó thử Windows 10/11 đại diện trước khi dùng rộng.
