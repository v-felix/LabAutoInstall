# Kết quả kiểm tra ngày 23/10/2026

- Windows PowerShell **5.1.26100.9711**: **61 assertions passed** ngày 24/10 (60 ngày 23/10, thêm parse `Check-LabReady.ps1`). Bao gồm bảo toàn/idempotence PATH, chặn downgrade, đọc kiến trúc PE, quoting Unicode/space/backslash/metacharacters qua tiến trình thực, giữ exit code/stderr, timeout, dependency/pack VSIX, JSON workspace, giữ bài làm, phát hiện thiếu/sai hash và hai cấu trúc thư mục CLI của VS Code.
- Ngày 23/10 đã import runtime **PSADT 4.1.8** từ release v4, đối chiếu tên tham số `Open-ADTSession` và `Start-ADTProcess`. Phép kiểm tra ban đầu chưa kiểm tra cách truyền giá trị switch; xem kiểm thử tích hợp bổ sung bên dưới. Không chạy installer trong các phép kiểm tra phát triển.
- JDK MSI, Python EXE và VS Code EXE: chữ ký Authenticode **Valid**, publisher lần lượt Eclipse Foundation, Python Software Foundation và Microsoft Corporation. Hash được đối chiếu với nguồn chính thức.
- C/C++ **1.34.4**: metadata xác nhận **win32-x64**, engine VS Code `^1.77.0`, không khai báo extension dependency/pack. VS Code **1.143.1** đáp ứng engine này.
- VSIX có sẵn `bin/cpptools.exe` và `debugAdapters/bin/OpenDebugAD7.exe`. Đã thử helper gọi CLI `--version` trên VS Code **1.142.0** hiện có, kết quả exit 0 và x64. Helper chọn đường dẫn CLI đang dùng từ `bin/code.cmd`, hỗ trợ tài nguyên nằm trong thư mục mang mã commit. Không cài hoặc thay extension trong lần kiểm tra này.
- Máy khảo sát **FELIX, Windows 11 build 26300** có Dev-C++ tại `C:\Program Files (x86)\Dev-Cpp\MinGW64\bin`, **GCC 4.8.1**, **GDB 7.6.1**, target `x86_64-w64-mingw32`. Chế độ Auto chọn **c++11**. Đã compile mẫu, chạy ra `SCHOOLLAB_CPP_OK`, GDB dừng tại `main`, chạy tiếp và `exited normally`. Tệp kiểm thử chỉ nằm trong `school-lab/test-results/cpp-existing-mingw/`.
- Đã tạo và kiểm tra toàn vẹn gói offline. Không cài JDK/Python/VS Code, không cài extension, không sửa PATH/JAVA_HOME, policy hoặc HKLM Run trên máy hiện tại.

**Chưa kiểm thử:** chuỗi cài đặt toàn máy (kể cả repair/reboot thực), Windows 10, tài khoản học sinh, named profile, CLI cài VSIX khi ngắt mạng, F5 trong VS Code, máy Dev-C++ khác, GPO/agent hoặc đóng băng. Các mục này là điều kiện nghiệm thu pilot trong README, trước khi triển khai rộng.

Log kiểm thử cục bộ nằm trong `test-results/` (không đưa inventory máy cá nhân vào gói phân phối). Mỗi bản build có PackageId và lock riêng. Tài liệu này mô tả kết quả phát triển, không phải chứng nhận đã triển khai thành công lên các máy của trường.

## Cập nhật hướng dẫn ngày 24/10/2026

Đã xác nhận các tài khoản dùng trong lớp đều có quyền admin. Hướng dẫn ngắn giao các bước cài, Restart/đăng nhập lại, kiểm tra tự động và mở thử F5 cho giáo viên thực hiện trước buổi học. Nút `Check-LabReady.cmd` chỉ đọc kết quả máy/tài khoản của đúng gói, kiểm tra yêu cầu restart và sự tồn tại của shortcut/workspace. Nút này không tự cài extension, không xác minh Workspace Trust hoặc thay thế việc mở thử F5 của giáo viên. Chuỗi cài đặt vẫn cần nghiệm thu pilot.

Đã chạy script kiểm tra sẵn sàng trên máy phát triển khi chưa triển khai toàn máy: trả mã **2 / CHUA SAN SANG** đúng dự kiến. Chưa thử trạng thái xanh sau một lần cài đặt thực tế.

## Sửa lỗi nạp PSADT từ log máy thử

Log do người dùng cung cấp từ Windows 10 Pro build 19045, máy DESKTOP-3KSEBBP, cho thấy pending reboot đã hết; MinGW GCC 4.9.2/GDB 7.8.1 được nhận diện và C++14 qua preflight. Dừng ở nạp PSADT.ClientServer.Server.dll với HRESULT 0x80131515; các installer đều NotRun. Bản 1.0.2 bổ sung Unblock-File cho module sau xác minh hash và trước Import-Module, theo template PSADT 4.1.8. Thêm thông báo các giai đoạn chép/kiểm tra/chạy để tránh màn hình trống. Cần chạy lại trên máy thử để xác nhận lỗi được giải quyết và nghiệm thu phần cài đặt tiếp theo.

## Sửa cách truyền RequireAdmin — bản 1.0.3 / fix2

Ảnh thử fix1 cho thấy đã qua nạp DLL, dừng ở bind SessionState với giá trị True. Nguyên nhân xác định từ mã module 4.1.8: RequireAdmin có kiểu SwitchParameter; cú pháp `-RequireAdmin $true` để lại một đối số vị trí, bị bind vào SessionState. Bản sửa dùng hashtable splatting có SessionState đúng kiểu và ScriptDirectory rõ ràng.

