# LDFix — Gỡ lỗi tab LDPlayer 4

Công cụ cứu dữ liệu khi một tab (instance) LDPlayer 4 bị lỗi, không mở được.

## Cách dùng

1. Tải **LDFix.exe** ở mục **Releases** (hoặc tab **Actions** → bản build mới nhất → Artifacts).
2. Mở LDFix.exe (Windows sẽ hỏi quyền Admin → chọn **Yes**).
3. Chọn tab bị lỗi trong danh sách → bấm **GỠ LỖI TAB ĐÃ CHỌN**.
4. Đợi tool chạy xong → mở tab mới tên `Fix_tab<số>`, dữ liệu cũ đã nằm trong đó.

> Không có exe? Tải cả thư mục về, nhấp đúp **LDFix.bat**.

## Tool làm gì

1. Tắt toàn bộ LDPlayer.
2. Sao lưu tab lỗi vào `<thư mục LDPlayer>\LDFix_Backup\`.
3. Tạo tab mới bằng `ldconsole.exe`, bật lên 1 lần để khởi tạo.
4. Chép `data.vmdk` (app, tài khoản) và `sdcard.vmdk` (ảnh, file) từ tab lỗi sang tab mới.

Tab cũ **không bị xoá**.

## Lưu ý

- Nếu tab mới vẫn lỗi, nghĩa là bản thân `data.vmdk` của tab cũ đã hỏng — cách này không cứu được.
- Một số game/app có thể bắt đăng nhập lại vì thông tin thiết bị thay đổi.
- Nút **Chép sang tab có sẵn...** dùng khi muốn tự tạo tab mới bằng tay rồi chép dữ liệu vào.
- Cần còn trống ổ đĩa khoảng **2 lần** dung lượng tab lỗi.

## Build exe

Mỗi lần push lên `main`, GitHub Actions tự build `LDFix.exe` bằng [ps2exe](https://github.com/MScholtes/PS2EXE).
Push tag `v1.0.0` để tạo bản Release có file exe đính kèm.
