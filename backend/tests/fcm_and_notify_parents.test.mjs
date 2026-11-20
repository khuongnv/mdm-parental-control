import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";

import {
  buildChildCommandFcmMessage,
  buildParentAlertFcmMessage,
  clearAccessTokenCache,
  createServiceAccountJwt,
  getGoogleAccessToken,
  isStaleFcmTokenError,
  normalizePemPrivateKey,
  resolveFirebaseCredentials,
  stringifyDataMap,
} from "../supabase/functions/_shared/fcm.mjs";

import {
  buildParentNotificationCopy,
  deduplicateParentUserIds,
  handleNotifyFamilyParents,
} from "../supabase/functions/_shared/notify_parents.mjs";

function generateTestRsaKeyPair() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync("rsa", {
    modulusLength: 2048,
    publicKeyEncoding: { type: "spki", format: "pem" },
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
  });
  return { publicKey, privateKey };
}

test("resolveFirebaseCredentials supports JSON, FIREBASE_SERVICE_ACCOUNT alias, split vars, and missing/invalid handling", () => {
  const fromPrimary = resolveFirebaseCredentials((k) =>
    k === "FIREBASE_SERVICE_ACCOUNT_JSON"
      ? JSON.stringify({
          project_id: "proj-1",
          client_email: "svc@proj-1.iam.gserviceaccount.com",
          private_key: "pem-1",
        })
      : undefined
  );
  assert.deepEqual(fromPrimary, {
    projectId: "proj-1",
    clientEmail: "svc@proj-1.iam.gserviceaccount.com",
    privateKey: "pem-1",
  });

  const fromAlias = resolveFirebaseCredentials((k) =>
    k === "FIREBASE_SERVICE_ACCOUNT"
      ? JSON.stringify({
          project_id: "proj-alias",
          client_email: "svc@proj-alias.iam.gserviceaccount.com",
          private_key: "pem-alias",
        })
      : undefined
  );
  assert.deepEqual(fromAlias, {
    projectId: "proj-alias",
    clientEmail: "svc@proj-alias.iam.gserviceaccount.com",
    privateKey: "pem-alias",
  });

  const fromSplit = resolveFirebaseCredentials((k) =>
    ({
      FIREBASE_PROJECT_ID: "proj-split",
      FIREBASE_CLIENT_EMAIL: "svc@proj-split.iam.gserviceaccount.com",
      FIREBASE_PRIVATE_KEY: "pem-split",
    })[k]
  );
  assert.deepEqual(fromSplit, {
    projectId: "proj-split",
    clientEmail: "svc@proj-split.iam.gserviceaccount.com",
    privateKey: "pem-split",
  });

  assert.equal(resolveFirebaseCredentials(() => undefined), null);
  assert.throws(
    () =>
      resolveFirebaseCredentials((k) =>
        k === "FIREBASE_SERVICE_ACCOUNT_JSON" ? "{bad-json" : undefined
      ),
    /Invalid Firebase service account JSON/
  );
});

test("createServiceAccountJwt & normalizePemPrivateKey sign verifiable RS256 JWT even with escaped \\\\n", async () => {
  const { publicKey, privateKey } = generateTestRsaKeyPair();
  const escapedPrivateKey = privateKey.replace(/\n/g, "\\n");

  assert.ok(!normalizePemPrivateKey(escapedPrivateKey).includes("BEGIN"));
  assert.ok(!normalizePemPrivateKey(escapedPrivateKey).includes("\\n"));

  const nowSec = 1700000000;
  const jwt = await createServiceAccountJwt({
    clientEmail: "firebase-adminsdk@example.iam.gserviceaccount.com",
    privateKey: escapedPrivateKey,
    nowSeconds: nowSec,
  });

  const parts = jwt.split(".");
  assert.equal(parts.length, 3);

  const header = JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8"));
  const claims = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
  assert.deepEqual(header, { alg: "RS256", typ: "JWT" });
  assert.equal(claims.iss, "firebase-adminsdk@example.iam.gserviceaccount.com");
  assert.equal(claims.scope, "https://www.googleapis.com/auth/firebase.messaging");
  assert.equal(claims.aud, "https://oauth2.googleapis.com/token");
  assert.equal(claims.iat, nowSec);
  assert.equal(claims.exp, nowSec + 3600);

  const isValid = crypto.verify(
    "RSA-SHA256",
    Buffer.from(`${parts[0]}.${parts[1]}`),
    publicKey,
    Buffer.from(parts[2], "base64url")
  );
  assert.equal(isValid, true);
});

