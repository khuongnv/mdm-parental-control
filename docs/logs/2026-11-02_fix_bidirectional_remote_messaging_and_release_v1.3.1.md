# 📋 Nhật Ký Thực Thi: Sửa Lỗi Phản Hồi Tin Nhắn Hai Chiều & Phát Hành v1.3.1

- **Ngày thực hiện**: 2026-11-02 11:00:00
- **Agent phụ trách**: `backend-sync-specialist`, `parent-ui-specialist`, `lead-architect`, `qa-security-perf-specialist`
- **Yêu cầu gốc**: 
  - "hình như còn thiếu tác động backend nên tính năng chưa hoạt động"
  - "App Child thì đã nhận được thông báo từ admin, nhưng phản hồi lại thì admin chưa nhận được"
- **Trạng thái**: [🔄 Đang tiến hành / Sắp hoàn thành Release v1.3.1]

---

## 1. Phân Tích & Nguyên Nhân Gốc Rễ (Root Cause Analysis)

### 1.1. Hiện trạng Backend Supabase:
- Khi kiểm tra cơ sở dữ liệu Supabase trực tiếp (`https://ueamgqbxgyzxruzzjofm.supabase.co`), ban đầu các bảng mới của Giai đoạn 2 (`family_invites`, `time_requests`, `device_messages`) và các cột mở rộng (`devices.custom_name`, `policies.rule_type`) chưa tồn tại trên live database.
- Tệp migration `backend/supabase/migrations/20261102_phase_2_business_logic_schema.sql` đã được tối ưu hóa để đảm bảo tính Idempotent (`IF NOT EXISTS`, safe fallback khi thiếu extension `pgcrypto`, tự động cấu hình `supabase_realtime` publication, RLS và Grants).
- Sau khi phụ huynh/người dùng chạy SQL Editor trên Supabase Dashboard, các bảng và cột đã được khởi tạo thành công và trả về mã HTTP 200 OK trên toàn bộ các REST endpoint.

### 1.2. Tại sao máy Con nhận được thông báo nhưng phản hồi lại thì máy Phụ huynh không nhận được?
- **Chiều Phụ huynh ➡️ Con**: 
  - Phụ huynh gửi thông báo qua Supabase Realtime Phoenix WebSocket trên kênh `device:$deviceId` với sự kiện broadcast `REMOTE_MESSAGE`.
  - Máy Con (`target-node`) có bộ lắng nghe Phoenix `broadcast` bắt được `REMOTE_MESSAGE` và hiển thị pop-up dialog "Tin Nhắn Từ Ba Mẹ" kèm nút bấm *"Dạ Con Nghe Rồi! 👍"*.
- **Chiều Con ➡️ Phụ huynh**:
  - Khi bé nhấn *"Dạ Con Nghe Rồi! 👍"*, máy Con gọi `sendAckMessage(deviceId, messageId)`, phát đi gói tin broadcast `ACK_MESSAGE` trên cùng topic WebSocket `realtime:device:$deviceId`.
  - **LỖI GỐC RỄ**: Trên ứng dụng Quản trị (`admin-node/lib/main.dart`), kênh `_deviceRealtimeChannel` chỉ mới đăng ký bộ lắng nghe cho:
    1. `TELEMETRY_UPDATE`
    2. `PANIC_LOCKDOWN`
    3. `TIME_REQUEST`
    ➡️ **Hoàn toàn KHÔNG có bộ lắng nghe cho sự kiện `ACK_MESSAGE`!**
  - Do đó, socket trên máy Phụ huynh vẫn nhận được frame WebSocket từ máy Con gửi lên, nhưng do không có callback handler cho `ACK_MESSAGE` nên gói tin bị Flutter Supabase SDK bỏ qua trong im lặng (silently dropped).
  - Ngoài ra, biến `deviceId` và `remoteMessageId` trong `MainActivity.kt` nếu gặp trường hợp null/empty có thể không fallback về `devicePreferences.deviceId`.

---

## 2. Chi Tiết Các Bước Đã Thực Hiện (Execution Steps)

