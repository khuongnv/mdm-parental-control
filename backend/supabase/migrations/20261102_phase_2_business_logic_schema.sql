-- ==============================================================================
-- MDM Parental Control - Phase 2 Business Logic & Multi-Device Schema
-- Migration: 20261102_phase_2_business_logic_schema.sql
-- ==============================================================================

-- 1. ALTER EXISTING TABLES
ALTER TABLE public.devices
    ADD COLUMN IF NOT EXISTS custom_name TEXT,
    ADD COLUMN IF NOT EXISTS battery_level INT DEFAULT 100,
    ADD COLUMN IF NOT EXISTS is_charging BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS current_app_name TEXT DEFAULT 'Màn hình chính',
    ADD COLUMN IF NOT EXISTS current_package_name TEXT,
    ADD COLUMN IF NOT EXISTS is_unpaired BOOLEAN DEFAULT false;

ALTER TABLE public.policies
    ADD COLUMN IF NOT EXISTS rule_type TEXT NOT NULL DEFAULT 'daily' CHECK (rule_type IN ('daily', 'weekly')),
    ADD COLUMN IF NOT EXISTS weekly_screen_time_limit_mins INT NOT NULL DEFAULT 840,
    ADD COLUMN IF NOT EXISTS weekday_limits JSONB NOT NULL DEFAULT '{"mon": 120, "tue": 120, "wed": 120, "thu": 120, "fri": 120, "sat": 180, "sun": 180}'::jsonb,
    ADD COLUMN IF NOT EXISTS auto_reset_hour INT NOT NULL DEFAULT 0;

-- 2. CREATE PHASE 2 TABLES

-- 2.1. Family Invites (Chia sẻ quyền quản lý Co-Admin)
CREATE TABLE IF NOT EXISTS public.family_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id UUID NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
    invite_code VARCHAR(20) NOT NULL UNIQUE,
    created_by UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'parent' CHECK (role IN ('parent', 'viewer')),
    expires_at TIMESTAMPTZ NOT NULL,
    is_used BOOLEAN NOT NULL DEFAULT false,
    used_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_family_invites_code ON public.family_invites(invite_code) WHERE is_used = false;

-- 2.2. Time Requests (Yêu cầu xin thêm giờ từ con)
CREATE TABLE IF NOT EXISTS public.time_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,
    family_id UUID NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
    requested_minutes INT NOT NULL CHECK (requested_minutes > 0),
    reason TEXT NOT NULL DEFAULT 'Chưa xong bài tập',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
    resolved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    resolved_minutes INT DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_time_requests_device ON public.time_requests(device_id, status);
CREATE INDEX IF NOT EXISTS idx_time_requests_family ON public.time_requests(family_id, status);

-- 2.3. Device Messages (Tin nhắn & mẫu nhắc nhở phụ huynh gửi con)
CREATE TABLE IF NOT EXISTS public.device_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,
    family_id UUID NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    template_key TEXT,
    message_text TEXT NOT NULL,
    is_acknowledged BOOLEAN NOT NULL DEFAULT false,
    acknowledged_at TIMESTAMPTZ,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_device_messages_device ON public.device_messages(device_id, sent_at DESC);

-- 3. ROW LEVEL SECURITY (RLS)
ALTER TABLE public.family_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members can view invites of their family" ON public.family_invites;
CREATE POLICY "Members can view invites of their family" ON public.family_invites
    FOR SELECT USING (public.is_member_of_family(family_id) OR EXISTS (
        SELECT 1 FROM public.families WHERE id = family_id AND created_by = auth.uid()
    ));

DROP POLICY IF EXISTS "Allow authenticated to query active invite by code" ON public.family_invites;
CREATE POLICY "Allow authenticated to query active invite by code" ON public.family_invites
    FOR SELECT USING (is_used = false AND expires_at > now());

DROP POLICY IF EXISTS "Parents can view and resolve time requests" ON public.time_requests;
CREATE POLICY "Parents can view and resolve time requests" ON public.time_requests
    FOR ALL USING (public.is_member_of_family(family_id) OR EXISTS (
        SELECT 1 FROM public.families WHERE id = family_id AND created_by = auth.uid()
    ));

DROP POLICY IF EXISTS "Target agent can insert time requests" ON public.time_requests;
CREATE POLICY "Target agent can insert time requests" ON public.time_requests
    FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Parents can view and send device messages" ON public.device_messages;
CREATE POLICY "Parents can view and send device messages" ON public.device_messages
    FOR ALL USING (public.is_member_of_family(family_id) OR EXISTS (
        SELECT 1 FROM public.families WHERE id = family_id AND created_by = auth.uid()
    ));

DROP POLICY IF EXISTS "Target agent can acknowledge device messages" ON public.device_messages;
CREATE POLICY "Target agent can acknowledge device messages" ON public.device_messages
    FOR UPDATE USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Target agent can insert acknowledged device messages" ON public.device_messages;
CREATE POLICY "Target agent can insert acknowledged device messages" ON public.device_messages
    FOR INSERT WITH CHECK (true);

-- 4. STORED PROCEDURES (RPC)