test("getGoogleAccessToken caches token per clientEmail and refreshes when near expiry", async () => {
  clearAccessTokenCache();
  const { privateKey } = generateTestRsaKeyPair();
  let tokenCallCount = 0;
  let currentSec = 1700000000;

  const mockFetch = async (url) => {
    assert.equal(url, "https://oauth2.googleapis.com/token");
    tokenCallCount += 1;
    return new Response(
      JSON.stringify({ access_token: `access-tok-${tokenCallCount}`, expires_in: 3600 }),
      { status: 200 }
    );
  };

  const t1 = await getGoogleAccessToken({
    clientEmail: "cache-test@example.iam.gserviceaccount.com",
    privateKey,
    fetchImpl: mockFetch,
    nowSeconds: () => currentSec,
  });
  const t2 = await getGoogleAccessToken({
    clientEmail: "cache-test@example.iam.gserviceaccount.com",
    privateKey,
    fetchImpl: mockFetch,
    nowSeconds: () => currentSec + 100,
  });
  assert.equal(t1, "access-tok-1");
  assert.equal(t2, "access-tok-1");
  assert.equal(tokenCallCount, 1);

  currentSec += 3400; // within 300s of 3600s expiry
  const t3 = await getGoogleAccessToken({
    clientEmail: "cache-test@example.iam.gserviceaccount.com",
    privateKey,
    fetchImpl: mockFetch,
    nowSeconds: () => currentSec,
  });
  assert.equal(t3, "access-tok-2");
  assert.equal(tokenCallCount, 2);
});

test("buildChildCommandFcmMessage handles all 6 actions, omits null values, and adds silent APNs", () => {
  const actions = [
    { action: "PANIC_LOCKDOWN", is_locked: true, reason: null },
    { action: "GRANT_EXTRA_TIME", extra_minutes: 15, reason: "Hoàn thành bài tập" },
    { action: "ADJUST_SCREEN_TIME", delta_minutes: -10, reason: null },
    { action: "SYNC_POLICY" },
    { action: "REMOTE_MESSAGE", title: "Nhắc nhở", body: "Đi ngủ thôi", message_id: "msg-1", template_key: "bedtime" },
    { action: "TIME_REQUEST_RESOLVED", status: "approved", granted_minutes: 20 },
  ];

  for (const item of actions) {
    const msg = buildChildCommandFcmMessage("child-fcm-token", { device_id: "dev-1", ...item }, 1700000000000);
    assert.equal(msg.message.token, "child-fcm-token");
    assert.equal(msg.message.notification, undefined, "Child commands must stay Android data-only");
    assert.equal(msg.message.data.action, item.action);
    assert.equal(msg.message.data.device_id, "dev-1");
    assert.equal(msg.message.data.timestamp, "1700000000000");

    for (const [k, v] of Object.entries(msg.message.data)) {
      assert.equal(typeof v, "string", `data.${k} must be a string`);
      assert.notEqual(v, "null", `data.${k} must not serialize null`);
    }
    assert.equal("reason" in msg.message.data, item.reason != null);

    assert.deepEqual(msg.message.android, {
      priority: "HIGH",
      direct_boot_ok: true,
    });
    assert.deepEqual(msg.message.apns, {
      headers: {
        "apns-push-type": "background",
        "apns-priority": "5",
      },
      payload: {
        aps: {
          "content-available": 1,
        },
      },
    });
  }
});

test("buildParentAlertFcmMessage produces Android vfam_admin_alerts + iOS APNs alert payload", () => {
  const msg = buildParentAlertFcmMessage("parent-tok-1", {
    title: "Bé Xin Thêm Giờ",
    body: "Xin thêm +15 phút",
    data: {
      event_type: "TIME_REQUEST",
      requested_minutes: 15,
      ignored_null: null,
    },
  });

  assert.deepEqual(msg.message.notification, {
    title: "Bé Xin Thêm Giờ",
    body: "Xin thêm +15 phút",
  });
  assert.deepEqual(msg.message.data, {
    event_type: "TIME_REQUEST",
    requested_minutes: "15",
  });
  assert.deepEqual(msg.message.android, {
    priority: "HIGH",
    notification: {
      channel_id: "vfam_admin_alerts",
      sound: "default",
    },
  });
  assert.deepEqual(msg.message.apns, {
    headers: {
      "apns-priority": "10",
      "apns-push-type": "alert",
    },
    payload: {
      aps: {
        alert: {
          title: "Bé Xin Thêm Giờ",
          body: "Xin thêm +15 phút",
        },
        sound: "default",
        badge: 1,
        "content-available": 1,
      },
    },
  });
});

test("isStaleFcmTokenError distinguishes unregistered/token errors from non-token BadRequest errors", () => {
  assert.equal(
    isStaleFcmTokenError(404, {
      error: {
        status: "NOT_FOUND",
        message: "Requested entity was not found.",
        details: [{ errorCode: "UNREGISTERED" }],
      },
    }),
    true
  );

  assert.equal(
    isStaleFcmTokenError(400, {
      error: {
        status: "INVALID_ARGUMENT",
        message: "The registration token is not a valid FCM registration token",
        details: [{ errorCode: "INVALID_ARGUMENT" }],
      },
    }),
    true
  );

  assert.equal(
    isStaleFcmTokenError(400, {
      error: {
        status: "INVALID_ARGUMENT",
        message: "Invalid APNs payload",
        details: [
          {
            "@type": "type.googleapis.com/google.rpc.BadRequest",
            fieldViolations: [{ field: "message.apns.headers", description: "bad header" }],
          },
        ],
      },
    }),
    false
  );

  assert.equal(
    isStaleFcmTokenError(500, {
      error: { status: "INTERNAL", message: "Backend error" },
    }),
    false
  );
});

