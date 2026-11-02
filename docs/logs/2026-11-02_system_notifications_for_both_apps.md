# 📋 Nhật Ký Thực Thi: Hiển Thị Thông Báo Vào Trung Tâm Thông Báo Hệ Thống (System Notification Center) Cho Cả 2 App

- **Ngày thực hiện**: 2026-11-02 11:05:00
- **Agent phụ trách**: `lead-architect`, `device-owner-specialist`, `parent-ui-specialist`, `usage-tracking-specialist`, `qa-security-perf-specialist`
- **Yêu cầu gốc**: "Lưu ý các mes thông báo tác động tới 2 app đều sẽ hiển thị vào trung tâm thông báo của thiết bị (dể không cần mở app cũng biết có thông báo tới)"
- **Trạng thái**: [🔄 Đang tiến hành]

---

## 1. Phân Tích & Kế Hoạch (Analysis & Planning)

### 1.1. Thực trạng hiện tại:
- **Admin App (`admin-node` - Flutter)**:
  - Chỉ sử dụng widget in-app banner `AppleNotification.show(context, ...)` hiển thị đè lên màn hình Compose/Flutter khi app đang mở.
  - Khi Phụ huynh thoát app ra màn hình chính (Home) hoặc khóa màn hình, các sự kiện như:
    - Bé xin thêm giờ (`TIME_REQUEST`)
    - Bé phản hồi xác nhận lời nhắc (`ACK_MESSAGE`)
    - Cảnh báo thiết bị
    ➡️ **Hoàn toàn KHÔNG hiển thị vào Thanh thông báo (Status Bar / Notification Center) của điện thoại Android**.
- **Child App (`target-node` - Android Kotlin)**:
  - Khi mở app: Hiển thị Dialog Compose `showRemoteMessageDialog`.
  - Khi app chạy ngầm: `UsageTrackingForegroundService` có `showRemoteMessageNotification`, nhưng chưa có PendingIntent mở app, thiếu Action Button trực tiếp trên notification, và các sự kiện như Duyệt giờ (`TIME_REQUEST_RESOLVED`), Thưởng/Phạt giờ (`ADJUST_TIME`), Khóa khẩn cấp (`PANIC_LOCKDOWN`) chỉ dùng `Toast.makeText` thay vì đẩy vào Trung tâm thông báo hệ thống.

### 1.2. Mục tiêu triển khai:
Tất cả các thông điệp tác động tới 2 ứng dụng bắt buộc phải đẩy vào **Trung tâm thông báo hệ thống của thiết bị** (System Notification Tray với Heads-up, âm thanh, rung):
1. **Đối với Admin App (`admin-node`)**:
   - Tích hợp `flutter_local_notifications`.
   - Cấu hình Notification Channel mức độ ưu tiên cao (`Importance.max`, `Priority.high`).
   - Khai báo và yêu cầu quyền `POST_NOTIFICATIONS` (Android 13+).
   - Đẩy thông báo hệ thống cho: Bé phản hồi tin nhắn (`ACK_MESSAGE`), Bé xin thêm giờ (`TIME_REQUEST`), Khóa khẩn cấp, v.v.
2. **Đối với Child App (`target-node`)**:
   - Xây dựng lớp chuyên trách `SystemNotificationHelper` chuẩn hóa việc tạo thông báo hệ thống với Channel `IMPORTANCE_HIGH`.
   - Tự động cấp quyền `POST_NOTIFICATIONS` ngầm thông qua đặc quyền Device Owner.
   - Thêm Action Button trực tiếp trên thanh thông báo: bé có thể bấm *"Dạ Con Nghe Rồi! 👍"* ngay từ thanh thông báo mà không cần mở app.
   - Đẩy thông báo hệ thống cho: Tin nhắn từ Ba Mẹ (`REMOTE_MESSAGE`), Kết quả duyệt xin giờ (`TIME_REQUEST_RESOLVED`), Thưởng/Phạt giờ (`ADJUST_TIME`), Khóa khẩn cấp (`PANIC_LOCKDOWN`), Cảnh báo còn 5 phút (`5_MIN_WARNING`).

---

## 2. Chi Tiết Các Bước Thực Hiện (Execution Steps)
*(Đang cập nhật...)*

## 3. Danh Sách Tệp Thay Đổi (Impacted Files)
*(Đang cập nhật...)*

## 4. Kiểm Thử & Đánh Giá Bảo Mật (Verification & Security Audit)
*(Đang cập nhật...)*

## 5. Kết Luận
*(Đang cập nhật...)*