Đã chạy `tests/Test-LabPSADTSession.ps1` trên Windows PowerShell 5.1: lấy chính hashtable trong script triển khai, xác nhận RequireAdmin=true và SessionState đúng kiểu; để mở phiên bằng token phát triển không nâng quyền, chỉ thay RequireAdmin=false và tên phiên/đường dẫn thử. Mở phiên PSADT 4.1.8 thật thành công, Start-ADTProcess chạy một tiến trình PowerShell `exit 7`, nhận đúng ExitCode=7, Close-ADTSession kết thúc mã 0. Không chạy installer hoặc sửa môi trường máy. Cần tiếp tục thử chuỗi cài trên máy Windows 10 của người dùng.

## Rà soát và mở rộng bản 2.0.0 — 24/10/2026

Log người dùng gửi từ DESKTOP-3KSEBBP xác nhận bản fix2 đã cài JDK 27+35, Python 3.15.1 và VS Code 1.143.1 trên Windows 10 Pro 19045, exit code 0, Java/Python/C++/GDB smoke tests Passed. CMD đóng vì batch chỉ pause khi lỗi. UserProvisioning ở PendingUserLogon nên chưa thể coi tài khoản hoàn tất. Đây là bằng chứng thực tế cho base installer, không phải lỗi crash.

Các thay đổi đã rà soát:

- Batch luôn giữ màn hình kết quả; sửa tác vụ VS Code installer thành !runcode để không tự mở ứng dụng. Nguồn code.iss của Microsoft 1.143.1 xác nhận runcode là task riêng dùng trong silent mode.
- Thêm Embarcadero Dev-C++ 6.3 full NSIS installer, dùng /S /D=... ở cuối, kèm TDM-GCC 9.2 theo mã NSIS chính thức. SHA256 9EA2F0237E5C72D485F9FA29DEF3F0A11C51F8B252F650BE533E09A5E2ADA247 khớp tệp từ GitHub Embarcadero và manifest Microsoft winget. Giữ Dev-C++ đã có; xác định IDE trước, ưu tiên cặp compiler của IDE nếu chỉ có một cặp hợp lệ.
- Bổ sung đủ Java/Python VSIX cùng dependency/pack. Thứ tự dựa trên hard dependency, không coi vòng tham chiếu pack là hard cycle. Cấm CLI tự kéo extension pack khi cài local vì toàn bộ pack đã có trong payload.
- Launcher chỉ khởi tạo tài khoản ngay khi SID hiện tại sở hữu Explorer trong cùng session; SYSTEM/admin khác để lại trạng thái chờ rõ ràng. Giữ mutex launcher suốt cả máy và tài khoản. Nhật ký được ghi atomic; có dòng/stack khi lỗi.
- Tạo ba workspace và shortcut, cấu hình interpreter/JDK/build/debug, bảo toàn bài làm. Java template dùng UTF-8 không BOM sau khi phép chạy javac thật phát hiện lỗi BOM của PowerShell 5.1.

Các kiểm thử bổ sung đã chạy (không cài ứng dụng toàn máy trên máy phát triển):

1. Test-LabLogic: kiểm parse, PATH, version/downgrade, argv Unicode, timeout/exit/stderr, hash, hard dependency/pack, phát hiện Dev-C++, JSON runtime và Java BOM, giữ bài làm. Tổng assertion của lần cuối in trong test-results.
2. Test-LabPSADTSession: mở/đóng phiên PSADT 4.1.8 thật với hashtable production (test dùng RequireAdmin=false), chạy tiến trình exit 7 và nhận đúng mã.
3. Test-LabExtensions: đã cài và liệt kê đúng 7 VSIX trên VS Code 1.143.1 trong user-data-dir/extensions-dir riêng ở test-results, không đổi extension của tài khoản thật. Cấu hình proxy Marketplace 127.0.0.1:9 để các yêu cầu lấy dependency ngoài bị lỗi. CLI không có cảnh báo option không nhận diện. Có deprecation warning nội bộ Node nhưng exit 0 và version đúng.
4. Test-LabRuntimes: dùng JDK 27+35 và full Python 3.15.1 runtime ZIP từ nguồn chính thức, kiểm hash trước giải nén vào test-results; không đăng ký/cài vào máy. Java compile/run, Python thường/isolated, pip 26.2.2, tạo venv và pip của venv, C++/GDB đạt. Debugpy 2026.6.0 đóng gói trong VSIX khởi tạo listener loopback thành công dưới Python 3.15.1; có cảnh báo frozen modules, không cản phép thử.
5. Đã chạy đúng lệnh compile/run của workspace Java/Python bằng runtime tương ứng; kết quả SCHOOLLAB_JAVA_OK/SCHOOLLAB_PYTHON_OK.
6. probe_jdtls.py: Java language server của VSIX redhat.java 1.58.0 khởi tạo JSON-RPC/LSP thành công bằng JDK 27, nạp kèm debugger Java bundle từ VSIX, không mở GUI.

Còn phải nghiệm thu trên máy trường: cài thực Dev-C++ khi máy chưa có, toàn bộ luồng launcher cấu hình ngay tài khoản lớp, Start-Lab dưới SYSTEM/admin khác, đăng nhập lại, đóng băng, profile đã có và thao tác F5/IntelliSense trong VS Code của ba ngôn ngữ. Các kiểm thử CLI/runtime nêu trên không thay thế kiểm thử giao diện hoặc chứng minh toàn bộ 300 máy đã được triển khai.

