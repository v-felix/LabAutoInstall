# SFIT Tracker 2.0

Tự hoạt động theo lịch trong [config.js](config.js), **không nhập mã vào thi**.

- Trang thi: **https://utcoj.info/**.
- Lịch hiện tại: **01/11/2026, 13:00–17:00 giờ Việt Nam**.
- SchoolLab 2.5 tạo profile **Olympic Đặc Biệt 2026** và shortcut Desktop để mở đúng profile; giữ nguyên mọi profile cũ.

Sửa startAt/endAt với múi giờ +07:00; giờ kết thúc phải sau bắt đầu. Sửa nguồn trong repo cần build gói mới. Nếu sửa Files/ChromeExtension/config.js trên USB đã build, lưu rồi chạy lại Install-ChromeExtension.cmd trên máy cần cập nhật, không cần build lại.

Trước giờ WAITING, trong giờ ACTIVE, hết giờ ENDED và tự ngừng giới hạn. Đồng hồ máy phải đúng. Khi Load unpacked thủ công, sửa file trong thư mục đã nạp rồi Reload tại chrome://extensions/.

Mô tả: [SFIT-2.0.vi.md](../school-lab/SFIT-2.0.vi.md). Chỉ kiểm soát profile đã nạp; không khóa profile/trình duyệt khác hoặc chống quyền admin.
