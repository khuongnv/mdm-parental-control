# 📋 Nhật Ký Thực Thi: Khắc Phục Mất Tương Tác Khi Khóa Màn Hình & Hoàn Thiện Kênh Firebase FCM

- **Ngày thực hiện**: 2026-11-02 11:35:00
- **Agent phụ trách**: `lead-architect`, `backend-sync-specialist`, `device-owner-specialist`, `usage-tracking-specialist`, `parent-ui-specialist`, `qa-security-perf-specialist`
- **Yêu cầu gốc**: "Có vẻ cả 2 app sau khi khóa màn hình sau đấy thì không còn nhận được tương tác với nhau nữa? Tôi nghi ngờ chỗ gửi firebase tin có vấn đề."
- **Trạng thái**: [🔄 Đang tiến hành]

---

## 1. Phân Tích & Nguyên Nhân Gốc Rễ (Root Cause Analysis)

### 1.1. Lỗ hổng về phía Firebase Cloud Messaging (FCM):
1. **Supabase RLS chặn `fcm_token` của máy con**:
   - Bảng `devices` trên Supabase chỉ có policy UPDATE cho `public.is_member_of_family(family_id)` (yêu cầu JWT phụ huynh `auth.uid()`).
   - Máy con dùng `anonKey` gửi `PATCH /rest/v1/devices?id=eq.$deviceId` cập nhật `fcm_token` bị RLS chặn âm thầm (0 rows affected).
   - Truy vấn trực tiếp database cho thấy **100% thiết bị đều có `fcm_token: null`**!
2. **App Phụ huynh (`admin-node`) chưa từng gọi gửi bản tin FCM**:
   - Khi phụ huynh thực hiện Khóa khẩn cấp, Thưởng giờ hay Gửi tin nhắn, mã nguồn trong `mdm_supabase_service.dart` chỉ phát sóng qua Supabase WebSocket `channel.sendBroadcastMessage()`.
   - Hoàn toàn chưa có mã nguồn gọi Edge Function `send-fcm-command` hay gửi FCM Push!
3. **Edge Function `send-fcm-command` chưa được deploy**:
   - Kiểm tra endpoint `https://ueamgqbxgyzxruzzjofm.supabase.co/functions/v1/send-fcm-command` trả về HTTP 404 NOT_FOUND do chưa deploy và chưa cấu hình secret `FIREBASE_SERVICE_ACCOUNT_JSON`.
4. **Máy con thiếu bộ nhận `REMOTE_MESSAGE` trong `MdmFirebaseMessagingService`**:
   - `MdmFirebaseMessagingService.kt` chỉ có case cho `PANIC_LOCKDOWN` và `GRANT_EXTRA_TIME`, thiếu hoàn toàn `REMOTE_MESSAGE`, `ADJUST_TIME` và `TIME_REQUEST_RESOLVED`.

### 1.2. Lỗ hổng về kết nối khi Khóa màn hình (Screen OFF / Doze Mode):
1. **Phía Máy Con (`target-node`)**:
   - Khi màn hình tắt (`ACTION_SCREEN_OFF`), `UsageTrackingForegroundService` gọi `stopAdaptivePolling()`.
   - Service không giữ `PARTIAL_WAKE_LOCK` và chưa xin miễn trừ tối ưu hóa pin (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`). Sau một khoảng thời gian ngắn tắt màn hình, Android đưa CPU vào Deep Sleep (Doze Mode), ngắt kết nối TCP của WebSocket.
   - Khi `MainActivity` mở, nó gọi `connectRealtime()`, ngắt kết nối của `UsageTrackingForegroundService`. Khi khóa màn hình, `MainActivity` bị pause/stop nhưng Service không khôi phục lại kết nối.
2. **Phía Máy Phụ Huynh (`admin-node`)**:
   - Ứng dụng Flutter không có Background Service chạy ngầm.
   - Khi phụ huynh khóa màn hình, Android lập tức đóng băng (freeze) Flutter Engine và đình chỉ socket mạng.
   - Khi máy con gửi phản hồi ACK hay yêu cầu xin giờ, máy phụ huynh đang khóa màn hình nên không nhận được cho đến khi bật sáng màn hình và mở app.

---

## 2. Kế Hoạch Khắc Phục (Action Plan)

### Bước 1: Khắc phục triệt để kết nối chạy ngầm khi Khóa màn hình trên Máy Con (`target-node`)
- Bổ sung `PowerManager.WakeLock` (`PARTIAL_WAKE_LOCK`) trong `UsageTrackingForegroundService`.
- Tự động miễn trừ tối ưu hóa pin (Battery Optimization Exemption) thông qua Device Owner.
- Chuyển `UsageTrackingForegroundService` thành đơn vị duy nhất quản lý WebSocket Realtime. `MainActivity` chỉ đăng ký lắng nghe sự kiện từ Service, không được phép ngắt kết nối của Service.
- Bổ sung xử lý đầy đủ các action (`REMOTE_MESSAGE`, `ADJUST_TIME`, v.v.) trong `MdmFirebaseMessagingService.kt`.

### Bước 2: Khắc phục Supabase Database RLS & Lưu trữ `fcm_token`
- Tạo Migration / Stored Procedure `update_device_telemetry` và policy `Agents can update telemetry and fcm_token` cho phép cập nhật `fcm_token`, `battery_level`, `current_app` bằng `anonKey`.

### Bước 3: Duy trì kết nối chạy ngầm khi Khóa màn hình trên Máy Phụ Huynh (`admin-node`)
- Sử dụng Foreground Service hoặc cơ chế giữ kết nối ngầm cho Flutter (`flutter_foreground_task` hoặc native Android Service) để duy trì socket liên tục ngay cả khi phụ huynh khóa màn hình.

---
*(Đang triển khai...)*
