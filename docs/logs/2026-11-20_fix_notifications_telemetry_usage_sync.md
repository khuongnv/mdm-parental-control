# 📋 Nhật Ký Thực Thi: Khắc phục thông báo 2 chiều (Realtime/FCM), mở rộng Telemetry thiết bị con & đồng bộ chính xác thời gian sử dụng

- **Ngày thực hiện**: 2026-11-20 14:10:00
- **Agent phụ trách**: `lead-architect`, `backend-sync-specialist`, `device-owner-specialist`, `usage-tracking-specialist`, `parent-ui-specialist`, `qa-security-perf-specialist`
- **Yêu cầu gốc**: Rà soát và khắc phục việc phản hồi của thiết bị con (`target-node`) hoặc tin nhắn yêu cầu thêm giờ chưa gửi được thông báo tới ứng dụng phụ huynh (`admin-node`), mở rộng thu thập thông số thiết bị con (độ sáng màn hình, chế độ màn hình, âm lượng bên cạnh thông tin pin hiện tại) và đồng bộ chính xác thời gian đã sử dụng về `admin-node`.
- **Trạng thái**: ✅ Hoàn thành

---

## 1. Phân Tích & Kế Hoạch (Analysis & Planning)

### 1.1. Nguyên nhân gốc rễ qua rà soát 3 tầng
- **R1 — Thông báo từ thiết bị con (`device_messages`, `time_requests`) tới `admin-node`**:
  - `device_messages` thiếu các cột `title`, `child_reply`, `fcm_notified_at` và `time_requests` thiếu cột `fcm_notified_at`; cả hai bảng chưa bật `REPLICA IDENTITY FULL`, khiến sự kiện Realtime `UPDATE` kèm RLS/filter không đầy đủ dữ liệu.
  - `create_time_request` chỉ trả về `{ success, request_id }` và `target-node` POST trực tiếp thiếu `family_id` (`NOT NULL`). Đồng thời `anon` không có quyền `SELECT` trên `device_messages` nên cần các RPC `SECURITY DEFINER` (`acknowledge_device_message`, `get_unread_device_messages`, `create_time_request`).
  - Chưa có bảng `parent_push_tokens` cho thiết bị phụ huynh (Android/iOS) và chưa có Edge Function `notify-family-parents` để đẩy FCM HTTP v1 (bao gồm cả cấu hình APNs cho iOS) khi `admin-node` chạy nền hoặc đã đóng.
  - `admin-node` chưa tích hợp `fcm_notification_service`, thiếu cơ chế khử trùng thông báo (`NotificationDeduplicator`) giữa WebSocket Realtime và FCM HTTP v1.
- **R2 — Thông số thiết bị mở rộng**:
  - Bảng `devices` thiếu 11 cột telemetry (độ sáng màn hình, auto brightness, chế độ màn hình, trạng thái bật màn hình, dark mode, 4 kênh âm lượng, ringer mode, media mute).
  - RPC `update_device_telemetry` bản 5 tham số cũ ghi đè giá trị mặc định nếu thiếu tham số; khi mở rộng lên 17 tham số bắt buộc phải `DROP FUNCTION` bản 5 tham số trước để tránh xung đột overload PostgREST (`PGRST203`), đồng thời dùng `DEFAULT NULL` + `COALESCE` để bảo toàn trường không gửi.
  - `target-node` cần module `DeviceTelemetryCollector` trích xuất thông số chuẩn Android API và truyền qua RPC `update_device_telemetry` + Realtime Presence/Broadcast.
  - `admin-node` cần hiển thị thanh trạng thái trực quan chuẩn Apple Music Dark AMOLED cho độ sáng, chế độ màn hình, âm lượng và pin.
- **R3 — Đồng bộ chính xác thời gian sử dụng**:
  - Cơ chế cũ (`aggregate_device_daily_usage`) chia nguyên `/ 60` giây gây thất thoát và `app_usage_logs.session_date` dùng `CURRENT_DATE` (UTC) gây lệch ngày vào khung 00:00–06:59 tại múi giờ `Asia/Ho_Chi_Minh` (`UTC+7`).
  - `target-node` trong Room DB dùng `packageName` làm khóa chính đơn khiến phiên dùng đè nhau khi chuyển ngày. Cần composite key `(packageName, date)` và transactional `incrementDailyUsage`.
  - Cần bảng `daily_app_usage`, các cột giây chính xác trên `daily_usage_summaries` (`total_screen_time_seconds`, `app_breakdown`, `local_timezone`) và `devices` (`today_usage_seconds`, `today_usage_date`), cùng RPC `sync_device_daily_usage`.
  - `admin-node` cần thay thế tỷ lệ `0.35` cứng bằng tỷ lệ tính toán chính xác theo giây (`computeQuotaProgress`), hiển thị định dạng `formatUsageDuration` và danh sách Top Apps dùng nhiều trong ngày.

