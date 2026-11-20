// Shared Web-Standard ESM orchestration for `notify-family-parents` Edge Function.
// Zero Node-only imports; runs identically on Deno and Node.js v20+ (`node --test`).

import {
  buildParentAlertFcmMessage,
  getGoogleAccessToken,
  isStaleFcmTokenError,
  resolveFirebaseCredentials,
  sendFcmV1Message,
  stringifyDataMap,
} from "./fcm.mjs";

export const VALID_EVENT_TYPES = [
  "TIME_REQUEST",
  "DEVICE_MESSAGE_ACK",
  "DEVICE_MESSAGE_REPLY",
];

export function resolveEventTable(eventType) {
  if (eventType === "TIME_REQUEST") {
    return "time_requests";
  }
  if (eventType === "DEVICE_MESSAGE_ACK" || eventType === "DEVICE_MESSAGE_REPLY") {
    return "device_messages";
  }
  return null;
}

export function deduplicateParentUserIds(memberRows, familyRow) {
  const seen = new Set();
  const out = [];

  if (Array.isArray(memberRows)) {
    for (const row of memberRows) {
      const uid = row?.user_id ? String(row.user_id).trim() : "";
      if (uid && !seen.has(uid)) {
        seen.add(uid);
        out.push(uid);
      }
    }
  }

  const ownerId = familyRow?.created_by ? String(familyRow.created_by).trim() : "";
  if (ownerId && !seen.has(ownerId)) {
    seen.add(ownerId);
    out.push(ownerId);
  }

  return out;
}

const MAX_NOTIFICATION_TITLE_CHARS = 200;
const MAX_NOTIFICATION_BODY_CHARS = 1000;
const MAX_DATA_TEXT_CHARS = 1000;

function truncateText(value, maxLen) {
  const str = String(value ?? "");
  const chars = Array.from(str);
  if (chars.length <= maxLen) {
    return str;
  }
  if (maxLen <= 1) {
    return chars.slice(0, maxLen).join("");
  }
  return `${chars.slice(0, maxLen - 1).join("")}…`;
}

export function buildParentNotificationCopy({
  eventType,
  deviceName,
  title,
  body,
  data = {},
  claimedRecord = null,
}) {
  const safeData = data && typeof data === "object" && !Array.isArray(data) ? data : {};
  const safeDeviceName = String(deviceName || "").trim() || "Thiết bị con";
  const explicitTitle = typeof title === "string" && title.trim() !== "" ? title.trim() : null;
  const explicitBody = typeof body === "string" && body.trim() !== "" ? body.trim() : null;

  let defaultTitle = `🔔 Thông báo từ ${safeDeviceName}`;
  let defaultBody = `${safeDeviceName} vừa gửi cập nhật mới.`;

  if (eventType === "TIME_REQUEST") {
    const minutes = safeData?.requested_minutes ?? claimedRecord?.requested_minutes;
    const reason = String(safeData?.reason ?? claimedRecord?.reason ?? "").trim();
    defaultTitle = `🙋 ${safeDeviceName} Xin Thêm Giờ Chơi!`;
    defaultBody = minutes
      ? `Xin thêm +${minutes} phút${reason ? `. Lý do: "${reason}"` : "."}`
      : `${safeDeviceName} vừa gửi yêu cầu xin thêm giờ${reason ? `: "${reason}"` : "."}`;
  } else if (eventType === "DEVICE_MESSAGE_REPLY") {
    const reply = String(
      safeData?.child_reply ?? safeData?.reply_text ?? claimedRecord?.child_reply ?? ""
    ).trim();
    defaultTitle = `💬 ${safeDeviceName} Đã Trả Lời!`;
    defaultBody = reply
      ? `"${reply}"`
      : `${safeDeviceName} vừa gửi phản hồi tin nhắn.`;
  } else if (eventType === "DEVICE_MESSAGE_ACK") {
    const msgText = String(safeData?.message_text ?? claimedRecord?.message_text ?? "").trim();
    defaultTitle = `👍 ${safeDeviceName} Đã Xác Nhận!`;
    defaultBody = msgText
      ? `Bé đã xác nhận đã đọc: "${msgText}"`
      : `Bé đã bấm "Dạ con nghe rồi!"`;
  }

  return {
    title: truncateText(explicitTitle ?? defaultTitle, MAX_NOTIFICATION_TITLE_CHARS),
    body: truncateText(explicitBody ?? defaultBody, MAX_NOTIFICATION_BODY_CHARS),
  };
}