## Sửa khởi tạo tài khoản — bản 2.0.1 / 24/10/2026

Ảnh máy thử bản 2.0.0 xác nhận phiên PSADT cài toàn máy kết thúc mã 0, nhưng bước [4/4] thất bại mã 69020. Lỗi phát sinh trước vòng cài extension: `New-Object Threading.Mutex` với biểu thức nối SID bị PowerShell 5.1 bind thành constructor ba đối số, đòi đối số cuối là PSReference. Chưa thể coi tài khoản lớp đã sẵn sàng.

Bản 2.0.1 tách tên mutex thành một chuỗi và dùng constructor hai đối số `[System.Threading.Mutex]::new`. Việc tạo mutex nằm trong try/catch để cả lỗi ban đầu cũng được ghi vào initialize.log/result.json; finally chỉ dispose khi mutex đã được tạo.

Đã chạy Test-LabLogic trên Windows PowerShell 5.1, **95 assertions passed**. Kiểm thử bổ sung gọi đúng helper production, giữ mutex và xác nhận một tiến trình PowerShell khác bị chặn, sau đó nhận được mutex khi tiến trình đầu nhả. Đã chạy chính Initialize-LabUser.ps1 với LOCALAPPDATA ở thư mục thử và settings cố ý không tồn tại: qua được tạo mutex, đến bước đọc settings, trả đúng 69020 và ghi log/JSON lỗi có kiểm soát. Phép thử này dừng trước thay đổi PATH, cài extension hay tạo bài mẫu trong tài khoản thật.

Đã kiểm tra thêm debugpy bằng giao thức DAP với Python 3.15.1: initialize/launch, xác nhận breakpoint, stopped event, continue, output mẫu và terminated event đều đạt. Đây là kiểm thử adapter, chưa phải thao tác F5 trong giao diện VS Code.

Cần chạy lại nguyên gói 2.0.1 trên máy thử, xác nhận bước tài khoản và Check-LabReady đạt, rồi mở thử các bài C++/Java/Python. Không suy ra toàn bộ luồng đã đạt chỉ từ mã 0 của phiên PSADT hoặc các kiểm thử phát triển.

## SchoolLab 2.1.0 / SFIT Tracker 2.0.0 — 28/10/2026

Đã triển khai lịch trực tiếp trong config.js, kiểm dữ liệu/timezone, state WAITING/ACTIVE/ENDED/DISABLED, DNR session rules (navigation/strict), quản lý tab theo profile, lưu log giới hạn, bỏ mật khẩu chung/auto-submit và vòng đo DevTools 100 ms. Có trang trạng thái, xuất log và bridge Native Messaging chỉ nhận báo cáo trạng thái, không thực thi lệnh.

SchoolLab có bước cài bằng accessibility UI Automation, chép extension vào Program Files, xác minh handshake đúng nonce/PackageId/version/config SHA/SID, mã lỗi 69030 và lệnh thử lại riêng. UIA chạy trên apartment nền sống suốt tiến trình, từng thao tác có giới hạn 8 giây, toàn quy trình có deadline. Không kill Chrome hoặc bấm tọa độ. Đã kiểm tra read-only rằng COM Explorer desktop có thể lấy được; chưa gọi thao tác cài UI trên máy phát triển.

Người dùng được sửa riêng config.js trong gói USB rồi chạy script. Updater kiểm tất cả hash còn lại, chỉ chấp nhận một comment header và object JSON, kiểm lịch, sửa riêng metadata/hash cấu hình và tạo PackageId phụ thuộc digest. Không chấp nhận sửa mã khác hoặc chèn statement vào config. Cần build lại khi logic/manifest/installer thay đổi.

Kiểm thử đã chạy:

- Test-LabLogic.ps1 trên Windows PowerShell 5.1: **98 assertions passed**, gồm parse các script mới và hồi quy logic cũ.
- tests/sfit.test.cjs trên Node 24: **18 tests passed**. Bao gồm ranh giới thời gian, timezone, ngày sai, host giả/credentials, CDN không thành main-frame allowlist, chuyển trạng thái, restart, tab mới/cũ, log không có query secret, invalid config, giới hạn quyền message và payload native có đúng hash/nonce.
- Test-SfitIntegration.ps1 trên Windows PowerShell 5.1: **21 checks passed**. Compile C# production host/UI driver; dùng chính validator/writer của host với thư mục thử; atomic replace; từ chối origin/token/version/hash/package sai; thử framing 4-byte qua EXE thật bằng message bị từ chối trước khi ghi tài khoản thật; chạy updater thật qua tiến trình PS5.1, kiểm idempotence và chặn code thay đổi/injection/lịch ngược.
- probe-sfit-browser.cjs: **Passed trên Microsoft Edge 156.0.4314.42 headless**, profile riêng và HTTP server loopback trong test-results. Nạp MV3 worker thật, WAITING -> ACTIVE bằng alarm thật, strict DNR rules được engine chấp nhận, request main_frame/API ngoài khớp luật chặn, chat ẩn trong giờ, ENDED bằng alarm thật gỡ toàn bộ luật, chat hiện lại và textarea chứa bài chưa lưu giữ nguyên. Không thay đổi profile Edge/Chrome đang dùng. Đây là kiểm thử engine Chromium, không phải chứng minh thao tác UI installer Chrome Stable đã đạt.