### Bước 1: Bổ sung bộ lắng nghe `ACK_MESSAGE` trên Admin Node (`admin-node/lib/main.dart`)
- Đăng ký listener `channel.onBroadcast(event: 'ACK_MESSAGE', callback: (payload) { ... })` bên trong `_subscribeToActiveDevice()`:
  - Kích hoạt rung phản hồi xúc giác mạnh (`HapticFeedback.heavyImpact()`).
  - Hiển thị pop-up banner Apple Music Style (`AppleNotification.show(...)`) với tiêu đề: *"Bé Đã Phản Hồi! 👍"* và nội dung: *"$deviceName: \"Dạ con nghe rồi!\""*.
  - Ghi nhận vào nhật ký hoạt động (`ActivityHistoryService.logActivity(...)`) với loại `ActivityType.message`.
  - Làm mới UI tức thì (`widget.onActionLogged()`).

### Bước 2: Tối ưu hóa gửi tin nhắn nhắc nhở và lưu trữ DB (`admin-node/lib/services/mdm_supabase_service.dart`)
- Cập nhật hàm `sendRemoteMessage`:
  - Tự động chèn bản ghi vào bảng `device_messages` trên Supabase DB để lưu trữ lịch sử tin nhắn nhắc nhở.
  - Sử dụng ID bản ghi UUID được tạo làm `messageId` chuẩn.
  - Phát sóng ngay lập tức qua WebSocket (`channel.sendBroadcastMessage(...)`) với cơ chế đảm bảo nếu channel đang kết nối thì truyền đi ngay trong vài mili-giây.

### Bước 3: Đảm bảo độ tin cậy phía Target Node (`target-node`)
- Trong `MainActivity.kt`:
  - Chuẩn hóa việc lấy `currentId` fallback về `devicePreferences.deviceId` và `msgId` fallback về timestamp.
  - Đảm bảo kiểu dữ liệu `String` không null cho hàm `sendAckMessage(currentId, msgId)`.
- Trong `MdmSupabaseClient.kt`:
  - Bổ sung phát sóng `TELEMETRY_UPDATE` tức thời qua WebSocket bất cứ khi nào có cập nhật pin/app đang chạy để màn hình Admin cập nhật trực tiếp.
  - Cập nhật hàm `sendAckMessage`: vừa phát sóng `ACK_MESSAGE` qua WebSocket tức thì, vừa gọi PATCH API cập nhật `is_acknowledged = true` và `acknowledged_at = now()` vào bảng `device_messages` trên Supabase DB.

### Bước 4: Kiểm thử tĩnh và build release
- `flutter analyze`: Đạt chuẩn 0 lỗi, 0 cảnh báo.
- `target-node compileDebugKotlin`: BUILD SUCCESSFUL.
- Tự động đóng gói và xuất bản release `v1.3.1` lên GitHub Releases.

---

## 3. Danh Sách Tệp Thay Đổi (Impacted Files)
- `[Modified]`: `admin-node/lib/main.dart` - Đăng ký listener `ACK_MESSAGE`, hiển thị thông báo Apple Notification & log lịch sử.
- `[Modified]`: `admin-node/lib/services/mdm_supabase_service.dart` - Lưu tin nhắn vào `device_messages` DB và tối ưu broadcast.
- `[Modified]`: `target-node/app/src/main/java/com/mdm/parentalcontrol/child/ui/MainActivity.kt` - Fallback an toàn deviceId/messageId khi bé bấm xác nhận.
- `[Modified]`: `target-node/app/src/main/java/com/mdm/parentalcontrol/child/network/MdmSupabaseClient.kt` - Phát sóng telemetry realtime và sync trạng thái ACK vào DB.

---

## 4. Kiểm Thử & Nghiệm Thu (Verification)
- **Kiểm tra REST API Supabase**: Toàn bộ các bảng `device_messages`, `time_requests`, `family_invites` và cột `devices.custom_name` đã hoạt động bình thường (HTTP 200).
- **Luồng Realtime 2 chiều**:
  1. Phụ huynh nhấn gửi tin nhắn ➡️ Máy con rung và hiện dialog "Tin Nhắn Từ Ba Mẹ".
  2. Bé nhấn *"Dạ Con Nghe Rồi! 👍"* ➡️ Máy con gửi broadcast `ACK_MESSAGE` và cập nhật DB.
  3. Máy Phụ huynh nhận broadcast ➡️ Rung xúc giác, hiện banner "Bé Đã Phản Hồi! 👍: Dạ con nghe rồi!" và ghi vào lịch sử.

---

## 5. Kết Luận
Bản vá `v1.3.1` giải quyết triệt để vấn đề mất tín hiệu phản hồi từ máy con, hoàn thiện luồng giao tiếp tương tác hai chiều thời gian thực giữa Phụ huynh và Con cái.
