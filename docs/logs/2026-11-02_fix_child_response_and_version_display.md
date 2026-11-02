# 📋 Nhật Ký Thực Thi: Khắc Phục Lỗi Phản Hồi Từ Máy Con & Đồng Bộ Phiên Bản App (v1.3.4)

- **Ngày thực hiện**: 2026-11-02 12:40:00
- **Agent phụ trách**: `lead-architect`, `device-owner-specialist`, `backend-sync-specialist`, `qa-security-perf-specialist`
- **Yêu cầu gốc**: "chid phản hồi có vấn đề, version app child cũng hiển thị chưa đúng"
- **Trạng thái**: 🔄 Đang tiến hành

---

## 1. Phân Tích & Kế Hoạch (Analysis & Planning)
### Vấn đề 1: Version app child hiển thị chưa đúng
- Trong `MainActivity.kt`, biến `currentAppVersion` bị gán cứng là `"1.2.4"`, chuỗi hiển thị là `"Phiên bản 1.2.4 (Build 6) • GitHub Release"`.
- Trong `target-node/app/build.gradle.kts`, `versionName` vẫn là `"1.3.0"`, `versionCode = 8`.
- Trong `admin-node/pubspec.yaml`, `version: 1.3.0+8`.
- Trong `MdmSupabaseClient.kt`, `p_agent_version` gửi lên Supabase bị gán cứng `"1.0.0"`, hàm `updateTelemetry` không gửi `agent_version`.
- Khi đóng gói phát hành qua `deploy.ps1`, file kịch bản chỉ đổi tên artifact đầu ra `vfam-child-$Version.apk` mà không đồng bộ ngược lại vào `build.gradle.kts` và `pubspec.yaml`.

### Vấn đề 2: Phản hồi từ máy con có vấn đề (Child ACK & Time Request không tới Admin)
- **Cấu trúc lồng gói tin Broadcast (Payload nesting mismatch)**: OkHttp trong `MdmSupabaseClient.sendBroadcast` bọc thêm một tầng `"payload"` nữa trong `"payload"`. Kết quả là `admin-node` khi đọc `payload['requested_minutes']` hay `payload['message_id']` nhận giá trị null hoặc không trigger đúng.
- **Vòng đời BroadcastReceiver bị hủy sớm (`NotificationActionReceiver`)**: Khi bé nhấn nút "Dạ Con Nghe Rồi! 👍" trên khay thông báo hệ thống, `NotificationActionReceiver.onReceive()` kết thúc ngay lập tức mà không gọi `goAsync()`. Android OS thu hồi tiến trình khiến các yêu cầu OkHttp bất đồng bộ bị hủy trước khi kịp gửi tới Supabase.
- **Kênh truyền nhận 1 chiều đơn lẻ**: Admin chỉ lắng nghe duy nhất `channel.onBroadcast(event: 'ACK_MESSAGE')`. Nếu máy Admin tắt màn hình, rớt mạng tạm thời hoặc kết nối lại socket đúng thời điểm bé bấm, bản tin broadcast bị mất vĩnh viễn vì WebSocket broadcast là ephemeral (không lưu trữ).
- **MainActivity thiếu `onNewIntent`**: Khi bé nhấn vào thân thông báo tin nhắn trong lúc app con đang chạy nền, Activity không cập nhật Intent mới chứa `SHOW_REMOTE_MESSAGE_ID`.
- **Yêu cầu xin thêm giờ (`sendTimeRequest`) chỉ gửi socket**: Chưa ghi nhận bản ghi vào bảng `time_requests` qua REST API để phụ huynh có thể duyệt offline hoặc qua Postgres Realtime.

---

## 2. Kế Hoạch Chi Tiết Các Bước
- [x] **Bước 1**: Cập nhật `build.gradle.kts` (v1.3.4, build 9) và `pubspec.yaml` (v1.3.4+9). Cập nhật `deploy.ps1` tự động đồng bộ version vào file cấu hình trước khi build.
- [ ] **Bước 2**: Sửa `MainActivity.kt` sử dụng `BuildConfig.VERSION_NAME` và `BuildConfig.VERSION_CODE`, bổ sung override `onNewIntent`.
- [ ] **Bước 3**: Cập nhật `MdmSupabaseClient.kt`:
  - Phẳng hóa cấu trúc Broadcast payload (vừa có top-level keys vừa giữ nested `payload` tương thích ngược).
  - Gửi `agent_version` động trong `createPairingSession` và `updateTelemetry`.
  - Cải tiến `sendAckMessage`: vừa broadcast, vừa PATCH bảng `device_messages` (hỗ trợ cả UUID lẫn fallback device_id).
  - Cải tiến `sendTimeRequest`: vừa broadcast, vừa POST vào bảng `time_requests`.
- [ ] **Bước 4**: Cải tiến `NotificationActionReceiver.kt`: Sử dụng `goAsync()` và giữ `WakeLock` tạm thời đảm bảo gửi ACK thành công 100% từ khay thông báo kể cả khi màn hình khóa.
- [ ] **Bước 5**: Cải tiến `admin-node`:
  - Trong `_subscribeToActiveDevice`: Đăng ký đa kênh lắng nghe (Broadcast `ACK_MESSAGE` + `postgres_changes` trên bảng `device_messages` + `postgres_changes` trên bảng `time_requests`).
  - Hỗ trợ unwrap an toàn payload lồng nhau trong `_showTimeRequestDialog` và các event listener.
  - Hiển thị phiên bản app máy con (`agent_version`) trên thẻ thiết bị con.
  - Mở rộng Edge Function `send-fcm-command` cho các action tin nhắn và duyệt giờ.
- [ ] **Bước 6**: Kiểm thử compile, phân tích mã nguồn (`flutter analyze`, Gradle build).
- [ ] **Bước 7**: Build và phát hành bản phát hành v1.3.4 lên GitHub Releases.
