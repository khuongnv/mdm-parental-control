-- ==============================================================================
-- MDM Parental Control - Enhanced Family Management & Daily Quota Reset
-- Migration: 20261117_family_management_and_daily_reset.sql
-- ==============================================================================

-- 1. Bổ sung trường display_name cho thành viên gia đình
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'family_members' AND column_name = 'display_name'
    ) THEN
        ALTER TABLE public.family_members ADD COLUMN display_name TEXT DEFAULT 'Phụ huynh';
    END IF;
END $$;

-- 2. Đảm bảo RLS cho phép authenticated / anon thực hiện thao tác thích hợp
ALTER TABLE public.families ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.family_members ENABLE ROW LEVEL SECURITY;

-- 3. RPC: Tạo gia đình mới với tên gia đình và tên hiển thị của người tạo
CREATE OR REPLACE FUNCTION public.create_new_family(
    p_family_name TEXT,
    p_display_name TEXT DEFAULT 'Chủ gia đình'
)
RETURNS JSONB AS $$
DECLARE
    v_family_id UUID;
    v_user_id UUID;
    v_clean_fam_name TEXT;
    v_clean_disp_name TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yêu cầu đăng nhập để tạo gia đình';
    END IF;

    v_clean_fam_name := coalesce(nullif(trim(p_family_name), ''), 'Gia Đình Tôi');
    v_clean_disp_name := coalesce(nullif(trim(p_display_name), ''), 'Chủ gia đình');

    -- Tạo gia đình mới
    INSERT INTO public.families (name, created_by)
    VALUES (v_clean_fam_name, v_user_id)
    RETURNING id INTO v_family_id;

    -- Thêm người tạo làm Owner
    INSERT INTO public.family_members (family_id, user_id, role, display_name)
    VALUES (v_family_id, v_user_id, 'owner', v_clean_disp_name)
    ON CONFLICT (family_id, user_id) 
    DO UPDATE SET role = 'owner', display_name = EXCLUDED.display_name;

    RETURN jsonb_build_object(
        'success', true,
        'family_id', v_family_id,
        'family_name', v_clean_fam_name,
        'role', 'owner',
        'display_name', v_clean_disp_name,
        'message', 'Tạo gia đình thành công!'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. RPC: Lấy danh sách các gia đình của user hiện tại
CREATE OR REPLACE FUNCTION public.get_my_families()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_result JSONB;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_array();
    END IF;

    SELECT coalesce(jsonb_agg(
        jsonb_build_object(
            'id', f.id,
            'name', f.name,
            'created_at', f.created_at,
            'role', fm.role,
            'display_name', fm.display_name,
            'is_owner', (fm.role = 'owner' OR f.created_by = v_user_id),
            'parent_count', (SELECT count(*) FROM public.family_members WHERE family_id = f.id),
            'device_count', (SELECT count(*) FROM public.devices WHERE family_id = f.id)
        ) ORDER BY (fm.role = 'owner') DESC, f.created_at ASC
    ), '[]'::jsonb)
    INTO v_result
    FROM public.families f
    JOIN public.family_members fm ON f.id = fm.family_id
    WHERE fm.user_id = v_user_id;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. RPC: Lấy thông tin chi tiết một gia đình (phụ huynh + máy con)
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

    -- Kiểm tra quyền xem gia đình
    SELECT * INTO v_family FROM public.families WHERE id = p_family_id;
    IF v_family IS NULL THEN
        RAISE EXCEPTION 'Không tìm thấy gia đình này';
    END IF;

    IF NOT (public.is_member_of_family(p_family_id) OR v_family.created_by = v_user_id) THEN
        RAISE EXCEPTION 'Bạn không có quyền truy cập thông tin gia đình này';
    END IF;

    -- Lấy danh sách phụ huynh
    SELECT coalesce(jsonb_agg(
        jsonb_build_object(
            'id', fm.id,
            'user_id', fm.user_id,
            'role', fm.role,
            'display_name', coalesce(fm.display_name, 'Phụ huynh'),
            'joined_at', fm.joined_at,
            'is_current_user', (fm.user_id = v_user_id)
        ) ORDER BY (fm.role = 'owner') DESC, fm.joined_at ASC
    ), '[]'::jsonb)
    INTO v_parents
    FROM public.family_members fm
    WHERE fm.family_id = p_family_id;

    -- Lấy danh sách thiết bị con
    SELECT coalesce(jsonb_agg(
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
            'last_seen_at', d.last_seen_at
        ) ORDER BY d.created_at ASC
    ), '[]'::jsonb)
    INTO v_devices
    FROM public.devices d
    WHERE d.family_id = p_family_id AND (d.is_unpaired IS NULL OR d.is_unpaired = false);

    RETURN jsonb_build_object(
        'family_id', v_family.id,
        'family_name', v_family.name,
        'created_at', v_family.created_at,
        'is_owner', (v_family.created_by = v_user_id OR EXISTS (
            SELECT 1 FROM public.family_members WHERE family_id = p_family_id AND user_id = v_user_id AND role = 'owner'
        )),
        'parents', v_parents,
        'devices', v_devices
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. RPC: Cập nhật tên gia đình
CREATE OR REPLACE FUNCTION public.update_family_name(
    p_family_id UUID,
    p_name TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yêu cầu đăng nhập';
    END IF;

    IF NOT (public.is_member_of_family(p_family_id) OR EXISTS (
        SELECT 1 FROM public.families WHERE id = p_family_id AND created_by = v_user_id
    )) THEN
        RAISE EXCEPTION 'Bạn không có quyền đổi tên gia đình này';
    END IF;

    UPDATE public.families
    SET name = trim(p_name), updated_at = now()
    WHERE id = p_family_id;

    RETURN jsonb_build_object('success', true, 'message', 'Đổi tên gia đình thành công');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. RPC: Tham gia gia đình bằng mã mời kèm Tên hiển thị (v2)
CREATE OR REPLACE FUNCTION public.join_family_by_code_v2(
    p_invite_code TEXT,
    p_display_name TEXT DEFAULT 'Phụ huynh'
)
RETURNS JSONB AS $$
DECLARE
    v_invite RECORD;
    v_user_id UUID;
    v_clean_name TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Yêu cầu xác thực tài khoản';
    END IF;

    v_clean_name := coalesce(nullif(trim(p_display_name), ''), 'Phụ huynh');

    SELECT * INTO v_invite FROM public.family_invites
    WHERE invite_code = upper(trim(p_invite_code))
      AND is_used = false
      AND expires_at > now();

    IF v_invite IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Mã mời không hợp lệ hoặc đã hết hạn.');
    END IF;

    INSERT INTO public.family_members (family_id, user_id, role, display_name)
    VALUES (v_invite.family_id, v_user_id, v_invite.role, v_clean_name)
    ON CONFLICT (family_id, user_id) 
    DO UPDATE SET role = EXCLUDED.role, display_name = EXCLUDED.display_name;

    UPDATE public.family_invites
    SET is_used = true, used_by = v_user_id
    WHERE id = v_invite.id;

    RETURN jsonb_build_object(
        'success', true,
        'family_id', v_invite.family_id,
        'message', 'Gia nhập gia đình thành công!'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. RPC: Xóa thành viên phụ huynh khỏi gia đình hoặc Tự rời gia đình
CREATE OR REPLACE FUNCTION public.remove_family_member(
    p_family_id UUID,
    p_target_user_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_current_user UUID;
    v_is_owner BOOLEAN;
    v_target_role TEXT;
BEGIN
    v_current_user := auth.uid();
    IF v_current_user IS NULL THEN
        RAISE EXCEPTION 'Yêu cầu đăng nhập';
    END IF;

    -- Kiểm tra quyền
    v_is_owner := EXISTS (
        SELECT 1 FROM public.family_members 
        WHERE family_id = p_family_id AND user_id = v_current_user AND role = 'owner'
    ) OR EXISTS (
        SELECT 1 FROM public.families 
        WHERE id = p_family_id AND created_by = v_current_user
    );

    SELECT role INTO v_target_role FROM public.family_members
    WHERE family_id = p_family_id AND user_id = p_target_user_id;

    IF v_target_role IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Thành viên không tồn tại trong gia đình');
    END IF;

    -- Nếu tự rời
    IF v_current_user = p_target_user_id THEN
        IF v_target_role = 'owner' THEN
            -- Không cho phép owner rời nếu còn thành viên khác mà chưa chuyển quyền
            IF (SELECT count(*) FROM public.family_members WHERE family_id = p_family_id) > 1 THEN
                RETURN jsonb_build_object('success', false, 'message', 'Chủ gia đình không thể rời khi gia đình còn thành viên khác');
            END IF;
        END IF;

        DELETE FROM public.family_members WHERE family_id = p_family_id AND user_id = p_target_user_id;
        RETURN jsonb_build_object('success', true, 'message', 'Đã rời gia đình thành công');
    END IF;

    -- Nếu Owner xóa thành viên
    IF NOT v_is_owner THEN
        RAISE EXCEPTION 'Chỉ chủ gia đình mới có quyền xóa thành viên khác';
    END IF;

    IF v_target_role = 'owner' THEN
        RETURN jsonb_build_object('success', false, 'message', 'Không thể xóa chủ gia đình');
    END IF;

    DELETE FROM public.family_members WHERE family_id = p_family_id AND user_id = p_target_user_id;
    RETURN jsonb_build_object('success', true, 'message', 'Đã xóa thành viên khỏi gia đình');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 9. RPC: Reset hạn mức extra_time_minutes của thiết bị khi sang ngày mới
CREATE OR REPLACE FUNCTION public.reset_device_daily_quota(
    p_device_id UUID
)
RETURNS JSONB AS $$
BEGIN
    UPDATE public.devices
    SET extra_time_minutes = 0,
        updated_at = now()
    WHERE id = p_device_id;

    RETURN jsonb_build_object('success', true, 'message', 'Đã reset hạn mức ngày mới cho thiết bị.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 10. Phân quyền EXECUTE cho anon và authenticated
GRANT EXECUTE ON FUNCTION public.create_new_family TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.get_my_families TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.get_family_details TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.update_family_name TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.join_family_by_code_v2 TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.remove_family_member TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.reset_device_daily_quota TO authenticated, service_role, anon;