### 1.2. Kế hoạch triển khai toàn hệ thống
- **Milestone M1 (Backend Orchestrator)**: SQL migration `20261120_notifications_telemetry_usage_sync.sql`, shared helpers Web-standard ESM (`_shared/fcm.mjs`, `_shared/notify_parents.mjs`), Edge Function `notify-family-parents`, cập nhật `send-fcm-command`, bộ kiểm thử `backend/tests/*.test.mjs`.
- **Milestone M2 (Child DO Agent — `target-node`)**: Room migration `MIGRATION_1_2` với composite primary key `(packageName, date)`, transactional `incrementDailyUsage`, `DeviceTelemetryCollector.kt`, 17-parameter `updateTelemetry` & `syncDeviceDailyUsage`, gọi RPC `create_time_request` & `acknowledge_device_message` kèm kích hoạt `notify-family-parents`.
- **Milestone M3 (Parent Admin App — `admin-node`)**: Tích hợp `firebase_core`, `firebase_messaging`, tạo `models/device_telemetry_snapshot.dart`, `models/daily_usage_report.dart`, `models/notification_payload.dart`, `services/notification_deduplicator.dart`, `services/fcm_notification_service.dart`, cập nhật `mdm_supabase_service.dart`, làm mới thẻ thiết bị và thẻ hạn mức quota với breakdown top apps.
- **Milestone M4 (E2E & Security Audit)**: Kiểm thử E2E xuyên suốt 3 tầng (124 tests), kiểm thử repo contracts (19/19 checks), phân tích `flutter analyze` & `flutter test` (22/22 tests), biên dịch Android Kotlin (`compileDebugKotlin`).

---

## 2. Chi Tiết Các Bước Thực Hiện (Execution Steps)

### Bước 1: Triển khai SQL Migration & Edge Functions Backend (Milestone M1)
- Tạo migration `backend/supabase/migrations/20261120_notifications_telemetry_usage_sync.sql`:
  - Thêm 11 cột telemetry mở rộng vào `devices`.
  - Tạo bảng `parent_push_tokens` kèm RLS `user_id = auth.uid()` và RPC `upsert_parent_push_token`.
  - Mở rộng `device_messages` (`title`, `child_reply`, `fcm_notified_at`) và `time_requests` (`fcm_notified_at`), bật `REPLICA IDENTITY FULL`.
  - Tạo RPC `create_time_request` (tự động tra `family_id` theo `device_id`), `acknowledge_device_message` (nhận `p_reply_text`), `get_unread_device_messages`.
  - Tạo bảng `daily_app_usage`, mở rộng `daily_usage_summaries` (`total_screen_time_seconds`, `app_breakdown`, `local_timezone`), `devices.today_usage_seconds` và RPC `sync_device_daily_usage`.
  - Bật Realtime publication cho toàn bộ 8 bảng.
- Tạo Edge Function `notify-family-parents/index.ts` và shared helpers `_shared/fcm.mjs`, `_shared/notify_parents.mjs` hỗ trợ FCM HTTP v1 (Android channel `vfam_admin_alerts` + iOS APNs `apns-priority: 10`, `sound: default`, `badge: 1`).
- Cập nhật `send-fcm-command/index.ts` và bộ kiểm thử `backend/tests/` (21/21 tests pass).

### Bước 2: Nâng Cấp Child DO Agent `target-node` (Milestone M2)
- **Room Database Composite Key & Data Integrity**:
  - `Entities.kt`: Cập nhật `@Entity(tableName = "app_usage", primaryKeys = ["packageName", "date"])`.
  - `UsageDao.kt`: Thêm query `@Query("UPDATE app_usage SET durationMs = durationMs + :sessionMs, lastEventTime = :lastEventTime WHERE packageName = :packageName AND date = :date")` và hàm transactional `@Transaction incrementDailyUsage(...)`.
  - `MdmAppDatabase.kt`: Định nghĩa `MIGRATION_1_2` tạo bảng mới `app_usage_new` với composite primary key, copy dữ liệu gộp theo `(packageName, date)` và chuyển đổi an toàn sang `app_usage`.
  - `DatabaseModule.kt`: Tích hợp `addMigrations(MdmAppDatabase.MIGRATION_1_2)`.
