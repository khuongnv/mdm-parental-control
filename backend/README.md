# ☁️ Backend: Supabase BaaS & Real-Time Orchestrator

Hệ thống máy chủ điều phối trung tâm của giải pháp **MDM Parental Control**, được triển khai trên nền tảng **Supabase** (PostgreSQL 15+, Supabase Realtime Phoenix WebSockets, Row Level Security, Auth & Edge Functions).

> [!NOTE]
> Hệ thống sử dụng **Supabase BaaS** theo [EPIC 04: Thay Thế & Tối Ưu Backend Bằng Supabase](../docs/epics/EPIC_04_Supabase_Backend_Replacement.md) để đạt độ trễ thời gian thực < 100ms, kết hợp kênh **FCM HTTP v1** (Android + iOS APNs) khi ứng dụng ở nền hoặc đã đóng.

---

## 🎯 1. Năng Lực Cốt Lõi Trên Supabase
- **Kênh Điều Khiển Tức Thời (< 100ms)**: Sử dụng **Supabase Realtime Broadcast** trên kênh `device:{id}` và `postgres_changes` (`REPLICA IDENTITY FULL` trên `devices`, `device_messages`, `time_requests`, `daily_usage_summaries`, `daily_app_usage`).
- **Thông Báo Đẩy 2 Chiều (FCM HTTP v1 + iOS APNs)**:
  - `send-fcm-command`: Gửi lệnh điều khiển ưu tiên cao (data-only Android + silent APNs) từ Phụ huynh tới thiết bị con.
  - `notify-family-parents`: Gửi thông báo đẩy (`vfam_admin_alerts` Android + APNs `alert` iOS) tới tất cả phụ huynh trong gia đình (`parent_push_tokens`) khi bé xin thêm giờ (`TIME_REQUEST`) hoặc xác nhận/trả lời tin nhắn (`DEVICE_MESSAGE_ACK` / `DEVICE_MESSAGE_REPLY`), kèm khóa chống gửi trùng `fcm_notified_at` và tự động dọn token hết hạn (`UNREGISTERED`).
- **Thông Số Thiết Bị Mở Rộng (Extended Telemetry)**: Thu thập và đồng bộ pin, độ sáng màn hình, chế độ màn hình, chế độ tối, âm lượng (media/ring/notification/alarm) và trạng thái tắt tiếng thông qua `update_device_telemetry` (`COALESCE` an toàn cho payload từng phần) và `get_family_details`.
- **Đồng Bộ Thời Gian Sử Dụng Chính Xác (Usage Sync)**: Bảng `daily_app_usage`, cột `total_screen_time_seconds` / `app_breakdown` / `local_timezone` trên `daily_usage_summaries` và RPC `sync_device_daily_usage` theo ngày địa phương của thiết bị con (không bị lệch múi giờ UTC `CURRENT_DATE` hay làm tròn phút `/ 60`).

---

## 📂 2. Cấu Trúc Thư Mục Backend
```
backend/
├── README.md
├── tests/
│   ├── migration_contract.test.mjs              # Kiểm thử hợp đồng SQL migration R1/R2/R3
│   └── fcm_and_notify_parents.test.mjs          # Kiểm thử unit/integration cho _shared & Edge Functions
└── supabase/
    ├── .env.example                             # Mẫu biến môi trường & Firebase Secrets
    ├── functions/
    │   ├── _shared/
    │   │   ├── fcm.mjs                          # Web-standard ESM helpers (FCM HTTP v1, RS256 JWT, APNs)
    │   │   ├── fcm.d.ts
    │   │   ├── notify_parents.mjs               # Logic điều phối notify-family-parents & dedup
    │   │   └── notify_parents.d.ts
    │   ├── notify-family-parents/
    │   │   └── index.ts                         # Edge Function: Child -> Parent push notifications
    │   └── send-fcm-command/
    │       └── index.ts                         # Edge Function: Parent -> Child commands
    └── migrations/
        ├── 20261101_initial_schema.sql
        ├── 20261101_fix_claim_device_pairing.sql
        ├── 20261102_phase_2_business_logic_schema.sql
        ├── 20261102_fix_device_telemetry_and_grants.sql
        ├── 20261117_family_management_and_daily_reset.sql
        └── 20261120_notifications_telemetry_usage_sync.sql
```

---

## 🚀 3. Hướng Dẫn Triển Khai (Deployment)

### 3.1. Áp dụng Database Migrations
Chạy lần lượt các tệp trong `backend/supabase/migrations/` theo thứ tự thời gian trên **Supabase SQL Editor** (hoặc `supabase db push`):
1. `20261101_initial_schema.sql`
2. `20261101_fix_claim_device_pairing.sql`
3. `20261102_phase_2_business_logic_schema.sql`
4. `20261102_fix_device_telemetry_and_grants.sql`
5. `20261117_family_management_and_daily_reset.sql`
6. `20261120_notifications_telemetry_usage_sync.sql`

> [!TIP]
> Trigger `pg_net` (`notify_family_parents_via_pg_net`) hoạt động như kênh dự phòng phía DB. Để bật kênh này trên Supabase Cloud, có thể cấu hình `app.settings.supabase_url` & `app.settings.service_role_key` (hoặc lưu `supabase_url` / `service_role_key` trong Supabase Vault). Nếu chưa cấu hình, trigger sẽ bỏ qua an toàn mà không làm lỗi `INSERT`/`UPDATE`.

### 3.2. Cấu hình Secrets & Triển khai Edge Functions
```bash
# Cấu hình Firebase Service Account JSON cho FCM HTTP v1
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'

# Deploy các Edge Functions
supabase functions deploy send-fcm-command
supabase functions deploy notify-family-parents --no-verify-jwt
```
> [!IMPORTANT]
> `notify-family-parents` được gọi bởi `target-node` (dùng `anon` key) và trigger `pg_net` phía PostgreSQL; hàm tự xác thực `device_id` và thực hiện atomic claim `fcm_notified_at IS NULL` bằng `SUPABASE_SERVICE_ROLE_KEY`. Khi deploy, cần giữ `--no-verify-jwt` hoặc truyền `Authorization: Bearer <anon/service_role jwt>` hợp lệ.

---

## 🧪 4. Kiểm Thử Tự Động (Backend Tests)
Chạy bộ kiểm thử tự động trên Node.js 20+ (không cần cài đặt thêm package ngoài):
```bash
# Chạy trên tất cả nền tảng (Windows PowerShell, macOS, Linux)
node --test backend/tests

# Hoặc trên bash/zsh hỗ trợ glob
node --test backend/tests/*.test.mjs
```

---

## 📋 5. Đặc Tả Chi Tiết Epics
- [`docs/epics/EPIC_04_Supabase_Backend_Replacement.md`](../docs/epics/EPIC_04_Supabase_Backend_Replacement.md)
- [`docs/epics/backend_epics.md`](../docs/epics/backend_epics.md)