Chưa nghiệm thu: cài UI tự động vào Chrome Stable trên Windows 10/11, nhãn UI/first-run dialog trên từng bản Chrome, đăng ký Native Messaging thật với Chrome, toàn chuỗi SchoolLab 2.1 trên máy trường và OJ đăng nhập/nộp bài/CDN thực. Không cài JDK/Python/VS Code/Chrome toàn máy, không đăng ký native host hay sửa policy trên máy phát triển. Cần thử một máy/VM trước khi dùng diện rộng.

Bản đóng gói cuối **2.1.1** bổ sung nạp tường minh module Utility của chính Windows PowerShell đang chạy. Phép thử production entry qua ProcessStartInfo từ PowerShell 7 phát hiện PSModulePath kế thừa có thể làm Get-FileHash không được nạp trong child 5.1. Bản 2.1.0 được giữ như build phát triển trước sửa; dùng thư mục 2.1.1.

## Sửa điều hướng cài Chrome — bản 2.1.2 / 28/10/2026

Máy ảo của người dùng xác nhận phần máy và khởi tạo VS Code hoàn tất, nhưng Chrome timeout ở DeveloperMode, mã 69030. Log UIA cho thấy tài liệu đang hoạt động là trang “Adblock Plus has been installed!”, kèm nhiều tab chào mừng extension khác. Vì vậy nguyên nhân trực tiếp là bộ cài cũ tìm Developer mode trên sai trang, không phải Java/Python/C++ cài thất bại.

Đã sửa driver production: ưu tiên cửa sổ Chrome có omnibox chrome://extensions/, chọn tab Extensions bằng SelectionItemPattern; không có trang đúng thì launcher yêu cầu cửa sổ riêng, giới hạn hai lần phục hồi sau khoảng đợi 10 giây. Không đóng tab cũ. Developer mode/Load unpacked đều kiểm lại địa chỉ nội bộ trước thao tác. Chỉ chuyển bước khi Load unpacked đã hiện, không phụ thuộc duy nhất ControlType của switch. Invoke mở hộp thư mục chạy trên MTA riêng, không chiếm actor cần tìm và điền dialog. Thêm install.log, Step/ElapsedSeconds trong kết quả lỗi, và ưu tiên tab/điều khiển cài trong chẩn đoán.

Đã chạy Windows PowerShell 5.1:

- Test-SfitIntegration.ps1: **39 checks passed**, gồm compile host và driver C# thật, kiểm bridge/updater cũ, và 18 kiểm hồi quy mới dùng chính planner/nhận diện production cho welcome page, chọn tab có sẵn, trang đúng, địa chỉ giả và nhãn Anh/Việt. Không phát sinh thao tác giao diện hay thay đổi profile/registry/Program Files trên máy phát triển.
- Test-LabLogic.ps1: **98 assertions passed**, gồm parse script mới và các hồi quy cũ.

SFIT extension vẫn là 2.0.0, lịch và logic lọc không đổi. Cần chạy lại Install-ChromeExtension.cmd của 2.1.2 trên máy ảo đang lỗi, xác nhận chọn đúng trang, nạp đúng thư mục và có SFIT DA XAC NHAN/mã 0. Kiểm thử planner/compile chưa chứng minh toàn bộ Chrome UI + Native Messaging trên máy ảo đã đạt. Nếu retry chỉ Chrome từ gói mới, kết quả Chrome có mã gói mới; chạy Install-Lab.cmd của gói mới nếu cần Check-LabReady xác nhận toàn bộ báo cáo cùng PackageId.

## Chuẩn bị một profile Chrome qua USB — bản 2.2.0 / 28/10/2026

Theo lựa chọn tiếp tục USB offline, thêm Chrome.Profile.psm1: lưu nguyên User Data của tài khoản Windows hiện tại vào SchoolLabChromeBackups trên cùng ổ bằng directory rename, journal Prepared/Archived/Ready, profile Default mới tên SchoolLab, không ghim extension mặc định. Không dùng recursive delete, không sửa Secure Preferences/HMAC. Lần chạy lại giữ dữ liệu SchoolLab mới; phát hiện thêm Profile N thì dừng, không âm thầm reset lại. Từ chối đường dẫn gốc reparse point, nguồn/đích chồng lấn, khác ổ và Chrome UserDataDir policy tùy chỉnh. Cùng một global mutex được dùng cho cài và restore; kiểm tra Chrome của SID hiện tại trên mọi session phải đóng.

Policy chặn nút Add profile, Guest, Incognito; tắt browser sign-in/Sync, cho phép SFIT với default_unpinned, mặc định chặn extension không có ngoại lệ. Chỉ ghi các giá trị liên quan, giữ ngoại lệ/settings khác. Có snapshot gốc và restore, phát hiện xung đột nếu quản trị viên đã thay đổi giá trị. Không đặt force_installed giả cho bản unpacked, không khóa Developer mode, không tuyên bố đã chặn menu Remove. Không thêm chặn chrome://extensions vì không giải quyết chống gỡ và cản bảo trì/luồng UI đang dùng.

Trong quá trình kiểm thử đã bắt và sửa hai lỗi Windows PowerShell 5.1: File.Replace cần NullString thay vì $null bị ép thành chuỗi rỗng; New-Item -Force trên registry key đã có có thể làm mất giá trị không liên quan, nên chỉ tạo key khi chưa tồn tại. Hai lỗi được phát hiện trong thư mục giả/HKCU test key, không chạy trên dữ liệu hay policy Chrome thật.

Kết quả:

