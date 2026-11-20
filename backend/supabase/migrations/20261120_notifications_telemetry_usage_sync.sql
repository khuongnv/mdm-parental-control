-- ==============================================================================
-- MDM Parental Control - Notifications (R1), Extended Telemetry (R2) & Usage Sync (R3)
-- Migration: 20261120_notifications_telemetry_usage_sync.sql
-- ==============================================================================

-- ==============================================================================
-- SECTION 1: R1 — NOTIFICATIONS (device_messages, time_requests, parent_push_tokens)
-- ==============================================================================

-- 1.1. Bổ sung cột cho device_messages và time_requests
ALTER TABLE public.device_messages
    ADD COLUMN IF NOT EXISTS title TEXT DEFAULT 'Lời nhắc từ Ba Mẹ',
    ADD COLUMN IF NOT EXISTS child_reply TEXT,
    ADD COLUMN IF NOT EXISTS fcm_notified_at TIMESTAMPTZ;

ALTER TABLE public.time_requests
    ADD COLUMN IF NOT EXISTS fcm_notified_at TIMESTAMPTZ;

-- 1.2. Bật REPLICA IDENTITY FULL để Supabase Realtime UPDATE phát đủ row + RLS
ALTER TABLE public.device_messages REPLICA IDENTITY FULL;
ALTER TABLE public.time_requests REPLICA IDENTITY FULL;
ALTER TABLE public.devices REPLICA IDENTITY FULL;

-- 1.3. Bảng lưu FCM/APNs Push Tokens của thiết bị Phụ huynh
CREATE TABLE IF NOT EXISTS public.parent_push_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    fcm_token TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
    device_label TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, fcm_token)
);

CREATE INDEX IF NOT EXISTS idx_parent_push_tokens_user ON public.parent_push_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_parent_push_tokens_token ON public.parent_push_tokens(fcm_token);

DROP TRIGGER IF EXISTS tr_parent_push_tokens_updated_at ON public.parent_push_tokens;
CREATE TRIGGER tr_parent_push_tokens_updated_at
    BEFORE UPDATE ON public.parent_push_tokens
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

ALTER TABLE public.parent_push_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Parents can manage own push tokens" ON public.parent_push_tokens;
CREATE POLICY "Parents can manage own push tokens" ON public.parent_push_tokens
    FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

GRANT ALL ON public.parent_push_tokens TO authenticated, service_role;