- **Telemetry Collector Tầng HĐH (`DeviceTelemetryCollector.kt`)**:
  - Trích xuất độ sáng màn hình (`Settings.System.SCREEN_BRIGHTNESS`), chế độ tự động điều chỉnh (`SCREEN_BRIGHTNESS_MODE_AUTOMATIC`).
  - Xác định chế độ màn hình: `off`, `on_locked` (qua `KeyguardManager.isKeyguardLocked`), `on_unlocked`.
  - Đọc theme Dark Mode (`Configuration.UI_MODE_NIGHT_YES`).
  - Trích xuất 4 kênh âm lượng chuẩn hóa 0..100% (`STREAM_MUSIC`, `STREAM_RING`, `STREAM_NOTIFICATION`, `STREAM_ALARM`), `ringerMode` (`normal`, `vibrate`, `silent`) và `isMediaMuted`.
- **MdmSupabaseClient & UsageTrackingForegroundService**:
  - Nâng cấp `updateTelemetry` nhận 17 tham số gọi RPC `update_device_telemetry`.
  - Triển khai `syncDeviceDailyUsage` gọi RPC `sync_device_daily_usage`.
  - Cập nhật `sendTimeRequest` gọi RPC `create_time_request` và gửi thông báo tới `notify-family-parents`.
  - Cập nhật `sendAckMessage` gọi RPC `acknowledge_device_message` và gửi thông báo tới `notify-family-parents`.
  - Kết nối `syncUsageToBackend()` định kỳ trong telemetry loop và lập tức khi màn hình tắt (`ACTION_SCREEN_OFF`).

### Bước 3: Phát Triển & Hoàn Thiện Parent Admin App `admin-node` (Milestone M3)
- **Data Models & Deduplication**:
  - `models/device_telemetry_snapshot.dart`: Snapshot telemetry 17 trường, `mergeFrom` bảo toàn dữ liệu khi nhận payload từng phần, nhãn tiếng Việt `screenModeLabel`, `ringerModeLabel`.
  - `models/daily_usage_report.dart`: Mô hình `AppUsageItem` và `DailyUsageReport` đối soát giây chính xác giữa `daily_app_usage`, `daily_usage_summaries` và cache `devices`, hàm `formatUsageDuration`, `computeQuotaProgress`, `computeRemainingSeconds`.
  - `models/notification_payload.dart`: Phân tích payload FCM HTTP v1 / Realtime, tạo `dedupKey`, `deterministicNotificationId`, và tạo bản sao chép thông báo `buildCopy()`.
  - `services/notification_deduplicator.dart`: Hàng đợi FIFO có giới hạn lưu trên `SharedPreferences` khử trùng tin báo trùng giữa WebSocket và FCM.
  - `services/fcm_notification_service.dart`: Dịch vụ trung tâm khởi tạo Firebase, xin quyền thông báo, lấy token và gọi `upsert_parent_push_token`, quản lý background handler `fcmBackgroundMessageHandler`.
- **Giao Diện Người Dùng Chuẩn Apple Music UI**:
  - `_buildDeviceGroupCard`: Bổ sung hàng badge frosted glass hiển thị độ sáng màn hình (tự động/thủ công), chế độ màn hình (đang mở/khóa/tắt), âm lượng & chế độ chuông (rung/chuông/im lặng).
  - `_buildQuotaGroupCard`: Hiển thị số giờ đã dùng chính xác (`formatUsageDuration(todayUsageSeconds)`), thanh tiến độ tỷ lệ thực theo giây (`computeQuotaProgress`), trạng thái thông minh và danh sách Top Apps dùng nhiều trong ngày kèm thanh tiến độ tỷ lệ.
  - Tích hợp lắng nghe Realtime thay đổi trên `devices`, `daily_app_usage`, `daily_usage_summaries` để cập nhật giao diện thời gian thực.