test("stringifyDataMap and deduplicateParentUserIds and copy builders behave deterministically", () => {
  assert.deepEqual(
    stringifyDataMap({ a: 1, b: true, c: null, d: undefined, e: "ok" }),
    { a: "1", b: "true", e: "ok" }
  );

  assert.deepEqual(
    deduplicateParentUserIds(
      [{ user_id: "u1" }, { user_id: "u2" }, { user_id: "u1" }],
      { created_by: "u1" }
    ),
    ["u1", "u2"]
  );
  assert.deepEqual(
    deduplicateParentUserIds([{ user_id: "u2" }], { created_by: "owner-1" }),
    ["u2", "owner-1"]
  );

  const replyCopy = buildParentNotificationCopy({
    eventType: "DEVICE_MESSAGE_REPLY",
    deviceName: "iPad của Bi",
    claimedRecord: { child_reply: "Con làm xong bài rồi ạ!" },
  });
  assert.match(replyCopy.title, /iPad của Bi/);
  assert.match(replyCopy.body, /Con làm xong bài rồi ạ!/);
});

test("handleNotifyFamilyParents enforces credentials-before-claim, atomic dedup, parent dedup, and stale token cleanup", async () => {
  const baseEnv = {
    SUPABASE_URL: "https://example.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "service-role-secret",
    FIREBASE_SERVICE_ACCOUNT: JSON.stringify({
      project_id: "vfam-proj",
      client_email: "firebase@vfam-proj.iam.gserviceaccount.com",
      private_key: "unused-due-to-provider",
    }),
  };

  // 1. Missing Firebase credentials fails BEFORE claiming fcm_notified_at
  const callsWhenNoCreds = [];
  const noCredsRes = await handleNotifyFamilyParents({
    payload: {
      device_id: "dev-1",
      event_type: "TIME_REQUEST",
      record_id: "req-1",
    },
    env: {
      SUPABASE_URL: "https://example.supabase.co",
      SUPABASE_SERVICE_ROLE_KEY: "service-role-secret",
    },
    fetchImpl: async (url, init) => {
      callsWhenNoCreds.push({ url, method: init?.method || "GET" });
      return new Response("[]", { status: 200 });
    },
  });
  assert.equal(noCredsRes.status, 500);
  assert.equal(callsWhenNoCreds.length, 0);

  // 2. Full fan-out + atomic dedup + stale token cleanup
  let claimed = false;
  const fcmSentPayloads = [];
  const deletedPaths = [];

  const mockFetch = async (url, init = {}) => {
    const method = init.method || "GET";
    if (url.includes("/rest/v1/devices?")) {
      return new Response(
        JSON.stringify([
          {
            id: "dev-1",
            family_id: "fam-1",
            device_name: "Galaxy A54",
            custom_name: "Máy của Bông",
          },
        ]),
        { status: 200 }
      );
    }

    if (
      url.includes(
        "/rest/v1/time_requests?id=eq.req-1&device_id=eq.dev-1&family_id=eq.fam-1&fcm_notified_at=is.null"
      ) &&
      method === "PATCH"
    ) {
      if (claimed) {
        return new Response(JSON.stringify([]), { status: 200 });
      }
      claimed = true;
      return new Response(
        JSON.stringify([
          {
            id: "req-1",
            requested_minutes: 20,
            reason: "Làm nốt bài tiếng Anh",
          },
        ]),
        { status: 200 }
      );
    }

    if (url.includes("/rest/v1/family_members?")) {
      return new Response(
        JSON.stringify([{ user_id: "parent-1" }, { user_id: "parent-2" }]),
        { status: 200 }
      );
    }

    if (url.includes("/rest/v1/families?")) {
      return new Response(
        JSON.stringify([{ created_by: "parent-1" }]),
        { status: 200 }
      );
    }

    if (url.includes("/rest/v1/parent_push_tokens?") && method === "GET") {
      // Confirm deduplicated user_ids (parent-1, parent-2 — not parent-1 twice)
      assert.ok(url.includes("user_id=in.(parent-1,parent-2)"));
      return new Response(
        JSON.stringify([
          { id: "tok-id-1", user_id: "parent-1", fcm_token: "valid-android-tok", platform: "android" },
          { id: "tok-id-dup", user_id: "parent-1", fcm_token: "valid-android-tok", platform: "android" },
          { id: "tok-id-2", user_id: "parent-2", fcm_token: "stale-ios-tok", platform: "ios" },
          { id: "tok-id-3", user_id: "parent-2", fcm_token: "bad-payload-tok", platform: "ios" },
        ]),
        { status: 200 }
      );
    }

    if (url.includes("fcm.googleapis.com/v1/projects/vfam-proj/messages:send")) {
      const body = JSON.parse(init.body);
      fcmSentPayloads.push(body);
      if (body.message.token === "stale-ios-tok") {
        return new Response(
          JSON.stringify({
            error: {
              status: "NOT_FOUND",
              message: "Requested entity was not found.",
              details: [{ errorCode: "UNREGISTERED" }],
            },
          }),
          { status: 404 }
        );
      }
      if (body.message.token === "bad-payload-tok") {
        return new Response(
          JSON.stringify({
            error: {
              status: "INVALID_ARGUMENT",
              message: "Invalid APNs field",
              details: [
                {
                  "@type": "type.googleapis.com/google.rpc.BadRequest",
                  fieldViolations: [{ field: "message.apns.payload", description: "transient" }],
                },
              ],
            },
          }),
          { status: 400 }
        );
      }
      return new Response(JSON.stringify({ name: "projects/vfam-proj/messages/123" }), {
        status: 200,
      });
    }

    if (url.includes("/rest/v1/parent_push_tokens?") && method === "DELETE") {
      deletedPaths.push(url);
      return new Response(null, { status: 204 });
    }

    throw new Error(`Unexpected fetch: ${method} ${url}`);
  };

  const first = await handleNotifyFamilyParents({
    payload: {
      device_id: "dev-1",
      event_type: "TIME_REQUEST",
      record_id: "req-1",
    },
    env: baseEnv,
    fetchImpl: mockFetch,
    nowMs: 1700000000123,
    accessTokenProvider: async () => "mock-oauth-token",
  });

  assert.equal(first.status, 200);
  assert.equal(first.body.success, true);
  assert.equal(first.body.total_tokens, 3);
  assert.equal(first.body.sent, 1);
  assert.equal(first.body.failed, 2);
  assert.equal(first.body.stale_tokens_removed, 1);

  assert.equal(fcmSentPayloads.length, 3);
  assert.equal(fcmSentPayloads[0].message.android.notification.channel_id, "vfam_admin_alerts");
  assert.equal(fcmSentPayloads[0].message.apns.headers["apns-priority"], "10");
  assert.equal(fcmSentPayloads[0].message.data.requested_minutes, "20");
  assert.equal(fcmSentPayloads[0].message.data.device_name, "Máy của Bông");
  assert.match(fcmSentPayloads[0].message.notification.title, /Máy của Bông/);

  assert.equal(deletedPaths.length, 1);
  assert.ok(deletedPaths[0].includes("id=in.(tok-id-2)"));
  assert.ok(!deletedPaths[0].includes("tok-id-3"), "Non-token BadRequest must not delete token");

  // Second concurrent/duplicate invocation for same record_id must deduplicate without sending FCM
  const second = await handleNotifyFamilyParents({
    payload: {
      device_id: "dev-1",
      event_type: "TIME_REQUEST",
      record_id: "req-1",
    },
    env: baseEnv,
    fetchImpl: mockFetch,
    nowMs: 1700000000456,
    accessTokenProvider: async () => "mock-oauth-token",
  });

  assert.equal(second.status, 200);
  assert.equal(second.body.deduplicated, true);
  assert.equal(second.body.skipped, true);
  assert.equal(fcmSentPayloads.length, 3);
});

