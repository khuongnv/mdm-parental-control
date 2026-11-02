# 📋 Nhật Ký Thực Thi: Tạo Bộ Epics Giai Đoạn 2 - Hoàn Thiện Logic Nghiệp Vụ, Quota, Thông Báo & Tương Tác 2 Chiều

- **Ngày thực hiện**: 2026-11-02 08:55:00
- **Agent phụ trách**: `lead-architect` (phối hợp cùng `device-owner-specialist`, `usage-tracking-specialist`, `backend-sync-specialist`, `parent-ui-specialist`, `qa-security-perf-specialist`)
- **Yêu cầu gốc**: Tạo Epics Giai đoạn 2 cho dự án liên quan đến vấn đề logic:
  1. Đối với app Admin: Quản lý nhiều thiết bị con, đổi tên gợi nhớ, hiển thị đúng trạng thái máy con (online/offline/pin/app đang mở), xóa quản lý máy con (unpair), chia sẻ quản lý cho admin khác (co-admin), quy tắc giới hạn giờ (ngày hoặc tuần, mặc định ngày thì qua ngày auto-reset về 2h và có điều chỉnh được), gửi thông báo/mẫu nhắc nhở tới máy con.
  2. Đối với app Con: Nhận thông báo thưởng/phạt giờ chơi đúng giá trị động (thay vì cố định +15p), bổ sung yêu cầu request xin thêm thời gian, đưa thông báo cảnh báo khi còn 5 phút và đếm ngược, QR code & OTP pair có đếm ngược thời gian còn hiệu lực (TTL 5p).
- **Trạng thái**: ✅ Hoàn thành

---

## 1. Phân Tích & Kế Hoạch (Analysis & Planning)
- **Bối cảnh**: Sau khi hoàn thiện nền tảng kỹ thuật Giai đoạn 1 (Device Owner setup, UsageEvents engine, Supabase BaaS migration), dự án bước vào Giai đoạn 2 tập trung giải quyết triệt để **Logic Nghiệp Vụ Vận Hành Đa Thiết Bị** giữa Phụ huynh và Con cái.
- **Phân rã phạm vi 3 tầng**:
  1. **Admin Node (Parent App - Flutter)**:
     - Multi-device carousel, đổi tên gợi nhớ (`custom_name`).
     - Live presence & telemetry (Online/Offline, mức pin, app Foreground, tiến độ quota).
     - Hủy quản lý thiết bị an toàn 2 bước (Unpair).
     - Chia sẻ quản lý gia đình (Co-admin invite bằng mã 6 số / QR code).
     - Quy tắc Ngày / Tuần: cấu hình hạn mức (mặc định 2h = 120m, tùy biến 15m - 8h), cơ chế auto-reset lúc 00:00:00.
     - Gửi tin nhắn tức thì: 6 mẫu nhắc nhở nhanh + văn bản tự do 150 ký tự, hiển thị trạng thái đã gửi / con đã bấm xác nhận (ACK).
  2. **Target Node (Child Device Owner - Kotlin Native)**:
     - Nhận lệnh thưởng/phạt động (+15m, +30m, +60m, -15m, -30m) qua Realtime/FCM; cập nhật Room DB; nếu phạt vượt quota thì lập tức suspend app.
     - Nút và dialog xin thêm giờ (+15m, +30m) kèm lý do; cơ chế cooldown chống spam; nhận kết quả phê duyệt và un-suspend.
     - Cảnh báo 5 phút (Heads-up notification ưu tiên cao) và đồng hồ đếm ngược trực quan; tự động suspend khi chạm mốc 00:00.
     - Màn hình ghép nối hiển thị đồng hồ đếm lùi 5 phút (TTL 300s) cho mã QR & OTP; hết hạn làm mờ và có nút tạo mã mới.
     - Engine cục bộ tự động reset lúc 00:00:00 bằng `AlarmManager` (hoạt động bền bỉ cả khi offline).
  3. **Backend Cloud (Supabase BaaS / PostgreSQL)**:
     - Lược đồ bảng mở rộng: `time_requests`, `family_invites`, `device_messages`, trường `custom_name`, `battery_level`, `is_charging`, `current_app_name`, `rule_type`, `weekly_screen_time_limit_mins`, `weekday_limits`.
     - Stored Procedures RPC: `create_family_invite`, `join_family_by_code`, `revoke_device_management`, `create_time_request`, `resolve_time_request`.
     - Kênh Realtime Phoenix Channels & contracts: `REMOTE_MESSAGE`, `ACK_MESSAGE`, `ADJUST_SCREEN_TIME`, `TIME_REQUEST`, `TIME_REQUEST_RESOLVED`, `DEVICE_UNPAIRED`.
     - RLS policies bảo mật đa gia đình nghiêm ngặt.

