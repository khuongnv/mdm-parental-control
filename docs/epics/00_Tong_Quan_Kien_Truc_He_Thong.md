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

## 3. Lộ Trình Phát Triển & Epics

### Giai Đoạn 1: Nền Tảng Cốt Lõi (Core MDM Foundations)
- [`EPIC_01_Device_Owner_Core_Agent.md`](./EPIC_01_Device_Owner_Core_Agent.md): Setup DO, Anti-Tampering, Zero-Bypass.
- [`EPIC_02_Usage_Tracking_Engine.md`](./EPIC_02_Usage_Tracking_Engine.md): UsageStatsManager, Service chạy ngầm pin thấp.
- [`EPIC_03_Policy_Enforcement_Blocking.md`](./EPIC_03_Policy_Enforcement_Blocking.md): setPackagesSuspended, setApplicationHidden.
- [`EPIC_04_Supabase_Backend_Replacement.md`](./EPIC_04_Supabase_Backend_Replacement.md): Chuyển đổi sang Supabase BaaS, Realtime Phoenix Channels.
- [`EPIC_05_Parent_App_Management_UI.md`](./EPIC_05_Parent_App_Management_UI.md): Giao diện Flutter và điều khiển tức thì.

### Giai Đoạn 2: Logic Nghiệp Vụ & Vận Hành Đa Thiết Bị (Phase 2 Business Logic)
- **Tổng quan kiến trúc Phase 2**: [`PHASE_2_EPICS_OVERVIEW.md`](./PHASE_2_EPICS_OVERVIEW.md)
- **Epics Admin Node (Flutter)**: [`PHASE_2_ADMIN_NODE_EPICS.md`](./PHASE_2_ADMIN_NODE_EPICS.md) (Quản lý đa thiết bị, đổi tên, telemetry trực tiếp, hủy quản lý, mời co-admin, quy tắc ngày/tuần auto-reset 2h, gửi tin nhắn nhắc nhở).
- **Epics Target Node (Android DO)**: [`PHASE_2_TARGET_NODE_EPICS.md`](./PHASE_2_TARGET_NODE_EPICS.md) (Thưởng/phạt động, xin thêm giờ, cảnh báo 5p + đếm ngược, đếm ngược TTL QR code 5p, local reset lúc 00:00).
- **Epics Backend (Supabase)**: [`PHASE_2_BACKEND_SUPABASE_EPICS.md`](./PHASE_2_BACKEND_SUPABASE_EPICS.md) (Lược đồ bảng mới, RPC procedures, Realtime broadcast protocol, phân quyền RLS).
