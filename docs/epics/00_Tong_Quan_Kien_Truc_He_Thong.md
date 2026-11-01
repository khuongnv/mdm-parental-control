# TÀI LIỆU DỰ ÁN: HỆ THỐNG GIÁM SÁT & QUẢN LÝ THIẾT BỊ ANDROID (PARENTAL CONTROL / MDM)

## 1. Giới thiệu tổng quan
Hệ thống giám sát và quản lý thiết bị Android cấp độ doanh nghiệp/MDM (Mobile Device Management) nhằm khắc phục hoàn toàn các nhược điểm của các ứng dụng quản lý người dùng thông thường (dễ bị bypass, force stop, tắt quyền Accessibility, gỡ cài đặt hoặc reboot vào Safe Mode).
Hệ thống sử dụng đặc quyền **Android Device Owner (DO)** để áp đặt chính sách hệ thống tuyệt đối.

## 2. Mô hình kiến trúc 3 thành phần
1. **Target Agent (Child Device Owner App):**
   - Viết bằng Kotlin / Android Native.
   - Nắm quyền Device Owner (kích hoạt qua ADB hoặc Provisioning QR Code).
   - Đọc và phân tích `UsageStatsManager` (chính xác đến từng mili-giây qua `UsageEvents`).
   - Thực thi chính sách khóa/mở bằng `setPackagesSuspended` (icon xám, chặn native tầng HĐH) hoặc `setApplicationHidden`.
   - Vô hiệu hóa Safe Boot, Factory Reset, Debugging và gỡ cài đặt.
2. **Backend Server (Điều phối trung tâm):**
   - Quản lý định danh, pairing (ghép nối QR/OTP giữa Bố và Con).
   - Lưu trữ rule, quota, time-windows (theo ngày, cuối tuần, bedtime).
   - Xử lý đồng bộ dữ liệu thời gian thực (WebSockets / MQTT) và High-Priority Push Notification (FCM).
3. **Parent App (Ứng dụng quản trị viên):**
   - Dashboard trực quan hóa dữ liệu sử dụng màn hình theo thời gian thực.
   - Cấu hình rule chặn/mở, bedtime, blacklist/whitelist.
   - Nút can thiệp tức thì (Khóa khẩn cấp / Mở thêm giờ).

---
