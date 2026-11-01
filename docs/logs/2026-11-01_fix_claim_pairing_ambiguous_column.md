# 📋 Nhật Ký Thực Thi: Khắc Phục Lỗi Ambiguous "device_id" Trong RPC Stored Procedure

- **Ngày thực hiện**: 2026-11-01 20:57:00
- **Agent phụ trách**: `lead-architect` & `backend-sync-specialist`
- **Yêu cầu gốc**: Khắc phục lỗi `PostgrestException(message: column reference "device_id" is ambiguous, code: 42702)` khi máy phụ huynh gửi lệnh ghép nối OTP trên Supabase.
- **Trạng thái**: ✅ Hoàn thành

---

## 1. Phân Tích & Kế Hoạch (Analysis & Planning)
- **Hiện tượng**:
  - Người dùng đã bật Anonymous Sign-In thành công trên Supabase (lỗi 422 đã hoàn toàn biến mất).
  - Khi người dùng nhập OTP và bấm ghép nối, Supabase trả về ngoại lệ PostgreSQL:
    `PostgrestException(message: column reference "device_id" is ambiguous, code: 42702, details: It could refer to either a PL/pgSQL variable or a table column., hint: null)`.
- **Nguyên nhân kỹ thuật**:
  - Hàm `claim_device_pairing` khai báo `RETURNS TABLE (device_id UUID, ...)`. Trong PL/pgSQL, khai báo này tự động sinh ra một biến ngầm tên là `device_id`.
  - Bên trong thân hàm, câu lệnh `INSERT INTO public.policies (...) ON CONFLICT (device_id) DO NOTHING;` chứa `device_id`.
  - PostgreSQL gặp xung đột tên giữa cột `policies.device_id` và biến đầu ra `device_id` của hàm, dẫn tới lỗi biên dịch `42702 (ambiguous column reference)`.

---

## 2. Giải Pháp Khắc Phục (Resolution Steps)
- **Thực hiện cập nhật Stored Procedure**:
  - Thêm chỉ thị `#variable_conflict use_column` vào đầu block hàm.
  - Thay thế `ON CONFLICT (device_id)` bằng kiểm tra tường minh:
    ```sql
    IF NOT EXISTS (SELECT 1 FROM public.policies p WHERE p.device_id = target_device_id) THEN
        INSERT INTO public.policies (device_id, daily_screen_time_limit_mins, bedtime_start, bedtime_end, is_bedtime_enabled)
        VALUES (target_device_id, 120, '21:00:00', '06:00:00', true);
    END IF;
    ```
  - Định danh rõ ràng bảng trong các câu lệnh `UPDATE` (`pairing_sessions.id`, `devices.id`).
- Tạo file migration: [`backend/supabase/migrations/20261101_fix_claim_device_pairing.sql`](../../backend/supabase/migrations/20261101_fix_claim_device_pairing.sql).

---

## 3. Danh Sách Tệp Thay Đổi (Impacted Files)
- `[Created]`: `backend/supabase/migrations/20261101_fix_claim_device_pairing.sql` - Kịch bản SQL vá lỗi.
- `[Modified]`: `backend/supabase/migrations/20261101_initial_schema.sql` - Cập nhật schema chuẩn.
- `[Created]`: `docs/logs/2026-11-01_fix_claim_pairing_ambiguous_column.md` - Tệp nhật ký này.
- `[Modified]`: `docs/logs/README.md` - Đăng ký nhật ký truy vết.
