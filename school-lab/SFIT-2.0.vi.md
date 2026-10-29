# SchoolLab 2.3.0 / SFIT Tracker 2.0.0

**Luồng hiện tại:** dọn dữ liệu Chrome cũ, không sao lưu; tạo một profile Default/SchoolLab; tự mở `chrome://extensions/` để Load unpacked. Đã bỏ phần khóa profile/Guest/Incognito/Sync và restore. Policy của SchoolLab 2.2 được tự dọn khi chạy gói mới. Chi tiết: [CHROME-PROFILE-USB.vi.md](CHROME-PROFILE-USB.vi.md).

Driver giữ điều hướng bằng omnibox từ 2.2.1: kiểm foreground/focus/phím bổ trợ trước Enter và đợi tài liệu Extensions thật tải xong. Không chỉ dựa vào lệnh mở Chrome hoặc URL vừa được nhập. SFIT vẫn là extension unpacked; không triển khai khóa gỡ hay khóa tạo profile mới theo yêu cầu hiện tại.

## Thay đổi chính

Lịch thi viết thẳng trong `config.js`, không tạo phiên hay nhập mật khẩu. Đến giờ tự áp dụng bộ lọc, hết giờ tự bỏ chặn. SchoolLab bổ sung cài extension từ USB bằng UI Automation của Chrome và xác minh extension đã chạy qua Native Messaging. Đây là bản pilot, chưa phải chứng nhận nghiệm thu 300 máy.

### Sửa lỗi Chrome trong bản 2.1.2

Log máy ảo của bản 2.1.1 cho thấy tab đang hoạt động là **Adblock Plus has been installed!**, không phải chrome://extensions. Các extension đã có mở trang chào mừng lúc Chrome khởi động; bộ cài cũ cứ tìm Developer mode trên trang web đó rồi timeout 69030.

Bản 2.1.2 ưu tiên cửa sổ Chrome có đúng địa chỉ nội bộ, chọn lại tab Extensions nếu có, và chỉ tìm/bấm Developer mode/Load unpacked khi thanh địa chỉ đã xác nhận chrome://extensions/. Nếu trang chưa sẵn sàng sau 10 giây, script yêu cầu một cửa sổ đúng trang; tối đa hai lần phục hồi trong deadline chung. Không đóng tab hay gỡ extension đã có. Không tự bấm qua đăng nhập Google hoặc trang mua gói của extension khác.

Load unpacked được Invoke trên luồng MTA riêng vì lời gọi mở dialog có thể chờ đến khi dialog đóng; luồng UIA chính vẫn tìm và điền thư mục được. Developer mode chỉ bật khi đang Off; chỉ chuyển bước khi nút Load unpacked hiện ra. Không bấm theo tọa độ. Log ghi riêng Navigate/DeveloperMode/Load/Folder/Verify và ưu tiên ghi danh sách tab trong chẩn đoán.

**Thử lại riêng phần lỗi:** đóng Chrome hoàn toàn, chạy `Install-ChromeExtension.cmd` của bản 2.1.2 bằng Administrator. Không cần gỡ/cài lại Java, Python, VS Code. Chỉ coi bước Chrome đạt khi có **SFIT DA XAC NHAN** và mã 0. Nếu muốn Check-LabReady của gói 2.1.2 xác nhận toàn bộ, chạy Install-Lab.cmd của chính gói này để báo cáo phần máy/tài khoản/Chrome có cùng PackageId; các phần mềm đã đúng được bỏ qua. Lịch riêng đã sửa trong gói cũ cần chép lại vào config.js của gói mới trước khi chạy.

Đã có kiểm thử logic hồi quy từ tình huống Adblock; chưa thay thế lần chạy giao diện Chrome thật trên máy ảo của trường. Nếu vẫn lỗi, gửi ba file result.json, install.log, uia-diagnostic.txt trong %LOCALAPPDATA%\SchoolLab\Chrome.

## Sửa ngày giờ

Mã nguồn trong repo: `1-sfit-tracker\config.js`.

```js
  "enabled": true,
  "startAt": "2026-11-01T08:00:00+07:00",
  "endAt":   "2026-11-01T11:00:00+07:00",
```

**Đây là lịch mẫu**, cần đổi theo lịch thật. Giữ dấu ngoặc kép và `+07:00` (giờ Việt Nam). Bắt đầu tính bao gồm `startAt`; kết thúc tính không bao gồm `endAt`. Không đếm lại từ lúc cài hoặc lúc mở Chrome. `enabled: false` tắt bộ lọc. Lịch sai bị từ chối; không khóa máy vô hạn.

### Sửa source rồi build gói USB

