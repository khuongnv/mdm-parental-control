-- ==============================================================================
-- MDM Parental Control - Initial Supabase Database Schema & Realtime Setup
-- Migration: 20261101_initial_schema.sql
-- Project: ueamgqbxgyzxruzzjofm
-- ==============================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==============================================================================
-- 2. CORE TABLES
-- ==============================================================================

-- 2.1. Families (Gia đình)
CREATE TABLE IF NOT EXISTS public.families (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2.2. Family Members (Thành viên / Phụ huynh trong gia đình)
CREATE TABLE IF NOT EXISTS public.family_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id UUID NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'parent' CHECK (role IN ('owner', 'parent', 'viewer')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (family_id, user_id)
);

-- 2.3. Devices (Thiết bị con - Managed Devices)
CREATE TABLE IF NOT EXISTS public.devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id UUID REFERENCES public.families(id) ON DELETE SET NULL,
    device_name TEXT NOT NULL,
    model TEXT,
    os_version TEXT,
    agent_version TEXT,
    fcm_token TEXT,
    is_locked BOOLEAN NOT NULL DEFAULT false,
    extra_time_minutes INT NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'pending_pairing' CHECK (status IN ('pending_pairing', 'active', 'paused', 'revoked')),
    last_seen_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2.4. Pairing Sessions (Phiên ghép nối OTP / QR 1 lần - TTL 5 phút)
CREATE TABLE IF NOT EXISTS public.pairing_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,
    otp_code VARCHAR(6) NOT NULL,
    qr_token TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    is_claimed BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2.5. Policies (Chính sách & Giới hạn sử dụng thiết bị)
CREATE TABLE IF NOT EXISTS public.policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE UNIQUE,
    daily_screen_time_limit_mins INT NOT NULL DEFAULT 120, -- Mặc định 2 giờ/ngày
    bedtime_start TIME NOT NULL DEFAULT '21:00:00',
    bedtime_end TIME NOT NULL DEFAULT '06:00:00',
    is_bedtime_enabled BOOLEAN NOT NULL DEFAULT true,
    emergency_whitelist JSONB NOT NULL DEFAULT '["com.android.dialer", "com.google.android.dialer", "com.mdm.parentalcontrol.child"]'::jsonb,
    version INT NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2.6. App Rules (Quy tắc cho từng ứng dụng cụ thể)
CREATE TABLE IF NOT EXISTS public.app_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_id UUID NOT NULL REFERENCES public.policies(id) ON DELETE CASCADE,
    package_name TEXT NOT NULL,
    app_name TEXT NOT NULL,
    app_category TEXT NOT NULL DEFAULT 'Other',
    is_blocked BOOLEAN NOT NULL DEFAULT false,
    daily_limit_mins INT NOT NULL DEFAULT 0, -- 0 = Kế thừa quota chung
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (policy_id, package_name)
);

-- 2.7. Daily Usage Summaries (Báo cáo tổng hợp theo ngày)
CREATE TABLE IF NOT EXISTS public.daily_usage_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,
    summary_date DATE NOT NULL,
    total_screen_time_mins INT NOT NULL DEFAULT 0,
    category_breakdown JSONB NOT NULL DEFAULT '{}'::jsonb,
    top_apps JSONB NOT NULL DEFAULT '[]'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (device_id, summary_date)
);

-- 2.8. App Usage Logs (Nhật ký Telemetry thô - Batch gửi 15 phút/lần)
-- LƯU Ý: Không thêm bảng này vào Supabase Realtime để tránh quá tải WAL.
CREATE TABLE IF NOT EXISTS public.app_usage_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    device_id UUID NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,
    package_name TEXT NOT NULL,
    app_category TEXT NOT NULL DEFAULT 'Other',
    duration_seconds INT NOT NULL,
    session_date DATE NOT NULL DEFAULT CURRENT_DATE,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ==============================================================================
-- 3. INDEXES CHO HIỆU NĂNG TRUY VẤN
-- ==============================================================================