test("handleNotifyFamilyParents supports DEVICE_MESSAGE_ACK, DEVICE_MESSAGE_REPLY, and validation errors", async () => {
  const baseEnv = {
    SUPABASE_URL: "https://example.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "service-role-secret",
    FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({
      project_id: "vfam-proj",
      client_email: "firebase@vfam-proj.iam.gserviceaccount.com",
      private_key: "unused",
    }),
  };

  const badEvent = await handleNotifyFamilyParents({
    payload: { device_id: "dev-1", event_type: "UNKNOWN_EVENT" },
    env: baseEnv,
  });
  assert.equal(badEvent.status, 400);

  const sentMessages = [];
  const mockFetch = async (url, init = {}) => {
    const method = init.method || "GET";
    if (url.includes("/rest/v1/devices?")) {
      return new Response(
        JSON.stringify([{ id: "dev-2", family_id: "fam-2", device_name: "Pixel 8", custom_name: null }]),
        { status: 200 }
      );
    }
    if (
      url.includes(
        "/rest/v1/device_messages?id=eq.msg-99&device_id=eq.dev-2&family_id=eq.fam-2&fcm_notified_at=is.null"
      ) &&
      method === "PATCH"
    ) {
      return new Response(
        JSON.stringify([
          {
            id: "msg-99",
            message_text: "Tắt máy đi ngủ nhé",
            child_reply: "Vâng ạ, con đi ngủ ngay",
          },
        ]),
        { status: 200 }
      );
    }
    if (url.includes("/rest/v1/family_members?")) {
      return new Response(JSON.stringify([{ user_id: "p-1" }]), { status: 200 });
    }
    if (url.includes("/rest/v1/families?")) {
      return new Response(JSON.stringify([{ created_by: "p-1" }]), { status: 200 });
    }
    if (url.includes("/rest/v1/parent_push_tokens?")) {
      return new Response(
        JSON.stringify([{ id: "t-1", user_id: "p-1", fcm_token: "ios-tok-1", platform: "ios" }]),
        { status: 200 }
      );
    }
    if (url.includes("fcm.googleapis.com/v1/projects/vfam-proj/messages:send")) {
      sentMessages.push(JSON.parse(init.body));
      return new Response(JSON.stringify({ name: "msg/ok" }), { status: 200 });
    }
    throw new Error(`Unexpected fetch: ${method} ${url}`);
  };

  const res = await handleNotifyFamilyParents({
    payload: {
      device_id: "dev-2",
      event_type: "DEVICE_MESSAGE_REPLY",
      record_id: "msg-99",
    },
    env: baseEnv,
    fetchImpl: mockFetch,
    nowMs: 1700000000999,
    accessTokenProvider: async () => "mock-token",
  });

  assert.equal(res.status, 200);
  assert.equal(res.body.sent, 1);
  assert.equal(sentMessages.length, 1);
  assert.equal(sentMessages[0].message.data.event_type, "DEVICE_MESSAGE_REPLY");
  assert.equal(sentMessages[0].message.data.child_reply, "Vâng ạ, con đi ngủ ngay");
  assert.equal(sentMessages[0].message.apns.headers["apns-push-type"], "alert");
  assert.match(sentMessages[0].message.notification.title, /Pixel 8/);
});