- Test-ChromeProfiles.ps1: **49 checks passed** trên Windows PowerShell 5.1. Thực hiện chuyển/khôi phục dữ liệu giả, đối chiếu SHA256 từng tệp, ACL thư mục riêng, giữ bài mới khi chạy lại/restore, chặn đường dẫn không hợp lệ, phục hồi journal bị ngắt, tài khoản chưa có Chrome data; dùng chính code production để ghi/khôi phục policy trong một HKCU test key riêng, giữ giá trị khác, giữ baseline qua rerun, chặn xung đột, phục hồi transaction dở và từ chối thay thế policy force-installed đã có. Test key riêng được dọn trong finally.
- Test-LabLogic.ps1: **101 assertions passed**, gồm parse module và script restore mới cùng các hồi quy cũ.
- Test-SfitIntegration.ps1: **39 checks passed**, code extension/native bridge không đổi.

Không cài policy lên HKLM/HKCU Software\Policies\Google\Chrome của máy phát triển; không reset Chrome thật. Chưa nghiệm thu profile mới/policy hiệu lực/không ghim trên giao diện Chrome Stable Windows 10/11. Cần thử cài, chạy lại, đổi lịch và khôi phục trên VM trước khi đưa ra 300 máy.

**Phần chưa đáp ứng được với điều kiện hiện tại:** khóa gỡ SFIT. USB unpacked + quyền admin không bảo đảm được việc này. result.json ghi UninstallProtection=NotAvailable_OfflineUnpacked; Check-LabReady và console in giới hạn. DefaultUnpinned không phải ẩn khỏi menu extension và không ngăn ghim lại. BrowserAddPersonEnabled hạn chế giao diện, không chứng minh chặn mọi cách tạo profile/dùng user-data-dir khác hay trình duyệt khác.

## Tự điều hướng tới trang quản lý — bản 2.2.1 / 29/10/2026

Log do người dùng cung cấp thuộc gói 2.1.2 (20261028-ec5d301d), Chrome 156.0.8078.74. Sau lệnh mở Chrome, cửa sổ vẫn ở New Tab; cả hai lần recovery mở URL cũng không chuyển tới trang quản lý. Khi người thử mở quản lý bằng tay, driver chọn tab, bật Developer mode, nạp thư mục và nhận handshake WAITING thành công. Vì vậy không coi việc phát lệnh ShellExecute hoặc mở cửa sổ là chứng minh Chrome đã điều hướng. Cơ chế thiếu này cũng có trong source 2.2.0.

Bản 2.2.1 thêm điều hướng chủ động: ưu tiên chọn tab Extensions có sẵn; nếu chưa có trang đúng, tìm omnibox gốc của Chrome, đưa cửa sổ lên foreground, xác nhận focus, đặt URL cố định chrome://extensions/ qua ValuePattern rồi commit Enter bằng SendInput. Không dùng clipboard, WScript.SendKeys, tọa độ, URL tùy ý hoặc nhập liệu vào form web. Từ chối ô có tên giống thanh địa chỉ nhưng nằm trong Document; không thao tác màn hình đăng nhập/khởi tạo nếu không có omnibox.

Trước native Enter kiểm lại process Chrome/session/class, foreground, focus đúng omnibox, giá trị URL và Ctrl/Alt/Shift/Win đều được thả. Nếu không đúng thì không gửi Enter. Giới hạn ba lần điều hướng cho một cửa sổ, có khoảng chờ tải trang; recovery cửa sổ và deadline chung vẫn có giới hạn. Chỉ trạng thái có cả địa chỉ đúng VÀ tài liệu Extensions đã tải mới cho qua DeveloperMode/Load; việc vừa nhập text vào omnibox chưa được coi là Ready.

Đã chạy Windows PowerShell 5.1:

- Test-SfitIntegration.ps1: **58 checks passed**. Compile chính driver C# cùng adapter kiểm thử không có UI; chạy chính navigation controller production với tình huống New Tab, nhập URL/Enter đúng thứ tự, URL text chưa tải document không thành Ready, target không phải Chrome, không lấy được foreground/focus, focus bị mất khi nhập, phím bổ trợ đang giữ và ô từ chối text đều không phát Enter. Kiểm layout INPUT Win32 đúng 40 byte trên x64. Các kiểm bridge/updater và nhận diện cũ vẫn đạt.
- Test-LabLogic.ps1: **101 assertions passed**.
- Test-ChromeProfiles.ps1: **49 checks passed**; logic sao lưu/policy/restore không thay đổi.

Các kiểm điều hướng dùng fake native boundary, không gửi phím vào desktop hoặc chạy code UI trên Chrome thật của máy phát triển. Chưa xác nhận toàn bộ UIA/SendInput/Chrome 156 trên VM; cần chạy lại bản 2.2.1 ở VM đang lỗi và kiểm install.log phải có NavigationRequested -> xác nhận tài liệu Extensions -> Load/Folder/Verify -> Passed mà không mở trang quản lý bằng tay. Bản này tiếp tục có bước chuẩn bị một profile từ 2.2.0; lần đầu dùng trên máy đang ở 2.1.2 sẽ sao lưu/chuyển dữ liệu Chrome cũ trước khi tạo profile SchoolLab.

## Đơn giản hóa cài Chrome — bản 2.3.0 / 29/10/2026

Người dùng đổi yêu cầu: không cần backup/restore hay chặn tạo profile; máy thực hành cho phép xóa dữ liệu Chrome cũ. Chỉ cần một profile dùng sau cài và tự mở trang quản lý để Load unpacked. Module profile được thay bằng luồng reset schema 2; đã bỏ Restore-ChromeProfiles.ps1/cmd, PrepareSingleChromeProfile/BackupRoot và mọi thao tác đặt policy hạn chế mới.

