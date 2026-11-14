# LDFix — Gỡ lỗi tab LDPlayer 4

Công cụ cứu dữ liệu khi một tab (instance) LDPlayer 4 bị lỗi, không mở được.

## Cách dùng

1. Tải **[LDFix.zip](https://github.com/tnhhdongquanvlad-creator/LDFix/releases/latest/download/LDFix.zip)**, giải nén ra 1 thư mục (giữ `LDFix.exe`, `7z.exe`, `7z.dll` cùng chỗ).
2. Mở LDFix.exe (Windows hỏi quyền Admin → **Yes**).
3. Chọn tab bị lỗi → bấm **CỨU GAME TỪ TAB LỖI** → tick game cần cứu.
4. Tool tạo tab sạch `Game_tab<số>`, tự bật Root, cài game và chép dữ liệu game vào, rồi mở game.

## Cứu game làm gì (v3)

Tab đứng ở 94% = Android vẫn chạy nhưng không khởi động xong vì phần hệ thống trong `data.vmdk` bị hỏng.

**Cách 1 (ưu tiên, không cần ổ trống lớn):** tool tự bật Root cho tab lỗi, mở nó lên, lấy file cài game (`/data/app/<game>`) và dữ liệu game (`/data/data/<game>`, `Android/data`, `Android/obb`) qua ADB.

**Cách 2 (dự phòng):** nếu ADB không vào được, đọc bên trong `data.vmdk` bằng 7-Zip. Cách này phải bung cả ổ ảo (có thể tới ~64 GB), tool tự dùng ổ còn trống nhiều nhất (C:, D:, ...).

Sau đó tool tạo tab sạch `Game_tab<số>`, bật Root, cài game, chép dữ liệu game vào, chỉnh quyền file và mở game.
Thư mục tạm `LDFix_Work` được xoá khi xong.

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
