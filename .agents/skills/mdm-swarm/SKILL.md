---
name: mdm-swarm
description: Operational runbook and multi-agent coordination protocol for the MDM Parental Control project across Child DO Agent, Backend Orchestrator, and Parent App.
---

# MDM Parental Control - Swarm Coordination Skill

Skill này cung cấp cẩm nang vận hành, quy trình điều phối đa tác nhân (Multi-Agent Swarm) và kịch bản cộng tác chuyên sâu giữa các agent để hiện thực hóa 5 Epic cốt lõi của dự án **MDM Parental Control**:

1. **EPIC 01**: Core Target Agent & Thiết lập quyền Device Owner (DO).
2. **EPIC 02**: Engine Thu thập & Thống kê Thời lượng Sử dụng (Usage Tracking Engine).
3. **EPIC 03**: Cơ chế Thực thi Giới hạn & Chặn ứng dụng (Rule Enforcement & App Suspension).
4. **EPIC 04**: Backend Server & Đồng bộ Điều phối Thời gian thực.
5. **EPIC 05**: Ứng dụng Phụ huynh (Parent Management Dashboard & Controller).

---

## 👥 1. Danh Sách Subagents Chuyên Trách

| Subagent Name | Lĩnh vực chuyên trách | Khi nào triệu hồi? |
| :--- | :--- | :--- |
| `lead-architect` | Điều phối tổng thể, Clean Architecture, API & Protocol Contract, Review | Khi tiếp nhận Epic mới, chia tách subtasks, thiết kế kiến trúc hệ thống |
| `device-owner-specialist` | DevicePolicyManager, DeviceAdminReceiver, Anti-Tampering, Suspension | Khi thực hiện EPIC 01, EPIC 03, cấu hình MDM, khóa ứng dụng cấp HĐH |
| `usage-tracking-specialist` | UsageStatsManager, Foreground Service, Room DB, Local Rule Engine | Khi thực hiện EPIC 02, tối ưu pin, xử lý sự kiện app, offline calculation |
| `backend-sync-specialist` | REST API, WebSocket/MQTT, FCM Push, Pairing Token, Time-Series DB | Khi thực hiện EPIC 04, đồng bộ dữ liệu thời gian thực, lưu trữ rule |
| `parent-ui-specialist` | Jetpack Compose Parent App, Real-time Charts, QR Pairing, Controls | Khi thực hiện EPIC 05, thiết kế giao diện phụ huynh, bảng điều khiển |
| `qa-security-perf-specialist` | Security Audit, Anti-Bypass Testing, Battery Profiling, Unit Tests | Rà soát lỗ hổng, test bypass Safe Mode/Force Stop, đo mức tiêu hao pin |

---

## 🛠️ 2. Kịch Bản Phối Hợp Mẫu Theo Các Epic (Standard Swarm Workflows)

### Kịch bản 1: Kích Hoạt Device Owner & Anti-Tampering (EPIC 01)
1. **`lead-architect`**:
   - Định nghĩa cấu trúc project Android cho Target Agent (`app-child`), thiết lập `build.gradle.kts`, Hilt DI.
2. **`device-owner-specialist`**:
   - Khai báo `DeviceAdminReceiver` và cấu hình policy XML (`res/xml/device_admin_receiver.xml`).
   - Viết module `AntiTamperManager`: gọi `setSafeModeDisabled`, `setFactoryResetDisabled`, `setUninstallBlocked`, `addUserRestriction(DISALLOW_DEBUGGING_FEATURES)`, `setAutoTimeRequired`.
   - Viết module `SilentPermissionManager`: tự động cấp `PACKAGE_USAGE_STATS` qua `setPermissionGrantState`.
3. **`qa-security-perf-specialist`**:
   - Kiểm thử các kịch bản phá hoại: Cố gắng gỡ app, cố gắng reboot vào Safe Mode, cố gắng chỉnh lùi giờ để xác nhận bị chặn 100%.

### Kịch bản 2: Thu Thập Thời Lượng Sử Dụng Siêu Nhẹ & Tối Ưu Pin (EPIC 02)
1. **`usage-tracking-specialist`**:
   - Xây dựng `UsageEventsWatcher`: đọc `ACTIVITY_RESUMED` và `ACTIVITY_PAUSED` qua `UsageStatsManager.queryEvents()`.
   - Triển khai `UsageWatcherForegroundService` với silent notification.
   - Tạo Room Database (`AppUsageDatabase`, `DailyUsageEntity`, `AppUsageDao`).
   - Thiết lập `ScreenStateReceiver` để tạm dừng ticker khi màn hình tắt (`SCREEN_OFF`), giảm tải tối đa cho CPU.
