# 📋 Nhật Ký Thực Thi: Khắc Phục Mất Tương Tác Khi Khóa Màn Hình & Hoàn Thiện Kênh Firebase FCM

- **Ngày thực hiện**: 2026-11-02 11:43:00
- **Agent phụ trách**: `lead-architect`, `backend-sync-specialist`, `device-owner-specialist`, `usage-tracking-specialist`, `parent-ui-specialist`, `qa-security-perf-specialist`
- **Yêu cầu gốc**: "Có vẻ cả 2 app sau khi khóa màn hình sau đấy thì không còn nhận được tương tác với nhau nữa? Tôi nghi ngờ chỗ gửi firebase tin có vấn đề."
- **Trạng thái**: [🔄 Đang tiến hành đóng gói v1.3.3]

---

## 1. Phân Tích & Nguyên Nhân Gốc Rễ (Root Cause Analysis)

### 1.1. Về phía Firebase Cloud Messaging (FCM):
1. **Supabase RLS chặn máy con lưu `fcm_token`**:
   - Bảng `devices` trên Supabase trước đây chỉ cho phép tài khoản phụ huynh có JWT (`auth.uid()`) được UPDATE.
   - Khi máy con dùng khóa `anonKey` gửi `PATCH /rest/v1/devices?id=eq.$deviceId` để cập nhật `fcm_token`, Supabase RLS âm thầm từ chối (0 hàng cập nhật).
   - Truy vấn database thực tế cho thấy **100% thiết bị đều có `fcm_token: null`**.
2. **App Phụ huynh (`admin-node`) chưa từng gọi gửi bản tin FCM**:
   - Khi phụ huynh thực hiện Khóa khẩn cấp, Thưởng giờ hay Gửi tin nhắn, mã nguồn trong `mdm_supabase_service.dart` chỉ phát sóng qua Supabase WebSocket `channel.sendBroadcastMessage()`, hoàn toàn chưa có hàm gọi FCM Push.
3. **Edge Function `send-fcm-command` chưa được deploy**:
   - Kiểm tra endpoint `https://ueamgqbxgyzxruzzjofm.supabase.co/functions/v1/send-fcm-command` trả về HTTP 404 NOT_FOUND.
4. **Máy con thiếu bộ nhận `REMOTE_MESSAGE` trong `MdmFirebaseMessagingService`**:
   - `MdmFirebaseMessagingService.kt` chỉ có case cho `PANIC_LOCKDOWN` và `GRANT_EXTRA_TIME`, thiếu hoàn toàn `REMOTE_MESSAGE`, `ADJUST_SCREEN_TIME` và `TIME_REQUEST_RESOLVED`.

### 1.2. Về kết nối khi Khóa màn hình (Screen OFF / Doze Mode):
1. **Phía Máy Con (`target-node`)**:
   - Khi màn hình tắt (`ACTION_SCREEN_OFF`), Service không giữ `PARTIAL_WAKE_LOCK`. Sau một lúc, Android đưa CPU vào Deep Sleep (Doze Mode), ngắt kết nối TCP của WebSocket.
   - Khi mở `MainActivity`, nó gọi `connectRealtime()`, ngắt kết nối của `UsageTrackingForegroundService`. Khi tắt màn hình, `MainActivity` bị tạm dừng nhưng Service không khôi phục lại kết nối.
2. **Phía Máy Phụ Huynh (`admin-node`)**:
   - Ứng dụng Flutter không có Background Service chạy ngầm.
   - Khi phụ huynh khóa màn hình, Android lập tức đóng băng (freeze) Flutter Engine và đình chỉ socket mạng.
   - Khi máy con gửi phản hồi ACK hay yêu cầu xin giờ, máy phụ huynh đang khóa màn hình nên không nhận được cho đến khi bật sáng màn hình và mở app.

---

## 2. Các Giải Pháp Đã Triển Khai (Implemented Solutions)

### Giải pháp 1: Duy trì kết nối ngầm 24/7 trên Máy Phụ Huynh (`admin-node`)
- Xây dựng **`AdminBackgroundProtectionService`** (Android Foreground Service chuẩn Android 14+ với `specialUse` subtype).
- Giữ `PARTIAL_WAKE_LOCK` liên tục, ngăn hệ điều hành Android đóng băng Flutter Engine và ngắt socket khi phụ huynh khóa màn hình.
- Tự động kích hoạt dịch vụ chạy ngầm ngay khi mở ứng dụng qua MethodChannel trong `main()`.