Ảnh máy ảo xác nhận driver đi tới trang Extensions/Developer mode/Load unpacked nhưng Chrome báo “Extension installation is blocked by policy”. Đã đối chiếu source Chromium hiện tại: UnpackedInstaller::IsLoadingUnpackedAllowed kiểm mặc định blocklist trước khi đọc thư mục; allowlist riêng ID không cứu được default block cho unpacked. Vì thế policy `ExtensionSettings.*.installation_mode=blocked` do SchoolLab 2.2 thêm là sai với cơ chế đang dùng. Không áp dụng lại policy này.

2.3 tự đọc journal policy cũ của SchoolLab và hoàn tác đúng phần đã thay đổi. Với ExtensionSettings, hoàn tác theo từng field dựa trên Original/Applied, giữ các field/ID khác và thay đổi mới của quản trị viên. Không xóa cả nhánh policy, không yêu cầu restore thủ công. Có kiểm tra policy cấm từ nguồn khác trước khi xóa dữ liệu Chrome.

Reset chỉ nhắm vào đường dẫn tuyệt đối LOCALAPPDATA\Google\Chrome\User Data của tài khoản đang dùng. Trước recursive delete kiểm các đường dẫn gốc và duyệt cây từng cấp, không theo reparse point; nếu có link thì dừng trước khi xóa. Không tạo backup. Tạo Default/SchoolLab, dữ liệu chọn last_used/last_active_profiles, cache chỉ Default và First Run sentinel. Rerun giữ profile khi chỉ có Default; nếu xuất hiện profile/cache khác thì reset lại. ResetPending cho phép tiếp tục một lần xóa bị ngắt. Các shortcut Chrome chuẩn được đưa về Default, shortcut ứng dụng khác và custom user-data-dir giữ nguyên; tạo SchoolLab Chrome trên Desktop. Không có tác vụ dọn ngầm lúc khởi động hay chặn người dùng tạo thêm profile.

Đã chạy Windows PowerShell 5.1:

- Test-ChromeProfiles.ps1: **55 checks passed** với dữ liệu giả trong workspace và HKCU test key riêng. Bao gồm thực sự xóa profile/dữ liệu/cache cũ, giữ tệp ngoài Chrome, tạo một profile, chạy lại không reset thừa, dọn profile mới/metadata profile tùy ý, tiếp tục reset bị ngắt, chuyển journal cũ, từ chối đường dẫn không hợp lệ và junction mà không xóa dữ liệu ngoài. Kiểm file .lnk thật trong desktop giả: sửa profile flag các dạng quote, giữ shortcut khác/custom data và idempotence. Migration thử đúng sáu policy từ 2.2, giữ ngoại lệ/thay đổi mới của quản trị viên, không gỡ policy cấm không thuộc SchoolLab, chẩn đoán Developer mode/UserDataDir bị quản lý.
- Test-SfitIntegration.ps1: **58 checks passed**; điều hướng omnibox và native bridge giữ nguyên bản đã kiểm.
- Test-LabLogic.ps1: **100 assertions passed** ở lần chạy cuối sau bổ sung normalize shortcut, gồm parser các script mới và hồi quy logic cũ.

Không xóa profile, sửa shortcut hay đổi policy Chrome thật trên máy phát triển. Cần VM nghiệm thu gói 2.3: tự hết lỗi policy do SchoolLab cũ, tự mở đúng trang và cài SFIT, mở Chrome lại chỉ có Default/SchoolLab, lịch hoạt động đúng, chạy lại đạt. Các kết quả cũ của 2.2 về backup/khóa profile chỉ là lịch sử, không mô tả hành vi hiện tại.

Nguồn: https://chromium.googlesource.com/chromium/src/+/refs/heads/main/extensions/browser/unpacked_installer.cc (hàm IsLoadingUnpackedAllowed; source đã đọc trong phiên sửa, lưu tham chiếu ở test-results/chromium-policy-review).

## SchoolLab 2.4.0 — giữ nguyên Chrome profile (2026-10-30)

- Bỏ hoàn toàn hàm reset/xóa Chrome User Data và đổi shortcut. Không gọi cleanup dữ liệu profile từ journal 2.3.
- Đọc cửa sổ Chrome đang mở/gần nhất, tạo tab setup riêng, xác minh Profile Path tại chrome://version; nếu đóng Chrome thì khởi chạy last_used qua Explorer.
- Giữ cố định HWND; không chọn cửa sổ khác khi cài. Bỏ ghim bằng toggle Pin to toolbar trên trang detail có đúng ID, không ghi file Preferences đang chạy.
- Nạp SFIT, đợi native report mới sau thao tác Load; xác nhận SFIT detail và không ghim trong cửa sổ đó trước khi đạt. Journal schema 3 ghi profile được chọn, readiness không yêu cầu chỉ có Default.
- Đã đạt 55 kiểm tra profile/bảo toàn từng byte/migration policy giả lập và force-pin policy; 75 kiểm tra SFIT/UI boundary; 100 kiểm tra hồi quy.
- Các kiểm tra trên không mở/điều khiển Chrome thật, không sửa dữ liệu/policy Chrome thật của máy phát triển. Cần pilot UI Windows 10/11 với profile Default và Profile 1/2, extension đang ghim và lượt chạy lại.

## SchoolLab 2.5.0 — profile OLBDB và UTCOJ (2026-10-30)