async function postgrestFetch({
  supabaseUrl,
  serviceRoleKey,
  path,
  method = "GET",
  headers = {},
  body = undefined,
  fetchImpl = globalThis.fetch,
}) {
  const baseUrl = String(supabaseUrl).replace(/\/+$/, "");
  const res = await fetchImpl(`${baseUrl}/rest/v1/${path}`, {
    method,
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      "Content-Type": "application/json",
      ...headers,
    },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });

  let data = null;
  const text = await res.text();
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
  }

  if (!res.ok) {
    throw new Error(`PostgREST ${method} ${path} failed (${res.status}): ${JSON.stringify(data)}`);
  }

  return data;
}

async function rollbackFcmClaim({
  supabaseUrl,
  serviceRoleKey,
  table,
  recordId,
  deviceId,
  familyId,
  fetchImpl,
}) {
  if (!table || !recordId) {
    return;
  }
  try {
    await postgrestFetch({
      supabaseUrl,
      serviceRoleKey,
      path: `${table}?id=eq.${encodeURIComponent(recordId)}&device_id=eq.${encodeURIComponent(deviceId)}&family_id=eq.${encodeURIComponent(familyId)}`,
      method: "PATCH",
      body: {
        fcm_notified_at: null,
      },
      fetchImpl,
    });
  } catch {
    // Best-effort rollback so transient OAuth/FCM failures remain retryable
  }
}