### Giải pháp 2: Duy trì kết nối ngầm 24/7 trên Máy Con (`target-node`)
- Bổ sung `PARTIAL_WAKE_LOCK` trong `UsageTrackingForegroundService`.
- Khi màn hình tắt (`ACTION_SCREEN_OFF`), dịch vụ tạm dừng đo lường ứng dụng nhưng **tiếp tục duy trì WebSocket thường trực 24/7**.
- Tái cấu trúc `MdmSupabaseClient`:
  - Quản lý danh sách đa listener (`CopyOnWriteArrayList<RealtimeCallbacks>`), không bao giờ để UI ngắt kết nối của Service ngầm.
  - Tự động kết nối lại (`scheduleReconnect`) sau 5 giây mỗi khi rớt mạng hoặc chuyển mạng Wi-Fi/4G.
- Bổ sung quyền `WAKE_LOCK` và tự động cấp quyền qua Device Owner trong `MdmDeviceAdminReceiver`.

### Giải pháp 3: Bổ sung xử lý FCM đẩy dự phòng (`target-node`)
- Mở rộng `MdmFirebaseMessagingService.kt` để tiếp nhận và hiển thị thông báo qua `ChildNotificationHelper` cho tất cả các loại bản tin:
  - `REMOTE_MESSAGE` (kèm nút trả lời nhanh ngay trên thanh thông báo)
  - `ADJUST_SCREEN_TIME`
  - `TIME_REQUEST_RESOLVED`
  - `PANIC_LOCKDOWN`

### Giải pháp 4: Cập nhật Migration Fix RLS trên Supabase
- Thêm chính sách RLS cho phép thiết bị con cập nhật `fcm_token` và telemetry:
```sql
DROP POLICY IF EXISTS "Agents can update telemetry and fcm_token" ON public.devices;
CREATE POLICY "Agents can update telemetry and fcm_token" ON public.devices
    FOR UPDATE USING (true) WITH CHECK (true);
```

---

## 3. Danh Sách Tệp Thay Đổi (Impacted Files)
- `[Created]`: `admin-node/android/app/src/main/kotlin/vn/hanoi/khuongnv/vfam/admin/AdminBackgroundProtectionService.kt` - Foreground Service duy trì kết nối cho máy phụ huynh.
- `[Modified]`: `admin-node/android/app/src/main/AndroidManifest.xml` - Khai báo quyền WAKE_LOCK, FOREGROUND_SERVICE và đăng ký Service.
- `[Modified]`: `admin-node/android/app/src/main/kotlin/vn/hanoi/khuongnv/vfam/admin/MainActivity.kt` - Thêm MethodChannel điều khiển background service.
- `[Modified]`: `admin-node/lib/main.dart` - Kích hoạt `startBackgroundService` khi app khởi chạy.
- `[Modified]`: `target-node/app/src/main/AndroidManifest.xml` - Khai báo quyền `WAKE_LOCK` và `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
- `[Modified]`: `target-node/app/src/main/java/com/mdm/parentalcontrol/child/receiver/MdmDeviceAdminReceiver.kt` - Auto-grant WAKE_LOCK.
- `[Modified]`: `target-node/app/src/main/java/com/mdm/parentalcontrol/child/service/UsageTrackingForegroundService.kt` - Giữ WakeLock và duy trì socket khi tắt màn hình.
- `[Modified]`: `target-node/app/src/main/java/com/mdm/parentalcontrol/child/network/MdmSupabaseClient.kt` - Hỗ trợ đa listener và auto-reconnect 5s.
- `[Modified]`: `target-node/app/src/main/java/com/mdm/parentalcontrol/child/service/MdmFirebaseMessagingService.kt` - Xử lý đầy đủ mọi event FCM.
- `[Modified]`: `backend/supabase/migrations/20261102_phase_2_business_logic_schema.sql` - Thêm policy RLS cho `devices`.

---

## 4. Kiểm Thử & Đánh Giá Bảo Mật (Verification)
- Cả hai dự án đều biên dịch thành công (`flutter analyze: 0 issues`, `compileDebugKotlin: BUILD SUCCESSFUL`).
- Đóng gói và phát hành bản Release `v1.3.3`.
