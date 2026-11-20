import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { createE2EEnv, waitFor } from '../harness/sim_clients.mjs';

describe('Tier 2 — Boundary & Corner Cases F1–F4 (R1)', () => {
  let env;

  beforeEach(async () => {
    env = await createE2EEnv();
  });

  afterEach(async () => {
    await env.close();
  });

  // ---- F1 Boundary Cases (5) ----
  it('T2-F1-01: Blank/whitespace-only p_reply_text is normalized to NULL', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({
      id: 'msg-b1',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Đi học bài',
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id });
    const res = await child.acknowledgeMessage('msg-b1', '   \t\n  ', { invokeEdgeFn: false });

    assert.equal(res.status, 200);
    assert.equal(res.body.is_acknowledged, true);
    assert.equal(res.body.child_reply, null);
    assert.equal(res.body.updated_count, 1);

    await waitFor(() => parent.inAppAlerts.length === 1);
    assert.equal(parent.inAppAlerts[0].replyText, null);
  });

  it('T2-F1-02: p_message_id = NULL acknowledges only the latest unread message', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({
      id: 'msg-old',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Tin 1',
      sent_at: '2026-11-20T08:00:00.000Z',
    });
    env.supabase.seedDeviceMessage({
      id: 'msg-new',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Tin 2',
      sent_at: '2026-11-20T09:00:00.000Z',
    });

    const child = env.createChildAgent({ deviceId: dev.id });
    const res = await child.acknowledgeMessage(null, 'OK', { invokeEdgeFn: false });

    assert.equal(res.status, 200);
    assert.equal(res.body.id, 'msg-new');
    assert.equal(res.body.is_acknowledged, true);
    assert.equal(res.body.child_reply, 'OK');
    assert.equal(res.body.updated_count, 1);
    assert.equal(env.supabase.tables.device_messages.get('msg-old').is_acknowledged, false);
  });

  it('T2-F1-03: Idempotent re-acknowledgement when no unread messages remain', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({
      id: 'msg-b2',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Đã đọc',
      is_acknowledged: true,
      acknowledged_at: '2026-11-20T09:00:00.000Z',
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id });
    const res = await child.acknowledgeMessage('msg-b2', null, { invokeEdgeFn: false });

    assert.equal(res.status, 200);
    assert.equal(res.body.updated_count, 0);
    await new Promise((r) => setTimeout(r, 25));
    assert.equal(parent.inAppAlerts.length, 0);
  });

  it('T2-F1-04: Out-of-order offline-queued ACK arrives after a newer message was already acknowledged', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({
      id: 'msg-1',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Tin 1',
      sent_at: '2026-11-20T08:00:00.000Z',
    });
    env.supabase.seedDeviceMessage({
      id: 'msg-2',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Tin 2',
      sent_at: '2026-11-20T09:00:00.000Z',
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    const child = env.createChildAgent({ deviceId: dev.id });

    // Newer msg-2 acknowledged first, then offline-queued msg-1 replays
    await child.acknowledgeMessage('msg-2', 'Trả lời trước', { invokeEdgeFn: false });
    await child.acknowledgeMessage('msg-1', 'Trả lời muộn', { invokeEdgeFn: false });

    await waitFor(() => parent.inAppAlerts.length === 2);
    assert.equal(env.supabase.tables.device_messages.get('msg-2').child_reply, 'Trả lời trước');
    assert.equal(env.supabase.tables.device_messages.get('msg-1').child_reply, 'Trả lời muộn');
    assert.ok(parent.persistedDedupKeys.has('ack_msg_msg-1'));
    assert.ok(parent.persistedDedupKeys.has('ack_msg_msg-2'));
  });

  it('T2-F1-05: Very long / Unicode Vietnamese + emoji p_reply_text (2000 chars) over RFC 6455 WS & RPC', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({
      id: 'msg-b3',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Viết phản hồi dài',
    });

    const baseUnit = 'Con đang làm bài tập Toán tiếng Việt 📚✅ ';
    const longReply = (baseUnit.repeat(Math.ceil(2000 / baseUnit.length)).slice(0, 1999) + '!').trim();
    assert.equal(longReply.length, 2000);

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.connectRealtime();
    const res = await child.acknowledgeMessage('msg-b3', longReply, { invokeEdgeFn: false });

    assert.equal(res.status, 200);
    assert.equal(res.body.child_reply, longReply);

    await waitFor(() => parent.messageHistory.length === 1);
    assert.equal(parent.messageHistory[0].child_reply, longReply);
    const preview = parent.getTelemetryView('dev-1').formatReplyPreview(longReply);
    assert.ok(preview.length <= 141 && preview.endsWith('…'));
  });

  // ---- F2 Boundary Cases (6) ----
  it('T2-F2-01: Concurrent DB trigger + Client notify-family-parents deduped by atomic fcm_notified_at', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({
      id: 'msg-f1',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Nhắc nhở',
    });

    const parent = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'background' });
    await parent.registerPushToken('tok-race-1');

    const callEdge = () =>
      fetch(`${env.supabase.baseUrl}/functions/v1/notify-family-parents`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
        body: JSON.stringify({
          device_id: dev.id,
          event_type: 'DEVICE_MESSAGE_REPLY',
          record_id: 'msg-f1',
        }),
      }).then((r) => r.json());

    const [res1, res2] = await Promise.all([callEdge(), callEdge()]);
    const totalSent = (res1.sent || 0) + (res2.sent || 0);
    const dedupedCount = [res1, res2].filter((r) => r.deduplicated === true).length;

    assert.equal(totalSent, 1);
    assert.equal(dedupedCount, 1);
    assert.equal(env.fcm.getSentMessages().length, 1);
  });

  it('T2-F2-02: Stale/unregistered FCM token (UNREGISTERED 404 / 410) auto-cleaned without blocking valid tokens', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    env.supabase.seedFamilyMember({ family_id: fam.id, user_id: 'parent-2', role: 'parent' });
    env.supabase.seedFamilyMember({ family_id: fam.id, user_id: 'parent-3', role: 'parent' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({ id: 'msg-stale', device_id: dev.id, family_id: fam.id, message_text: 'Test' });

    const p1 = env.createParentClient({ userId: 'parent-1', platform: 'android' });
    const p2 = env.createParentClient({ userId: 'parent-2', platform: 'android' });
    const p3 = env.createParentClient({ userId: 'parent-3', platform: 'ios' });
    await p1.registerPushToken('tok-stale-404');
    await p2.registerPushToken('tok-stale-410');
    await p3.registerPushToken('tok-valid');

    env.fcm.setTokenError('tok-stale-404', 404, 'UNREGISTERED');
    env.fcm.setTokenError('tok-stale-410', 410, 'UNREGISTERED');

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.acknowledgeMessage('msg-stale', 'OK', { invokeEdgeFn: false });
    const edgeResp = await fetch(`${env.supabase.baseUrl}/functions/v1/notify-family-parents`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        device_id: dev.id,
        event_type: 'DEVICE_MESSAGE_REPLY',
        record_id: 'msg-stale',
      }),
    });
    assert.equal(edgeResp.status, 200);
    const edgeJson = await edgeResp.json();
    assert.equal(edgeJson.success, true);
    assert.equal(edgeJson.sent, 1);
    assert.equal(edgeJson.failed, 2);
    assert.equal(edgeJson.stale_tokens_removed, 2);
    assert.equal(edgeJson.deduplicated, false);

    assert.equal(env.fcm.getSentToToken('tok-valid').length, 1);
    const remainingTokens = [...env.supabase.tables.parent_push_tokens.values()].map((t) => t.fcm_token);
    assert.deepEqual(remainingTokens, ['tok-valid']);
  });

  it('T2-F2-03: Multi-device parent (same user logged in on Android tablet + iOS phone)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({ id: 'msg-f2', device_id: dev.id, family_id: fam.id, message_text: 'Ping' });

    const pAnd = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'background' });
    const pIos = env.createParentClient({ userId: 'parent-1', platform: 'ios', lifecycleState: 'background' });
    await pAnd.registerPushToken('tok-and-tab', 'Galaxy Tab');
    await pIos.registerPushToken('tok-ios-ph', 'iPhone 15');

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.acknowledgeMessage('msg-f2', 'Dạ', { invokeEdgeFn: true });

    assert.equal(env.fcm.getSentToToken('tok-and-tab').length, 1);
    assert.equal(env.fcm.getSentToToken('tok-ios-ph').length, 1);
    assert.ok(env.fcm.getSentToToken('tok-and-tab')[0].message.android);
    assert.ok(env.fcm.getSentToToken('tok-ios-ph')[0].message.apns);
  });

  it('T2-F2-04: Parent family with zero registered parent_push_tokens or missing record_id returns graceful no-op', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const resp = await fetch(`${env.supabase.baseUrl}/functions/v1/notify-family-parents`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({ device_id: dev.id, event_type: 'DEVICE_MESSAGE_ACK' }),
    });
    assert.equal(resp.status, 200);
    const json = await resp.json();
    assert.equal(json.success, true);
    assert.equal(json.sent, 0);
    assert.equal(json.deduplicated, false);
    assert.equal(env.fcm.getSentMessages().length, 0);

    // Non-existent record_id skips sending even when a parent token exists
    const p = env.createParentClient({ userId: 'parent-1', platform: 'android' });
    await p.registerPushToken('tok-exists');
    const missingRecResp = await fetch(`${env.supabase.baseUrl}/functions/v1/notify-family-parents`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        device_id: dev.id,
        event_type: 'DEVICE_MESSAGE_ACK',
        record_id: '00000000-0000-0000-0000-000000000999',
      }),
    });
    assert.equal(missingRecResp.status, 200);
    const missingRecJson = await missingRecResp.json();
    assert.equal(missingRecJson.sent, 0);
    assert.equal(missingRecJson.deduplicated, false);
    assert.equal(env.fcm.getSentMessages().length, 0);
  });

  it('T2-F2-05: All FCM data payload values are strictly strings (no raw numbers/booleans)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const p = env.createParentClient({ userId: 'parent-1', platform: 'android' });
    await p.registerPushToken('tok-str-check');

    // Verify FCM server itself enforces strict string-only data map (rejects raw number)
    const tokenResp = await fetch(`${env.fcm.baseUrl}/oauth2/v4/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: 'a.b.c',
      }).toString(),
    }).then((r) => r.json());

    const rawFcmBad = await fetch(`${env.fcm.baseUrl}/v1/projects/${env.fcm.projectId}/messages:send`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${tokenResp.access_token}` },
      body: JSON.stringify({ message: { token: 'tok-str-check', data: { requested_minutes: 15 } } }),
    });
    assert.equal(rawFcmBad.status, 400);

    // Edge Function converts numeric/boolean metadata into strings
    const edgeResp = await fetch(`${env.supabase.baseUrl}/functions/v1/notify-family-parents`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        device_id: dev.id,
        event_type: 'DEVICE_MESSAGE_REPLY',
        data: { requested_minutes: 15, is_acknowledged: true },
      }),
    });
    assert.equal(edgeResp.status, 200);
    const sent = env.fcm.getSentToToken('tok-str-check');
    assert.equal(sent.length, 1);
    for (const val of Object.values(sent[0].message.data)) {
      assert.equal(typeof val, 'string');
    }
    assert.equal(sent[0].message.data.requested_minutes, '15');
    assert.equal(sent[0].message.data.is_acknowledged, 'true');
  });

  it('T2-F2-06: Android vs iOS platform-specific FCM HTTP v1 payload structure', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    env.supabase.seedFamilyMember({ family_id: fam.id, user_id: 'parent-2', role: 'parent' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({ id: 'msg-plat', device_id: dev.id, family_id: fam.id, message_text: 'Hi' });

    const pAnd = env.createParentClient({ userId: 'parent-1', platform: 'android' });
    const pIos = env.createParentClient({ userId: 'parent-2', platform: 'ios' });
    await pAnd.registerPushToken('tok-and');
    await pIos.registerPushToken('tok-ios');

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.acknowledgeMessage('msg-plat', 'Chào bố mẹ', { invokeEdgeFn: true });

    const andMsg = env.fcm.getSentToToken('tok-and')[0].message;
    assert.deepEqual(andMsg.android, {
      priority: 'HIGH',
      notification: { channel_id: 'vfam_admin_alerts', sound: 'default' },
    });

    const iosMsg = env.fcm.getSentToToken('tok-ios')[0].message;
    assert.deepEqual(iosMsg.apns, {
      headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
      payload: { aps: { sound: 'default', badge: 1, 'content-available': 1 } },
    });
  });

  // ---- F3 Boundary Cases (5) ----
  it('T2-F3-01: create_time_request with empty/omitted p_reason uses safe default', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const r1 = await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/create_time_request`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({ p_device_id: dev.id, p_requested_minutes: 15 }),
    });
    assert.equal(r1.status, 200);
    const b1 = await r1.json();
    assert.equal(typeof b1.reason, 'string');

    const r2 = await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/create_time_request`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({ p_device_id: dev.id, p_requested_minutes: 15, p_reason: '' }),
    });
    assert.equal(r2.status, 200);
    const b2 = await r2.json();
    assert.equal(b2.reason, '');
  });

  it('T2-F3-02: create_time_request rejects p_requested_minutes <= 0 (0 and -10)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id });

    const rZero = await child.submitTimeRequest(0, 'Zero');
    const rNeg = await child.submitTimeRequest(-10, 'Negative');

    assert.equal(rZero.status, 400);
    assert.equal(rNeg.status, 400);
    assert.equal(env.supabase.tables.time_requests.size, 0);
    assert.equal(env.fcm.getSentMessages().length, 0);
  });

  it('T2-F3-03: create_time_request on unpaired / unknown device_id (family_id IS NULL)', async () => {
    env.supabase.seedDevice({ id: 'dev-unpaired', family_id: null });
    const child = env.createChildAgent({ deviceId: 'dev-unpaired' });

    const rUnpaired = await child.submitTimeRequest(15, 'Test');
    assert.equal(rUnpaired.status, 400);
    assert.match(rUnpaired.body.message, /chưa được ghép nối/);

    const unknownChild = env.createChildAgent({ deviceId: '00000000-0000-0000-0000-000000000999' });
    const rUnknown = await unknownChild.submitTimeRequest(15, 'Test');
    assert.equal(rUnknown.status, 400);
    assert.equal(env.supabase.tables.time_requests.size, 0);
  });

  it('T2-F3-04: Duplicate rapid clicks / multiple pending requests from Child keep distinct IDs', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id });
    const [rA, rB] = await Promise.all([
      child.submitTimeRequest(15, 'Lần 1', { invokeEdgeFn: false }),
      child.submitTimeRequest(30, 'Lần 2', { invokeEdgeFn: false }),
    ]);

    assert.notEqual(rA.body.id, rB.body.id);
    assert.equal(env.supabase.tables.time_requests.size, 2);
    await waitFor(() => parent.inAppAlerts.length === 2);
    assert.ok(parent.persistedDedupKeys.has(`time_req_${rA.body.id}`));
    assert.ok(parent.persistedDedupKeys.has(`time_req_${rB.body.id}`));
  });

  it('T2-F3-05: Non-member parent from fam-2 cannot resolve or insert fam-1 time_request (and anon cannot POST parent tables)', async () => {
    const fam1 = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    env.supabase.seedFamily({ id: 'fam-2', created_by: 'parent-2' });
    const dev1 = env.supabase.seedDevice({ id: 'dev-1', family_id: fam1.id, extra_time_minutes: 0 });

    const child = env.createChildAgent({ deviceId: dev1.id });
    const reqRes = await child.submitTimeRequest(15, 'Xin thêm', { invokeEdgeFn: false });

    const intruder = env.createParentClient({ userId: 'parent-2' });
    const res = await intruder.resolveTimeRequest(reqRes.body.id, 'approved', 30);

    assert.equal(res.status, 403);
    assert.equal(env.supabase.tables.time_requests.get(reqRes.body.id).status, 'pending');
    assert.equal(env.supabase.tables.devices.get(dev1.id).extra_time_minutes, 0);

    // Cross-family direct POST /rest/v1/time_requests is also blocked by RLS
    const crossPost = await fetch(`${env.supabase.baseUrl}/rest/v1/time_requests`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: env.supabase.anonKey,
        Authorization: `Bearer ${intruder.jwt}`,
      },
      body: JSON.stringify({ device_id: dev1.id, family_id: fam1.id, requested_minutes: 60 }),
    });
    assert.equal(crossPost.status, 403);
    const crossPostBody = await crossPost.json();
    assert.equal(crossPostBody.code, '42501');

    // Anon POST to parent-only table is blocked by RLS
    const anonPost = await fetch(`${env.supabase.baseUrl}/rest/v1/parent_push_tokens`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({ user_id: 'parent-1', fcm_token: 'spoof', platform: 'android' }),
    });
    assert.equal(anonPost.status, 403);
  });

  // ---- F4 Boundary Cases (5) ----
  it('T2-F4-01: TIME_REQUEST FCM atomic idempotency (fcm_notified_at) prevents double push from pg_net + client', async () => {
    await env.close();
    env = await createE2EEnv({ enablePgNetTriggers: true });

    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const parent = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'background' });
    await parent.registerPushToken('tok-pgnet-race');

    const child = env.createChildAgent({ deviceId: dev.id });
    const reqRes = await child.submitTimeRequest(15, 'Cả hai kênh', { invokeEdgeFn: true });

    await waitFor(() => env.fcm.getSentToToken('tok-pgnet-race').length >= 1);
    await new Promise((r) => setTimeout(r, 30));
    assert.equal(env.fcm.getSentToToken('tok-pgnet-race').length, 1);
    assert.ok(env.supabase.tables.time_requests.get(reqRes.body.id).fcm_notified_at);
  });

  it('T2-F4-02: Cross-family isolation on notify-family-parents', async () => {
    const fam1 = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    env.supabase.seedFamily({ id: 'fam-2', created_by: 'parent-2' });
    const dev1 = env.supabase.seedDevice({ id: 'dev-1', family_id: fam1.id });

    const p1 = env.createParentClient({ userId: 'parent-1', platform: 'android' });
    const p2 = env.createParentClient({ userId: 'parent-2', platform: 'android' });
    await p1.registerPushToken('tok-fam1');
    await p2.registerPushToken('tok-fam2');

    const child = env.createChildAgent({ deviceId: dev1.id });
    await child.submitTimeRequest(15, 'Fam1 only', { invokeEdgeFn: true });

    assert.equal(env.fcm.getSentToToken('tok-fam1').length, 1);
    assert.equal(env.fcm.getSentToToken('tok-fam2').length, 0);
  });

  it('T2-F4-03: families.created_by owner included without duplicate if also in family_members', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    // seedFamily already adds parent-1 to family_members; verify deduplication
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const p1 = env.createParentClient({ userId: 'parent-1', platform: 'android' });
    await p1.registerPushToken('tok-owner-1');

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.submitTimeRequest(15, 'Owner dedup', { invokeEdgeFn: true });

    assert.equal(env.fcm.getSentToToken('tok-owner-1').length, 1);
  });

  it('T2-F4-04: Client sends mismatched/spoofed family_id in notify-family-parents request -> 403 and zero FCM pushes', async () => {
    const fam1 = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const fam2 = env.supabase.seedFamily({ id: 'fam-2', created_by: 'parent-2' });
    const dev1 = env.supabase.seedDevice({ id: 'dev-1', family_id: fam1.id });
    env.supabase.seedDevice({ id: 'dev-2', family_id: fam2.id });

    const p1 = env.createParentClient({ userId: 'parent-1', platform: 'android' });
    const p2 = env.createParentClient({ userId: 'parent-2', platform: 'android' });
    await p1.registerPushToken('tok-1');
    await p2.registerPushToken('tok-2');

    const resp = await fetch(`${env.supabase.baseUrl}/functions/v1/notify-family-parents`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        device_id: dev1.id,
        family_id: fam2.id, // spoofed!
        event_type: 'TIME_REQUEST',
      }),
    });
    assert.equal(resp.status, 403);
    const json = await resp.json();
    assert.equal(json.success, false);
    assert.match(json.error, /family_id does not match/);
    assert.equal(env.fcm.getSentToToken('tok-1').length, 0);
    assert.equal(env.fcm.getSentToToken('tok-2').length, 0);
  });

  it('T2-F4-05: Extreme requested_minutes (1 min and 1440 mins) formatted safely in FCM payload', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const p1 = env.createParentClient({ userId: 'parent-1', platform: 'android' });
    await p1.registerPushToken('tok-ext');

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.submitTimeRequest(1, 'Một phút', { invokeEdgeFn: true });
    await child.submitTimeRequest(1440, 'Cả ngày', { invokeEdgeFn: true });

    const sent = env.fcm.getSentToToken('tok-ext');
    assert.equal(sent.length, 2);
    assert.equal(sent[0].message.data.requested_minutes, '1');
    assert.equal(sent[1].message.data.requested_minutes, '1440');
    assert.equal(typeof sent[0].message.notification.title, 'string');
    assert.equal(typeof sent[1].message.notification.body, 'string');
  });
});