CREATE INDEX IF NOT EXISTS idx_devices_family ON public.devices(family_id);
CREATE INDEX IF NOT EXISTS idx_family_members_user ON public.family_members(user_id);
CREATE INDEX IF NOT EXISTS idx_pairing_otp ON public.pairing_sessions(otp_code) WHERE is_claimed = false;
CREATE INDEX IF NOT EXISTS idx_policies_device ON public.policies(device_id);
CREATE INDEX IF NOT EXISTS idx_app_rules_policy ON public.app_rules(policy_id);
CREATE INDEX IF NOT EXISTS idx_usage_logs_device_date ON public.app_usage_logs(device_id, session_date);
CREATE INDEX IF NOT EXISTS idx_usage_summary_device_date ON public.daily_usage_summaries(device_id, summary_date);

-- ==============================================================================
-- 4. TRIGGERS AUTO UPDATE `updated_at`
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_families_updated_at ON public.families;
CREATE TRIGGER tr_families_updated_at BEFORE UPDATE ON public.families FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS tr_devices_updated_at ON public.devices;
CREATE TRIGGER tr_devices_updated_at BEFORE UPDATE ON public.devices FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS tr_policies_updated_at ON public.policies;
CREATE TRIGGER tr_policies_updated_at BEFORE UPDATE ON public.policies FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS tr_app_rules_updated_at ON public.app_rules;
CREATE TRIGGER tr_app_rules_updated_at BEFORE UPDATE ON public.app_rules FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- ==============================================================================
-- 5. ROW LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================

ALTER TABLE public.families ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.family_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pairing_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_usage_summaries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_usage_logs ENABLE ROW LEVEL SECURITY;

-- Helper Function: Kiểm tra user có thuộc family hay không
CREATE OR REPLACE FUNCTION public.is_member_of_family(check_family_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.family_members
        WHERE family_id = check_family_id AND user_id = auth.uid()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Policies: Families
DROP POLICY IF EXISTS "Users can view their families" ON public.families;
CREATE POLICY "Users can view their families" ON public.families
    FOR SELECT USING (public.is_member_of_family(id) OR created_by = auth.uid());

DROP POLICY IF EXISTS "Authenticated users can create family" ON public.families;
CREATE POLICY "Authenticated users can create family" ON public.families
    FOR INSERT WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Owners can update family" ON public.families;
CREATE POLICY "Owners can update family" ON public.families
    FOR UPDATE USING (created_by = auth.uid());

-- Policies: Family Members
DROP POLICY IF EXISTS "Members can view family roster" ON public.family_members;
CREATE POLICY "Members can view family roster" ON public.family_members
    FOR SELECT USING (public.is_member_of_family(family_id));

-- Policies: Devices
DROP POLICY IF EXISTS "Parents can view family devices" ON public.devices;
CREATE POLICY "Parents can view family devices" ON public.devices
    FOR SELECT USING (family_id IS NULL OR public.is_member_of_family(family_id));

DROP POLICY IF EXISTS "Parents can update family devices" ON public.devices;
CREATE POLICY "Parents can update family devices" ON public.devices
    FOR UPDATE USING (public.is_member_of_family(family_id));

DROP POLICY IF EXISTS "Agents can register initial device" ON public.devices;
CREATE POLICY "Agents can register initial device" ON public.devices
    FOR INSERT WITH CHECK (true);

-- Policies: Pairing Sessions
DROP POLICY IF EXISTS "Allow anon create and view pairing session" ON public.pairing_sessions;
CREATE POLICY "Allow anon create and view pairing session" ON public.pairing_sessions
    FOR ALL USING (true) WITH CHECK (true);

-- Policies: Policies & App Rules
DROP POLICY IF EXISTS "Parents can view policies" ON public.policies;
CREATE POLICY "Parents can view policies" ON public.policies
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.devices d WHERE d.id = device_id AND (d.family_id IS NULL OR public.is_member_of_family(d.family_id)))
    );

DROP POLICY IF EXISTS "Parents can update policies" ON public.policies;
CREATE POLICY "Parents can update policies" ON public.policies
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM public.devices d WHERE d.id = device_id AND public.is_member_of_family(d.family_id))
    );

