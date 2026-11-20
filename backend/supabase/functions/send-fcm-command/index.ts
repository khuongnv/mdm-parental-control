// Supabase Edge Function: send-fcm-command
// Gửi bản tin ngầm ưu tiên cao (FCM High-Priority Silent Push) tới máy con qua FCM HTTP v1 API

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.4";
import {
  buildChildCommandFcmMessage,
  corsHeaders,
  getGoogleAccessToken,
  jsonResponse,
  resolveFirebaseCredentials,
  sendFcmV1Message,
} from "../_shared/fcm.mjs";

interface FcmPayload {
  device_id: string;
  action:
    | "PANIC_LOCKDOWN"
    | "GRANT_EXTRA_TIME"
    | "ADJUST_SCREEN_TIME"
    | "SYNC_POLICY"
    | "REMOTE_MESSAGE"
    | "TIME_REQUEST_RESOLVED";
  is_locked?: boolean;
  extra_minutes?: number;
  delta_minutes?: number;
  reason?: string;
  title?: string;
  body?: string;
  message_id?: string;
  template_key?: string;
  status?: string;
  granted_minutes?: number;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const body: FcmPayload = await req.json();
    const { device_id, action } = body;

    if (!device_id || !action) {
      return jsonResponse({ error: "device_id and action are required" }, 400);
    }

    // Lấy FCM token của thiết bị từ Supabase
    const { data: device, error: devError } = await supabase
      .from("devices")
      .select("id, device_name, fcm_token")
      .eq("id", device_id)
      .single();

    if (devError || !device || !device.fcm_token) {
      return jsonResponse({
        success: false,
        message: "Thiết bị chưa đăng ký fcm_token hoặc không tìm thấy",
      });
    }

    // Đọc cấu hình Firebase từ Supabase Secrets (hỗ trợ cả FIREBASE_SERVICE_ACCOUNT_JSON và FIREBASE_SERVICE_ACCOUNT)
    const creds = resolveFirebaseCredentials((key: string) => Deno.env.get(key));
    if (!creds) {
      return jsonResponse(
        {
          success: false,
          message:
            "Thiếu cấu hình Firebase Service Account trên server (FIREBASE_SERVICE_ACCOUNT_JSON)",
        },
        500
      );
    }

    // Lấy OAuth2 Access Token (có cache trong isolate và tự động unescape \\n trong PEM)
    const accessToken = await getGoogleAccessToken({
      clientEmail: creds.clientEmail,
      privateKey: creds.privateKey,
    });

    // Chuẩn bị Data Payload (Silent high-priority push cho Android + silent background APNs)
    const fcmMessage = buildChildCommandFcmMessage(
      device.fcm_token,
      body as unknown as Record<string, unknown>
    );

    const { ok, status, result } = await sendFcmV1Message({
      projectId: creds.projectId,
      accessToken,
      message: fcmMessage,
    });

    if (!ok) {
      return jsonResponse({ success: false, error: result }, status);
    }

    return jsonResponse({
      success: true,
      message: "FCM Push sent successfully",
      fcm_name: result.name,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ success: false, error: message }, 500);
  }
});