Sửa `1-sfit-tracker\config.js`, sau đó từ thư mục `school-lab` chạy bằng **Windows PowerShell 5.1**:

```powershell
.\Build-OfflinePackage.ps1 -OutputDirectory .\dist\SchoolLab-TenBanMoi
```

Máy build cần Node.js và compiler .NET Framework; máy trạm không cần Node.js. Builder kiểm lịch, tính hash, giữ ID extension ổn định và biên dịch bridge. Đầu ra phải là thư mục mới.

### Đổi giờ trực tiếp trong gói USB đã build

1. Sửa **`Files\ChromeExtension\config.js` trong chính bộ cài USB**.
2. Chạy `Install-Lab.cmd` hoặc chỉ `Install-ChromeExtension.cmd` nếu phần mềm đã đủ.
3. Script xác minh các tệp khác nguyên vẹn, đọc object JSON trong config, kiểm lịch và tự cập nhật hash/PackageId trước khi cài. Không cần băm lại bằng tay. Thư mục bộ cài cần cho phép ghi khi cấu hình đã thay đổi.

Chỉ cấu hình được sửa theo quy trình này; sửa manifest, JS logic, native host hay PowerShell phải build lại. Sửa source cạnh dự án không thay đổi một USB đã build trước đó. Không sửa bản trong Program Files rồi coi kết quả gói USB còn đúng.

### Tester dùng Load unpacked trực tiếp

Sửa `config.js`, sau đó bấm Reload extension ở `chrome://extensions` hoặc đóng/mở Chrome. Sửa file mà không Reload không đảm bảo worker đọc lịch mới. Bản standalone có token rỗng trong `deployment.json` nên không cần native host.

Test nhanh: đặt bắt đầu trước hiện tại một phút, kết thúc sau hiện tại hai phút. Đồng bộ giờ Windows/VM, nhất là sau snapshot hoặc suspend. Nếu để nguyên lịch mẫu, trước ngày mẫu chỉ thấy WAITING.

## Chạy ở máy trạm

1. Đăng nhập đúng tài khoản dùng trong lớp. Đóng Chrome hoàn toàn, kể cả tiến trình nền; đóng VS Code nếu cài cả bộ. Script không kill Chrome.
2. Chuột phải `Install-Lab.cmd` > Run as administrator. Java/Python/Dev-C++/VS Code vẫn theo luồng cũ, bỏ qua thành phần đúng phiên bản.
3. Bước cuối tự chép extension vào `C:\Program Files\SchoolLab\ChromeExtension\1-sfit-tracker`, đăng ký bridge, nhờ Explorer mở Chrome bằng token thường rồi tự nạp extension. Để máy yên trong lúc tự thao tác.
4. Chỉ báo Passed khi nhận báo cáo mới đúng ID/phiên bản/hash cấu hình/PackageId/token cài/SID. Chỉ copy tệp hoặc bấm xong Load unpacked chưa được coi là đạt.
5. Nếu riêng bước Chrome lỗi **69030**, đóng Chrome rồi chạy `Install-ChromeExtension.cmd`, không cần cài lại JDK/Python/VS Code. Xem log nếu timeout.

Cần **Chrome Stable 120+ đã cài**, desktop đang mở khóa, đúng SID sở hữu Explorer; SYSTEM/admin khác không được dùng để nạp profile. Bộ này chưa kèm Chrome installer; thiếu Chrome báo lỗi rõ ràng. Không đăng ký Google Core, không sửa bảo mật Windows hay bỏ qua policy cấm Developer mode.

Profile duy nhất được chuẩn bị là `Default`, tên hiển thị `SchoolLab`. UI driver hỗ trợ tên điều khiển Anh/Việt, có timeout mặc định 120 giây, không bấm tọa độ và không báo thành công khi chưa có handshake. Thời gian thực cần đo ở pilot.

## Bộ lọc và trạng thái

| Trạng thái | Hành vi |
| --- | --- |
| WAITING | Chưa đến giờ; không chặn, không ép tab, không ẩn chat |
| ACTIVE | Áp dụng bộ lọc và kiểm soát tab theo cấu hình |
| ENDED | Gỡ luật/overlay/ẩn chat, giữ nguyên bài và trang đang mở |
| DISABLED | Không áp dụng vì enabled=false |
| INVALID_CONFIG / ERROR | Hiển thị lỗi, gỡ luật để tránh khóa nhầm; bộ cài không nghiệm thu đạt |

`allowedHosts` dùng hostname chính xác, gồm cả tên có/không www nếu cần. Không cho tên miền giả có hậu tố như `laptrinhonline.club.evil.test`.