- Đổi cấu hình sang https://utcoj.info/, allowlist chính xác utcoj.info, lịch 01/11/2026 13:00–17:00 +07:00.
- Giữ nguyên profile cũ; journal/marker sở hữu dành riêng cho OLBDB, seed Preferences chỉ trong thư mục mới trước khi Chrome mở; rerun không tạo trùng/reset/ghi đè Preferences.
- Chỉ dùng cửa sổ Chrome mới và xác minh đúng Profile Path của OLBDB; shortcut Desktop/OLBDB.lnk trỏ đúng thư mục và examUrl. Không ghi đè shortcut không thuộc lượt triển khai.
- Ghi SFIT sang Program Files/SchoolLab/ChromeExtension/OLBDB, không ghi đè các tệp SFIT đã cài ở đường dẫn cũ. Metadata/updater đồng bộ examUrl để shortcut theo đúng site sau khi sửa config.js.
- Bản nguồn SFIT 2.0 hiện tại đã không có màn hình nhập code. Thêm regression cho ACTIVE theo lịch không cần hành động join/code và popup/block page không có input/form nhập mã.
- Đạt 89 kiểm tra profile/migration/shortcut/khôi phục journal; 77 kiểm tra tích hợp SFIT; 19 bài kiểm tra runtime SFIT; 100 kiểm tra hồi quy.
- Chrome 156.0.8078.48 headless với user-data-dir cô lập đã xác nhận mở đúng thư mục mới, giữ tên OLBDB, đăng ký OLBDB vào info_cache và không đổi Preferences của profile cũ. Kết quả ở test-results/olbdb-engine-ab06f0f12e8344d18a4678a1f0799f86/result.json, không đóng gói.
- Không cài/gỡ extension hay tạo profile trên tài khoản Chrome thật của máy phát triển. Chưa chạy installer UI Load unpacked thực tế trên Windows 10/11; vẫn cần pilot trước khi nhân rộng.

## SchoolLab 2.5.1 — tên profile tiếng Việt (2026-10-31)

- Tên hiển thị và shortcut: Olympic Đặc Biệt 2026. Giữ mã nội bộ OLBDB và journal cũ để chuyển tên từ 2.5.0 mà không tạo profile mới/reset.
- Cho phép tên có dấu/khoảng trắng; UTF-8 BOM cho LabConfig.psd1 bảo đảm Windows PowerShell 5.1 đọc đúng. Seed profile mới với tên tiếng Việt; profile cũ đổi qua chrome://settings/manageProfile, blur và kiểm tra lại sau vòng điều hướng trước khi ghi nhận.
- Thêm IShellLinkW/IPersistFile cho shortcut Unicode: WScript.Shell không đọc được một số tên tiếng Việt trên máy dùng code page ANSI. Chỉ chuyển tên shortcut cũ khi target/profile đã được xác minh, không sửa shortcut không thuộc bộ cài.
- Đạt 98 kiểm tra profile/shortcut/migration, 81 kiểm tra SFIT/boundary UI và 100 kiểm tra hồi quy. Chrome 156 headless trong user-data-dir cô lập đã lưu tên Olympic Đặc Biệt 2026 đúng vào Preferences/Local State và giữ nguyên profile cũ (test-results/profile-name-engine-cfb5911801394404b72efc76d0a3db17).
- Giữ https://utcoj.info/ và lịch 01/11/2026 13:00–17:00 +07:00, không cần nhập code. Chưa chạy luồng UI rename/load unpacked trên VM thật; cần pilot trước khi triển khai rộng.

## SchoolLab 2.6.0 — chỉ tự restart ở cuối (2026-10-31)

- Pending reboot đầu vào được ghi nhận/cảnh báo, không chặn mặc định và không restart giữa chừng. Mã 3010 của installer được giữ lại; launcher tiếp tục cấu hình tài khoản VS Code và Chrome/SFIT. Lỗi thật vẫn dừng và lưu đúng mã.
- Chỉ khi các bước phần mềm, smoke test, tài khoản và SFIT đã đạt mới đếm ngược 60 giây, yêu cầu một lần restart cuối. Không cần restart thì kết thúc bình thường. Ctrl+C hủy đếm ngược; shutdown dùng /t 0, không /f nên ứng dụng chưa lưu có thể chặn restart.
- Tác vụ đăng nhập gắn đúng SID, Interactive/Highest, không lưu mật khẩu. Chỉ dùng bộ cài đã chép vào Program Files/Staging và đã kiểm hash, không phụ thuộc USB/LAN. Sau reboot thực và đăng nhập lại đúng tài khoản, chỉ kiểm tra readiness, không chạy lại installer/Chrome UI và không tự restart thêm. Tác vụ được gỡ sau kiểm tra, giữ journal và log; không sửa tác vụ không khớp sở hữu.
- Check-LabReady kiểm tra Windows còn báo pending reboot sau lần boot hay không; còn yêu cầu thì báo chưa sẵn sàng và không tạo vòng lặp restart.
- Windows PowerShell 5.1: **97 kiểm tra restart** (quyết định cuối, lỗi từng thành phần, journal, SID/path/task identity, countdown, giới hạn một lần, lỗi đăng ký/OS và handler installer thật với kết quả PSADT giả lập). Đã tạo các đối tượng CIM ScheduledTasks thật trong bộ nhớ để kiểm tra tham số/enum, **không đăng ký tác vụ hoặc restart máy phát triển**.
- Hồi quy: **102** kiểm tra logic/parse, **98** kiểm tra bảo toàn Chrome profile, **81** kiểm tra SFIT integration và **19** bài runtime SFIT đều đạt. Giữ profile Olympic Đặc Biệt 2026, UTCOJ và lịch 01/11/2026 13:00–17:00 +07:00.
- Chưa kiểm thử chuỗi cài đặt + restart + tác vụ đăng nhập thật trên Windows 10/11. Pilot cần xác nhận máy đang pending reboot vẫn đi hết bước [5/5], restart ở cuối, đăng nhập đúng tài khoản tự kiểm tra và không lặp restart; trường hợp lỗi cài đặt không được tự restart.
- Đã build `dist/SchoolLab-2.6.0-20261031`, PackageId `20261031-0c4c2183`, 262 file có hash, khoảng 766 MiB. `Install-ChromeExtension.ps1 -ValidateOnly` đạt, lock không thay đổi; toàn bộ script trong gói khớp hash với nguồn. Không chạy installer hoặc restart thật trên máy phát triển.

