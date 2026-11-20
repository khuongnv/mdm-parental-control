// Shared Web-Standard ESM helpers for Firebase Cloud Messaging (FCM HTTP v1)
// Compatible with both Supabase Edge Functions (Deno) and Node.js v20+ (`node --test`).

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

/**
 * Resolve Firebase Service Account credentials from environment getter.
 * Supports FIREBASE_SERVICE_ACCOUNT_JSON, FIREBASE_SERVICE_ACCOUNT,
 * and individual FIREBASE_PROJECT_ID / FIREBASE_CLIENT_EMAIL / FIREBASE_PRIVATE_KEY.
 */
export function resolveFirebaseCredentials(getEnv) {
  if (typeof getEnv !== "function") {
    return null;
  }

  const rawJson = getEnv("FIREBASE_SERVICE_ACCOUNT_JSON") || getEnv("FIREBASE_SERVICE_ACCOUNT");
  let projectId = getEnv("FIREBASE_PROJECT_ID") || "";
  let clientEmail = getEnv("FIREBASE_CLIENT_EMAIL") || "";
  let privateKey = getEnv("FIREBASE_PRIVATE_KEY") || "";

  if (rawJson && String(rawJson).trim() !== "") {
    let parsed;
    try {
      parsed = JSON.parse(rawJson);
    } catch (err) {
      throw new Error(`Invalid Firebase service account JSON: ${err instanceof Error ? err.message : String(err)}`);
    }
    projectId = parsed.project_id || projectId;
    clientEmail = parsed.client_email || clientEmail;
    privateKey = parsed.private_key || privateKey;
  }

  projectId = String(projectId || "").trim();
  clientEmail = String(clientEmail || "").trim();
  privateKey = String(privateKey || "").trim();

  if (!projectId || !clientEmail || !privateKey) {
    return null;
  }

  return { projectId, clientEmail, privateKey };
}

/**
 * Unescape literal `\\n`, strip PEM header/footer, and remove whitespace.
 */
export function normalizePemPrivateKey(privateKey) {
  return String(privateKey || "")
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/g, "")
    .replace(/-----END [A-Z0-9 ]*PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
}

function bytesToBase64(bytes) {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    const chunk = bytes.subarray(i, i + chunkSize);
    binary += String.fromCharCode(...chunk);
  }
  return btoa(binary);
}

