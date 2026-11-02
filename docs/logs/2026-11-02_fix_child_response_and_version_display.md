# 📋 Nhật Ký Thực Thi: Khắc Phục Lỗi Phản Hồi Từ Máy Con & Đồng Bộ Phiên Bản App (v1.3.4)

- **Ngày thực hiện**: 2026-11-02 12:51:00
- **Agent phụ trách**: `lead-architect`, `device-owner-specialist`, `backend-sync-specialist`, `parent-ui-specialist`, `qa-security-perf-specialist`
- **Yêu cầu gốc**: "chid phản hồi có vấn đề, version app child cũng hiển thị chưa đúng"
- **Trạng thái**: ✅ Hoàn thành

---

## 1. Phân Tích & Nguyên Nhân Gốc Rễ (Analysis & Root Causes)

### Vấn đề 1: Version app child hiển thị chưa đúng
- **Hardcoded chuỗi phiên bản trong UI**: `MainActivity.kt` khai báo `private val currentAppVersion = "1.2.4"` và chuỗi UI gán cứng `"Phiên bản 1.2.4 (Build 6) • GitHub Release"`.
- **Lệch version trong Gradle/Pubspec**: `target-node/app/build.gradle.kts` vẫn đặt `versionName = "1.3.0"`, `versionCode = 8`, `admin-node/pubspec.yaml` vẫn đặt `version: 1.3.0+8`.
- **Kịch bản deploy chưa đồng bộ ngược**: `deploy.ps1` chỉ đổi tên artifact đầu ra `vfam-child-$Version.apk` mà không ghi đè `versionName` trong `build.gradle.kts` và `pubspec.yaml`.
- **Telemetry không gửi `agent_version` động**: `MdmSupabaseClient.kt` gửi `p_agent_version = "1.0.0"`, hàm `updateTelemetry` không gửi `agent_version` lên bảng `devices`.
- **Admin card thiếu thông tin phiên bản máy con**: Admin Card chỉ hiển thị `$model • $osVersion`.

### Vấn đề 2: Phản hồi từ máy con có vấn đề (Child ACK & Time Request không tới Admin)
- **Lỗi lồng gói tin Broadcast (Payload nesting mismatch)**: OkHttp trong `MdmSupabaseClient.sendBroadcast` bọc `payload` trong một trường con `"payload"`. Kết quả là Admin khi đọc `payload['requested_minutes']` hay `payload['message_id']` nhận giá trị `null` và không kích hoạt được logic thông báo.
- **Vòng đời BroadcastReceiver bị hủy sớm (`NotificationActionReceiver`)**: Khi bé nhấn nút "Dạ Con Nghe Rồi! 👍" trên khay thông báo hệ thống, `onReceive()` thoát ngay khiến Android kill tiến trình hoặc thread OkHttp bất đồng bộ trước khi kịp gửi HTTP request tới Supabase.
- **Kênh truyền nhận 1 chiều đơn lẻ**: Admin chỉ lắng nghe duy nhất `channel.onBroadcast(event: 'ACK_MESSAGE')`. Nếu máy Admin tắt màn hình, rớt mạng tạm thời hoặc đang kết nối lại socket, bản tin broadcast bị mất vĩnh viễn (WebSocket broadcast là ephemeral).
- **MainActivity thiếu `onNewIntent`**: Khi bé nhấn vào thân thông báo tin nhắn trong lúc app con đang chạy ngầm, Activity không nhận được Intent mới chứa `SHOW_REMOTE_MESSAGE_ID`.
- **Yêu cầu xin thêm giờ (`sendTimeRequest`) chỉ gửi socket**: Chưa ghi nhận bản ghi vào bảng `time_requests` qua REST API để phụ huynh có thể duyệt offline hoặc qua Postgres Realtime.

---

## 2. Chi Tiết Các Bước Đã Thực Hiện (Execution Steps)