## SchoolLab 2.6.1 — luôn tạo profile thi mới (2026-10-31)

- Theo yêu cầu mới, mỗi lượt cài SFIT tạo một thư mục profile và token mới. Không dùng lại/adopt profile đã có; journal Prepared/Creating cũ, marker thiếu/sai, profile đã xóa tay hoặc journal JSON hỏng không ngăn tạo profile mới. Giữ nguyên dữ liệu các profile cũ để quản trị viên tự xóa.
- Shortcut Olympic Đặc Biệt 2026 của SchoolLab được cập nhật sang profile mới, kể cả khi thư mục profile cũ không còn. Chỉ nhận dạng shortcut đúng Chrome và đúng mẫu launcher SchoolLab; shortcut khác được giữ nguyên.
- Bước xác nhận tên sau khi Chrome mở chỉ xác minh journal/marker/directory/token của đúng lượt cài hiện tại, không gọi hàm tạo profile lần nữa. Vẫn kiểm tra đúng Profile Path, Load unpacked, SFIT không ghim và native report mới trước khi đạt.
- Windows PowerShell 5.1 đạt **116** kiểm tra profile/shortcut/bảo toàn dữ liệu, gồm hồi quy Prepared + thiếu marker như lỗi VM đã báo, journal cũ hỏng, profile cũ đã xóa, đổi shortcut sang profile mới, sai token hiện tại và không tạo profile thừa lúc xác nhận tên. Hồi quy **102** logic/parse, **81** SFIT integration, **97** restart và **19** runtime SFIT đều đạt.
- Không sửa dữ liệu Chrome, cài phần mềm hoặc restart máy phát triển. Luồng UI thật trên Windows 10/11 vẫn cần pilot. Giữ UTCOJ, lịch 01/11/2026 13:00–17:00 +07:00 và chỉ tự restart ở cuối nếu cần.
- Đã build `dist/SchoolLab-2.6.1-20261031`, PackageId `20261031-2874241d`, 262 file có hash, khoảng 766 MiB. ValidateOnly đạt, package-lock không đổi; script và README trong gói khớp hash với nguồn.

## SchoolLab 2.6.2 — sửa xác minh bỏ ghim SFIT (2026-10-31)

- Lỗi trong ảnh VM: sau native handshake, code bỏ qua document chi tiết vì chỉ nhận đúng tên Extensions/Tiện ích, trong khi Chrome hiển thị Extensions - SFIT Tracker. Thêm nhận diện tiêu đề chi tiết riêng, giữ selector trang danh sách riêng và vẫn đối chiếu URL chrome://extensions/?id= với ID trong nội dung đã tải.
- Nhận switch nằm bên trong hàng pin-to-toolbar; đọc trạng thái Off/On bằng TogglePattern. Có cuộn tới control hoặc cuộn trang theo ScrollPattern, giới hạn 8 bước. Không click tọa độ hoặc ghi Preferences đang chạy. Không suy ra đã bỏ ghim chỉ vì không tìm thấy control.
- Bộ điều khiển quyết định dùng chung cho production và fake boundary: chỉ Off mới đạt; On phải được thao tác và đọc lại, sai trang/khóa policy/ngoài màn hình/thiếu control/provider chưa hỗ trợ/indeterminate không được báo thành công.
- Bước SFIT chờ tối đa 45 giây để xác minh bỏ ghim, ghi từng thay đổi trạng thái vào install.log; diagnostic có title document, address, AutomationId, offscreen và toggle. Lỗi mới phân biệt SFIT đã nạp/có native report với lỗi xác minh toolbar.
- Windows PowerShell 5.1 đạt **122** kiểm tra SFIT integration; **102** logic/parse, **116** profile/shortcut và **97** restart đều đạt. Các boundary test không thao tác Chrome thật. Giữ profile mới mỗi lượt cài, tên Olympic Đặc Biệt 2026, UTCOJ, lịch 01/11/2026 13:00–17:00 +07:00 và restart chỉ ở cuối.
- Đã đối chiếu cấu trúc pin-to-toolbar và switch lồng trong mã nguồn Chromium: https://github.com/chromium/chromium/blob/main/chrome/browser/resources/extensions/detail_view.html.ts và https://github.com/chromium/chromium/blob/main/chrome/browser/resources/extensions/toggle_row.html.ts . Chỉ quan sát máy ảo bằng computer-use; chưa chạy installer/UI bỏ ghim thật trong lượt này vì máy ảo đang có thao tác gỡ phần mềm. Cần pilot lại Install-ChromeExtension.cmd trên Windows 10/11 trước khi triển khai rộng.
- Đã build `dist/SchoolLab-2.6.2-20261031`, PackageId `20261031-aace1434`, 262 file có hash, khoảng 766 MiB. ValidateOnly đạt, lock không thay đổi; script/README trong gói khớp hash với nguồn. 19 bài runtime SFIT cũng đạt; không đổi mã runtime hoặc lịch thi.
