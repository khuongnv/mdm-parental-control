-- ==============================================================================
-- MDM Parental Control - Fix Device Telemetry & Anon Grants
-- Migration: 20261102_fix_device_telemetry_and_grants.sql
-- ==============================================================================

-- 1. Cấp quyền bảng devices cho anon và authenticated
GRANT ALL ON public.devices TO authenticated, service_role, anon;

-- 2. Đảm bảo các cột telemetry tồn tại
ALTER TABLE public.devices
    ADD COLUMN IF NOT EXISTS battery_level INT DEFAULT 100,
    ADD COLUMN IF NOT EXISTS is_charging BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS current_app_name TEXT DEFAULT 'Màn hình chính',
    ADD COLUMN IF NOT EXISTS agent_version TEXT DEFAULT '1.3.5';

-- 3. Tạo RPC chuyên dụng cập nhật Telemetry từ máy con (SECURITY DEFINER để vượt qua mọi rào cản RLS/quyền)
CREATE OR REPLACE FUNCTION public.update_device_telemetry(
    p_device_id UUID,
    p_battery_level INT DEFAULT 100,
    p_is_charging BOOLEAN DEFAULT false,
    p_current_app TEXT DEFAULT 'Màn hình chính',
    p_agent_version TEXT DEFAULT '1.3.5'
)
RETURNS JSONB AS $$
BEGIN
    UPDATE public.devices
    SET battery_level = p_battery_level,
        is_charging = p_is_charging,
        current_app_name = p_current_app,
        agent_version = p_agent_version,
        last_seen_at = now(),
        status = 'active',
        updated_at = now()
    WHERE id = p_device_id;

    RETURN jsonb_build_object(
        'success', true,
        'device_id', p_device_id,
        'battery_level', p_battery_level,
        'is_charging', p_is_charging,
        'current_app_name', p_current_app,
        'agent_version', p_agent_version
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.update_device_telemetry TO authenticated, service_role, anon;

-- 4. Bổ sung policy cho phép anon cập nhật telemetry
DROP POLICY IF EXISTS "Agents can update telemetry and fcm_token" ON public.devices;
CREATE POLICY "Agents can update telemetry and fcm_token" ON public.devices
    FOR UPDATE USING (true) WITH CHECK (true);