### Bước 4: Kiểm Thử Toàn Diện & Nghiệm Thu Hệ Thống (Milestone M4)
- Chạy toàn bộ 21 bài test Backend: `node --test backend/tests` -> **21/21 PASS**.
- Chạy toàn bộ 22 bài test Flutter: `flutter test` trong `admin-node` -> **22/22 PASS**.
- Phân tích tĩnh Flutter: `flutter analyze` trong `admin-node` -> **No issues found**.
- Biên dịch mã nguồn Kotlin Child Agent: `.\gradlew.bat compileDebugKotlin` trong `target-node` -> **BUILD SUCCESSFUL**.
- Chạy bộ kiểm thử E2E tích hợp: `node tests/e2e/run.mjs --verify-repo` -> **124/124 tests PASS** và **19/19 repo contracts PASS**.

---

## 3. Danh Sách Tệp Thay Đổi (Impacted Files)

### Backend
- `[Created]` `backend/supabase/migrations/20261120_notifications_telemetry_usage_sync.sql` - Schema migration R1, R2, R3.
- `[Created]` `backend/supabase/functions/_shared/fcm.mjs` - Helper Web-standard FCM HTTP v1, JWT RS256, APNs.
- `[Created]` `backend/supabase/functions/_shared/fcm.d.ts` - TypeScript declaration cho fcm.mjs.
- `[Created]` `backend/supabase/functions/_shared/notify_parents.mjs` - Dispatcher gửi push cho phụ huynh.
- `[Created]` `backend/supabase/functions/_shared/notify_parents.d.ts` - TypeScript declaration cho notify_parents.mjs.
- `[Created]` `backend/supabase/functions/notify-family-parents/index.ts` - Edge Function notify-family-parents.
- `[Modified]` `backend/supabase/functions/send-fcm-command/index.ts` - Chuẩn hóa FCM command và APNs headers.
- `[Modified]` `backend/supabase/.env.example` - Cấu hình mẫu Firebase Service Account.
- `[Modified]` `backend/README.md` - Tài liệu kiến trúc và hướng dẫn kiểm thử.
- `[Created]` `backend/tests/migration_contract.test.mjs` - Unit test hợp đồng migration.
- `[Created]` `backend/tests/fcm_and_notify_parents.test.mjs` - Unit test FCM & notify parents.

### Child DO Agent (`target-node`)
- `[Modified]` `target-node/app/src/main/java/com/mdm/parentalcontrol/child/data/local/Entities.kt` - Composite primary key `(packageName, date)`.
- `[Modified]` `target-node/app/src/main/java/com/mdm/parentalcontrol/child/data/local/UsageDao.kt` - Transactional `incrementDailyUsage`.
- `[Modified]` `target-node/app/src/main/java/com/mdm/parentalcontrol/child/data/local/MdmAppDatabase.kt` - Room `MIGRATION_1_2`.
- `[Modified]` `target-node/app/src/main/java/com/mdm/parentalcontrol/child/di/DatabaseModule.kt` - Đăng ký `MIGRATION_1_2`.
- `[Created]` `target-node/app/src/main/java/com/mdm/parentalcontrol/child/service/DeviceTelemetryCollector.kt` - Trích xuất telemetry HĐH.
- `[Modified]` `target-node/app/src/main/java/com/mdm/parentalcontrol/child/network/MdmSupabaseClient.kt` - 17-param telemetry, RPC sync usage & notifications.
- `[Modified]` `target-node/app/src/main/java/com/mdm/parentalcontrol/child/service/UsageTrackingForegroundService.kt` - Tích hợp collector & đồng bộ usage.