DROP POLICY IF EXISTS "Parents can view app rules" ON public.app_rules;
CREATE POLICY "Parents can view app rules" ON public.app_rules
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.policies p 
            JOIN public.devices d ON d.id = p.device_id 
            WHERE p.id = policy_id AND (d.family_id IS NULL OR public.is_member_of_family(d.family_id))
        )
    );

DROP POLICY IF EXISTS "Parents can modify app rules" ON public.app_rules;
CREATE POLICY "Parents can modify app rules" ON public.app_rules
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.policies p 
            JOIN public.devices d ON d.id = p.device_id 
            WHERE p.id = policy_id AND public.is_member_of_family(d.family_id)
        )
    );

-- Policies: Usage Summaries & Logs
DROP POLICY IF EXISTS "Parents can view usage summaries" ON public.daily_usage_summaries;
CREATE POLICY "Parents can view usage summaries" ON public.daily_usage_summaries
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.devices d WHERE d.id = device_id AND public.is_member_of_family(d.family_id))
    );

DROP POLICY IF EXISTS "Agents can insert usage summaries" ON public.daily_usage_summaries;
CREATE POLICY "Agents can insert usage summaries" ON public.daily_usage_summaries
    FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Parents can view usage logs" ON public.app_usage_logs;
CREATE POLICY "Parents can view usage logs" ON public.app_usage_logs
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.devices d WHERE d.id = device_id AND public.is_member_of_family(d.family_id))
    );

DROP POLICY IF EXISTS "Agents can insert usage logs" ON public.app_usage_logs;
CREATE POLICY "Agents can insert usage logs" ON public.app_usage_logs
    FOR INSERT WITH CHECK (true);

-- ==============================================================================
-- 6. RPC STORED PROCEDURES (BẮT TAY GHÉP NỐI & TỔNG HỢP)
-- ==============================================================================

-- 6.1. Tạo hoặc Tham Gia Family
CREATE OR REPLACE FUNCTION public.create_or_join_family(p_family_name TEXT)
RETURNS UUID AS $$
DECLARE
    new_family_id UUID;
BEGIN
    INSERT INTO public.families (name, created_by)
    VALUES (p_family_name, auth.uid())
    RETURNING id INTO new_family_id;

    INSERT INTO public.family_members (family_id, user_id, role)
    VALUES (new_family_id, auth.uid(), 'owner');

    RETURN new_family_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6.2. Thiết Bị Con Tạo Phiên Ghép Nối (Sinh OTP 6 số, TTL 5 phút)
CREATE OR REPLACE FUNCTION public.create_device_pairing(
    p_device_name TEXT,
    p_model TEXT DEFAULT 'Android Device',
    p_os_version TEXT DEFAULT 'Android 14',
    p_agent_version TEXT DEFAULT '1.0.0'
)
RETURNS TABLE (
    device_id UUID,
    otp_code VARCHAR(6),
    qr_token TEXT,
    expires_at TIMESTAMPTZ
) AS $$
DECLARE
    new_device_id UUID;
    gen_otp VARCHAR(6);
    gen_token TEXT;
    exp_time TIMESTAMPTZ;
BEGIN
    -- Sinh mã OTP ngẫu nhiên 6 số (100000 - 999999)
    gen_otp := lpad(floor(random() * 900000 + 100000)::text, 6, '0');
    gen_token := encode(gen_random_bytes(24), 'hex');
    exp_time := now() + interval '5 minutes';

    -- Tạo device ở trạng thái pending
    INSERT INTO public.devices (device_name, model, os_version, agent_version, status)
    VALUES (p_device_name, p_model, p_os_version, p_agent_version, 'pending_pairing')
    RETURNING id INTO new_device_id;

    -- Tạo phiên ghép nối
    INSERT INTO public.pairing_sessions (device_id, otp_code, qr_token, expires_at)
    VALUES (new_device_id, gen_otp, gen_token, exp_time);

    RETURN QUERY SELECT new_device_id, gen_otp, gen_token, exp_time;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6.3. Phụ Huynh Nhận Quyền Kiểm Soát Bằng OTP (Claim Pairing)
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
DECLARE
    target_device_id UUID;
    target_device_name TEXT;
    session_id UUID;