---

## 2. Chi Tiết Các Bước Thực Hiện (Execution Steps)

- **Bước 1**: Rà soát hiện trạng mã nguồn của cả 3 node (`admin-node`, `target-node`, `backend`) để đảm bảo các yêu cầu Giai đoạn 2 tương thích 100% với nền tảng Giai đoạn 1 đã triển khai.
- **Bước 2**: Khởi tạo tài liệu tổng quan [`PHASE_2_EPICS_OVERVIEW.md`](../epics/PHASE_2_EPICS_OVERVIEW.md) bao gồm:
  - Sơ đồ kiến trúc luồng dữ liệu 3 tầng.
  - Ma trận phân rã Epics Giai đoạn 2 (P2-ADMIN, P2-CHILD, P2-BACKEND).
  - 3 Sequence Diagrams cho các luồng nghiệp vụ tương tác cốt lõi.
  - Bảng tham số và quy định chuẩn hóa (Reset 00:00, Daily 120m, Weekly 840m, TTL 300s).
- **Bước 3**: Xây dựng tài liệu chi tiết cho Admin Node [`PHASE_2_ADMIN_NODE_EPICS.md`](../epics/PHASE_2_ADMIN_NODE_EPICS.md) với 6 Epics:
  - P2-ADMIN-01: Quản lý Đa thiết bị & Đổi tên gợi nhớ.
  - P2-ADMIN-02: Live Telemetry & Trạng thái máy con chuẩn xác.
  - P2-ADMIN-03: Hủy quản lý & Xóa thiết bị khỏi gia đình.
  - P2-ADMIN-04: Chia sẻ quyền quản lý Co-Admin (Family Sharing).
  - P2-ADMIN-05: Cấu hình giới hạn Ngày/Tuần & Auto-Reset 2h lúc 00:00.
  - P2-ADMIN-06: Gửi tin nhắn nhắc nhở & 6 mẫu câu nhanh.
- **Bước 4**: Xây dựng tài liệu chi tiết cho Target Node [`PHASE_2_TARGET_NODE_EPICS.md`](../epics/PHASE_2_TARGET_NODE_EPICS.md) với 5 Epics:
  - P2-CHILD-01: Thưởng/Phạt giờ chơi theo giá trị động và suspend tức thì khi âm giờ.
  - P2-CHILD-02: Luồng gửi yêu cầu xin thêm giờ từ máy con.
  - P2-CHILD-03: Cảnh báo 5 phút còn lại & Live Countdown HUD.
  - P2-CHILD-04: Đếm ngược thời gian hiệu lực QR Code & OTP (5 phút).
  - P2-CHILD-05: Engine tự động reset cục bộ lúc 00:00:00 (Offline Resilient).
- **Bước 5**: Xây dựng tài liệu chi tiết Backend [`PHASE_2_BACKEND_SUPABASE_EPICS.md`](../epics/PHASE_2_BACKEND_SUPABASE_EPICS.md) & script migration SQL [`20261102_phase_2_business_logic_schema.sql`](../../backend/supabase/migrations/20261102_phase_2_business_logic_schema.sql).
- **Bước 6**: Cập nhật tài liệu kiến trúc tổng thể [`00_Tong_Quan_Kien_Truc_He_Thong.md`](../epics/00_Tong_Quan_Kien_Truc_He_Thong.md).

---

## 3. Danh Sách Tệp Thay Đổi (Impacted Files)

