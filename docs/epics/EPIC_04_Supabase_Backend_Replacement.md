# ⚡ EPIC 04: Thay Thế & Tối Ưu Backend Bằng Supabase (BaaS & Realtime Pipeline)

- **Mã Epic**: `EPIC-BACKEND-SUPABASE` (Thay thế cho kiến trúc ASP.NET Core + Redis truyền thống)
- **Nền tảng công nghệ**: **Supabase** (PostgreSQL 15+, Supabase Realtime, Supabase Auth, Supabase Edge Functions / Deno)
- **Agent phụ trách**: `lead-architect` & `backend-sync-specialist`
- **Các node liên quan**: `admin-node` (Flutter), `target-node` (Android Device Owner)
- **Mục tiêu**: Đơn giản hóa kiến trúc, loại bỏ chi phí vận hành máy chủ phức tạp, tăng tốc độ phát triển và tận dụng tối đa thế mạnh Realtime của Supabase cùng SDK `supabase_flutter` cho ứng dụng Phụ huynh.

---

## 🎯 1. Bối Cảnh & Mục Tiêu Chuyển Đổi (Why Supabase?)

Hệ thống MDM Parental Control đòi hỏi 4 năng lực máy chủ cốt lõi:
1. **Kênh điều khiển tức thì (< 3s)**: Khóa khẩn cấp toàn máy, mở thưởng +15m.
2. **Cập nhật trạng thái kết nối liên tục**: Nhận biết máy con đang Online hay Offline.
3. **Phân quyền dữ liệu nghiêm ngặt**: Phụ huynh chỉ quản lý thiết bị con của gia đình mình.
4. **Thu thập dữ liệu sử dụng định kỳ**: Nhận batch logs từ máy con mà không làm sập hệ thống.

Việc tự vận hành Web API + SignalR Hub + Redis Backplane + PostgreSQL đòi hỏi hạ tầng phức tạp. Chuyển sang **Supabase** giải quyết triệt để vấn đề này:
- **Supabase Realtime Broadcast**: Đẩy lệnh điều khiển tức thời với độ trễ < 100ms.
- **Supabase Realtime Presence**: Tự động theo dõi trạng thái Online/Offline của thiết bị con không cần viết Redis heartbeat.
- **Postgres Row Level Security (RLS)**: Bảo mật dữ liệu nhiều gia đình (Multi-tenancy) ngay ở tầng cơ sở dữ liệu.
- **Tích hợp Flutter First-Class**: `supabase_flutter` hỗ trợ reactive streams (`StreamBuilder`) cực kỳ mượt mà.

---

## 🏛️ 2. Kiến Trúc Hệ Thống Với Supabase

```mermaid
flowchart TD
    subgraph ParentApp["Admin App (Flutter)"]
        P_Auth["Supabase Auth (Email / Google)"]
        P_UI["Dashboard & Remote Controls"]
        P_Stream["Realtime Subscriptions"]
    end

    subgraph SupabaseCore["Hạ Tầng Supabase (Cloud / Self-Hosted)"]
        subgraph RealtimeEngine["Supabase Realtime (WebSockets)"]
            RT_Broadcast["Broadcast Channel (device:{id})"]
            RT_Presence["Presence Tracker (Online/Offline)"]
            RT_CDC["Postgres Changes (Policies Update)"]
        end

        subgraph DB["PostgreSQL 15+"]
            RLS["Row Level Security (RLS)"]
            T_Family["Bảng families & members"]
            T_Devices["Bảng devices"]
            T_Policies["Bảng policies & app_rules"]
            T_Logs["Bảng app_usage_logs (Partitioned)"]
            T_Summary["Bảng daily_usage_summaries"]
        end

        subgraph EdgeCompute["Supabase Edge Functions (Deno / TS)"]
            EF_Pairing["fn: pairing-handshake (OTP)"]
            EF_FCM["fn: send-fcm-push (Fallback)"]
            EF_Aggregator["fn: aggregate-daily-usage"]
        end
    end

    subgraph ChildApp["Target Agent (Android Device Owner)"]
        C_DO["DevicePolicyManager & Suspender"]
        C_Tracker["UsageStats Engine & Room DB"]
        C_Client["Supabase Realtime Client & Worker"]
        C_FCM["FCM High-Priority Push Receiver"]
    end

    %% Parent Interactions
    P_Auth --> DB
    P_UI -- "1. Bấm Khóa / Thưởng giờ" --> RT_Broadcast
    P_Stream <-- "Lắng nghe Presence & Policy" --- RealtimeEngine
    P_UI -- "Cập nhật Hạn mức / Giờ ngủ" --> T_Policies

    %% Child Interactions
    RT_Broadcast -- "Nhận lệnh tức thì (< 100ms)" --> C_Client
    C_Client -- "Báo cáo trạng thái sống" --> RT_Presence
    C_DO <-- "Thực thi khóa/mở app native" --- C_Client
    C_Tracker -- "Gửi batch log (15 phút/lần)" --> T_Logs

    %% FCM Fallback Flow
    RT_Broadcast -. "Nếu Target Agent Offline" .-> EF_FCM
    EF_FCM -- "FCM High-Priority Push" --> C_FCM
    C_FCM -- "Đánh thức Service" --> C_DO

    %% Pairing Flow
    C_Client -- "Tạo mã ghép nối" --> EF_Pairing
    P_UI -- "Quét QR / Nhập OTP" --> EF_Pairing
```

