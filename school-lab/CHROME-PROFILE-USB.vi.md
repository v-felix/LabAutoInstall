# Chrome/SFIT — SchoolLab 2.6.3

- Giữ nguyên toàn bộ profile và dữ liệu đang có, không reset/xóa hoặc chiếm một profile cũ có tên Olympic Đặc Biệt 2026.
- Mỗi lần chạy cài SFIT tạo profile mới tên Olympic Đặc Biệt 2026, thư mục duy nhất dưới Chrome User Data. Ghi journal/marker mới; không đọc lại journal cũ để dùng lại profile, không sửa Preferences của profile đã tồn tại.
- Chỉ khởi tạo Preferences trong thư mục mới trước khi Chrome mở. Chrome tự đăng ký profile vào Local State; script không ghi đè Local State đang chạy.
- Mở cửa sổ mới bằng `--profile-directory`, chỉ xét cửa sổ mới và kiểm tra Profile Path phải trùng chính xác thư mục Olympic Đặc Biệt 2026. Không chọn/nạp SFIT vào cửa sổ profile cũ.
- Tạo/cập nhật Desktop/Olympic Đặc Biệt 2026.lnk trỏ đúng Chrome, profile mới nhất và https://utcoj.info/, kể cả khi profile cũ đã bị xóa. Không sửa shortcut Chrome khác.
- Tự mở chrome://extensions, bật Developer mode, bỏ ghim extension trong Olympic Đặc Biệt 2026 và Load unpacked SFIT. Cần native report mới và xác nhận SFIT không ghim trong cửa sổ đó mới đạt.
- Bản 2.6.3 nhận diện cả tiêu đề trang chi tiết `Extensions - SFIT Tracker`, tìm switch trong hàng Pin to toolbar và tự cuộn có giới hạn. Chỉ trạng thái Off thực tế mới đạt; thiếu nút hoặc chưa đọc được trạng thái vẫn báo lỗi cụ thể trong install.log/uia-diagnostic.txt.
- Site: https://utcoj.info/. Lịch: 01/11/2026, 13:00–17:00 (+07:00). Không code vào thi, không phiên; hết giờ tự gỡ giới hạn.

Chạy Install-ChromeExtension.cmd bằng Administrator nếu chỉ cập nhật Olympic Đặc Biệt 2026/SFIT, hoặc Install-Lab.cmd để cài toàn bộ. Sau cài mở shortcut Olympic Đặc Biệt 2026 trên Desktop; không cần cắm USB.

Log: %LOCALAPPDATA%/SchoolLab/Chrome. olbdb-profile.json ghi profile do SchoolLab sở hữu; profile-state.json schema 4 ghi kết quả cài/shortcut. Không cần xóa/restore dữ liệu cũ.

Đã có kiểm tra fixture bảo toàn từng byte, chạy lại, shortcut, lịch không cần code và Chrome thật headless trong user-data-dir cô lập. Luồng UI Load unpacked vẫn cần thử trên máy ảo Windows 10/11 trước khi triển khai rộng.

Mỗi lần chạy cài SFIT sẽ tạo một profile mới; profile cũ được giữ nguyên để quản trị viên tự xóa khi cần. Shortcut thi do SchoolLab tạo được cập nhật sang profile mới, kể cả khi profile cũ đã bị xóa tay.