test("handleNotifyFamilyParents enforces authoritative device.family_id, rejects mismatches with 403, and binds record_id claim", async () => {
  const baseEnv = {
    SUPABASE_URL: "https://example.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "service-role-secret",
    FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({
      project_id: "vfam-proj",
      client_email: "firebase@vfam-proj.iam.gserviceaccount.com",
      private_key: "unused",
    }),
  };

  // 1. Forged/nonexistent device_id with attacker-supplied family_id must skip without FCM or claim
  let sideEffectCalls = 0;
  const nonexistentRes = await handleNotifyFamilyParents({
    payload: {
      device_id: "forged-dev-id",
      family_id: "victim-fam-uuid",
      event_type: "TIME_REQUEST",
      record_id: "req-victim",
    },
    env: baseEnv,
    fetchImpl: async (url, init = {}) => {
      if (url.includes("/rest/v1/devices?")) {
        return new Response(JSON.stringify([]), { status: 200 });
      }
      sideEffectCalls += 1;
      throw new Error(`Unexpected call: ${init.method || "GET"} ${url}`);
    },
    accessTokenProvider: async () => {
      sideEffectCalls += 1;
      return "should-not-be-called";
    },
  });
  assert.equal(nonexistentRes.status, 200);
  assert.equal(nonexistentRes.body.skipped, true);
  assert.equal(nonexistentRes.body.reason, "missing_family_id");
  assert.equal(sideEffectCalls, 0);

  // 2. Unpaired device (family_id: null) with attacker-supplied family_id must also skip
  const unpairedRes = await handleNotifyFamilyParents({
    payload: {
      device_id: "unpaired-dev",
      family_id: "victim-fam-uuid",
      event_type: "TIME_REQUEST",
    },
    env: baseEnv,
    fetchImpl: async (url, init = {}) => {
      if (url.includes("/rest/v1/devices?")) {
        return new Response(
          JSON.stringify([{ id: "unpaired-dev", family_id: null, device_name: "Tablet" }]),
          { status: 200 }
        );
      }
      sideEffectCalls += 1;
      throw new Error(`Unexpected call: ${init.method || "GET"} ${url}`);
    },
  });
  assert.equal(unpairedRes.status, 200);
  assert.equal(unpairedRes.body.skipped, true);
  assert.equal(unpairedRes.body.reason, "missing_family_id");
  assert.equal(sideEffectCalls, 0);

  // 3. Mismatched payload.family_id !== device.family_id returns 403 without claiming or calling FCM
  const mismatchRes = await handleNotifyFamilyParents({
    payload: {
      device_id: "dev-in-fam-A",
      family_id: "fam-VICTIM-B",
      event_type: "TIME_REQUEST",
      record_id: "req-1",
    },
    env: baseEnv,
    fetchImpl: async (url, init = {}) => {
      if (url.includes("/rest/v1/devices?")) {
        return new Response(
          JSON.stringify([{ id: "dev-in-fam-A", family_id: "fam-A", device_name: "Phone A" }]),
          { status: 200 }
        );
      }
      sideEffectCalls += 1;
      throw new Error(`Unexpected call: ${init.method || "GET"} ${url}`);
    },
  });
  assert.equal(mismatchRes.status, 403);
  assert.equal(mismatchRes.body.success, false);
  assert.match(mismatchRes.body.error, /does not match/i);
  assert.equal(sideEffectCalls, 0);

  // 4. record_id claim URL includes device_id and family_id; foreign record returns [] and skips FCM
  const patchUrls = [];
  const foreignRecordRes = await handleNotifyFamilyParents({
    payload: {
      device_id: "dev-A",
      event_type: "TIME_REQUEST",
      record_id: "req-belonging-to-dev-B",
    },
    env: baseEnv,
    fetchImpl: async (url, init = {}) => {
      const method = init.method || "GET";
      if (url.includes("/rest/v1/devices?")) {
        return new Response(
          JSON.stringify([{ id: "dev-A", family_id: "fam-A", device_name: "Phone A" }]),
          { status: 200 }
        );
      }
      if (url.includes("/rest/v1/family_members?")) {
        return new Response(JSON.stringify([{ user_id: "p-A" }]), { status: 200 });
      }
      if (url.includes("/rest/v1/families?")) {
        return new Response(JSON.stringify([{ created_by: "p-A" }]), { status: 200 });
      }
      if (url.includes("/rest/v1/parent_push_tokens?")) {
        return new Response(
          JSON.stringify([{ id: "tok-A", user_id: "p-A", fcm_token: "fcm-A", platform: "android" }]),
          { status: 200 }
        );
      }
      if (url.includes("/rest/v1/time_requests?") && method === "PATCH") {
        patchUrls.push(url);
        return new Response(JSON.stringify([]), { status: 200 });
      }
      throw new Error(`Unexpected fetch: ${method} ${url}`);
    },
    accessTokenProvider: async () => "mock-oauth-tok",
  });
  assert.equal(foreignRecordRes.status, 200);
  assert.equal(foreignRecordRes.body.deduplicated, true);
  assert.equal(foreignRecordRes.body.skipped, true);
  assert.equal(patchUrls.length, 1);
  assert.ok(patchUrls[0].includes("id=eq.req-belonging-to-dev-B"));
  assert.ok(patchUrls[0].includes("device_id=eq.dev-A"));
  assert.ok(patchUrls[0].includes("family_id=eq.fam-A"));
  assert.ok(patchUrls[0].includes("fcm_notified_at=is.null"));
});