---

## 📋 3. Danh Sách Sub-Epics & Nhiệm Vụ Kỹ Thuật Chi Tiết

### 🗄️ SUB-EPIC 01: Thiết Kế Database Schema & Row Level Security (RLS)
*Mục tiêu: Xây dựng cấu trúc quan hệ chuẩn xác, phân quyền đa người dùng chống truy cập chéo giữa các gia đình.*

- [ ] **Task 1.1: Tạo Schema Core Identity & Family**
  - Bảng `families (id, name, created_at, created_by)`.
  - Bảng `family_members (id, family_id, user_id, role, joined_at)`: Quản lý quyền Phụ huynh chính (Owner) hoặc Đồng quản lý (Member).
- [ ] **Task 1.2: Tạo Schema Thiết Bị Con & Ghép Nối**
  - Bảng `devices (id, family_id, device_name, model, os_version, agent_version, is_locked, extra_time_minutes, status, last_seen_at)`.
  - Bảng `pairing_sessions (id, device_id, otp_code, qr_token, expires_at, is_claimed)`.
- [ ] **Task 1.3: Tạo Schema Chính Sách & Hạn Mức Sử Dụng**
  - Bảng `policies (id, device_id, daily_screen_time_limit_mins, bedtime_start, bedtime_end, is_bedtime_enabled, version, updated_at)`.
  - Bảng `app_rules (id, policy_id, package_name, app_name, app_category, is_blocked, daily_limit_mins)`.
- [ ] **Task 1.4: Tạo Schema Dữ Liệu Báo Cáo & Telemetry (Big Data Safe)**
  - Bảng `app_usage_logs (id, device_id, package_name, app_category, duration_seconds, session_date, created_at)`:
    - *Lưu ý*: Partitioning theo tháng, **tuyệt đối không bật Supabase Realtime** trên bảng này để bảo vệ tài nguyên WAL.
  - Bảng `daily_usage_summaries (id, device_id, summary_date, total_screen_time_mins, breakdown_json, updated_at)`.
- [ ] **Task 1.5: Thiết lập Chính sách Row Level Security (RLS)**
  - Chỉ cho phép User thuộc `family_id` mới được `SELECT/INSERT/UPDATE` dữ liệu của thiết bị thuộc gia đình đó.
  - Cung cấp Service Role Key hoặc Custom RPC bảo mật cho Agent ghi logs.

---

### 🤝 SUB-EPIC 02: Luồng Ghép Nối Thiết Bị An Toàn Bằng OTP / QR 1 Lần
*Mục tiêu: Đơn giản hóa quy trình ghép nối máy Con vào máy Bố, hoàn tất trong 1 bước với độ bảo mật tối đa.*

- [ ] **Task 2.1: Supabase Edge Function: `create-pairing-session`**
  - Máy con (khi mới cài đặt) gọi Function: Sinh mã OTP ngẫu nhiên 6 chữ số và chuỗi token QR bí mật (TTL = 5 phút).
  - Trả về mã OTP hiển thị trên màn hình máy con.
