# 📱 EPICS CHI TIẾT: TARGET-NODE (CHILD DEVICE OWNER AGENT)

- **Thành phần**: `target-node` (Android Native Application)
- **Đặc quyền**: **Android Device Owner (DO)** cấp độ doanh nghiệp
- **Mục tiêu**: Nắm quyền kiểm soát hệ điều hành tuyệt đối, thu thập thời lượng sử dụng chính xác mili-giây, chống phá hoại/gỡ cài đặt (Zero-Bypass) và thực thi khóa ứng dụng bằng API chuẩn của hệ thống.

---

## T-EPIC 01: Core Device Owner Setup & Chống Phá Hoại (Anti-Tampering)
*Phân rã từ: EPIC 01 toàn dự án*

### 1.1. Cấu hình DeviceAdminReceiver & Policy XML
- **Mục tiêu**: Thiết lập quyền hạn Quản trị viên thiết bị cấp cao nhất.
- **User Stories & Nhiệm vụ**:
  - Khai báo `MdmDeviceAdminReceiver : DeviceAdminReceiver` trong `AndroidManifest.xml`.
  - Cấu hình file chính sách `res/xml/device_admin_receiver.xml` hỗ trợ đầy đủ các cờ quản trị: `limit-password`, `watch-login`, `reset-password`, `force-lock`, `wipe-data`, `expire-password`, `encrypted-storage`, `disable-camera`, `disable-keyguard-features`.
  - Bắt các sự kiện `onProfileProvisioningComplete`, `onEnabled`, `onDisabled`, `onLockTaskModeEntering`.

### 1.2. Hai kịch bản kích hoạt Device Owner (Provisioning Engine)
- **Mục tiêu**: Cung cấp đường dẫn kích hoạt DO linh hoạt cho cả máy đang sử dụng lẫn máy mới xuất xưởng.
- **User Stories & Nhiệm vụ**:
  - **Kịch bản A (ADB Provisioning)**: Kích hoạt thông qua shell command mà không cần khôi phục cài đặt gốc:
    `adb shell dpm set-device-owner com.mdm.parentalcontrol.child/.receiver.MdmDeviceAdminReceiver`
  - **Kịch bản B (QR Code Provisioning)**: Tạo payload JSON cấu hình chuẩn Android Enterprise dùng khi chạm 6 lần vào màn hình Welcome của máy mới setup (chứa URL tải APK, mã băm SHA-256, Wi-Fi credentials và admin component).

### 1.3. Bộ khóa Chống Phá Hoại Bất Khả Xâm Phạm (Anti-Tampering Lockdown)
- **Mục tiêu**: Vô hiệu hóa mọi chiêu thức can thiệp, gỡ bỏ hoặc gian lận từ trẻ.
- **User Stories & Nhiệm vụ**:
  - `setUninstallBlocked(admin, packageName, true)`: Chặn gỡ cài đặt ứng dụng Agent trong Settings.
  - `setSafeModeDisabled(admin, true)`: Chặn khởi động máy vào Chế độ an toàn (Safe Mode).
  - `setFactoryResetDisabled(admin, true)`: Chặn người dùng khôi phục cài đặt gốc để xóa bỏ MDM.
  - `addUserRestriction(DISALLOW_DEBUGGING_FEATURES)`: Tắt ngay USB Debugging và Developer Options sau khi kích hoạt DO để ngăn can thiệp ADB.
  - `addUserRestriction(DISALLOW_CONFIG_DATE_TIME)` và gọi `setAutoTimeRequired(admin, true)`: Ép máy sử dụng giờ mạng viễn thông, ngăn đổi giờ máy lùi lại để gian lận quota.
  - `addUserRestriction(DISALLOW_ADD_USER)`: Ngăn tạo tài khoản phụ (Guest Mode / Second Space) để lách luật.
  - `addUserRestriction(DISALLOW_APPS_CONTROL)`: Vô hiệu hóa nút "Force Stop", "Clear Data" và menu chỉnh quyền của ứng dụng con trong Settings.

### 1.4. Tự động cấp quyền hệ thống ngầm (Silent Auto-Granting)
- **Mục tiêu**: Không để phụ huynh hay trẻ phải vào Settings cấp quyền thủ công.
- **User Stories & Nhiệm vụ**:
  - Tự cấp quyền `PACKAGE_USAGE_STATS` qua API `DevicePolicyManager.setPermissionGrantState`.
  - Tự động kích hoạt Notification Listener (nếu cần) thông qua `setSecureSetting(admin, Settings.Secure.ENABLED_NOTIFICATION_LISTENERS, ...)`.
  - Đưa Agent vào danh sách ngoại lệ tối ưu pin (`POWER_WHITELIST`) để không bị Doze Mode đóng băng.