-- 1.4. RPC: Đăng ký / cập nhật Push Token của phụ huynh
CREATE OR REPLACE FUNCTION public.upsert_parent_push_token(
    p_fcm_token TEXT,
    p_platform TEXT,
    p_device_label TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_token TEXT;
    v_platform TEXT;
    v_label TEXT;
    v_row RECORD;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yêu cầu xác thực tài khoản để đăng ký push token';
    END IF;

    v_token := NULLIF(TRIM(p_fcm_token), '');
    IF v_token IS NULL THEN
        RAISE EXCEPTION 'fcm_token không được để trống';
    END IF;

    v_platform := lower(TRIM(COALESCE(p_platform, '')));
    IF v_platform NOT IN ('android', 'ios') THEN
        RAISE EXCEPTION 'platform không hợp lệ (chỉ hỗ trợ android hoặc ios): %', p_platform;
    END IF;

    v_label := NULLIF(TRIM(p_device_label), '');

    -- Gỡ token cũ nếu cùng thiết bị vật lý chuyển sang tài khoản phụ huynh khác
    DELETE FROM public.parent_push_tokens
    WHERE fcm_token = v_token
      AND user_id <> v_user_id;

    INSERT INTO public.parent_push_tokens (user_id, fcm_token, platform, device_label)
    VALUES (v_user_id, v_token, v_platform, v_label)
    ON CONFLICT (user_id, fcm_token)
    DO UPDATE SET
        platform = EXCLUDED.platform,
        device_label = COALESCE(EXCLUDED.device_label, parent_push_tokens.device_label),
        updated_at = now()
    RETURNING id, user_id, fcm_token, platform, device_label, created_at, updated_at
    INTO v_row;

    RETURN jsonb_build_object(
        'success', true,
        'id', v_row.id,
        'user_id', v_row.user_id,
        'fcm_token', v_row.fcm_token,
        'platform', v_row.platform,
        'device_label', v_row.device_label,
        'created_at', v_row.created_at,
        'updated_at', v_row.updated_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.upsert_parent_push_token(TEXT, TEXT, TEXT) TO authenticated, service_role;

-- 1.5. RPC: Tạo yêu cầu xin thêm giờ (Drop chữ ký cũ để tránh overload, trả về đủ JSONB)
DROP FUNCTION IF EXISTS public.create_time_request(UUID, INT, TEXT);

CREATE OR REPLACE FUNCTION public.create_time_request(
    p_device_id UUID,
    p_requested_minutes INT,
    p_reason TEXT DEFAULT ''
)
RETURNS JSONB AS $$
DECLARE
    v_family_id UUID;
    v_reason TEXT;
    v_row RECORD;
BEGIN
    IF p_requested_minutes IS NULL OR p_requested_minutes <= 0 THEN
        RAISE EXCEPTION 'Số phút xin thêm phải lớn hơn 0';
    END IF;

    SELECT family_id INTO v_family_id
    FROM public.devices
    WHERE id = p_device_id;

    IF v_family_id IS NULL THEN
        RAISE EXCEPTION 'Thiết bị không tồn tại hoặc chưa được ghép nối vào gia đình';
    END IF;

    v_reason := COALESCE(NULLIF(TRIM(p_reason), ''), 'Con xin thêm giờ');

    INSERT INTO public.time_requests (device_id, family_id, requested_minutes, reason, status)
    VALUES (p_device_id, v_family_id, p_requested_minutes, v_reason, 'pending')
    RETURNING * INTO v_row;

    RETURN jsonb_build_object(
        'id', v_row.id,
        'device_id', v_row.device_id,
        'family_id', v_row.family_id,
        'requested_minutes', v_row.requested_minutes,
        'reason', v_row.reason,
        'status', v_row.status,
        'created_at', v_row.created_at,
        'success', true,
        'request_id', v_row.id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.create_time_request(UUID, INT, TEXT) TO authenticated, service_role, anon;

-- 1.6. RPC: Xác nhận đã đọc / gửi phản hồi tin nhắn từ máy con
CREATE OR REPLACE FUNCTION public.acknowledge_device_message(
    p_device_id UUID,
    p_message_id UUID DEFAULT NULL,
    p_reply_text TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_reply TEXT;
    v_target_id UUID;
    v_family_id UUID;
    v_updated_count INT := 0;
    v_row RECORD;
BEGIN
    v_reply := NULLIF(TRIM(p_reply_text), '');

    SELECT family_id INTO v_family_id
    FROM public.devices
    WHERE id = p_device_id;

    IF p_message_id IS NOT NULL THEN
        v_target_id := p_message_id;
    ELSE
        SELECT id INTO v_target_id
        FROM public.device_messages
        WHERE device_id = p_device_id
          AND is_acknowledged = false
        ORDER BY sent_at DESC
        LIMIT 1;
    END IF;

    IF v_target_id IS NULL THEN
        RETURN jsonb_build_object(
            'id', NULL,
            'device_id', p_device_id,
            'family_id', v_family_id,
            'title', NULL,
            'message_text', NULL,
            'child_reply', NULL,
            'is_acknowledged', false,
            'acknowledged_at', NULL,
            'updated_count', 0
        );
    END IF;

    UPDATE public.device_messages
    SET is_acknowledged = true,
        acknowledged_at = COALESCE(acknowledged_at, now()),
        child_reply = COALESCE(v_reply, child_reply),
        fcm_notified_at = CASE
            WHEN v_reply IS NOT NULL AND v_reply IS DISTINCT FROM child_reply THEN NULL
            ELSE fcm_notified_at
        END
    WHERE id = v_target_id
      AND device_id = p_device_id
      AND (
          is_acknowledged = false
          OR (v_reply IS NOT NULL AND v_reply IS DISTINCT FROM child_reply)
      )
    RETURNING * INTO v_row;

    IF FOUND THEN
        v_updated_count := 1;
    ELSE
        SELECT * INTO v_row
        FROM public.device_messages
        WHERE id = v_target_id
          AND device_id = p_device_id;

        IF NOT FOUND THEN
            RETURN jsonb_build_object(
                'id', NULL,
                'device_id', p_device_id,
                'family_id', v_family_id,
                'title', NULL,
                'message_text', NULL,
                'child_reply', NULL,
                'is_acknowledged', false,
                'acknowledged_at', NULL,
                'updated_count', 0
            );
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'id', v_row.id,
        'device_id', v_row.device_id,
        'family_id', v_row.family_id,
        'title', COALESCE(v_row.title, 'Lời nhắc từ Ba Mẹ'),
        'message_text', v_row.message_text,
        'child_reply', v_row.child_reply,
        'is_acknowledged', v_row.is_acknowledged,
        'acknowledged_at', v_row.acknowledged_at,
        'updated_count', v_updated_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.acknowledge_device_message(UUID, UUID, TEXT) TO authenticated, service_role, anon;

-- 1.7. RPC: Lấy danh sách tin nhắn chưa xác nhận cho máy con (vượt rào anon SELECT RLS)
CREATE OR REPLACE FUNCTION public.get_unread_device_messages(
    p_device_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', m.id,
                'device_id', m.device_id,
                'family_id', m.family_id,
                'template_key', m.template_key,
                'title', COALESCE(m.title, 'Lời nhắc từ Ba Mẹ'),
                'message_text', m.message_text,
                'sent_at', m.sent_at
            )
            ORDER BY m.sent_at DESC
        ),
        '[]'::jsonb
    )
    INTO v_result
    FROM public.device_messages m
    WHERE m.device_id = p_device_id
      AND m.is_acknowledged = false;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.get_unread_device_messages(UUID) TO authenticated, service_role, anon;

-- 1.8. Trigger pg_net an toàn (Fallback khi client không kịp gọi Edge Function)
CREATE OR REPLACE FUNCTION public.notify_family_parents_via_pg_net()
RETURNS TRIGGER AS $$
DECLARE
    v_has_pg_net BOOLEAN := false;
    v_url TEXT;
    v_key TEXT;
    v_event_type TEXT;
    v_payload JSONB;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'net'
          AND p.proname = 'http_post'
    ) INTO v_has_pg_net;

    IF NOT v_has_pg_net THEN
        RETURN NEW;
    END IF;

    v_url := NULLIF(current_setting('app.settings.supabase_url', true), '');
    IF v_url IS NULL AND to_regclass('vault.decrypted_secrets') IS NOT NULL THEN
        BEGIN
            EXECUTE 'SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = ''supabase_url'' LIMIT 1'
            INTO v_url;
        EXCEPTION WHEN OTHERS THEN
            v_url := NULL;
        END;
    END IF;

    v_key := COALESCE(
        NULLIF(current_setting('app.settings.service_role_key', true), ''),
        NULLIF(current_setting('app.settings.anon_key', true), '')
    );
    IF v_key IS NULL AND to_regclass('vault.decrypted_secrets') IS NOT NULL THEN
        BEGIN
            EXECUTE 'SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name IN (''service_role_key'', ''anon_key'') ORDER BY CASE name WHEN ''service_role_key'' THEN 1 ELSE 2 END LIMIT 1'
            INTO v_key;
        EXCEPTION WHEN OTHERS THEN
            v_key := NULL;
        END;
    END IF;

    IF v_url IS NULL OR v_key IS NULL THEN
        RETURN NEW;
    END IF;

    IF TG_TABLE_NAME = 'time_requests' THEN
        v_event_type := 'TIME_REQUEST';
        v_payload := jsonb_build_object(
            'device_id', NEW.device_id,
            'family_id', NEW.family_id,
            'event_type', v_event_type,
            'record_id', NEW.id,
            'data', jsonb_build_object(
                'requested_minutes', NEW.requested_minutes,
                'reason', COALESCE(NEW.reason, '')
            )
        );
    ELSIF TG_TABLE_NAME = 'device_messages' THEN
        v_event_type := CASE
            WHEN NULLIF(TRIM(NEW.child_reply), '') IS NOT NULL THEN 'DEVICE_MESSAGE_REPLY'
            ELSE 'DEVICE_MESSAGE_ACK'
        END;
        v_payload := jsonb_build_object(
            'device_id', NEW.device_id,
            'family_id', NEW.family_id,
            'event_type', v_event_type,
            'record_id', NEW.id,
            'data', jsonb_build_object(
                'message_id', NEW.id,
                'message_text', COALESCE(NEW.message_text, ''),
                'child_reply', COALESCE(NEW.child_reply, ''),
                'template_key', COALESCE(NEW.template_key, '')
            )
        );
    ELSE
        RETURN NEW;
    END IF;

    BEGIN
        EXECUTE 'SELECT net.http_post(url := $1, headers := $2, body := $3, timeout_milliseconds := 3000)'
        USING rtrim(v_url, '/') || '/functions/v1/notify-family-parents',
              jsonb_build_object(
                  'Content-Type', 'application/json',
                  'Authorization', 'Bearer ' || v_key,
                  'apikey', v_key
              ),
              v_payload;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'notify_family_parents_via_pg_net failed: %', SQLERRM;
    END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions;

DROP TRIGGER IF EXISTS tr_notify_parents_on_time_request ON public.time_requests;
CREATE TRIGGER tr_notify_parents_on_time_request
    AFTER INSERT ON public.time_requests
    FOR EACH ROW
    WHEN (NEW.status = 'pending' AND NEW.fcm_notified_at IS NULL)
    EXECUTE FUNCTION public.notify_family_parents_via_pg_net();

DROP TRIGGER IF EXISTS tr_notify_parents_on_device_message_ack ON public.device_messages;
CREATE TRIGGER tr_notify_parents_on_device_message_ack
    AFTER UPDATE ON public.device_messages
    FOR EACH ROW
    WHEN (
        NEW.is_acknowledged = true
        AND (
            OLD.is_acknowledged IS DISTINCT FROM TRUE
            OR NULLIF(TRIM(NEW.child_reply), '') IS DISTINCT FROM NULLIF(TRIM(OLD.child_reply), '')
        )
        AND NEW.fcm_notified_at IS NULL
    )
    EXECUTE FUNCTION public.notify_family_parents_via_pg_net();

-- ==============================================================================
-- SECTION 2: R2 — EXTENDED DEVICE TELEMETRY (devices, update_device_telemetry, get_family_details)
-- ==============================================================================

-- 2.1. Mở rộng cột thông số thiết bị trên public.devices
ALTER TABLE public.devices
    ADD COLUMN IF NOT EXISTS screen_brightness INT,
    ADD COLUMN IF NOT EXISTS is_auto_brightness BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS screen_mode TEXT DEFAULT 'unknown',
    ADD COLUMN IF NOT EXISTS is_screen_on BOOLEAN DEFAULT true,
    ADD COLUMN IF NOT EXISTS is_dark_mode BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS media_volume INT,
    ADD COLUMN IF NOT EXISTS ring_volume INT,
    ADD COLUMN IF NOT EXISTS notification_volume INT,
    ADD COLUMN IF NOT EXISTS alarm_volume INT,
    ADD COLUMN IF NOT EXISTS ringer_mode TEXT DEFAULT 'normal',
    ADD COLUMN IF NOT EXISTS is_media_muted BOOLEAN DEFAULT false;

-- 2.2. Bắt buộc DROP hàm 5 tham số cũ để tránh overload PGRST203 khi gọi qua PostgREST
DROP FUNCTION IF EXISTS public.update_device_telemetry(UUID, INT, BOOLEAN, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.update_device_telemetry(
    p_device_id UUID,
    p_battery_level INT DEFAULT NULL,
    p_is_charging BOOLEAN DEFAULT NULL,
    p_current_app TEXT DEFAULT NULL,
    p_agent_version TEXT DEFAULT NULL,
    p_current_package_name TEXT DEFAULT NULL,
    p_screen_brightness INT DEFAULT NULL,
    p_is_auto_brightness BOOLEAN DEFAULT NULL,
    p_screen_mode TEXT DEFAULT NULL,
    p_is_screen_on BOOLEAN DEFAULT NULL,
    p_is_dark_mode BOOLEAN DEFAULT NULL,
    p_media_volume INT DEFAULT NULL,
    p_ring_volume INT DEFAULT NULL,
    p_notification_volume INT DEFAULT NULL,
    p_alarm_volume INT DEFAULT NULL,
    p_ringer_mode TEXT DEFAULT NULL,
    p_is_media_muted BOOLEAN DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_battery INT;
    v_brightness INT;
    v_media_vol INT;
    v_ring_vol INT;
    v_notif_vol INT;
    v_alarm_vol INT;
    v_screen_mode TEXT;
    v_ringer_mode TEXT;
    v_dev RECORD;
BEGIN
    v_battery := CASE WHEN p_battery_level IS NOT NULL THEN LEAST(100, GREATEST(0, p_battery_level)) ELSE NULL END;
    v_brightness := CASE WHEN p_screen_brightness IS NOT NULL THEN LEAST(100, GREATEST(0, p_screen_brightness)) ELSE NULL END;
    v_media_vol := CASE WHEN p_media_volume IS NOT NULL THEN LEAST(100, GREATEST(0, p_media_volume)) ELSE NULL END;
    v_ring_vol := CASE WHEN p_ring_volume IS NOT NULL THEN LEAST(100, GREATEST(0, p_ring_volume)) ELSE NULL END;
    v_notif_vol := CASE WHEN p_notification_volume IS NOT NULL THEN LEAST(100, GREATEST(0, p_notification_volume)) ELSE NULL END;
    v_alarm_vol := CASE WHEN p_alarm_volume IS NOT NULL THEN LEAST(100, GREATEST(0, p_alarm_volume)) ELSE NULL END;

    v_screen_mode := CASE
        WHEN p_screen_mode IS NULL THEN NULL
        WHEN lower(TRIM(p_screen_mode)) IN ('on_unlocked', 'on_locked', 'doze', 'off', 'unknown') THEN lower(TRIM(p_screen_mode))
        ELSE 'unknown'
    END;

    v_ringer_mode := CASE
        WHEN p_ringer_mode IS NULL THEN NULL
        WHEN lower(TRIM(p_ringer_mode)) IN ('normal', 'vibrate', 'silent') THEN lower(TRIM(p_ringer_mode))
        ELSE NULL
    END;

    UPDATE public.devices
    SET battery_level = COALESCE(v_battery, battery_level),
        is_charging = COALESCE(p_is_charging, is_charging),
        current_app_name = COALESCE(NULLIF(TRIM(p_current_app), ''), current_app_name),
        agent_version = COALESCE(NULLIF(TRIM(p_agent_version), ''), agent_version),
        current_package_name = COALESCE(NULLIF(TRIM(p_current_package_name), ''), current_package_name),
        screen_brightness = COALESCE(v_brightness, screen_brightness),
        is_auto_brightness = COALESCE(p_is_auto_brightness, is_auto_brightness),
        screen_mode = COALESCE(v_screen_mode, screen_mode),
        is_screen_on = COALESCE(p_is_screen_on, is_screen_on),
        is_dark_mode = COALESCE(p_is_dark_mode, is_dark_mode),
        media_volume = COALESCE(v_media_vol, media_volume),
        ring_volume = COALESCE(v_ring_vol, ring_volume),
        notification_volume = COALESCE(v_notif_vol, notification_volume),
        alarm_volume = COALESCE(v_alarm_vol, alarm_volume),
        ringer_mode = COALESCE(v_ringer_mode, ringer_mode),
        is_media_muted = COALESCE(p_is_media_muted, is_media_muted),
        last_seen_at = now(),
        status = CASE WHEN status = 'revoked' THEN 'revoked' ELSE 'active' END,
        updated_at = now()
    WHERE id = p_device_id
    RETURNING * INTO v_dev;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'device_id', p_device_id,
            'message', 'Device not found'
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'device_id', v_dev.id,
        'battery_level', v_dev.battery_level,
        'is_charging', v_dev.is_charging,
        'current_app_name', v_dev.current_app_name,
        'current_package_name', v_dev.current_package_name,
        'agent_version', v_dev.agent_version,
        'screen_brightness', v_dev.screen_brightness,
        'is_auto_brightness', v_dev.is_auto_brightness,
        'screen_mode', v_dev.screen_mode,
        'is_screen_on', v_dev.is_screen_on,
        'is_dark_mode', v_dev.is_dark_mode,
        'media_volume', v_dev.media_volume,
        'ring_volume', v_dev.ring_volume,
        'notification_volume', v_dev.notification_volume,
        'alarm_volume', v_dev.alarm_volume,
        'ringer_mode', v_dev.ringer_mode,
        'is_media_muted', v_dev.is_media_muted,
        'last_seen_at', v_dev.last_seen_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.update_device_telemetry(
    UUID, INT, BOOLEAN, TEXT, TEXT, TEXT, INT, BOOLEAN, TEXT, BOOLEAN, BOOLEAN, INT, INT, INT, INT, TEXT, BOOLEAN
) TO authenticated, service_role, anon;

-- ==============================================================================
-- SECTION 3: R3 — ACCURATE USAGE TIME & SYNC (daily_app_usage, summaries, devices)
-- ==============================================================================

-- 3.1. Bảng lưu chi tiết thời gian sử dụng từng ứng dụng theo ngày địa phương
CREATE TABLE IF NOT EXISTS public.daily_app_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,
    usage_date DATE NOT NULL,
    package_name TEXT NOT NULL,
    app_name TEXT NOT NULL DEFAULT '',
    app_category TEXT NOT NULL DEFAULT 'Other',
    duration_seconds INT NOT NULL DEFAULT 0 CHECK (duration_seconds >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (device_id, usage_date, package_name)
);

CREATE INDEX IF NOT EXISTS idx_daily_app_usage_device_date
    ON public.daily_app_usage(device_id, usage_date, duration_seconds DESC);

DROP TRIGGER IF EXISTS tr_daily_app_usage_updated_at ON public.daily_app_usage;
CREATE TRIGGER tr_daily_app_usage_updated_at
    BEFORE UPDATE ON public.daily_app_usage
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

ALTER TABLE public.daily_app_usage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Parents can view daily app usage" ON public.daily_app_usage;
CREATE POLICY "Parents can view daily app usage" ON public.daily_app_usage
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM public.devices d
            LEFT JOIN public.families f ON f.id = d.family_id
            WHERE d.id = public.daily_app_usage.device_id
              AND (public.is_member_of_family(d.family_id) OR f.created_by = auth.uid())
        )
    );

ALTER TABLE public.daily_app_usage REPLICA IDENTITY FULL;

GRANT SELECT ON public.daily_app_usage TO authenticated;
GRANT ALL ON public.daily_app_usage TO service_role;

-- 3.2. Mở rộng daily_usage_summaries với giây chính xác & app_breakdown
ALTER TABLE public.daily_usage_summaries
    ADD COLUMN IF NOT EXISTS total_screen_time_seconds INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS app_breakdown JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS local_timezone TEXT DEFAULT 'Asia/Ho_Chi_Minh';

UPDATE public.daily_usage_summaries
SET total_screen_time_seconds = total_screen_time_mins * 60
WHERE total_screen_time_seconds = 0
  AND total_screen_time_mins > 0;

ALTER TABLE public.daily_usage_summaries REPLICA IDENTITY FULL;

GRANT SELECT ON public.daily_usage_summaries TO authenticated;
GRANT ALL ON public.daily_usage_summaries TO service_role;

-- 3.3. Mở rộng public.devices với cache thời gian sử dụng hôm nay (không dùng UTC CURRENT_DATE)
ALTER TABLE public.devices
    ADD COLUMN IF NOT EXISTS today_usage_seconds INT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS today_usage_date DATE;

-- 3.4. RPC: Cập nhật get_family_details (giữ nguyên toàn bộ key cũ + thêm telemetry & usage)
CREATE OR REPLACE FUNCTION public.get_family_details(
    p_family_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_family RECORD;
    v_parents JSONB;
    v_devices JSONB;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yêu cầu xác thực tài khoản';
    END IF;

    SELECT * INTO v_family FROM public.families WHERE id = p_family_id;
    IF v_family IS NULL THEN
        RAISE EXCEPTION 'Không tìm thấy gia đình này';
    END IF;

    IF NOT (public.is_member_of_family(p_family_id) OR v_family.created_by = v_user_id) THEN
        RAISE EXCEPTION 'Bạn không có quyền truy cập thông tin gia đình này';
    END IF;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', fm.id,
            'user_id', fm.user_id,
            'role', fm.role,
            'display_name', COALESCE(fm.display_name, 'Phụ huynh'),
            'joined_at', fm.joined_at,
            'is_current_user', (fm.user_id = v_user_id)
        ) ORDER BY (fm.role = 'owner') DESC, fm.joined_at ASC
    ), '[]'::jsonb)
    INTO v_parents
    FROM public.family_members fm
    WHERE fm.family_id = p_family_id;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', d.id,
            'device_name', d.device_name,
            'custom_name', d.custom_name,
            'model', d.model,
            'status', d.status,
            'battery_level', d.battery_level,
            'is_charging', d.is_charging,
            'is_locked', d.is_locked,
            'extra_time_minutes', d.extra_time_minutes,
            'current_app_name', d.current_app_name,
            'last_seen_at', d.last_seen_at,
            'agent_version', d.agent_version,
            'current_package_name', d.current_package_name,
            'screen_brightness', d.screen_brightness,
            'is_auto_brightness', d.is_auto_brightness,
            'screen_mode', d.screen_mode,
            'is_screen_on', d.is_screen_on,
            'is_dark_mode', d.is_dark_mode,
            'media_volume', d.media_volume,
            'ring_volume', d.ring_volume,
            'notification_volume', d.notification_volume,
            'alarm_volume', d.alarm_volume,
            'ringer_mode', d.ringer_mode,
            'is_media_muted', d.is_media_muted,
            'today_usage_seconds', d.today_usage_seconds,
            'today_usage_date', d.today_usage_date,
            'updated_at', d.updated_at
        ) ORDER BY d.created_at ASC
    ), '[]'::jsonb)
    INTO v_devices
    FROM public.devices d
    WHERE d.family_id = p_family_id
      AND (d.is_unpaired IS NULL OR d.is_unpaired = false);

    RETURN jsonb_build_object(
        'family_id', v_family.id,
        'family_name', v_family.name,
        'created_at', v_family.created_at,
        'is_owner', (v_family.created_by = v_user_id OR EXISTS (
            SELECT 1 FROM public.family_members
            WHERE family_id = p_family_id AND user_id = v_user_id AND role = 'owner'
        )),
        'parents', v_parents,
        'devices', v_devices
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.get_family_details(UUID) TO authenticated, service_role, anon;

-- 3.5. RPC: Đồng bộ thời gian sử dụng trong ngày theo múi giờ địa phương & giây chính xác
CREATE OR REPLACE FUNCTION public.sync_device_daily_usage(
    p_device_id UUID,
    p_usage_date DATE,
    p_total_seconds INT,
    p_apps JSONB,
    p_timezone TEXT DEFAULT 'Asia/Ho_Chi_Minh'
)
RETURNS JSONB AS $$
DECLARE
    v_tz TEXT;
    v_usage_date DATE;
    v_apps JSONB;
    v_apps_sum INT := 0;
    v_total_seconds INT := 0;
    v_app_count INT := 0;
    v_app_breakdown JSONB := '[]'::jsonb;
    v_top_apps JSONB := '[]'::jsonb;
    v_category_breakdown JSONB := '{}'::jsonb;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.devices WHERE id = p_device_id) THEN
        RAISE EXCEPTION 'Không tìm thấy thiết bị %', p_device_id;
    END IF;

    v_tz := COALESCE(NULLIF(TRIM(p_timezone), ''), 'Asia/Ho_Chi_Minh');
    v_usage_date := COALESCE(p_usage_date, (now() AT TIME ZONE v_tz)::date);
    v_apps := CASE
        WHEN p_apps IS NOT NULL AND jsonb_typeof(p_apps) = 'array' THEN p_apps
        ELSE '[]'::jsonb
    END;

    -- Xóa các package không còn trong snapshot ngày hiện tại (hỗ trợ reset hoặc lọc launcher/agent)
    DELETE FROM public.daily_app_usage
    WHERE device_id = p_device_id
      AND usage_date = v_usage_date
      AND package_name NOT IN (
          SELECT DISTINCT TRIM(x.package_name)
          FROM jsonb_to_recordset(v_apps) AS x(package_name TEXT)
          WHERE NULLIF(TRIM(x.package_name), '') IS NOT NULL
      );

    -- Gộp trùng package_name (nếu có) và upsert chính xác số giây
    INSERT INTO public.daily_app_usage (
        device_id,
        usage_date,
        package_name,
        app_name,
        app_category,
        duration_seconds
    )
    SELECT
        p_device_id,
        v_usage_date,
        TRIM(x.package_name) AS package_name,
        MAX(COALESCE(NULLIF(TRIM(x.app_name), ''), TRIM(x.package_name))) AS app_name,
        MAX(COALESCE(NULLIF(TRIM(x.app_category), ''), 'Other')) AS app_category,
        SUM(ROUND(GREATEST(0, COALESCE(x.duration_seconds, 0))))::INT AS duration_seconds
    FROM jsonb_to_recordset(v_apps) AS x(
        package_name TEXT,
        app_name TEXT,
        app_category TEXT,
        duration_seconds NUMERIC
    )
    WHERE NULLIF(TRIM(x.package_name), '') IS NOT NULL
    GROUP BY TRIM(x.package_name)
    ON CONFLICT (device_id, usage_date, package_name)
    DO UPDATE SET
        app_name = EXCLUDED.app_name,
        app_category = EXCLUDED.app_category,
        duration_seconds = EXCLUDED.duration_seconds,
        updated_at = now();

    SELECT COALESCE(SUM(duration_seconds), 0)::INT, COUNT(*)::INT
    INTO v_apps_sum, v_app_count
    FROM public.daily_app_usage
    WHERE device_id = p_device_id
      AND usage_date = v_usage_date;

    v_total_seconds := GREATEST(GREATEST(0, COALESCE(p_total_seconds, 0)), v_apps_sum);

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'package_name', a.package_name,
                'app_name', a.app_name,
                'app_category', a.app_category,
                'duration_seconds', a.duration_seconds,
                'minutes', (a.duration_seconds / 60)::INT
            )
            ORDER BY a.duration_seconds DESC, a.package_name ASC
        ),
        '[]'::jsonb
    )
    INTO v_app_breakdown
    FROM public.daily_app_usage a
    WHERE a.device_id = p_device_id
      AND a.usage_date = v_usage_date;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'package_name', t.package_name,
                'app_name', t.app_name,
                'app_category', t.app_category,
                'duration_seconds', t.duration_seconds,
                'minutes', (t.duration_seconds / 60)::INT
            )
            ORDER BY t.duration_seconds DESC, t.package_name ASC
        ),
        '[]'::jsonb
    )
    INTO v_top_apps
    FROM (
        SELECT package_name, app_name, app_category, duration_seconds
        FROM public.daily_app_usage
        WHERE device_id = p_device_id
          AND usage_date = v_usage_date
        ORDER BY duration_seconds DESC, package_name ASC
        LIMIT 5
    ) t;

    SELECT COALESCE(jsonb_object_agg(c.app_category, c.cat_seconds), '{}'::jsonb)
    INTO v_category_breakdown
    FROM (
        SELECT app_category, SUM(duration_seconds)::INT AS cat_seconds
        FROM public.daily_app_usage
        WHERE device_id = p_device_id
          AND usage_date = v_usage_date
        GROUP BY app_category
    ) c;

    INSERT INTO public.daily_usage_summaries (
        device_id,
        summary_date,
        total_screen_time_mins,
        total_screen_time_seconds,
        category_breakdown,
        top_apps,
        app_breakdown,
        local_timezone,
        updated_at
    )
    VALUES (
        p_device_id,
        v_usage_date,
        (v_total_seconds / 60)::INT,
        v_total_seconds,
        v_category_breakdown,
        v_top_apps,
        v_app_breakdown,
        v_tz,
        now()
    )
    ON CONFLICT (device_id, summary_date)
    DO UPDATE SET
        total_screen_time_mins = EXCLUDED.total_screen_time_mins,
        total_screen_time_seconds = EXCLUDED.total_screen_time_seconds,
        category_breakdown = EXCLUDED.category_breakdown,
        top_apps = EXCLUDED.top_apps,
        app_breakdown = EXCLUDED.app_breakdown,
        local_timezone = EXCLUDED.local_timezone,
        updated_at = now();

    -- Chỉ cập nhật cache today_usage trên devices nếu v_usage_date >= today_usage_date (tránh flush muộn ngày cũ ghi đè hôm nay)
    UPDATE public.devices
    SET today_usage_seconds = v_total_seconds,
        today_usage_date = v_usage_date,
        updated_at = now()
    WHERE id = p_device_id
      AND (today_usage_date IS NULL OR v_usage_date >= today_usage_date);

    RETURN jsonb_build_object(
        'success', true,
        'device_id', p_device_id,
        'usage_date', v_usage_date,
        'total_screen_time_seconds', v_total_seconds,
        'total_screen_time_mins', (v_total_seconds / 60)::INT,
        'app_count', v_app_count,
        'local_timezone', v_tz
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.sync_device_daily_usage(UUID, DATE, INT, JSONB, TEXT) TO authenticated, service_role, anon;

-- ==============================================================================
-- SECTION 4: IDEMPOTENT SUPABASE REALTIME PUBLICATION
-- ==============================================================================

DO $$
DECLARE
    v_tbl TEXT;
    v_tables TEXT[] := ARRAY[
        'devices',
        'policies',
        'app_rules',
        'pairing_sessions',
        'time_requests',
        'device_messages',
        'daily_usage_summaries',
        'daily_app_usage'
    ];
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        FOREACH v_tbl IN ARRAY v_tables LOOP
            IF NOT EXISTS (
                SELECT 1
                FROM pg_publication_tables
                WHERE pubname = 'supabase_realtime'
                  AND schemaname = 'public'
                  AND tablename = v_tbl
            ) THEN
                EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_tbl);
            END IF;
        END LOOP;
    END IF;
END $$;
