# Chrome/SFIT — SchoolLab 2.5.0

- Giữ nguyên toàn bộ profile và dữ liệu đang có, không reset/xóa hoặc chiếm một profile cũ có tên OLBDB.
- Tạo profile riêng tên OLBDB với thư mục duy nhất dưới Chrome User Data. Ghi journal/marker sở hữu; chạy lại dùng cùng thư mục, không sửa Preferences của profile đã tồn tại.
- Chỉ khởi tạo Preferences trong thư mục mới trước khi Chrome mở. Chrome tự đăng ký profile vào Local State; script không ghi đè Local State đang chạy.
- Mở cửa sổ mới bằng `--profile-directory`, chỉ xét cửa sổ mới và kiểm tra Profile Path phải trùng chính xác thư mục OLBDB. Không chọn/nạp SFIT vào cửa sổ profile cũ.
- Tạo Desktop/OLBDB.lnk trỏ đúng Chrome, đúng thư mục profile và https://utcoj.info/. Không sửa shortcut Chrome khác.
- Tự mở chrome://extensions, bật Developer mode, bỏ ghim extension trong OLBDB và Load unpacked SFIT. Cần native report mới và xác nhận SFIT không ghim trong cửa sổ đó mới đạt.
- Site: https://utcoj.info/. Lịch: 01/11/2026, 13:00–17:00 (+07:00). Không code vào thi, không phiên; hết giờ tự gỡ giới hạn.

Chạy Install-ChromeExtension.cmd bằng Administrator nếu chỉ cập nhật OLBDB/SFIT, hoặc Install-Lab.cmd để cài toàn bộ. Sau cài mở shortcut OLBDB trên Desktop; không cần cắm USB.

Log: %LOCALAPPDATA%/SchoolLab/Chrome. olbdb-profile.json ghi profile do SchoolLab sở hữu; profile-state.json schema 4 ghi kết quả cài/shortcut. Không cần xóa/restore dữ liệu cũ.

Đã có kiểm tra fixture bảo toàn từng byte, chạy lại, shortcut, lịch không cần code và Chrome thật headless trong user-data-dir cô lập. Luồng UI Load unpacked vẫn cần thử trên máy ảo Windows 10/11 trước khi triển khai rộng.