- [ ] **Task 2.2: Supabase Edge Function: `claim-pairing-session`**
  - Phụ huynh quét QR hoặc nhập mã OTP trên Flutter App.
  - Function kiểm tra:
    - OTP còn hiệu lực (< 5 phút) và chưa bị claim.
    - Cập nhật `device_id` vào `family_id` của Phụ huynh đang đăng nhập.
    - Đánh dấu `is_claimed = true`.
  - Trả về `device_auth_token` cho thiết bị con để duy trì phiên làm việc lâu dài.
- [ ] **Task 2.3: Phản hồi tự động cho máy con**
  - Máy con lắng nghe kênh ghép nối: Ngay khi Phụ huynh claim thành công, máy con nhận thông báo và chuyển sang màn hình "Đã Kích Hoạt Bảo Vệ".

---

### ⚡ SUB-EPIC 03: Kênh Điều Khiển Thời Gian Thực (< 100ms) & Trạng Thái Sống
*Mục tiêu: Thực thi lập tức các lệnh khẩn cấp và theo dõi trạng thái thiết bị theo thời gian thực.*

- [ ] **Task 3.1: Kênh Realtime Broadcast Điều Khiển Khẩn Cấp**
  - Tạo kênh Broadcast chuẩn: `channel("device:{deviceId}")`.
  - Sự kiện `PANIC_LOCKDOWN`: Truyền cờ `{ "is_locked": true/false, "reason": "Parent manual action" }`.
  - Sự kiện `GRANT_EXTRA_TIME`: Truyền tham số `{ "extra_minutes": 15/30/60 }`.
  - Sự kiện `SYNC_POLICY`: Thông báo máy con cập nhật chính sách mới.
- [ ] **Task 3.2: Kênh Realtime Presence Theo Dõi Sống/Chết (Online/Offline)**
  - Máy con track Presence khi ứng dụng hoạt động:
    `channel.track({ "status": "online", "current_app": "com.youtube", "battery": 85 })`.
  - Parent App tự động nhận diện thiết bị mất mạng ngay khi socket bị đứt mà không cần polling API.
- [ ] **Task 3.3: Lắng nghe Thay Đổi Chính Sách qua Postgres Changes (CDC)**
  - Bật Realtime trên bảng `policies`.
  - Khi Phụ huynh thay đổi hạn mức trên Dashboard, máy con tự động nhận event và cập nhật cấu hình Room Database cục bộ.

---

### 📲 SUB-EPIC 04: Kênh Dự Phòng FCM Đánh Thức Máy Con Khi Ngắt Mạng
*Mục tiêu: Đảm bảo lệnh điều khiển vẫn tới đích ngay cả khi thiết bị con ở chế độ ngủ sâu (Doze Mode) hoặc socket bị ngắt.*

- [ ] **Task 4.1: Lưu trữ FCM Device Token**
  - Bổ sung cột `fcm_token` vào bảng `devices`.
  - Máy con gửi FCM Token lên Supabase khi khởi chạy hoặc khi token refresh.
- [ ] **Task 4.2: Supabase Edge Function: `send-fcm-command`**
  - Tích hợp Firebase Admin SDK Service Account vào Deno Edge Function.
  - Khi Phụ huynh gửi lệnh điều khiển:
    - Nếu kênh Presence báo máy con đang `offline` (hoặc gửi đồng thời song song):
    - Edge Function phát bản tin **FCM High-Priority Data Message** tới `fcm_token`.
- [ ] **Task 4.3: Máy con xử lý FCM Message**
  - `FirebaseMessagingService` trên Android đón payload ngầm, kích hoạt `UsageWatcherForegroundService` hoặc gọi trực tiếp `AppSuspensionManager` để khóa app.

---

### 📊 SUB-EPIC 05: Tiếp Nhận Telemetry & Xử Lý Báo Cáo Dữ Liệu Lớn
*Mục tiêu: Ghi nhận lịch sử sử dụng ứng dụng ổn định, chính xác và trực quan hóa lên Dashboard.*