-- 4.1. Tạo mã mời Co-Admin
CREATE OR REPLACE FUNCTION public.create_family_invite(
    p_family_id UUID,
    p_role TEXT DEFAULT 'parent'
)
RETURNS JSONB AS $$
DECLARE
    v_code VARCHAR(20);
    v_invite_id UUID;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.family_members
        WHERE family_id = p_family_id AND user_id = auth.uid()
    ) AND NOT EXISTS (
        SELECT 1 FROM public.families
        WHERE id = p_family_id AND created_by = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Không có quyền tạo lời mời cho gia đình này';
    END IF;

    -- Sinh mã 6 ký tự chuẩn FAM-XXXX
    v_code := 'FAM-' || upper(substring(md5(random()::text || clock_timestamp()::text) from 1 for 4));

    INSERT INTO public.family_invites (family_id, invite_code, created_by, role, expires_at)
    VALUES (p_family_id, v_code, auth.uid(), p_role, now() + INTERVAL '24 hours')
    RETURNING id INTO v_invite_id;

    RETURN jsonb_build_object(
        'invite_id', v_invite_id,
        'invite_code', v_code,
        'expires_at', (now() + INTERVAL '24 hours')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4.2. Nhập mã mời để tham gia gia đình
CREATE OR REPLACE FUNCTION public.join_family_by_code(
    p_invite_code TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_invite RECORD;
BEGIN
    SELECT * INTO v_invite FROM public.family_invites
    WHERE invite_code = upper(trim(p_invite_code))
      AND is_used = false
      AND expires_at > now();

    IF v_invite IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Mã mời không hợp lệ hoặc đã hết hạn.');
    END IF;

    INSERT INTO public.family_members (family_id, user_id, role)
    VALUES (v_invite.family_id, auth.uid(), v_invite.role)
    ON CONFLICT (family_id, user_id) DO UPDATE SET role = EXCLUDED.role;

    UPDATE public.family_invites
    SET is_used = true, used_by = auth.uid()
    WHERE id = v_invite.id;

    RETURN jsonb_build_object(
        'success', true,
        'family_id', v_invite.family_id,
        'message', 'Gia nhập gia đình thành công!'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4.3. Hủy quản lý thiết bị
CREATE OR REPLACE FUNCTION public.revoke_device_management(
    p_device_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_family_id UUID;
BEGIN
    SELECT family_id INTO v_family_id FROM public.devices WHERE id = p_device_id;
    IF v_family_id IS NULL OR NOT (public.is_member_of_family(v_family_id) OR EXISTS (
        SELECT 1 FROM public.families WHERE id = v_family_id AND created_by = auth.uid()
    )) THEN
        RAISE EXCEPTION 'Không có quyền thao tác trên thiết bị này';
    END IF;

    UPDATE public.devices
    SET family_id = NULL,
        is_unpaired = true,
        status = 'revoked',
        is_locked = false,
        extra_time_minutes = 0,
        updated_at = now()
    WHERE id = p_device_id;

    RETURN jsonb_build_object('success', true, 'message', 'Đã hủy quản lý thiết bị thành công.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4.4. Tạo yêu cầu xin thêm giờ
CREATE OR REPLACE FUNCTION public.create_time_request(
    p_device_id UUID,
    p_requested_minutes INT,
    p_reason TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_family_id UUID;
    v_request_id UUID;
BEGIN
    SELECT family_id INTO v_family_id FROM public.devices WHERE id = p_device_id;
    IF v_family_id IS NULL THEN
        RAISE EXCEPTION 'Thiết bị chưa được ghép nối vào gia đình';
    END IF;

    INSERT INTO public.time_requests (device_id, family_id, requested_minutes, reason, status)
    VALUES (p_device_id, v_family_id, p_requested_minutes, p_reason, 'pending')
    RETURNING id INTO v_request_id;

    RETURN jsonb_build_object('success', true, 'request_id', v_request_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4.5. Phê duyệt hoặc từ chối yêu cầu xin giờ
CREATE OR REPLACE FUNCTION public.resolve_time_request(
    p_request_id UUID,
    p_status TEXT,
    p_granted_minutes INT DEFAULT 0
)
RETURNS JSONB AS $$
DECLARE
    v_req RECORD;
BEGIN
    SELECT * INTO v_req FROM public.time_requests WHERE id = p_request_id;
    IF v_req IS NULL THEN
        RAISE EXCEPTION 'Yêu cầu không tồn tại';
    END IF;

    IF NOT (public.is_member_of_family(v_req.family_id) OR EXISTS (
        SELECT 1 FROM public.families WHERE id = v_req.family_id AND created_by = auth.uid()
    )) THEN
        RAISE EXCEPTION 'Không có quyền duyệt yêu cầu của gia đình này';
    END IF;

    UPDATE public.time_requests
    SET status = p_status,
        resolved_minutes = CASE WHEN p_status = 'approved' THEN p_granted_minutes ELSE 0 END,
        resolved_by = auth.uid(),
        resolved_at = now()
    WHERE id = p_request_id;

    IF p_status = 'approved' AND p_granted_minutes > 0 THEN
        UPDATE public.devices
        SET extra_time_minutes = extra_time_minutes + p_granted_minutes,
            is_locked = false,
            updated_at = now()
        WHERE id = v_req.device_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'status', p_status, 'granted_minutes', p_granted_minutes);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. GRANTS & PERMISSIONS
GRANT ALL ON public.family_invites TO authenticated, service_role, anon;
GRANT ALL ON public.time_requests TO authenticated, service_role, anon;
GRANT ALL ON public.device_messages TO authenticated, service_role, anon;

GRANT EXECUTE ON FUNCTION public.create_family_invite TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.join_family_by_code TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.revoke_device_management TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.create_time_request TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.resolve_time_request TO authenticated, service_role, anon;

-- 6. REALTIME PUBLICATION
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'time_requests'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.time_requests;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'device_messages'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.device_messages;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'family_invites'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.family_invites;
    END IF;
END $$;