test("handleNotifyFamilyParents does not claim on OAuth failure and rolls back fcm_notified_at on 502 so retry succeeds", async () => {
  const baseEnv = {
    SUPABASE_URL: "https://example.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "service-role-secret",
    FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({
      project_id: "vfam-proj",
      client_email: "firebase@vfam-proj.iam.gserviceaccount.com",
      private_key: "unused",
    }),
  };

  let fcmNotifiedAt = null;
  let patchCount = 0;
  let fcmMode = "503";

  const mockFetch = async (url, init = {}) => {
    const method = init.method || "GET";
    if (url.includes("/rest/v1/devices?")) {
      return new Response(
        JSON.stringify([{ id: "dev-r", family_id: "fam-r", device_name: "Tab R" }]),
        { status: 200 }
      );
    }
    if (url.includes("/rest/v1/family_members?")) {
      return new Response(JSON.stringify([{ user_id: "p-r" }]), { status: 200 });
    }
    if (url.includes("/rest/v1/families?")) {
      return new Response(JSON.stringify([{ created_by: "p-r" }]), { status: 200 });
    }
    if (url.includes("/rest/v1/parent_push_tokens?")) {
      return new Response(
        JSON.stringify([{ id: "tok-r", user_id: "p-r", fcm_token: "fcm-r", platform: "android" }]),
        { status: 200 }
      );
    }
    if (url.includes("/rest/v1/time_requests?") && method === "PATCH") {
      patchCount += 1;
      const body = JSON.parse(init.body);
      if (url.includes("fcm_notified_at=is.null")) {
        if (fcmNotifiedAt !== null) {
          return new Response(JSON.stringify([]), { status: 200 });
        }
        fcmNotifiedAt = body.fcm_notified_at;
        return new Response(
          JSON.stringify([{ id: "req-r", requested_minutes: 15, reason: "Học bài" }]),
          { status: 200 }
        );
      }
      // Rollback PATCH setting fcm_notified_at = null
      fcmNotifiedAt = body.fcm_notified_at;
      return new Response(JSON.stringify([]), { status: 200 });
    }
    if (url.includes("fcm.googleapis.com/v1/projects/vfam-proj/messages:send")) {
      if (fcmMode === "503") {
        return new Response(
          JSON.stringify({ error: { status: "UNAVAILABLE", message: "Service unavailable" } }),
          { status: 503 }
        );
      }
      return new Response(JSON.stringify({ name: "projects/vfam-proj/messages/ok" }), {
        status: 200,
      });
    }
    throw new Error(`Unexpected fetch: ${method} ${url}`);
  };

  // 1. OAuth throws before claim -> fcm_notified_at remains null and 0 PATCHes issued
  await assert.rejects(
    () =>
      handleNotifyFamilyParents({
        payload: { device_id: "dev-r", event_type: "TIME_REQUEST", record_id: "req-r" },
        env: baseEnv,
        fetchImpl: mockFetch,
        accessTokenProvider: async () => {
          throw new Error("OAuth2 503 Service Unavailable");
        },
      }),
    /OAuth2 503 Service Unavailable/
  );
  assert.equal(patchCount, 0);
  assert.equal(fcmNotifiedAt, null);

  // 2. All-503 FCM failure returns 502 and rolls back fcm_notified_at to null
  const failedRes = await handleNotifyFamilyParents({
    payload: { device_id: "dev-r", event_type: "TIME_REQUEST", record_id: "req-r" },
    env: baseEnv,
    fetchImpl: mockFetch,
    nowMs: 1700000001000,
    accessTokenProvider: async () => "valid-oauth-tok",
  });
  assert.equal(failedRes.status, 502);
  assert.equal(failedRes.body.success, false);
  assert.equal(fcmNotifiedAt, null, "fcm_notified_at must be rolled back on 502");

  // 3. Subsequent retry once FCM recovers succeeds (sent: 1) instead of deduplicating
  fcmMode = "200";
  const retryRes = await handleNotifyFamilyParents({
    payload: { device_id: "dev-r", event_type: "TIME_REQUEST", record_id: "req-r" },
    env: baseEnv,
    fetchImpl: mockFetch,
    nowMs: 1700000002000,
    accessTokenProvider: async () => "valid-oauth-tok",
  });
  assert.equal(retryRes.status, 200);
  assert.equal(retryRes.body.success, true);
  assert.equal(retryRes.body.sent, 1);
  assert.equal(retryRes.body.deduplicated, undefined);
  assert.ok(fcmNotifiedAt !== null);

  // 4. Concurrent 10x race on a fresh record_id with OAuth-before-claim still produces 1 winner & 9 deduplicated
  let raceFcmNotifiedAt = null;
  let raceFcmDispatches = 0;
  const raceResults = await Promise.all(
    Array.from({ length: 10 }, (_, idx) =>
      handleNotifyFamilyParents({
        payload: { device_id: "dev-r", event_type: "TIME_REQUEST", record_id: "req-race" },
        env: baseEnv,
        nowMs: 1700000003000 + idx,
        accessTokenProvider: async () => "valid-oauth-tok",
        fetchImpl: async (url, init = {}) => {
          const method = init.method || "GET";
          if (url.includes("/rest/v1/devices?")) {
            return new Response(
              JSON.stringify([{ id: "dev-r", family_id: "fam-r", device_name: "Tab R" }]),
              { status: 200 }
            );
          }
          if (url.includes("/rest/v1/family_members?")) {
            return new Response(JSON.stringify([{ user_id: "p-r" }]), { status: 200 });
          }
          if (url.includes("/rest/v1/families?")) {
            return new Response(JSON.stringify([{ created_by: "p-r" }]), { status: 200 });
          }
          if (url.includes("/rest/v1/parent_push_tokens?")) {
            return new Response(
              JSON.stringify([{ id: "tok-r", user_id: "p-r", fcm_token: "fcm-r", platform: "android" }]),
              { status: 200 }
            );
          }
          if (url.includes("/rest/v1/time_requests?") && method === "PATCH") {
            await Promise.resolve();
            if (raceFcmNotifiedAt !== null) {
              return new Response(JSON.stringify([]), { status: 200 });
            }
            raceFcmNotifiedAt = JSON.parse(init.body).fcm_notified_at;
            return new Response(
              JSON.stringify([{ id: "req-race", requested_minutes: 10, reason: "Race" }]),
              { status: 200 }
            );
          }
          if (url.includes("fcm.googleapis.com/v1/projects/vfam-proj/messages:send")) {
            raceFcmDispatches += 1;
            return new Response(JSON.stringify({ name: "projects/vfam-proj/messages/race" }), {
              status: 200,
            });
          }
          throw new Error(`Unexpected fetch: ${method} ${url}`);
        },
      })
    )
  );
  const raceWinners = raceResults.filter((r) => r.body.sent === 1);
  const raceDeduped = raceResults.filter((r) => r.body.deduplicated === true);
  assert.equal(raceWinners.length, 1);
  assert.equal(raceDeduped.length, 9);
  assert.equal(raceFcmDispatches, 1);
});