export async function handleNotifyFamilyParents({
  payload,
  env,
  fetchImpl = globalThis.fetch,
  nowMs = Date.now(),
  accessTokenProvider = null,
}) {
  const getEnv = typeof env === "function" ? env : (key) => env?.[key];

  const deviceId = payload?.device_id ? String(payload.device_id).trim() : "";
  const eventType = payload?.event_type ? String(payload.event_type).trim() : "";
  const recordId = payload?.record_id ? String(payload.record_id).trim() : "";

  if (!deviceId || !eventType) {
    return {
      status: 400,
      body: { success: false, error: "device_id and event_type are required" },
    };
  }

  if (!VALID_EVENT_TYPES.includes(eventType)) {
    return {
      status: 400,
      body: {
        success: false,
        error: `Unsupported event_type '${eventType}'. Expected one of: ${VALID_EVENT_TYPES.join(", ")}`,
      },
    };
  }

  const supabaseUrl = String(getEnv("SUPABASE_URL") || "").trim();
  const serviceRoleKey = String(getEnv("SUPABASE_SERVICE_ROLE_KEY") || "").trim();
  if (!supabaseUrl || !serviceRoleKey) {
    return {
      status: 500,
      body: {
        success: false,
        error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY configuration",
      },
    };
  }

  let firebaseCreds;
  try {
    firebaseCreds = resolveFirebaseCredentials(getEnv);
  } catch (err) {
    return {
      status: 500,
      body: {
        success: false,
        error: err instanceof Error ? err.message : String(err),
      },
    };
  }

  if (!firebaseCreds) {
    return {
      status: 500,
      body: {
        success: false,
        error: "Missing Firebase Service Account configuration (FIREBASE_SERVICE_ACCOUNT_JSON / FIREBASE_SERVICE_ACCOUNT)",
      },
    };
  }

  // 1. Lookup device info (authoritative family_id & display name)
  const deviceRows = await postgrestFetch({
    supabaseUrl,
    serviceRoleKey,
    path: `devices?id=eq.${encodeURIComponent(deviceId)}&select=id,family_id,device_name,custom_name`,
    fetchImpl,
  });
  const device = Array.isArray(deviceRows) && deviceRows.length > 0 ? deviceRows[0] : null;
  const deviceFamilyId = device?.family_id ? String(device.family_id).trim() : "";

  if (!device || !deviceFamilyId) {
    return {
      status: 200,
      body: {
        success: false,
        skipped: true,
        reason: "missing_family_id",
        message: "Device not found or not paired to a family",
      },
    };
  }

  const suppliedFamilyId =
    payload?.family_id !== undefined && payload?.family_id !== null
      ? String(payload.family_id).trim()
      : "";
  if (suppliedFamilyId && suppliedFamilyId !== deviceFamilyId) {
    return {
      status: 403,
      body: {
        success: false,
        error: "family_id does not match paired device",
      },
    };
  }

  const familyId = deviceFamilyId;
  const deviceName =
    String(device?.custom_name || "").trim() ||
    String(device?.device_name || "").trim() ||
    "Thiết bị con";

  // 2. Collect deduplicated parent user_ids from family_members + families.created_by
  const [memberRows, familyRows] = await Promise.all([
    postgrestFetch({
      supabaseUrl,
      serviceRoleKey,
      path: `family_members?family_id=eq.${encodeURIComponent(familyId)}&select=user_id`,
      fetchImpl,
    }),
    postgrestFetch({
      supabaseUrl,
      serviceRoleKey,
      path: `families?id=eq.${encodeURIComponent(familyId)}&select=created_by`,
      fetchImpl,
    }),
  ]);

  const familyRow = Array.isArray(familyRows) && familyRows.length > 0 ? familyRows[0] : null;
  const parentUserIds = deduplicateParentUserIds(memberRows, familyRow);

  if (parentUserIds.length === 0) {
    return {
      status: 200,
      body: {
        success: true,
        sent: 0,
        total_tokens: 0,
        skipped: true,
        reason: "no_parents",
      },
    };
  }

  // 3. Query all parent push tokens and deduplicate by fcm_token
  const inFilter = parentUserIds.map((uid) => encodeURIComponent(uid)).join(",");
  const tokenRows = await postgrestFetch({
    supabaseUrl,
    serviceRoleKey,
    path: `parent_push_tokens?user_id=in.(${inFilter})&select=id,user_id,fcm_token,platform`,
    fetchImpl,
  });

  const seenTokens = new Set();
  const uniqueTokens = [];
  if (Array.isArray(tokenRows)) {
    for (const row of tokenRows) {
      const tok = row?.fcm_token ? String(row.fcm_token).trim() : "";
      if (tok && !seenTokens.has(tok)) {
        seenTokens.add(tok);
        uniqueTokens.push(row);
      }
    }
  }

  if (uniqueTokens.length === 0) {
    return {
      status: 200,
      body: {
        success: true,
        sent: 0,
        total_tokens: 0,
        skipped: true,
        reason: "no_push_tokens",
      },
    };
  }

  // 4. Obtain Google OAuth2 Access Token BEFORE claiming fcm_notified_at
  const accessToken = accessTokenProvider
    ? await accessTokenProvider(firebaseCreds)
    : await getGoogleAccessToken({
        clientEmail: firebaseCreds.clientEmail,
        privateKey: firebaseCreds.privateKey,
        fetchImpl,
      });

  // 5. Atomic idempotency claim when record_id is provided (bound to device_id & family_id)
  const eventTable = resolveEventTable(eventType);
  let claimedRecord = null;
  if (recordId) {
    const claimedRows = await postgrestFetch({
      supabaseUrl,
      serviceRoleKey,
      path: `${eventTable}?id=eq.${encodeURIComponent(recordId)}&device_id=eq.${encodeURIComponent(deviceId)}&family_id=eq.${encodeURIComponent(familyId)}&fcm_notified_at=is.null`,
      method: "PATCH",
      headers: {
        Prefer: "return=representation",
      },
      body: {
        fcm_notified_at: new Date(nowMs).toISOString(),
      },
      fetchImpl,
    });

    if (!Array.isArray(claimedRows) || claimedRows.length === 0) {
      return {
        status: 200,
        body: {
          success: true,
          deduplicated: true,
          skipped: true,
          record_id: recordId,
          event_type: eventType,
        },
      };
    }

    claimedRecord = claimedRows[0];
  }

  try {
    // 6. Build notification copy & stringified data payload
    const safePayloadData =
      payload?.data && typeof payload.data === "object" && !Array.isArray(payload.data)
        ? payload.data
        : {};

    const { title, body } = buildParentNotificationCopy({
      eventType,
      deviceName,
      title: payload?.title,
      body: payload?.body,
      data: safePayloadData,
      claimedRecord,
    });

    const rawReason = claimedRecord?.reason ?? safePayloadData?.reason;
    const rawChildReply = claimedRecord?.child_reply ?? safePayloadData?.child_reply;
    const rawMessageText = claimedRecord?.message_text ?? safePayloadData?.message_text;
    const rawReplyText = safePayloadData?.reply_text;

    const dataMap = stringifyDataMap({
      ...safePayloadData,
      event_type: eventType,
      device_id: deviceId,
      family_id: familyId,
      device_name: deviceName,
      title,
      body,
      ...(recordId ? { record_id: recordId } : {}),
      ...(claimedRecord?.requested_minutes != null
        ? { requested_minutes: claimedRecord.requested_minutes }
        : {}),
      ...(rawReason != null ? { reason: truncateText(rawReason, MAX_DATA_TEXT_CHARS) } : {}),
      ...(rawChildReply != null
        ? { child_reply: truncateText(rawChildReply, MAX_DATA_TEXT_CHARS) }
        : {}),
      ...(rawMessageText != null
        ? { message_text: truncateText(rawMessageText, MAX_DATA_TEXT_CHARS) }
        : {}),
      ...(rawReplyText != null
        ? { reply_text: truncateText(rawReplyText, MAX_DATA_TEXT_CHARS) }
        : {}),
      timestamp: String(nowMs),
    });

    // 7. Fan out FCM pushes concurrently
    const sendResults = await Promise.allSettled(
      uniqueTokens.map(async (row) => {
        const fcmMessage = buildParentAlertFcmMessage(row.fcm_token, {
          title,
          body,
          data: dataMap,
        });
        const res = await sendFcmV1Message({
          projectId: firebaseCreds.projectId,
          accessToken,
          message: fcmMessage,
          fetchImpl,
        });
        return { row, res };
      })
    );

    let sent = 0;
    let failed = 0;
    let nonStaleFailed = 0;
    const staleIds = [];
    const staleTokenStrings = [];

    for (const outcome of sendResults) {
      if (outcome.status === "rejected") {
        failed += 1;
        nonStaleFailed += 1;
        continue;
      }

      const { row, res } = outcome.value;
      if (res.ok) {
        sent += 1;
      } else {
        failed += 1;
        if (isStaleFcmTokenError(res.status, res.result)) {
          if (row.id) {
            staleIds.push(String(row.id));
          } else if (row.fcm_token) {
            staleTokenStrings.push(String(row.fcm_token));
          }
        } else {
          nonStaleFailed += 1;
        }
      }
    }

    // 8. Clean up stale/unregistered tokens from parent_push_tokens
    let staleTokensRemoved = 0;
    if (staleIds.length > 0) {
      const idFilter = staleIds.map((id) => encodeURIComponent(id)).join(",");
      await postgrestFetch({
        supabaseUrl,
        serviceRoleKey,
        path: `parent_push_tokens?id=in.(${idFilter})`,
        method: "DELETE",
        fetchImpl,
      });
      staleTokensRemoved += staleIds.length;
    }
    if (staleTokenStrings.length > 0) {
      const tokFilter = staleTokenStrings.map((t) => encodeURIComponent(t)).join(",");
      await postgrestFetch({
        supabaseUrl,
        serviceRoleKey,
        path: `parent_push_tokens?fcm_token=in.(${tokFilter})`,
        method: "DELETE",
        fetchImpl,
      });
      staleTokensRemoved += staleTokenStrings.length;
    }

    // 9. Roll back fcm_notified_at when all deliveries fail transiently (502) so retries succeed
    if (recordId && claimedRecord && sent === 0 && nonStaleFailed > 0) {
      await rollbackFcmClaim({
        supabaseUrl,
        serviceRoleKey,
        table: eventTable,
        recordId,
        deviceId,
        familyId,
        fetchImpl,
      });
    }

    const httpStatus = sent === 0 && nonStaleFailed > 0 ? 502 : 200;
    return {
      status: httpStatus,
      body: {
        success: sent > 0 || nonStaleFailed === 0,
        event_type: eventType,
        device_id: deviceId,
        family_id: familyId,
        record_id: recordId || null,
        total_tokens: uniqueTokens.length,
        sent,
        failed,
        stale_tokens_removed: staleTokensRemoved,
      },
    };
  } catch (err) {
    if (recordId && claimedRecord) {
      await rollbackFcmClaim({
        supabaseUrl,
        serviceRoleKey,
        table: eventTable,
        recordId,
        deviceId,
        familyId,
        fetchImpl,
      });
    }
    throw err;
  }
}
