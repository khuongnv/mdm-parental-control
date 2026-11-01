# EPIC 01: Core Target Agent & Thiết lập quyền Device Owner (DO)

## 1. Mục tiêu
Xây dựng ứng dụng con (Agent) cài đặt trên máy mục tiêu với đầy đủ quyền Device Owner, kích hoạt các cơ chế chống phá hoại, chống bypass và tự động cấp quyền hệ thống.

## 2. Danh sách User Stories / Tasks chi tiết
- **US1.1: Cấu hình DeviceAdminReceiver & Manifest:**
  - Khai báo `DeviceAdminReceiver` với file policy `device_admin_receiver.xml`.
  - Cấu hình các intent-filter và quyền hạn MDM cần thiết.
- **US1.2: Hỗ trợ kịch bản kích hoạt Device Owner:**
  - Kịch bản 1: Kích hoạt qua ADB shell (`dpm set-device-owner ...`) không cần wipe data.
  - Kịch bản 2: Kích hoạt qua QR Code Provisioning khi máy mới Setup / sau Factory Reset.
- **US1.3: Kích hoạt các chính sách chống phá hoại (Anti-Tampering):**
  - Khóa khởi động Chế độ an toàn: `setSafeModeDisabled(admin, true)`.
  - Chặn khôi phục cài đặt gốc: `setFactoryResetDisabled(admin, true)`.
  - Vô hiệu hóa gỡ cài đặt cho Agent: `setUninstallBlocked(admin, packageName, true)`.
  - Tắt gỡ lỗi ADB sau kích hoạt: `addUserRestriction(UserManager.DISALLOW_DEBUGGING_FEATURES)`.
  - Chặn thay đổi ngày giờ hệ thống: `addUserRestriction(UserManager.DISALLOW_CONFIG_DATE_TIME)` và ép `setAutoTimeRequired(true)`.
  - Chặn thêm tài khoản/Guest User: `addUserRestriction(UserManager.DISALLOW_ADD_USER)`.
- **US1.4: Tự động cấp quyền hệ thống (Silent Auto-Granting):**
  - Tự động cấp quyền `PACKAGE_USAGE_STATS` qua `setPermissionGrantState`.
  - Tự cấp quyền Notification Listener và Battery Optimization Exemption.

## 3. Tiêu chí chấp nhận (Acceptance Criteria)
- Ứng dụng không thể bị xóa thủ công trong Settings.
- Nút "Force Stop" và menu quản lý quyền của app trong Settings bị vô hiệu hóa hoặc ẩn.
- Máy không thể vào Safe Mode để gỡ app.
