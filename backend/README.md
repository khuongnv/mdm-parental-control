# ☁️ Backend: Central Orchestrator & Real-Time Pipeline (.NET Core)

Máy chủ điều phối trung tâm của hệ thống **MDM Parental Control**, được xây dựng trên nền tảng **ASP.NET Core (.NET 8 / .NET 9)** hiệu năng cao, chịu trách nhiệm quản lý định danh, bảo mật phiên kết nối, duy trì đường truyền điều khiển 2 chiều thời gian thực và xử lý khối lượng lớn dữ liệu telemetry thời gian sử dụng.

---

## 🎯 1. Vai Trò & Trách Nhiệm Chính
- **Định Danh & Ghép Nối 1 Bước (Pairing & Auth)**: Quản lý tài khoản phụ huynh, sinh mã OTP/QR Token 1 lần (TTL 5 phút) để ghép nối an toàn với máy con, cấp phát JWT/mTLS token mã hóa định danh.
- **Quản Lý & Phân Phối Chính Sách (Policy Engine)**: Lưu trữ lịch biểu hạn mức sử dụng (Daily Quota, Bedtime, App Rules), kiểm tra phiên bản ETag differential sync để giảm thiểu băng thông.
- **Kênh Điều Khiển Thời Gian Thực (< 3s)**: **ASP.NET Core SignalR Hubs** (hoặc WebSockets/MQTTnet) kết hợp **Redis Backplane (`StackExchange.Redis`)** để đẩy tức thì các lệnh khẩn cấp (Panic Lockdown, Thưởng thêm +15m).
- **Kênh Dự Phòng FCM**: Tích hợp `FirebaseAdmin` .NET SDK chính chủ từ Google để gửi FCM High-Priority Data Push đánh thức máy con khi socket bị ngắt.
- **Ingestion & Tổng Hợp Dữ Liệu Lớn**: Cổng tiếp nhận batch usage logs định kỳ 15 phút, sử dụng `System.Threading.Channels` và `BackgroundService` để xử lý bất đồng bộ không làm nghẽn HTTP thread pool; tổng hợp time-series theo giờ/ngày/tuần/tháng cho Parent Dashboard.

---

## 🛠️ 2. Kiến Trúc & Công Nghệ Chuẩn Hóa (.NET Core Stack)
- **Framework**: ASP.NET Core Web API (.NET 8 LTS / .NET 9).
- **Kiến trúc**: Clean Architecture + CQRS với MediatR.
- **Real-time Engine**: **ASP.NET Core SignalR** (hỗ trợ JSON & MessagePack binary protocol) + Redis Backplane (`Microsoft.AspNetCore.SignalR.StackExchangeRedis`).
- **Cơ sở dữ liệu**:
  - **PostgreSQL** kết hợp **EF Core 8** (Npgsql) cho dữ liệu quan hệ (Users, Devices, Policies, Audit Logs).
  - **Dapper** cho các truy vấn báo cáo thời gian sử dụng và dashboard siêu tốc.
  - **Redis** cho Caching, Session Token (mã ghép nối OTP/QR) và SignalR scale-out.
- **Hàng đợi & Tác vụ ngầm**: `System.Threading.Channels` cho Ingestion Pipeline; **Hangfire** hoặc `IHostedService` cho cron job tổng hợp báo cáo và reset quota ngày lúc 00:00:00.
- **Bảo mật**: ASP.NET Core Identity + JWT Bearer Authentication, Rate Limiting Middleware (`System.Threading.RateLimiting`).

---

## 📋 3. Danh Sách Epics Chi Tiết
Xem tài liệu đặc tả đầy đủ tại: [`docs/epics/backend_epics.md`](../docs/epics/backend_epics.md)
- **B-EPIC 01**: Quản Lý Định Danh, Xác Thực & Ghép Nối Thiết Bị (Identity & Pairing Engine).
- **B-EPIC 02**: Quản Trị & Đồng Bộ Chính Sách (Rule & Policy Management Engine).
- **B-EPIC 03**: Đường Truyền Thời Gian Thực Siêu Tốc & Dự Phòng FCM (Real-Time Pipeline).
- **B-EPIC 04**: Ingestion Pipeline & Thống Kê Báo Cáo Dữ Liệu Lớn (Telemetry & Analytics).
- **B-EPIC 05**: An Ninh Doanh Nghiệp, Kiểm Toán & Giới Hạn Tần Suất (Enterprise Security).
