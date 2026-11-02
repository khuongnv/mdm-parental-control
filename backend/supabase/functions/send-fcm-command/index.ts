// Supabase Edge Function: send-fcm-command
// Gửi bản tin ngầm ưu tiên cao (FCM High-Priority Silent Push) tới máy con qua FCM HTTP v1 API

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.4";

interface FcmPayload {
  device_id: string;
  action: "PANIC_LOCKDOWN" | "GRANT_EXTRA_TIME" | "SYNC_POLICY" | "REMOTE_MESSAGE" | "TIME_REQUEST_RESOLVED";
  is_locked?: boolean;
  extra_minutes?: number;
  title?: string;
  body?: string;
  message_id?: string;
  template_key?: string;
  status?: string;
  granted_minutes?: number;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

/**
 * Tạo Google OAuth2 Access Token cho FCM HTTP v1 từ Service Account Credentials
 */
async function getGoogleAccessToken(clientEmail: string, privateKey: string): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  // Ký JWT bằng Deno SubtleCrypto
  const encoder = new TextEncoder();
  const b64Url = (obj: any) =>
    btoa(unescape(encodeURIComponent(JSON.stringify(obj))))
      .replace(/=/g, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");

  const unsignedToken = `${b64Url(header)}.${b64Url(claim)}`;

  // Parse PEM private key
  const pemHeader = "-----BEGIN PRIVATE KEY-----";
  const pemFooter = "-----END PRIVATE KEY-----";
  const cleanKey = privateKey
    .replace(pemHeader, "")
    .replace(pemFooter, "")
    .replace(/\s+/g, "");
  const binaryKey = Uint8Array.from(atob(cleanKey), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    encoder.encode(unsignedToken)
  );

  const signatureB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");

  const jwt = `${unsignedToken}.${signatureB64}`;

  // Trao đổi lấy OAuth2 Access Token
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const tokenData = await tokenRes.json();
  if (!tokenRes.ok) {
    throw new Error(`Failed to obtain Google access token: ${JSON.stringify(tokenData)}`);
  }

  return tokenData.access_token;
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
    const { device_id, action, is_locked, extra_minutes } = body;

    if (!device_id || !action) {
      return new Response(JSON.stringify({ error: "device_id and action are required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Lấy FCM token của thiết bị từ Supabase
    const { data: device, error: devError } = await supabase
      .from("devices")
      .select("id, device_name, fcm_token")
      .eq("id", device_id)
      .single();

    if (devError || !device || !device.fcm_token) {
      return new Response(
        JSON.stringify({
          success: false,
          message: "Thiết bị chưa đăng ký fcm_token hoặc không tìm thấy",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Đọc cấu hình Firebase từ Supabase Secrets
    const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    let projectId = Deno.env.get("FIREBASE_PROJECT_ID");
    let clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL");
    let privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY");

    if (serviceAccountJson) {
      const parsed = JSON.parse(serviceAccountJson);
      projectId = parsed.project_id;
      clientEmail = parsed.client_email;
      privateKey = parsed.private_key;
    }

    if (!projectId || !clientEmail || !privateKey) {
      return new Response(
        JSON.stringify({
          success: false,
          message: "Thiếu cấu hình Firebase Service Account trên server (FIREBASE_SERVICE_ACCOUNT_JSON)",
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Lấy OAuth2 Access Token
    const accessToken = await getGoogleAccessToken(clientEmail, privateKey);

    // Chuẩn bị Data Payload (Silent high-priority push)
    const dataPayload: Record<string, string> = {
      action: action,
      device_id: device_id,
      timestamp: Date.now().toString(),
    };

    if (is_locked !== undefined) {
      dataPayload.is_locked = is_locked.toString();
    }
    if (extra_minutes !== undefined) {
      dataPayload.extra_minutes = extra_minutes.toString();
    }
    if (body.title !== undefined) dataPayload.title = body.title;
    if (body.body !== undefined) dataPayload.body = body.body;
    if (body.message_id !== undefined) dataPayload.message_id = body.message_id;
    if (body.template_key !== undefined) dataPayload.template_key = body.template_key;
    if (body.status !== undefined) dataPayload.status = body.status;
    if (body.granted_minutes !== undefined) dataPayload.granted_minutes = body.granted_minutes.toString();

    // Gửi bản tin FCM HTTP v1
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
    const fcmMessage = {
      message: {
        token: device.fcm_token,
        data: dataPayload,
        android: {
          priority: "HIGH",
          direct_boot_ok: true,
        },
      },
    };

    const fcmResponse = await fetch(fcmUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(fcmMessage),
    });

    const fcmResult = await fcmResponse.json();

    if (!fcmResponse.ok) {
      return new Response(
        JSON.stringify({ success: false, error: fcmResult }),
        { status: fcmResponse.status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: "FCM Push sent successfully",
        fcm_name: fcmResult.name,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