test("isStaleFcmTokenError does not delete valid tokens on generic FcmError INVALID_ARGUMENT without token text or fieldViolations", async () => {
  const oversizedPayloadErr = {
    error: {
      status: "INVALID_ARGUMENT",
      message: "Message payload exceeded max size 4096 bytes",
      details: [
        {
          "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
          errorCode: "INVALID_ARGUMENT",
        },
      ],
    },
  };
  assert.equal(isStaleFcmTokenError(400, oversizedPayloadErr), false);

  const deletedPaths = [];
  const res = await handleNotifyFamilyParents({
    payload: { device_id: "dev-oversize", event_type: "TIME_REQUEST" },
    env: {
      SUPABASE_URL: "https://example.supabase.co",
      SUPABASE_SERVICE_ROLE_KEY: "service-role-secret",
      FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({
        project_id: "vfam-proj",
        client_email: "firebase@vfam-proj.iam.gserviceaccount.com",
        private_key: "unused",
      }),
    },
    fetchImpl: async (url, init = {}) => {
      const method = init.method || "GET";
      if (url.includes("/rest/v1/devices?")) {
        return new Response(
          JSON.stringify([{ id: "dev-oversize", family_id: "fam-o", device_name: "Phone O" }]),
          { status: 200 }
        );
      }
      if (url.includes("/rest/v1/family_members?")) {
        return new Response(JSON.stringify([{ user_id: "p-o" }]), { status: 200 });
      }
      if (url.includes("/rest/v1/families?")) {
        return new Response(JSON.stringify([{ created_by: "p-o" }]), { status: 200 });
      }
      if (url.includes("/rest/v1/parent_push_tokens?") && method === "GET") {
        return new Response(
          JSON.stringify([{ id: "tok-keep", user_id: "p-o", fcm_token: "valid-tok", platform: "android" }]),
          { status: 200 }
        );
      }
      if (url.includes("/rest/v1/parent_push_tokens?") && method === "DELETE") {
        deletedPaths.push(url);
        return new Response(null, { status: 204 });
      }
      if (url.includes("fcm.googleapis.com/v1/projects/vfam-proj/messages:send")) {
        return new Response(JSON.stringify(oversizedPayloadErr), { status: 400 });
      }
      throw new Error(`Unexpected fetch: ${method} ${url}`);
    },
    accessTokenProvider: async () => "mock-oauth-tok",
  });

  assert.equal(res.status, 502);
  assert.equal(res.body.stale_tokens_removed, 0);
  assert.equal(deletedPaths.length, 0);
});