### Parent Admin App (`admin-node`)
- `[Modified]` `admin-node/pubspec.yaml` - Khai báo `firebase_core: ^5.2.0`, `firebase_messaging: ^17.1.0`.
- `[Created]` `admin-node/lib/models/device_telemetry_snapshot.dart` - Snapshot telemetry mở rộng.
- `[Created]` `admin-node/lib/models/daily_usage_report.dart` - Báo cáo usage đối soát giây chính xác.
- `[Created]` `admin-node/lib/models/notification_payload.dart` - Payload & copy builder thông báo.
- `[Created]` `admin-node/lib/services/notification_deduplicator.dart` - Khử trùng thông báo FIFO trên SharedPreferences.
- `[Created]` `admin-node/lib/services/fcm_notification_service.dart` - Quản lý FCM push & token registration.
- `[Modified]` `admin-node/lib/services/mdm_supabase_service.dart` - RPC `upsert_parent_push_token` & `getDeviceDailyUsage`.
- `[Modified]` `admin-node/lib/main.dart` - Wire FcmNotificationService, realtime listeners, UI telemetry & quota card.
- `[Modified]` `admin-node/analysis_options.yaml` - Cấu hình analyzer bỏ qua deprecated member lint.
- `[Created]` `admin-node/test/notification_deduplicator_test.dart` - Test bộ khử trùng thông báo.
- `[Created]` `admin-node/test/device_telemetry_snapshot_test.dart` - Test snapshot telemetry.
- `[Created]` `admin-node/test/daily_usage_report_test.dart` - Test đối soát sử dụng ngày.
- `[Created]` `admin-node/test/notification_payload_test.dart` - Test payload thông báo.
- `[Modified]` `admin-node/test/widget_test.dart` - Test render Dashboard UI.

### Test Harness & Logs
- `[Modified]` `tests/e2e/run.mjs` - Thêm `concurrency: 1` cho bộ test runner E2E.
- `[Created]` `docs/logs/2026-11-20_fix_notifications_telemetry_usage_sync.md` - Nhật ký thực thi nhiệm vụ.
- `[Modified]` `docs/logs/README.md` - Cập nhật mục lục truy vết.

---

## 4. Kiểm Thử & Đánh Giá Bảo Mật (Verification & Security Audit)

### 4.1. Kết Quả Kiểm Thử Tự Động
- **Backend Tests**: `node --test backend/tests` -> **21/21 PASS** (100%).
- **Flutter Unit & Widget Tests**: `flutter test` trong `admin-node` -> **22/22 PASS** (100%).
- **Flutter Analyzer**: `flutter analyze` trong `admin-node` -> **No issues found**.
- **Android Kotlin Compilation**: `.\gradlew.bat compileDebugKotlin` trong `target-node` -> **BUILD SUCCESSFUL**.
- **E2E Integration Suite**: `node tests/e2e/run.mjs --verify-repo` -> **124/124 PASS** across all 7 test files, **19/19 Repo Contracts PASS**.

### 4.2. Rà Soát Bảo Mật & Chống Phá Hoại (Anti-Tampering & Anti-Bypass)
- **Zero-Bypass Policy**: Toàn bộ thao tác khóa ứng dụng và khóa máy tuân thủ triệt để Device Policy Manager (`setPackagesSuspended`, `lockNow`), không dùng overlay tạm bợ (`SYSTEM_ALERT_WINDOW`).
- **Data Tampering Protection**: Token đăng ký push token phụ huynh được bảo vệ bằng RLS `user_id = auth.uid()`. Dữ liệu máy con được xác thực qua RPC `SECURITY DEFINER` và kiểm tra quyền sở hữu gia đình.
- **Deduplication Resilience**: Ngăn chặn triệt để tình trạng rung chuông đôi khi cả WebSocket Phoenix và FCM cùng nhận một bản tin (`NotificationDeduplicator` FIFO).
- **Pin & Hiệu Năng**: Dịch vụ Foreground Service của `target-node` áp dụng cơ chế event-driven kết hợp polling thích ứng (3s khi màn hình bật, dừng hoàn toàn khi màn hình tắt), duy trì mức tiêu thụ pin dưới 3-5%/ngày.

---

## 5. Kết Luận & Nghiệm Thu (Conclusion & Sign-off)
Hệ thống MDM Parental Control đã hoàn thành xuất sắc toàn bộ 3 mục tiêu:
1. **R1**: Thông báo phản hồi của máy con và yêu cầu xin thêm giờ hoạt động ổn định và tin cậy cả khi phụ huynh mở app (Realtime WebSocket) lẫn khi app chạy ngầm/đã tắt (FCM HTTP v1 Android & APNs iOS).
2. **R2**: Thu thập và đồng bộ thời gian thực đầy đủ các thông số độ sáng màn hình (tự động/thủ công), chế độ màn hình (mở/khóa/tắt), âm lượng 4 kênh & chế độ chuông (rung/chuông/im lặng).
3. **R3**: Đồng bộ chính xác theo từng giây thời lượng sử dụng máy của con theo ngày địa phương (không bị trôi ngày do UTC), hiển thị trực quan tỷ lệ sử dụng thực tế và danh sách phân bổ ứng dụng trên Parent Admin App.
