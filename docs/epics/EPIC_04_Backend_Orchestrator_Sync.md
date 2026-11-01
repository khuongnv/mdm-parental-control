# EPIC 04: Backend Server & Đồng bộ Điều phối Thời gian thực

## 1. Mục tiêu
Xây dựng trung tâm điều phối, xác thực, quản lý ghép nối thiết bị và duy trì kênh truyền tin điều khiển 2 chiều giữa máy Phụ huynh và máy Con.

## 2. Danh sách User Stories / Tasks chi tiết
- **US4.1: Quản lý Ghép nối Thiết bị (Device Pairing & Identity):**
  - API cấp phát mã ghép nối OTP / QR Token 1 lần để liên kết `ParentId` và `ChildDeviceId`.
  - Quản lý phiên làm việc, mã hóa token thiết bị (JWT / mTLS).
- **US4.2: Lưu trữ & Quản lý Chính sách (Rule & Policy Management API):**
  - CRUD lịch biểu sử dụng: Daily Quota, Weekend Quota, Bedtime schedule, Per-App rules.
  - Versioning chính sách để Agent tải về khi có thay đổi (E-Tag / Version Check).
- **US4.3: Kênh điều khiển Thời gian thực (Real-time Messaging Pipeline):**
  - Triển khai WebSocket / MQTT broker để đẩy lệnh khẩn cấp tức thời (Khóa tức thì, Mở thêm 15 phút).
  - Tích hợp Firebase Cloud Messaging (FCM) High-Priority Push làm kênh dự phòng đánh thức Agent.
- **US4.4: Ingestion & Thống kê Báo cáo Dữ liệu lớn (Data Ingestion & Aggregation):**
  - API nhận batch usage log từ Agent (5-15 phút/lần).
  - Tổng hợp số liệu theo giờ, ngày, tuần, tháng phục vụ dashboard phân tích.

## 3. Tiêu chí chấp nhận (Acceptance Criteria)
- Lệnh khóa từ Backend truyền xuống Agent thực thi trong vòng < 3 giây (khi có kết nối).
- Khả năng chịu tải và lưu trữ log đảm bảo toàn vẹn dữ liệu cho hàng ngàn thiết bị đồng thời.