- [ ] **Task 5.1: API Ingestion Batch Logs**
  - Máy con tổng hợp lịch sử mỗi 15 phút, gửi payload dạng mẻ (batch array) qua PostgREST REST API.
  - Tối ưu Index cho truy vấn: Index trên `(device_id, session_date)` và `(package_name)`.
- [ ] **Task 5.2: Postgres Function (RPC) Tổng Hợp Số Liệu Ngày**
  - Viết Stored Procedure `aggregate_daily_usage(p_device_id, p_date)`:
    - Gom nhóm thời gian theo danh mục (Học tập, Game, MXH, Giải trí).
    - Tính tổng thời gian On-Screen trong ngày.
    - Ghi đè hoặc cập nhật vào bảng `daily_usage_summaries`.
  - Cài đặt `pg_cron` (hoặc Scheduled Edge Function) tự động chạy định kỳ dọn dẹp log cũ > 30 ngày.
- [ ] **Task 5.3: Cung cấp API / View Thống Kê Cho Parent App**
  - View `v_device_today_usage`: Trả về số phút đã dùng hôm nay, quota còn lại, và top 5 app dùng nhiều nhất.

---

### 📱 SUB-EPIC 06: Chuyển Đổi & Tích Hợp Client (Flutter & Android DO)
*Mục tiêu: Hoàn thiện code kết nối ở cả 2 đầu ứng dụng.*

- [ ] **Task 6.1: Cập nhật `admin-node` (Flutter Parent App)**
  - Tích hợp `supabase_flutter`.
  - Thay thế `MdmApiService` cũ bằng Supabase Service.
  - Sử dụng `StreamBuilder` gắn vào Realtime Presence & Policies để UI phản hồi ngay lập tức khi trạng thái thay đổi.
- [ ] **Task 6.2: Cập nhật `target-node` (Android DO Agent)**
  - Tích hợp thư viện `supabase-kt` (sử dụng engine `io.ktor:ktor-client-okhttp`).
  - Thay thế `MdmSignalRClient` bằng `MdmSupabaseRealtimeClient`.
  - Đảm bảo cơ chế tự động kết nối lại (Auto-reconnect) khi chuyển từ Wi-Fi sang 4G hoặc bật màn hình.

---

## 🏆 4. Tiêu Chuẩn Nghiệm Thu (Acceptance Criteria)

1. **Tốc độ phản hồi Realtime**: Lệnh Khóa Khẩn Cấp (Panic Lockdown) từ Flutter App truyền xuống máy con và làm xám icon ứng dụng (`setPackagesSuspended`) trong thời gian **< 1.5 giây** (khi có mạng).
2. **Khả năng dự phòng Doze Mode**: Khi máy con tắt màn hình > 30 phút (hệ thống ngắt socket), lệnh khóa gửi qua FCM đánh thức máy con và thực thi thành công trong **< 5 giây**.
3. **An toàn dữ liệu tuyệt đối (Zero Leaks)**: RLS được kiểm thử nghiêm ngặt, Phụ huynh tài khoản A không thể đọc hoặc gửi lệnh tới thiết bị của Phụ huynh tài khoản B.
4. **Hiệu năng & Pin**: Việc lắng nghe Supabase Realtime WebSocket trên Background Service máy con không làm tiêu hao quá **3-5% pin/ngày**.
5. **Độ ổn định Offline**: Khi mất mạng hoàn toàn, máy con vẫn tự động khóa ứng dụng dựa trên hạn mức đã lưu trong Room Database cục bộ; khi có mạng trở lại, tự động bù log về bảng `app_usage_logs`.

---

## 📅 5. Lộ Trình Triển Khai Đề Xuất (Execution Roadmap)

- **Giai đoạn 1**: Khởi tạo Supabase Project + Viết file SQL khởi tạo Database Schema & RLS Policies (`backend/supabase/migrations/`).
- **Giai đoạn 2**: Viết Edge Function cho luồng Ghép nối OTP (`pairing-handshake`) và FCM Fallback.
- **Giai đoạn 3**: Tích hợp `supabase_flutter` vào `admin-node` để hoàn thiện luồng Parent.
- **Giai đoạn 4**: Tích hợp `supabase-kt` vào `target-node` thay thế SignalR.
- **Giai đoạn 5**: QA kiểm thử bảo mật RLS, độ trễ Realtime và battery profiling.

