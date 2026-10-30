# Chrome/SFIT trong SchoolLab 2.4.0

- Giữ nguyên toàn bộ profile, dữ liệu và shortcut Chrome. Không xóa, reset hay đổi tên profile.
- Mở sẵn đúng profile cần cài, nên chỉ để một cửa sổ Chrome; script dùng cửa sổ Chrome trước/gần nhất. Nếu Chrome đang đóng, mở profile dùng gần nhất.
- Tạo tab cài đặt riêng, đọc Profile Path trên chrome://version để kiểm tra đúng profile; giữ cố định cửa sổ trong cả lượt cài.
- Đến chrome://extensions/, bật Developer mode, bỏ ghim extension đang ghim trong profile đó và Load unpacked SFIT.
- Chỉ đạt khi nhận báo cáo native mới và xác nhận đúng SFIT trong trang chi tiết của profile đã chọn, với trạng thái không ghim.
- Không sửa Preferences/Local State trực tiếp khi Chrome đang chạy; việc bỏ ghim dùng toggle Pin to toolbar của Chrome. Không gỡ hoặc vô hiệu hóa extension khác.
- Không chặn tạo profile, không thêm policy khóa. Giữ bước dọn policy do SchoolLab 2.2 tạo nếu có journal; không thay policy bên ngoài.

Chạy Install-ChromeExtension.cmd bằng Administrator nếu chỉ cần cập nhật SFIT, hoặc Install-Lab.cmd để cài toàn bộ. Để máy yên khi Chrome tự thao tác. Các profile khác không được cài SFIT/bỏ ghim tự động trong lượt này.

Lịch: sửa Files/ChromeExtension/config.js trong bộ cài, giữ múi giờ +07:00 rồi chạy lại. Sửa mã nguồn trong 1-sfit-tracker cần build mới.

Log: %LOCALAPPDATA%/SchoolLab/Chrome. Chỉ đạt khi hiện SFIT DA XAC NHAN và mã 0. Nếu có policy ép ghim, trang chào mừng/đăng nhập hoặc không đọc được Profile Path, script báo lỗi để kiểm tra. Không yêu cầu xóa/restore profile.

Bản 2.4.0 đã có kiểm tra profile giả lập giữ nguyên từng byte, điều hướng UI qua boundary giả lập và biên dịch driver. Vẫn cần kiểm thử giao diện thật trên máy ảo Windows 10/11 trước khi nhân rộng.