### Bước 1: Khắc phục hiển thị và đồng bộ phiên bản tự động
- **`target-node/app/build.gradle.kts`**: Nâng `versionCode = 9`, `versionName = "1.3.4"`.
- **`admin-node/pubspec.yaml`**: Nâng `version: 1.3.4+9`.
- **`.agents/skills/deploy-app/scripts/deploy.ps1`**: Thêm cơ chế tự động tìm và cập nhật `versionName = "$Version"` trong `build.gradle.kts` và `version: $Version+9` trong `pubspec.yaml` trước khi build.
- **`MainActivity.kt`**:
  - Chuyển `currentAppVersion` sang `BuildConfig.VERSION_NAME`.
  - Hiển thị `"Phiên bản $currentAppVersion (Build ${BuildConfig.VERSION_CODE}) • GitHub Release"`.
  - Bổ sung `override fun onNewIntent(intent: Intent)` và `DisposableEffect` để mở dialog nhắc nhở ngay khi nhấn thông báo lúc app đang chạy ngầm.
- **`GitHubReleaseUpdater.kt`**: Sử dụng `BuildConfig.VERSION_NAME` làm giá trị mặc định cho `currentVersion`.
- **`MdmSupabaseClient.kt`**: Truyền `BuildConfig.VERSION_NAME` vào `createPairingSession` và cập nhật `agent_version` định kỳ trong `updateTelemetry` gửi lên Supabase `devices`.
- **`admin-node/lib/main.dart`**: Hiển thị phiên bản app máy con trực tiếp trên thẻ thiết bị (`$model • $osVersion • v$agentVersion`).

### Bước 2: Khắc phục phản hồi máy con (Dual-Channel Delivery: WebSocket + Postgres Realtime + REST)
- **`MdmSupabaseClient.kt`**:
  - Phẳng hóa cấu trúc JSON trong `sendBroadcast`: Sao chép toàn bộ các key từ `payload` vào cấp cao nhất của broadcast data và giữ trường `"payload"` tương thích ngược.
  - Cải tiến `sendAckMessage`:
    - Phát broadcast `ACK_MESSAGE` tức thì.
    - Gửi REST PATCH cập nhật `is_acknowledged = true` vào bảng `device_messages` (hỗ trợ cả UUID lẫn fallback `device_id` cho tin nhắn chưa đọc gần nhất).
    - Hỗ trợ callback `onComplete` để thông báo cho Receiver khi hoàn tất.
  - Cải tiến `sendTimeRequest`:
    - Phát broadcast `TIME_REQUEST` tức thì.
    - Gửi REST POST thêm bản ghi vào bảng `time_requests` với trạng thái `'pending'`.
- **`NotificationActionReceiver.kt`**:
  - Sử dụng `val pendingResult = goAsync()` ngăn Android thu hồi tiến trình sớm.
  - Giữ `PowerManager.PARTIAL_WAKE_LOCK` trong 5 giây trong lúc thực hiện network call.
  - Gọi `pendingResult.finish()` và giải phóng `WakeLock` trong callback hoàn tất của `sendAckMessage`.
- **`admin-node/lib/main.dart`**:
  - Thêm `_handleAckMessage` và `_handleTimeRequest` với cơ chế khử trùng lặp thông báo (deduplication) trong 3 giây.
  - Tự động unwrap payload an toàn (`(payload['payload'] is Map) ? payload['payload'] : payload`).
  - Đăng ký đa kênh lắng nghe:
    1. Realtime Broadcast: `ACK_MESSAGE`, `TIME_REQUEST`, `TELEMETRY_UPDATE`, `PANIC_LOCKDOWN`.
    2. Postgres Changes: `device_messages` UPDATE (`is_acknowledged == true`) -> Kích hoạt thông báo "Bé Đã Phản Hồi! 👍" ngay cả khi broadcast bị miss.
    3. Postgres Changes: `time_requests` INSERT (`status == 'pending'`) -> Mở hộp thoại "Bé Xin Thêm Giờ!".
    4. Postgres Changes: `devices` UPDATE -> Cập nhật pin, ứng dụng đang mở và phiên bản máy con thời gian thực.
