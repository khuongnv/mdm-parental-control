# ☁️ Backend: Supabase BaaS & Real-Time Orchestrator

Hệ thống máy chủ điều phối trung tâm của giải pháp **MDM Parental Control**, được triển khai trên nền tảng **Supabase** (PostgreSQL 15+, Supabase Realtime Phoenix WebSockets, Row Level Security, Auth & Edge Functions).

> [!NOTE]
> Hệ thống đã được chuyển đổi từ mô hình tự vận hành Web API sang **Supabase BaaS** theo [EPIC 04: Thay Thế & Tối Ưu Backend Bằng Supabase](../docs/epics/EPIC_04_Supabase_Backend_Replacement.md) để đạt độ trễ thời gian thực < 100ms, loại bỏ chi phí quản lý máy chủ và tận dụng trực tiếp tính năng reactive của `supabase_flutter`.

---

## 🎯 1. Năng Lực Cốt Lõi Trên Supabase
- **Kênh Điều Khiển Tức Thời (< 100ms)**: Sử dụng **Supabase Realtime Broadcast** trên kênh `device:{id}` để gửi lệnh Khóa Khẩn Cấp (`PANIC_LOCKDOWN`) và Thưởng Giờ (`GRANT_EXTRA_TIME`) tới máy con mà không cần qua hàng đợi HTTP.
- **Theo Dõi Trạng Thái Trực Tuyến Tự Động (Presence)**: Supabase Presence tự động phát hiện thiết bị con Online hay Offline dựa trên trạng thái kết nối socket mà không cần lập trình Redis heartbeat thủ công.
- **Bảo Mật Đa Tầng Cấp Cơ Sở Dữ Liệu (Postgres RLS)**: Toàn bộ bảng dữ liệu (`devices`, `families`, `policies`, `app_rules`, `daily_usage_summaries`) được bảo vệ bằng Row Level Security (RLS) để cô lập dữ liệu giữa các gia đình.
- **Ghép Nối OTP 1 Lần Trong 1 Bước**: Stored Procedure `create_device_pairing` và `claim_device_pairing` xử lý trọn gói việc tạo mã OTP 6 số (TTL 5 phút), xác thực và liên kết thiết bị vào gia đình an toàn.
- **Tổng Hợp Telemetry Tự Động**: Stored Procedure `aggregate_device_daily_usage` gom nhóm thời gian On-Screen theo từng danh mục (Học tập, Game, Mạng xã hội, Giải trí) phục vụ biểu đồ Dashboard của phụ huynh.

---

## 📂 2. Cấu Trúc Thư Mục Backend
```
backend/
├── supabase/
│   ├── .env                      # Credentials & Service Role Key (Git-ignored)
│   └── migrations/
│       └── 20261101_initial_schema.sql  # Toàn bộ Schema, Indexes, RLS Policies, RPCs & Realtime Publication
│
└── [Legacy] .NET Core 8 Solution # Kiến trúc Web API cũ (Lưu trữ tham khảo)
    ├── MdmParentalControl.sln
    ├── Mdm.Backend.Api/
    ├── Mdm.Backend.Core/
    └── Mdm.Backend.Infrastructure/
```

---

## 🚀 3. Hướng Dẫn Triển Khai (Deployment)
1. Đăng nhập vào [Supabase Dashboard](https://supabase.com/dashboard) của dự án (`ueamgqbxgyzxruzzjofm`).
2. Mở mục **SQL Editor**.
3. Dán nội dung tệp [`backend/supabase/migrations/20261101_initial_schema.sql`](./supabase/migrations/20261101_initial_schema.sql) và bấm **Run**.
4. Toàn bộ bảng, chính sách RLS, hàm RPC và Realtime Publication sẽ được kích hoạt tức thì.

---

## 📋 4. Đặc Tả Chi Tiết Epics
Xem tài liệu kiến trúc chuyển đổi chi tiết tại:
- [`docs/epics/EPIC_04_Supabase_Backend_Replacement.md`](../docs/epics/EPIC_04_Supabase_Backend_Replacement.md)
- [`docs/epics/backend_epics.md`](../docs/epics/backend_epics.md)