BEGIN
    -- Kiểm tra quyền phụ huynh trong family
    IF NOT public.is_member_of_family(p_family_id) THEN
        RETURN QUERY SELECT false, NULL::UUID, NULL::TEXT, 'Bạn không có quyền quản lý gia đình này'::TEXT;
        RETURN;
    END IF;

    -- Tìm phiên pairing hợp lệ
    SELECT s.id, s.device_id, d.device_name
    INTO session_id, target_device_id, target_device_name
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
    UPDATE public.pairing_sessions SET is_claimed = true WHERE id = session_id;

    -- Gán device vào family và kích hoạt
    UPDATE public.devices
    SET family_id = p_family_id,
        status = 'active',
        updated_at = now()
    WHERE id = target_device_id;

    -- Khởi tạo policy mặc định nếu chưa có
    INSERT INTO public.policies (device_id, daily_screen_time_limit_mins, bedtime_start, bedtime_end, is_bedtime_enabled)
    VALUES (target_device_id, 120, '21:00:00', '06:00:00', true)
    ON CONFLICT (device_id) DO NOTHING;

    RETURN QUERY SELECT true, target_device_id, target_device_name, 'Ghép nối thiết bị thành công'::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6.4. Tổng Hợp Số Liệu Ngày Từ Logs Thô
CREATE OR REPLACE FUNCTION public.aggregate_device_daily_usage(
    p_device_id UUID,
    p_date DATE
)
RETURNS VOID AS $$
DECLARE
    total_mins INT;
    cat_json JSONB;
    top_json JSONB;
BEGIN
    -- Tính tổng phút On-Screen
    SELECT COALESCE(SUM(duration_seconds) / 60, 0)
    INTO total_mins
    FROM public.app_usage_logs
    WHERE device_id = p_device_id AND session_date = p_date;

    -- Tổng hợp theo danh mục
    SELECT COALESCE(jsonb_object_agg(app_category, cat_total), '{}'::jsonb)
    INTO cat_json
    FROM (
        SELECT app_category, (SUM(duration_seconds) / 60)::INT AS cat_total
        FROM public.app_usage_logs
        WHERE device_id = p_device_id AND session_date = p_date
        GROUP BY app_category
    ) t;

    -- Lấy Top 5 ứng dụng dùng nhiều nhất
    SELECT COALESCE(jsonb_agg(row_to_json(a)), '[]'::jsonb)
    INTO top_json
    FROM (
        SELECT package_name, (SUM(duration_seconds) / 60)::INT AS minutes
        FROM public.app_usage_logs
        WHERE device_id = p_device_id AND session_date = p_date
        GROUP BY package_name
        ORDER BY minutes DESC
        LIMIT 5
    ) a;

    -- Ghi vào bảng summary
    INSERT INTO public.daily_usage_summaries (device_id, summary_date, total_screen_time_mins, category_breakdown, top_apps)
    VALUES (p_device_id, p_date, total_mins, cat_json, top_json)
    ON CONFLICT (device_id, summary_date)
    DO UPDATE SET
        total_screen_time_mins = EXCLUDED.total_screen_time_mins,
        category_breakdown = EXCLUDED.category_breakdown,
        top_apps = EXCLUDED.top_apps,
        updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==============================================================================
-- 7. BẬT SUPABASE REALTIME PUBLICATION
-- ==============================================================================
-- Lưu ý: Chỉ bật Realtime trên các bảng điều khiển cần độ trễ thấp.
-- Tuyệt đối KHÔNG add app_usage_logs vào publication để bảo vệ WAL.

ALTER PUBLICATION supabase_realtime ADD TABLE public.devices;
ALTER PUBLICATION supabase_realtime ADD TABLE public.policies;
ALTER PUBLICATION supabase_realtime ADD TABLE public.app_rules;
ALTER PUBLICATION supabase_realtime ADD TABLE public.pairing_sessions;

-- ==============================================================================
-- HOÀN TẤT THIẾT LẬP INITIAL SCHEMA
-- ==============================================================================