- `[Created]`: `docs/epics/PHASE_2_EPICS_OVERVIEW.md` - Tổng quan kiến trúc, ma trận phân rã Epics, Sequence diagrams, tiêu chuẩn DoD Giai đoạn 2.
- `[Created]`: `docs/epics/PHASE_2_ADMIN_NODE_EPICS.md` - Chi tiết 6 Epics cho ứng dụng Phụ huynh (Flutter).
- `[Created]`: `docs/epics/PHASE_2_TARGET_NODE_EPICS.md` - Chi tiết 5 Epics cho ứng dụng Con (Android DO Kotlin).
- `[Created]`: `docs/epics/PHASE_2_BACKEND_SUPABASE_EPICS.md` - Chi tiết 3 Epics cho Backend Supabase, hợp đồng dữ liệu Realtime và RLS.
- `[Created]`: `backend/supabase/migrations/20261102_phase_2_business_logic_schema.sql` - Script DDL PostgreSQL tạo bảng, cột mới, stored procedures RPC và chính sách RLS.
- `[Modified]`: `docs/epics/00_Tong_Quan_Kien_Truc_He_Thong.md` - Cập nhật lộ trình phát triển và danh mục liên kết tới các Epics Giai đoạn 2.
- `[Created]`: `docs/logs/2026-11-02_phase_2_epics_business_logic.md` - Nhật ký thực thi nhiệm vụ Swarm.
- `[Modified]`: `docs/logs/README.md` - Chỉ mục danh mục nhật ký truy vết.

---

## 4. Kiểm Thử & Đánh Giá Bảo Mật (Verification & Security Audit)

Được rà soát bởi `qa-security-perf-specialist`:
1. **Tính Nhất Quán (Contract Consistency)**:
   - Các gói tin Realtime Broadcast giữa Admin Node (`admin-node`), Target Node (`target-node`) và Supabase Backend (`backend`) đã được chuẩn hóa 100% về tên event, trường dữ liệu và kiểu dữ liệu (JSON).
2. **Khả Năng Chống Phá Hoại (Anti-Bypass & Offline Resilience)**:
   - Cơ chế reset 00:00 được thiết kế chạy cục bộ qua `AlarmManager.setExactAndAllowWhileIdle()` đảm bảo ngay cả khi máy con tắt mạng qua đêm vẫn tự reset quota đúng hạn và un-suspend bình thường.
   - Trẻ không thể lùi giờ máy để lách thời điểm reset vì đã có hạn chế `DISALLOW_CONFIG_DATE_TIME` và `setAutoTimeRequired(true)`.
3. **Phân Quyền & Bảo Mật Dữ Liệu (Multi-Tenancy RLS)**:
   - Toàn bộ các bảng mới (`family_invites`, `time_requests`, `device_messages`) đều được bật Row Level Security (RLS) gắn chặt với `family_id` của tài khoản phụ huynh đang xác thực.
4. **Tối Ưu Năng Lượng & Bộ Nhớ (Battery Friendly)**:
   - Bộ đếm ngược 5 phút chỉ kích hoạt khi thời gian thực sự chạm ngưỡng <= 5 phút; không chạy timer liên tục khi màn hình tắt.

---

## 5. Kết Luận & Hướng Dẫn Tiếp Theo (Conclusion & Next Steps)

- **Kết quả đạt được**: Toàn bộ yêu cầu nghiệp vụ Giai đoạn 2 của người dùng đã được mô tả chi tiết, phân rã thành các User Stories rõ ràng, có dữ liệu payload cụ thể, sẵn sàng cho các Agent chuyên môn bắt tay vào lập trình.
- **Các bước tiếp theo**:
  1. Chạy migration `20261102_phase_2_business_logic_schema.sql` trên Supabase SQL Editor.
  2. Điều phối `parent-ui-specialist` triển khai giao diện Quản lý đa thiết bị, Đổi tên, và Cấu hình quy tắc ngày/tuần trên Flutter.
  3. Điều phối `usage-tracking-specialist` và `device-owner-specialist` triển khai logic thưởng/phạt động, xin thêm giờ, cảnh báo 5p và TTL đếm ngược trên Kotlin.
