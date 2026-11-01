-- ==============================================================================
-- Migration: 20261101_fix_claim_device_pairing.sql
-- Khắc phục lỗi: column reference "device_id" is ambiguous (42702)
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.claim_device_pairing(
    p_otp_code VARCHAR(6),
    p_family_id UUID
)
RETURNS TABLE (
    success BOOLEAN,
    device_id UUID,
    device_name TEXT,
    message TEXT
) AS $$
#variable_conflict use_column
DECLARE
    target_device_id UUID;
    target_device_name TEXT;
    target_session_id UUID;
BEGIN
    -- Kiểm tra quyền phụ huynh trong family
    IF NOT public.is_member_of_family(p_family_id) THEN
        RETURN QUERY SELECT false, NULL::UUID, NULL::TEXT, 'Bạn không có quyền quản lý gia đình này'::TEXT;
        RETURN;
    END IF;

    -- Tìm phiên pairing hợp lệ
    SELECT s.id, s.device_id, d.device_name
    INTO target_session_id, target_device_id, target_device_name
    FROM public.pairing_sessions s
    JOIN public.devices d ON d.id = s.device_id
    WHERE s.otp_code = p_otp_code
      AND s.is_claimed = false
      AND s.expires_at > now()
    ORDER BY s.created_at DESC
    LIMIT 1;

    IF target_device_id IS NULL THEN
        RETURN QUERY SELECT false, NULL::UUID, NULL::TEXT, 'Mã OTP không hợp lệ hoặc đã hết hạn'::TEXT;
        RETURN;
    END IF;

    -- Đánh dấu session đã claim
    UPDATE public.pairing_sessions 
    SET is_claimed = true 
    WHERE pairing_sessions.id = target_session_id;

    -- Gán device vào family và kích hoạt
    UPDATE public.devices
    SET family_id = p_family_id,
        status = 'active',
        updated_at = now()
    WHERE devices.id = target_device_id;

    -- Khởi tạo policy mặc định nếu chưa có
    IF NOT EXISTS (SELECT 1 FROM public.policies p WHERE p.device_id = target_device_id) THEN
        INSERT INTO public.policies (device_id, daily_screen_time_limit_mins, bedtime_start, bedtime_end, is_bedtime_enabled)
        VALUES (target_device_id, 120, '21:00:00', '06:00:00', true);
    END IF;

    RETURN QUERY SELECT true, target_device_id, target_device_name, 'Ghép nối thiết bị thành công'::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