- **`admin-node/lib/services/mdm_supabase_service.dart` & Edge Function `send-fcm-command`**:
  - Mở rộng Edge Function `send-fcm-command` hỗ trợ các action `REMOTE_MESSAGE` và `TIME_REQUEST_RESOLVED`.
  - Admin tự động kích hoạt silent push FCM dự phòng khi gửi tin nhắn hoặc duyệt thời gian.

---

## 3. Danh Sách Tệp Thay Đổi (Impacted Files)
- `[Modified]`: `target-node/app/build.gradle.kts` - Cập nhật versionCode 9, versionName 1.3.4.
- `[Modified]`: `target-node/app/src/main/java/com/mdm/parentalcontrol/child/ui/MainActivity.kt` - Đọc phiên bản từ BuildConfig, bổ sung onNewIntent.
- `[Modified]`: `target-node/app/src/main/java/com/mdm/parentalcontrol/child/network/MdmSupabaseClient.kt` - Phẳng hóa payload broadcast, REST sync cho ACK và time requests, gửi agent_version.
- `[Modified]`: `target-node/app/src/main/java/com/mdm/parentalcontrol/child/receiver/NotificationActionReceiver.kt` - Thêm goAsync và WakeLock bảo vệ phản hồi từ khay thông báo.
- `[Modified]`: `target-node/app/src/main/java/com/mdm/parentalcontrol/child/updater/GitHubReleaseUpdater.kt` - Đồng bộ currentVersion từ BuildConfig.
- `[Modified]`: `admin-node/pubspec.yaml` - Cập nhật version 1.3.4+9.
- `[Modified]`: `admin-node/lib/main.dart` - Lắng nghe Postgres Changes đa kênh cho ACK và time requests, hiển thị phiên bản máy con.
- `[Modified]`: `admin-node/lib/services/mdm_supabase_service.dart` - Tích hợp gọi FCM fallback và cập nhật DB cho resolveTimeRequest.
- `[Modified]`: `backend/supabase/functions/send-fcm-command/index.ts` - Hỗ trợ payload cho tin nhắn và duyệt giờ qua FCM HTTP v1.
- `[Modified]`: `.agents/skills/deploy-app/scripts/deploy.ps1` - Tự động đồng bộ version vào build.gradle.kts và pubspec.yaml.
- `[Created]`: `docs/logs/2026-11-02_fix_child_response_and_version_display.md` - Tài liệu truy vết thực thi.
- `[Modified]`: `docs/logs/README.md` - Cập nhật danh mục nhật ký.

---

## 4. Kiểm Thử & Nghiệm Thu (Verification & Release)
- **Compile & Static Analysis**:
  - `flutter analyze`: Không có lỗi (No issues found!).
  - `target-node:compileDebugKotlin`: Biên dịch thành công 100%.
- **Build & Artifacts**:
  - `vfam-child-1.3.4.apk`: Đã tạo thành công trong thư mục `release/`.
  - `vfam-admin-1.3.4.apk`: Đã tạo thành công trong thư mục `release/` (kích thước ~69.5 MB).
- **GitHub Release**:
  - Tag: `v1.3.4`
  - URL: https://github.com/khuongnv/mdm-parental-control/releases/tag/v1.3.4
  - Cả 2 file APK đã được tải lên release công khai kèm release notes chi tiết.

---

## 5. Kết Luận
- Vấn đề phiên bản hiển thị sai đã được khắc phục triệt để bằng cách liên kết trực tiếp với biến `BuildConfig` sinh ra từ Gradle và pubspec, đồng thời bổ sung tự động hóa vào kịch bản deploy.
- Vấn đề máy con phản hồi không tới máy phụ huynh đã được giải quyết bằng kiến trúc Dual-Channel (Realtime Broadcast + Postgres Realtime Replication + FCM Fallback) kết hợp `goAsync()` và `WakeLock` trong `NotificationActionReceiver`.