function base64UrlFromBytes(bytes) {
  return bytesToBase64(bytes)
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function base64UrlFromJson(obj) {
  const encoded = new TextEncoder().encode(JSON.stringify(obj));
  return base64UrlFromBytes(encoded);
}

function base64ToBytes(b64) {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/**
 * Build and sign an RS256 Google OAuth2 Service Account JWT using Web Crypto API.
 */
export async function createServiceAccountJwt({
  clientEmail,
  privateKey,
  scope = "https://www.googleapis.com/auth/firebase.messaging",
  nowSeconds = Math.floor(Date.now() / 1000),
  subtle = globalThis.crypto?.subtle,
}) {
  if (!subtle) {
    throw new Error("Web Crypto SubtleCrypto is unavailable");
  }

  const header = { alg: "RS256", typ: "JWT" };
  const claim = {
    iss: clientEmail,
    scope,
    aud: "https://oauth2.googleapis.com/token",
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  };

  const unsignedToken = `${base64UrlFromJson(header)}.${base64UrlFromJson(claim)}`;
  const cleanKeyB64 = normalizePemPrivateKey(privateKey);
  const binaryKey = base64ToBytes(cleanKeyB64);

  const cryptoKey = await subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signatureBuffer = await subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(unsignedToken)
  );

  const signatureB64 = base64UrlFromBytes(new Uint8Array(signatureBuffer));
  return `${unsignedToken}.${signatureB64}`;
}

const accessTokenCache = new Map();

export function clearAccessTokenCache() {
  accessTokenCache.clear();
}

/**
 * Exchange Service Account JWT for a Google OAuth2 access token with warm-isolate caching.
 */
export async function getGoogleAccessToken({
  clientEmail,
  privateKey,
  fetchImpl = globalThis.fetch,
  nowSeconds = () => Math.floor(Date.now() / 1000),
  subtle = globalThis.crypto?.subtle,
  useCache = true,
}) {
  const currentSec = typeof nowSeconds === "function" ? nowSeconds() : nowSeconds;

  if (useCache) {
    const cached = accessTokenCache.get(clientEmail);
    if (cached && cached.expiresAt > currentSec + 300) {
      return cached.accessToken;
    }
  }

  const jwt = await createServiceAccountJwt({
    clientEmail,
    privateKey,
    nowSeconds: currentSec,
    subtle,
  });

  const tokenRes = await fetchImpl("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const rawTokenText = await tokenRes.text();
  let tokenData = null;
  if (rawTokenText) {
    try {
      tokenData = JSON.parse(rawTokenText);
    } catch {
      tokenData = null;
    }
  }
  if (!tokenRes.ok || !tokenData?.access_token) {
    const detail = tokenData ? JSON.stringify(tokenData) : rawTokenText.slice(0, 300);
    throw new Error(
      `Failed to obtain Google access token (HTTP ${tokenRes.status}): ${detail || "empty response"}`
    );
  }

  const ttl = Number(tokenData.expires_in) > 0 ? Number(tokenData.expires_in) : 3600;
  if (useCache) {
    accessTokenCache.set(clientEmail, {
      accessToken: tokenData.access_token,
      expiresAt: currentSec + ttl,
    });
  }

  return tokenData.access_token;
}

/**
 * Coerce all defined entries to strings; omit null/undefined so "null" never leaks into FCM data.
 */
export function stringifyDataMap(input) {
  const out = {};
  if (!input || typeof input !== "object") {
    return out;
  }

  for (const [key, value] of Object.entries(input)) {
    if (value === null || value === undefined) {
      continue;
    }
    if (typeof value === "string") {
      out[key] = value;
    } else if (typeof value === "number" || typeof value === "boolean") {
      out[key] = String(value);
    } else {
      out[key] = JSON.stringify(value);
    }
  }
  return out;
}

/**
 * Build FCM HTTP v1 payload for Parent -> Child silent/high-priority commands.
 * Preserves Android data-only behavior (no top-level notification block) and adds silent APNs block.
 */
export function buildChildCommandFcmMessage(token, payload, nowMs = Date.now()) {
  const data = stringifyDataMap({
    action: payload?.action,
    device_id: payload?.device_id,
    timestamp: String(nowMs),
    is_locked: payload?.is_locked,
    extra_minutes: payload?.extra_minutes,
    delta_minutes: payload?.delta_minutes,
    reason: payload?.reason,
    title: payload?.title,
    body: payload?.body,
    message_id: payload?.message_id,
    template_key: payload?.template_key,
    status: payload?.status,
    granted_minutes: payload?.granted_minutes,
  });

  return {
    message: {
      token,
      data,
      android: {
        priority: "HIGH",
        direct_boot_ok: true,
      },
      apns: {
        headers: {
          "apns-push-type": "background",
          "apns-priority": "5",
        },
        payload: {
          aps: {
            "content-available": 1,
          },
        },
      },
    },
  };
}

/**
 * Build FCM HTTP v1 alert payload for Child -> Parent notifications (Android + iOS APNs).
 */
export function buildParentAlertFcmMessage(token, { title, body, data = {} }) {
  const stringData = stringifyDataMap(data);

  return {
    message: {
      token,
      notification: {
        title,
        body,
      },
      data: stringData,
      android: {
        priority: "HIGH",
        notification: {
          channel_id: "vfam_admin_alerts",
          sound: "default",
        },
      },
      apns: {
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert",
        },
        payload: {
          aps: {
            alert: {
              title,
              body,
            },
            sound: "default",
            badge: 1,
            "content-available": 1,
          },
        },
      },
    },
  };
}

/**
 * Send an FCM HTTP v1 message payload.
 */
export async function sendFcmV1Message({
  projectId,
  accessToken,
  message,
  fetchImpl = globalThis.fetch,
}) {
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`;
  const res = await fetchImpl(fcmUrl, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(message),
  });

  let result;
  try {
    result = await res.json();
  } catch {
    result = { error: { message: `Non-JSON response with status ${res.status}` } };
  }

  return {
    ok: res.ok,
    status: res.status,
    result,
  };
}

/**
 * Determine whether an FCM HTTP v1 error response indicates an invalid/unregistered token
 * that should be cleaned up from `parent_push_tokens`.
 * Non-token BadRequest field violations (e.g. `message.apns`) return false.
 */
export function isStaleFcmTokenError(status, errorBody) {
  const errObj = errorBody?.error ?? errorBody ?? {};
  const errStatus = String(errObj.status || "").toUpperCase();
  const errMsg = String(errObj.message || "");
  const details = Array.isArray(errObj.details) ? errObj.details : [];

  const fieldViolations = [];
  let hasFcmUnregistered = false;
  let hasFcmInvalidArg = false;

  for (const detail of details) {
    if (!detail || typeof detail !== "object") continue;

    const errorCode = String(detail.errorCode || "").toUpperCase();
    if (errorCode === "UNREGISTERED" || errorCode === "NOT_REGISTERED") {
      hasFcmUnregistered = true;
    } else if (errorCode === "INVALID_ARGUMENT") {
      hasFcmInvalidArg = true;
    }

    if (Array.isArray(detail.fieldViolations)) {
      for (const fv of detail.fieldViolations) {
        fieldViolations.push(String(fv?.field || "").toLowerCase());
      }
    }
  }

  const hasNonTokenViolation = fieldViolations.some(
    (field) => field && !field.includes("token") && !field.includes("registration")
  );
  const hasTokenViolation = fieldViolations.some(
    (field) => field.includes("token") || field.includes("registration")
  );

  if (hasNonTokenViolation && !hasTokenViolation && !hasFcmUnregistered) {
    return false;
  }

  if (hasFcmUnregistered || errStatus === "UNREGISTERED") {
    return true;
  }

  if (
    (errStatus === "NOT_FOUND" || status === 404) &&
    /unregistered|notregistered/i.test(`${errMsg} ${JSON.stringify(details)}`)
  ) {
    return true;
  }

  if (hasFcmInvalidArg || errStatus === "INVALID_ARGUMENT") {
    if (hasTokenViolation) {
      return true;
    }
    if (
      fieldViolations.length === 0 &&
      /token|registration|notregistered|invalidregistration/i.test(
        `${errMsg} ${JSON.stringify(details)}`
      )
    ) {
      return true;
    }
  }

  if (/notregistered|invalidregistration|registration-token-not-registered/i.test(errMsg)) {
    return true;
  }

  return false;
}