---

## T-EPIC 02: Engine Thu Thập & Thống Kê Thời Lượng Sử Dụng Siêu Nhẹ (Usage Tracking)
*Phân rã từ: EPIC 02 toàn dự án*

### 2.1. Lắng nghe và xử lý Sự kiện Sử dụng chuẩn mili-giây
- **Mục tiêu**: Đo đạc chính xác thời gian active của ứng dụng Foreground mà không gây trễ.
- **User Stories & Nhiệm vụ**:
  - Truy vấn `UsageStatsManager.queryEvents(startTime, endTime)` lấy chính xác các mốc `UsageEvents.Event.ACTIVITY_RESUMED` và `ACTIVITY_PAUSED`.
  - Lưu vết phiên sử dụng (Session Duration) theo cặp sự kiện với sai số < 2 giây.

### 2.2. Vòng đời Polling thích ứng theo màn hình (Adaptive Screen-Aware Engine)
- **Mục tiêu**: Giảm tiêu hao pin < 3-5%/ngày, không giữ WakeLock khi màn hình tắt.
- **User Stories & Nhiệm vụ**:
  - Lắng nghe `Intent.ACTION_SCREEN_ON` và `Intent.ACTION_SCREEN_OFF`.
  - Khi màn hình BẬT: Polling mỗi 2.5 giây một lần để phát hiện tức thì khi mở app quá quota.
  - Khi màn hình TẮT: Ngắt hoàn toàn ticker, ghi nhận `ACTIVITY_PAUSED` cho app hiện tại, thả lỏng CPU cho Android đi vào Deep Sleep / Doze.

### 2.3. Dịch vụ chạy ngầm hai lớp (Two-Tier Service Architecture)
- **Mục tiêu**: Bất tử trước cơ chế Low Memory Killer (OOM) của Android.
- **User Stories & Nhiệm vụ**:
  - **Lớp 1 (Foreground Service)**: `UsageWatcherService` chạy thường trực với Silent Notification (`IMPORTANCE_MIN`), tiêu thụ RAM < 30MB.
  - **Lớp 2 (WorkManager Fail-Safe)**: `PeriodicWorkRequest` 15 phút/lần kiểm tra nếu `UsageWatcherService` bị kill thì lập tức khởi động lại.

### 2.4. Bộ đệm cục bộ & Cơ chế Ngoại tuyến (Room DB & Offline First)
- **Mục tiêu**: Vẫn trừ quota và khóa app bình thường kể cả khi mất Wi-Fi/4G nhiều ngày.
- **User Stories & Nhiệm vụ**:
  - Tạo Room Database gồm các bảng: `daily_app_usage`, `usage_sessions`, `cached_policies`.
  - Tự động reset số liệu và mở khóa quota vào thời khắc 00:00:00 hàng ngày.
  - Thu gom dữ liệu session để sẵn sàng đẩy batch lên Backend khi có mạng.

### 2.5. Phân loại danh mục ứng dụng (App Classification Engine)
- **Mục tiêu**: Nhận diện loại app để áp đặt quota theo nhóm (Học tập vs Game vs MXH).
- **User Stories & Nhiệm vụ**:
  - Đọc `ApplicationInfo.category` từ hệ điều hành Android (Games, Audio, Video, Social, Productivity).
  - Kết hợp bảng ánh xạ danh mục cục bộ (Local Taxonomy Mapping Cache) đồng bộ từ Backend.

---

## T-EPIC 03: Cơ Chế Thực Thi Giới Hạn Cấp Hệ Điều Hành (Policy Enforcement)
*Phân rã từ: EPIC 03 toàn dự án*

### 3.1. Khóa ứng dụng cấp HĐH bằng `setPackagesSuspended`
- **Mục tiêu**: Khóa triệt để native, không thể bypass bằng phím Home/Recent hay chia đôi màn hình.
- **User Stories & Nhiệm vụ**:
  - Tích hợp `DevicePolicyManager.setPackagesSuspended(admin, packageNames, true)`.
  - Khi bị suspend: Icon app trên mọi Launcher tự động chuyển sang màu xám; bấm vào sẽ bị Android chặn lại từ tầng `ActivityTaskManager`.
  - Tùy chỉnh thông điệp hiển thị trong System Suspension Dialog (ví dụ: *"Ứng dụng này đã hết hạn mức cho phép hôm nay"*).