2. **`qa-security-perf-specialist`**:
   - Profile năng lượng: Đo lượng pin tiêu hao qua `Battery Historian` hoặc dumpsys batterystats (mục tiêu < 3-5%/ngày).
   - Kiểm tra rò rỉ bộ nhớ khi chạy service liên tục trong nhiều giờ.

### Kịch bản 3: Thực Thi Giới Hạn Quota Cục Bộ & Giờ Đi Ngủ (EPIC 03)
1. **`usage-tracking-specialist`**:
   - Cập nhật số phút sử dụng vào Local Cache. Khi `currentUsage >= dailyQuota`, gửi sự kiện vi phạm cho Policy Enforcement.
2. **`device-owner-specialist`**:
   - Xây dựng `AppSuspensionManager`: gọi `dpm.setPackagesSuspended(admin, arrayOf(pkg), true)`.
   - Cài đặt dialog thông báo tùy biến khi trẻ bấm vào app bị khóa.
   - Thiết lập `BedtimeScheduleManager`: tự động khóa toàn bộ nhóm giải trí từ 21:00 đến 06:00 sáng.
   - Bảo đảm `EmergencyWhitelist`: Tuyệt đối không suspend Dial/Phone, SMS khẩn cấp, Maps và Target Agent.
3. **`qa-security-perf-specialist`**:
   - Thử mở app bằng launcher khác, notification hoặc chia đôi màn hình để xác nhận app không thể chạy.

### Kịch bản 4: Kênh Điều Khiển Thời Gian Thực & Đồng Bộ Dữ Liệu (EPIC 04)
1. **`backend-sync-specialist`**:
   - Khởi tạo Backend Server: Node.js (NestJS) hoặc Kotlin Ktor/Spring Boot.
   - Xây dựng WebSocket/MQTT Hub: Định tuyến lệnh từ Phụ huynh -> Máy con với độ trễ < 3 giây.
   - Xây dựng FCM High-Priority Push Fallback khi socket mất kết nối.
   - Thiết kế API tiếp nhận batch usage data từ `WorkManager` định kỳ 15 phút.
2. **`device-owner-specialist` & `usage-tracking-specialist`**:
   - Tích hợp Socket Client / FCM Receiver vào Target Agent.
   - Nhận lệnh `LOCK_DEVICE_NOW` -> gọi `dpm.lockNow()` hoặc suspend toàn bộ app giải trí.
   - Nhận lệnh `ADD_TIME` (+15 phút) -> cộng hạn mức vào Room DB và gọi `setPackagesSuspended(..., false)`.

### Kịch bản 5: Ghép Nối 1 Bước & Dashboard Ứng Dụng Phụ Huynh (EPIC 05)
1. **`parent-ui-specialist`**:
   - Xây dựng giao diện Jetpack Compose cho Parent App: Screen Time Chart, Category Bars, Status Badge.
   - Tích hợp CameraX quét QR Code từ màn hình Child App.
   - Tạo bộ điều khiển Quick Actions: Nút Khóa Khẩn Cấp (Lockdown), Nút +15m/+30m.
2. **`backend-sync-specialist`**:
   - Xây dựng Pairing Handshake API: Child tạo OTP/QR Token, Parent quét và trao đổi Auth Key.
3. **`qa-security-perf-specialist`**:
   - Đo lường độ trễ từ lúc Phụ huynh bấm nút "Khóa Ngay" đến khi máy Con suspend app (tiêu chuẩn < 3s).

---

## 📋 3. Bảng Tiêu Chuẩn Hoàn Thành (Definition of Done)

Trước khi đóng bất kỳ tác vụ hoặc epic nào, Swarm phải đảm bảo:
- [ ] **BẮT BUỘC**: Đã tạo và cập nhật đầy đủ nhật ký thực thi tại `docs/logs/YYYY-MM-DD_<task_slug>.md` và đưa vào chỉ mục `docs/logs/README.md`.
- [ ] Không sử dụng Overlay/Window lừa dối; áp dụng 100% API hệ thống của Device Owner (`setPackagesSuspended`, `UserManager` restrictions).
- [ ] Hoạt động Offline hoàn hảo: Máy con tự động ngắt app khi hết quota ngay cả khi không có mạng.
- [ ] Mọi thao tác I/O, Database, Network đều nằm trên Coroutine `Dispatchers.IO`.
- [ ] Mức tiêu thụ pin và tài nguyên đạt chuẩn quy định trong [Battery & Background Rules](../../rules/battery-background-rules.md).
- [ ] Đã chạy kiểm tra mã nguồn, không có lỗi biên dịch hay crash ngầm.
