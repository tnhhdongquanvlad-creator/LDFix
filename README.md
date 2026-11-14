# LDFix — Gỡ lỗi tab LDPlayer 4

Công cụ cứu dữ liệu khi một tab (instance) LDPlayer 4 bị lỗi, không mở được.

## Cách dùng

1. Tải **[LDFix.zip](https://github.com/tnhhdongquanvlad-creator/LDFix/releases/latest/download/LDFix.zip)**, giải nén ra 1 thư mục (giữ `LDFix.exe`, `7z.exe`, `7z.dll` cùng chỗ).
2. Mở LDFix.exe (Windows hỏi quyền Admin → **Yes**).
3. Chọn tab bị lỗi → bấm **CỨU GAME TỪ TAB LỖI** → tick game cần cứu.
4. Tool tạo tab sạch `Game_tab<số>`, tự bật Root, cài game và chép dữ liệu game vào, rồi mở game.

## Cứu game làm gì (v2)

Tab đứng ở 94% = phần hệ thống Android trong `data.vmdk` bị hỏng. v2 không chép nguyên ổ đĩa nữa mà:
1. Đọc **bên trong** `data.vmdk` của tab lỗi bằng 7-Zip (chỉ đọc).
2. Lấy riêng file cài game (`/data/app/<game>`) và dữ liệu game (`/data/data/<game>`), cùng `Android/data`, `Android/obb` trên sdcard.
3. Tạo tab sạch, bật Root, cài game, chép dữ liệu, chỉnh lại quyền sở hữu file.

Cần trống ổ đĩa đủ để bóc ảnh đĩa (thường vài GB). Thư mục tạm `LDFix_Work` được xoá sau khi xong.

## Chép nguyên tab (cách cũ)

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
Mỗi bản build được đăng ở mục **Releases**.
