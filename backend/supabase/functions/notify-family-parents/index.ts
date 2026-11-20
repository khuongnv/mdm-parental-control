// Supabase Edge Function: notify-family-parents
// Gửi thông báo đẩy FCM (Android + iOS APNs) tới toàn bộ thiết bị phụ huynh trong gia đình
// khi máy con tạo yêu cầu xin thêm giờ (time_requests) hoặc xác nhận/phản hồi tin nhắn (device_messages).

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { corsHeaders, jsonResponse } from "../_shared/fcm.mjs";
import { handleNotifyFamilyParents } from "../_shared/notify_parents.mjs";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Method not allowed" }, 405);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ success: false, error: "Invalid JSON payload" }, 400);
  }

  try {
    const result = await handleNotifyFamilyParents({
      payload,
      env: (key: string) => Deno.env.get(key),
    });
    return jsonResponse(result.body, result.status);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ success: false, error: message }, 500);
  }
});
