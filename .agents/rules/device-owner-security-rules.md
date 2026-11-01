# 🛡️ Quy Tắc Kỹ Thuật Device Owner & Chống Phá Hoại (Device Owner & Anti-Tampering Rules)

Tài liệu này là quy tắc kỹ thuật cốt lõi bắt buộc áp dụng khi triển khai mã nguồn trên **Target Agent (Child App)** của dự án **MDM Parental Control**.
Mục tiêu tối thượng: **Bất khả xâm phạm (Zero-Bypass), chống gỡ cài đặt, chống tắt quyền và kiểm soát cấp hệ điều hành Android**.

---

## 🔒 1. Nguyên Tắc Thiết Kế Cốt Lõi (Core Principles)

1. **Khóa Cấp Hệ Điều Hành (Native OS-Level Enforcement)**:
   - Nghiêm cấm dùng cơ chế vẽ đè (Overlay Window / `SYSTEM_ALERT_WINDOW`) để che màn hình khi ứng dụng bị khóa. Trẻ có thể bấm phím Recent Apps, chia đôi màn hình hoặc tắt quyền vẽ đè trong Settings để vượt rào.
   - Bắt buộc dùng `DevicePolicyManager.setPackagesSuspended(admin, packageNames, true)` để hệ thống Android tự động vô hiệu hóa gói ứng dụng, đổi màu icon thành xám và ngăn chặn Activity khởi chạy ngay từ tầng `ActivityTaskManager`.
   - Đối với các ứng dụng bị cấm vĩnh viễn (Blacklist), áp dụng `DevicePolicyManager.setApplicationHidden(admin, packageName, true)` để ẩn hoàn toàn khỏi App Drawer.

2. **Chống Gỡ Cài Đặt & Vô Hiệu Hóa (Anti-Tampering)**:
   - Agent phải được thiết lập cờ `setUninstallBlocked(admin, packageName, true)` ngay khi kích hoạt Device Owner.
   - Vô hiệu hóa nút "Force Stop" và menu "Clear Data" của Agent thông qua quyền hạn Device Owner.

3. **Bịt Kín Toàn Bộ Lỗ Hổng Bypass Hệ Thống (Zero-Bypass Policy)**:
   Khi Device Owner được cấp, Agent phải lập tức kích hoạt chuỗi ràng buộc người dùng (`UserManager` restrictions):
   - `DISALLOW_SAFE_BOOT` hoặc `setSafeModeDisabled(admin, true)`: Ngăn reboot vào Safe Mode để bypass background service.
   - `DISALLOW_FACTORY_RESET` hoặc `setFactoryResetDisabled(admin, true)`: Ngăn trẻ khôi phục cài đặt gốc để xóa bỏ Device Owner.
   - `DISALLOW_CONFIG_DATE_TIME` & `setAutoTimeRequired(admin, true)`: Ngăn trẻ chỉnh lùi ngày/giờ máy để tiếp tục dùng app quá hạn.
   - `DISALLOW_ADD_USER`: Ngăn trẻ tạo tài khoản Guest hoặc người dùng phụ để dùng app tự do.
   - `DISALLOW_DEBUGGING_FEATURES`: Vô hiệu hóa USB Debugging và ADB Developer Options sau khi kích hoạt DO để ngăn can thiệp dòng lệnh.
   - `DISALLOW_MODIFY_ACCOUNTS`: Khóa khả năng gỡ bỏ tài khoản giám sát.
   - `DISALLOW_APPS_CONTROL`: Ngăn trẻ truy cập vào App Info trong Settings để can thiệp quyền.

---

## ⚡ 2. Cấp Quyền Tự Động & Chạy Ngầm (Silent Auto-Granting)

Device Owner có toàn quyền cấp phép mà không cần người dùng xác nhận trên màn hình:
1. **Usage Stats Permission**:
   - Tự động gọi `setPermissionGrantState(admin, packageName, Manifest.permission.PACKAGE_USAGE_STATS, PERMISSION_GRANT_STATE_GRANTED)`.
2. **Notification Listener Service**:
   - Tự động ghi vào Secure Settings: `dpm.setSecureSetting(admin, Settings.Secure.ENABLED_NOTIFICATION_LISTENERS, ...)` (nếu cần giám sát thông báo nhạy cảm).
3. **Bỏ Qua Tối Ưu Hóa Pin (Battery Optimization Exemption)**:
   - Đưa Agent vào danh sách `POWER_WHITELIST` của hệ thống để không bị Doze Mode đóng băng tiến trình giám sát.

---

## 🚨 3. Danh Sách Trắng Khẩn Cấp (Emergency Whitelist)

> [!CAUTION]
> Dù thiết bị đang ở trạng thái Khóa Khẩn Cấp (Lockdown) hay Giờ Đi Ngủ (Bedtime Mode), **tuyệt đối không bao giờ được suspend hoặc ẩn** các ứng dụng/thành phần sau:
> - Trình gọi điện thoại khẩn cấp (`Intent.ACTION_DIAL`, `ACTION_CALL_PRIVILEGED`, 112/113/114/115/911).
> - Ứng dụng SMS mặc định (để phụ huynh gửi tin nhắn khẩn).
> - Ứng dụng Bản đồ định vị khẩn cấp.
> - Chính bản thân Target Agent (`context.packageName`).
> - Launcher hệ thống hoặc System UI (`com.android.systemui`).

---

## 🛡️ 4. Quy Chuẩn Kích Hoạt Device Owner (Provisioning)

1. **Phương pháp 1: ADB Provisioning (Dành cho máy đang dùng không wipe data)**:
   - Lệnh kích hoạt:
     ```bash
     adb shell dpm set-device-owner com.mdm.parentalcontrol.child/.receiver.MdmDeviceAdminReceiver
     ```
   - Điều kiện tiên quyết: Máy chưa khai báo tài khoản Google (hoặc tạm thời remove Google account trước khi chạy lệnh ADB).
2. **Phương pháp 2: QR Code Setup (Dành cho máy mới bóc hộp hoặc sau Factory Reset)**:
   - Gõ 6 lần vào màn hình Welcome (Setup Wizard) để kích hoạt camera quét QR.
   - Payload JSON bao gồm: Download URL của APK, SHA-256 Checksum, Admin Component Name, Wi-Fi credentials và Extra parameters.

---

## 📋 5. Tiêu Chuẩn Kiểm Thử Chống Phá Hoại (Anti-Tampering Checklist)

Mọi bản build trước khi nghiệm thu phải vượt qua 7 bài test:
- [ ] Test 1: Vào Settings -> Apps -> MdmChildAgent -> Nút "Uninstall" và "Force Stop" bị mờ (disabled).
- [ ] Test 2: Giữ nút nguồn chọn Reboot to Safe Mode -> Máy từ chối hoặc boot thẳng vào Normal Mode.
- [ ] Test 3: Vào Settings -> System -> Date & Time -> Khóa đổi múi giờ và thời gian thủ công.
- [ ] Test 4: Vào Settings -> System -> Reset Options -> Nút "Erase all data (factory reset)" bị khóa.
- [ ] Test 5: Vuốt thanh trạng thái chuyển sang Guest User -> Bị ẩn hoặc báo tính năng bị cấm bởi quản trị viên.
- [ ] Test 6: Cắm cáp máy tính gõ `adb devices` -> Báo unauthorized hoặc tính năng USB Debugging bị tắt.
- [ ] Test 7: Thử dùng launcher khác khởi chạy app bị suspend -> Hệ thống Android hiện popup "Ứng dụng này đã bị quản trị viên tạm dừng".