### 3.2. Ẩn ứng dụng Blacklist vĩnh viễn bằng `setApplicationHidden`
- **Mục tiêu**: Xóa sổ hoàn toàn icon ứng dụng cấm khỏi App Drawer.
- **User Stories & Nhiệm vụ**:
  - Tích hợp `DevicePolicyManager.setApplicationHidden(admin, packageName, true)`.
  - Áp dụng ngay cho các ứng dụng độc hại, cờ bạc, nội dung người lớn do phụ huynh đưa vào danh sách đen vĩnh viễn.

### 3.3. Bảo vệ Danh sách trắng Khẩn cấp (Emergency Whitelist)
- **Mục tiêu**: Đảm bảo an toàn tính mạng cho trẻ trong mọi tình huống.
- **User Stories & Nhiệm vụ**:
  - Tuyệt đối cấm suspend: Ứng dụng gọi điện thoại (`ACTION_DIAL`, các số khẩn cấp 112/113/114/115), ứng dụng SMS mặc định, ứng dụng Bản đồ định vị, System UI và chính Target Agent.

### 3.4. Quản lý Giờ đi ngủ (Bedtime Mode) & Khóa khẩn cấp cục bộ
- **Mục tiêu**: Tự động áp đặt giới hạn không phụ thuộc mạng.
- **User Stories & Nhiệm vụ**:
  - Sử dụng `AlarmManager.setExactAndAllowWhileIdle()` để kích hoạt Bedtime Mode đúng giờ (ví dụ 21h30).
  - Tự động suspend toàn bộ nhóm ứng dụng giải trí trong khung giờ Bedtime và mở lại vào sáng hôm sau.

---

## T-EPIC 04: Kênh Truyền Thông Thời Gian Thực & Đồng Bộ Dữ Liệu
*Phân rã từ: EPIC 04 toàn dự án*

### 4.1. WebSocket Client & Reconnect Tự Động
- **Mục tiêu**: Nhận lệnh từ phụ huynh với độ trễ < 3 giây.
- **User Stories & Nhiệm vụ**:
  - Duy trì kết nối WebSocket bền bỉ với Backend Server bằng OkHttp WebSocket Client.
  - Tự động reconnect với exponential backoff khi thay đổi mạng (Wi-Fi sang 4G).

### 4.2. Bộ Nhận Lệnh Khẩn Cấp (Real-Time Command Dispatcher)
- **Mục tiêu**: Thực thi tức thời các lệnh điều khiển.
- **User Stories & Nhiệm vụ**:
  - Nhận lệnh `COMMAND_PANIC_LOCKDOWN` -> Suspend ngay lập tức mọi app không thuộc Whitelist.
  - Nhận lệnh `COMMAND_ADD_BONUS_TIME` (+15m, +30m) -> Cộng thêm quota vào Room DB và lập tức un-suspend app.
  - Phản hồi mã ACK về server để xác nhận lệnh đã thi hành thành công.

### 4.3. Dự phòng bằng FCM High-Priority Push Notification
- **Mục tiêu**: Đánh thức Agent thi hành lệnh kể cả khi WebSocket bị ngắt kết nối nền.
- **User Stories & Nhiệm vụ**:
  - Tích hợp `FirebaseMessagingService`. Bắt Data Payload ưu tiên cao (`high_priority`), khởi động Foreground Service để áp đặt policy.

### 4.4. Đồng bộ dữ liệu Telemetry theo Batch (Telemetry Ingestion Worker)
- **Mục tiêu**: Gửi dữ liệu thống kê lên máy chủ mà không làm hao pin.
- **User Stories & Nhiệm vụ**:
  - Nén batch log 15 phút (JSON/Protobuf) và đẩy lên Backend qua HTTP POST khi có kết nối mạng.

---

## T-EPIC 05: Giao Diện Màn Hình Con & Ghép Nối (Child Pairing UI)
*Phân rã từ: EPIC 05 toàn dự án*

### 5.1. Hiển thị mã QR & OTP Ghép nối (Pairing Screen)
- **Mục tiêu**: Cho phép phụ huynh quét mã kết nối trong 1 bước duy nhất.
- **User Stories & Nhiệm vụ**:
  - Giao diện Jetpack Compose tối giản hiển thị mã QR Code (chứa Token 1 lần do Backend cấp) kèm mã OTP 6 số (TTL 5 phút).
  - Đếm ngược thời gian hết hạn mã token.

### 5.2. Màn hình Trạng thái Thiết bị Con (Child Device Status Screen)
- **Mục tiêu**: Thông báo minh bạch cho trẻ về quyền quản trị của phụ huynh.
- **User Stories & Nhiệm vụ**:
  - Hiển thị danh sách các app còn bao nhiêu thời gian trong ngày.
  - Hiển thị thông báo khi máy đang trong khung giờ Đi Ngủ (Bedtime Mode).