- `networkMode: "navigation"` mặc định: chặn mở trang HTTP(S) ngoài danh sách. Không lọc mọi API/tài nguyên nền hoặc iframe.
- `networkMode: "strict"`: chặn cả yêu cầu HTTP(S)/WebSocket ngoài danh sách. Cần khai báo đủ CDN/API thực tế trong `resourceHosts` và kiểm thử đăng nhập/nộp bài. Resource host được tải không tự thành trang được phép mở.
- Dùng DNR session rules để Chrome đóng thì không để lại luật chặn bền vững. Worker lập alarm ở mốc bắt đầu/kết thúc, kiểm lại mỗi 30 giây và khi có sự kiện. Alarm có thể trễ khi máy ngủ/bận; wake/sự kiện tiếp theo sẽ đối chiếu giờ. Không cam kết chính xác từng mili giây.
- `singleExamTab: true`: chọn một tab OJ hoặc tự mở; tab mới trong giờ có thể bị đóng; chuyển tab thì đưa về tab thi. Tab cũ không bị bulk-close, có overlay ngoài tab thi. Cần lưu bài và dọn tab trước khi đến giờ. Popup đăng nhập có thể xung đột; đăng nhập trước hoặc thử singleExamTab=false.
- Hết giờ không đóng tab, không tải lại bài làm. Một trang đã bị chuyển hướng sang thông báo chặn cần nhập lại địa chỉ khi hết giờ; không tự khôi phục URL có thông tin nhạy cảm.

Đã bỏ mật khẩu thi ghi cứng và auto-submit; đăng nhập/tham gia bằng cơ chế của OJ. Bỏ vòng đo kích thước cửa sổ 100 ms và alert đoán DevTools. Mất focus chỉ là tín hiệu, không tự kết luận gian lận.

## Trạng thái, log, native bridge

Icon SFIT mở trạng thái/lịch/giờ máy; nút Kiểm tra lại cập nhật báo cáo, Xuất nhật ký JSON tải log cục bộ. Log giới hạn mặc định 300 mục, khử lặp; không ghi bài làm, mật khẩu hoặc query string URL.

Tại `%LOCALAPPDATA%\SchoolLab\Chrome`:

- `result.json`: kết quả cài, đúng tài khoản và gói.
- `heartbeat.json`: báo cáo gần nhất, tối đa mỗi phút khi worker được đánh thức.
- `expected.json`: phiên bản/hash/token dự kiến, profile và đường dẫn.
- `install.log`: tiến trình từng bước và lần chọn lại tab/mở cửa sổ phục hồi.
- `uia-diagnostic.txt`: cây điều khiển khi timeout.

`Check-LabReady.cmd` đối chiếu kết quả cài với gói và hash lịch. Đây là kết quả ở thời điểm ghi log; không chứng minh extension chưa bị tắt sau đó. Bấm Kiểm tra lại trong SFIT để kiểm hiện tại.

Bridge chỉ nhận trạng thái từ ID đã đăng ký, kiểm token/hash/phiên bản rồi ghi báo cáo; không chạy lệnh tùy ý, không mở cổng mạng, không tự gửi log lên Internet. Nó không phải watchdog Windows độc lập.

## Giới hạn

Chỉ kiểm soát profile đã nạp. Profile khác, Guest/Incognito không được phủ hoặc trình duyệt khác vẫn là đường vòng. Không khóa Alt+Tab, Task Manager hoặc ứng dụng khác. Heartbeat còn sống không chứng minh học sinh đang xem profile thi.

Extension unpacked có thể bị tắt/gỡ/sửa. Quyền admin và đồng hồ Windows vẫn thuộc học sinh thì không thể chống can thiệp tuyệt đối. Có ghi tín hiệu đồng hồ lùi, không tự phạt hoặc khóa vô hạn. Theo yêu cầu mới không có tạo phiên, ký lịch hay màn hình mật khẩu; sửa lịch trực tiếp trong code.

Muốn phủ toàn máy cần tài khoản/mạng/policy riêng; bản này không tự triển khai các hạn chế đó.

## Nghiệm thu pilot

Kiểm trước/trong/sau lịch, lịch sai, Chrome restart trong giờ, reboot sau hết giờ, sleep qua deadline, đăng nhập/nộp bài/CDN/OAuth, tab cũ/mới, sửa lịch rồi cài lại, đúng/sai profile, Windows 10 và 11. Không dùng 300 máy làm lần thử UI đầu tiên.

Kiểm thử phát triển và phạm vi đã chạy được ghi trong `VALIDATION.md`. Mock/parse/compile không thay thế chạy UI installer thật trên máy trường.