test("handleNotifyFamilyParents executes DEVICE_MESSAGE_ACK directly, ignores array payload.data, truncates oversized text, and handles HTML 502 from OAuth", async () => {
  clearAccessTokenCache();
  const { privateKey } = generateTestRsaKeyPair();

  // 1. HTML 502 from OAuth throws clear HTTP error instead of SyntaxError
  await assert.rejects(
    () =>
      getGoogleAccessToken({
        clientEmail: "html-502@example.iam.gserviceaccount.com",
        privateKey,
        useCache: false,
        fetchImpl: async () =>
          new Response("<html><body>502 Bad Gateway</body></html>", { status: 502 }),
      }),
    (err) => {
      assert.equal(err instanceof SyntaxError, false);
      assert.match(err.message, /Failed to obtain Google access token \(HTTP 502\)/);
      return true;
    }
  );

  // 2. Direct DEVICE_MESSAGE_ACK + array payload.data ignored + truncation
  const sentMessages = [];
  const ackRes = await handleNotifyFamilyParents({
    payload: {
      device_id: "dev-ack",
      event_type: "DEVICE_MESSAGE_ACK",
      record_id: "msg-ack-1",
      data: ["item0", "item1"],
    },
    env: {
      SUPABASE_URL: "https://example.supabase.co",
      SUPABASE_SERVICE_ROLE_KEY: "service-role-secret",
      FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({
        project_id: "vfam-proj",
        client_email: "firebase@vfam-proj.iam.gserviceaccount.com",
        private_key: "unused",
      }),
    },
    fetchImpl: async (url, init = {}) => {
      const method = init.method || "GET";
      if (url.includes("/rest/v1/devices?")) {
        return new Response(
          JSON.stringify([{ id: "dev-ack", family_id: "fam-ack", device_name: "Galaxy Tab" }]),
          { status: 200 }
        );
      }
      if (url.includes("/rest/v1/family_members?")) {
        return new Response(JSON.stringify([{ user_id: "p-ack" }]), { status: 200 });
      }
      if (url.includes("/rest/v1/families?")) {
        return new Response(JSON.stringify([{ created_by: "p-ack" }]), { status: 200 });
      }
      if (url.includes("/rest/v1/parent_push_tokens?")) {
        return new Response(
          JSON.stringify([{ id: "t-ack", user_id: "p-ack", fcm_token: "tok-ack", platform: "android" }]),
          { status: 200 }
        );
      }
      if (
        url.includes(
          "/rest/v1/device_messages?id=eq.msg-ack-1&device_id=eq.dev-ack&family_id=eq.fam-ack&fcm_notified_at=is.null"
        ) &&
        method === "PATCH"
      ) {
        return new Response(
          JSON.stringify([{ id: "msg-ack-1", message_text: "Học xong rồi đi ngủ nhé" }]),
          { status: 200 }
        );
      }
      if (url.includes("fcm.googleapis.com/v1/projects/vfam-proj/messages:send")) {
        sentMessages.push(JSON.parse(init.body));
        return new Response(JSON.stringify({ name: "ok" }), { status: 200 });
      }
      throw new Error(`Unexpected fetch: ${method} ${url}`);
    },
    accessTokenProvider: async () => "mock-oauth-tok",
  });

  assert.equal(ackRes.status, 200);
  assert.equal(ackRes.body.sent, 1);
  assert.equal(sentMessages.length, 1);
  assert.equal(sentMessages[0].message.data.event_type, "DEVICE_MESSAGE_ACK");
  assert.equal("0" in sentMessages[0].message.data, false);
  assert.equal("1" in sentMessages[0].message.data, false);
  assert.match(sentMessages[0].message.notification.title, /Galaxy Tab/);
  assert.match(sentMessages[0].message.notification.body, /Học xong rồi đi ngủ nhé/);

  // 3. Oversized title & child_reply are safely truncated
  const oversizedCopy = buildParentNotificationCopy({
    eventType: "DEVICE_MESSAGE_REPLY",
    deviceName: "Máy của Bông",
    title: "T".repeat(350),
    claimedRecord: { child_reply: "😀".repeat(1500) },
  });
  assert.equal(Array.from(oversizedCopy.title).length, 200);
  assert.equal(Array.from(oversizedCopy.body).length, 1000);
  assert.ok(oversizedCopy.title.endsWith("…"));
  assert.ok(oversizedCopy.body.endsWith("…"));
});
