import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { createE2EEnv, waitFor } from '../harness/sim_clients.mjs';
import { validateIosPushConfigFiles } from '../harness/repo_contracts.mjs';

describe('Tier 1 — Notifications F1–F4 (R1)', () => {
  let env;

  beforeEach(async () => {
    env = await createE2EEnv();
  });

  afterEach(async () => {
    await env.close();
  });

  // ---- F1: Child device_messages ACK / Reply (Realtime) ----
  it('T1-F1-01: Parent sends message and Child fetches via get_unread_device_messages RPC', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, device_name: 'Tab A9' });
    env.supabase.seedDeviceMessage({
      id: 'msg-old',
      device_id: dev.id,
      family_id: fam.id,
      template_key: 'info',
      title: 'Cũ',
      message_text: 'Tin cũ',
      sent_at: '2026-11-20T09:00:00.000Z',
    });
    env.supabase.seedDeviceMessage({
      id: 'msg-1',
      device_id: dev.id,
      family_id: fam.id,
      template_key: 'homework',
      title: 'Nhắc nhở',
      message_text: 'Dừng chơi',
      sent_at: '2026-11-20T10:00:00.000Z',
    });

    const child = env.createChildAgent({ deviceId: dev.id });
    const res = await child.fetchUnreadMessages();

    assert.equal(res.status, 200);
    assert.equal(res.body.length, 2);
    assert.equal(res.body[0].id, 'msg-1');
    assert.equal(res.body[0].device_id, 'dev-1');
    assert.equal(res.body[0].family_id, 'fam-1');
    assert.equal(res.body[0].template_key, 'homework');
    assert.equal(res.body[0].title, 'Nhắc nhở');
    assert.equal(res.body[0].message_text, 'Dừng chơi');
    assert.match(res.body[0].sent_at, /^\d{4}-\d{2}-\d{2}T/);
    assert.equal(res.body[1].id, 'msg-old');
  });

  it('T1-F1-02: Child acknowledges message via acknowledge_device_message RPC (no reply text)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({
      id: 'msg-1',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Dừng chơi',
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.connectRealtime();
    const res = await child.acknowledgeMessage('msg-1', null, { invokeEdgeFn: false });

    assert.equal(res.status, 200);
    assert.equal(res.body.is_acknowledged, true);
    assert.ok(res.body.acknowledged_at);
    assert.equal(res.body.child_reply, null);
    assert.equal(res.body.updated_count, 1);
    assert.equal(res.body.family_id, 'fam-1');
    assert.equal(res.body.message_text, 'Dừng chơi');

    await waitFor(() => parent.inAppAlerts.length === 1);
    assert.equal(parent.inAppAlerts.length, 1);
    assert.equal(parent.inAppAlerts[0].recordId, 'msg-1');
  });

  it('T1-F1-03: Child replies to parent message with custom text (p_reply_text)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({
      id: 'msg-2',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Làm bài xong chưa?',
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.connectRealtime();
    const res = await child.acknowledgeMessage('msg-2', 'Con làm xong bài rồi ạ', { invokeEdgeFn: false });

    assert.equal(res.status, 200);
    assert.equal(res.body.is_acknowledged, true);
    assert.equal(res.body.child_reply, 'Con làm xong bài rồi ạ');
    assert.equal(res.body.updated_count, 1);

    await waitFor(() => parent.messageHistory.length === 1);
    assert.equal(parent.messageHistory[0].child_reply, 'Con làm xong bài rồi ạ');
    assert.equal(parent.inAppAlerts.length, 1);
    assert.equal(parent.inAppAlerts[0].replyText, 'Con làm xong bài rồi ạ');
  });

  it('T1-F1-04: Persistent ACK deduplication across Realtime Broadcast + Postgres UPDATE + restart', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({
      id: 'msg-3',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Đi ngủ nhé',
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.connectRealtime();
    await child.acknowledgeMessage('msg-3', 'Vâng ạ', { invokeEdgeFn: false });

    await waitFor(() => parent.messageHistory.length === 1);
    assert.equal(parent.inAppAlerts.length, 1);
    assert.ok(parent.persistedDedupKeys.has('ack_msg_msg-3'));

    // Restart parent app and re-sync pending events
    await parent.restartAndReconnect(fam.id);
    assert.equal(parent.inAppAlerts.length, 0);
    assert.ok(parent.persistedDedupKeys.has('ack_msg_msg-3'));
  });

  it('T1-F1-05: Multi-device family Realtime delivery across all active child devices', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev1 = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, device_name: 'Máy Bé An' });
    const dev2 = env.supabase.seedDevice({ id: 'dev-2', family_id: fam.id, device_name: 'Máy Bé Bình' });
    env.supabase.seedDeviceMessage({
      id: 'msg-4',
      device_id: dev2.id,
      family_id: fam.id,
      message_text: 'Tắt máy đi ngủ',
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    parent.selectDevice(dev1.id);
    assert.equal(parent.activeDeviceId, 'dev-1');

    const child2 = env.createChildAgent({ deviceId: dev2.id });
    await child2.acknowledgeMessage('msg-4', 'Con sắp tắt máy', { invokeEdgeFn: false });

    await waitFor(() => parent.inAppAlerts.length === 1);
    assert.equal(parent.inAppAlerts[0].deviceId, 'dev-2');
    assert.equal(parent.inAppAlerts[0].deviceName, 'Máy Bé Bình');
    assert.equal(parent.inAppAlerts[0].replyText, 'Con sắp tắt máy');
  });

  // ---- F2: Child device_messages ACK / Reply (FCM) ----
  it('T1-F2-01: Parent registers Android & iOS push tokens via upsert_parent_push_token RPC', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    env.supabase.seedFamilyMember({ family_id: fam.id, user_id: 'parent-2', role: 'parent' });

    const pAndroid = env.createParentClient({ userId: 'parent-1', platform: 'android' });
    const pIos = env.createParentClient({ userId: 'parent-2', platform: 'ios' });

    const r1 = await pAndroid.registerPushToken('tok-and-1', 'Pixel 8');
    const r2 = await pIos.registerPushToken('tok-ios-1', 'iPhone 15');
    assert.equal(r1.status, 200);
    assert.equal(r2.status, 200);
    assert.equal(env.supabase.tables.parent_push_tokens.size, 2);

    // Upserting same (user_id, fcm_token) updates label without creating duplicate row
    const r3 = await pAndroid.registerPushToken('tok-and-1', 'Pixel 8 Pro');
    assert.equal(r3.status, 200);
    assert.equal(env.supabase.tables.parent_push_tokens.size, 2);
    assert.equal(r3.body.device_label, 'Pixel 8 Pro');
  });

  it('T1-F2-02: DEVICE_MESSAGE_ACK triggers FCM HTTP v1 push to all family parents', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    env.supabase.seedFamilyMember({ family_id: fam.id, user_id: 'parent-2', role: 'parent' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, device_name: 'Tab A9' });
    env.supabase.seedDeviceMessage({
      id: 'msg-10',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Đã hết giờ',
    });

    const pAndroid = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'background' });
    const pIos = env.createParentClient({ userId: 'parent-2', platform: 'ios', lifecycleState: 'background' });
    await pAndroid.registerPushToken('tok-and-1', 'Android');
    await pIos.registerPushToken('tok-ios-1', 'iOS');

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.acknowledgeMessage('msg-10', null, { invokeEdgeFn: true });

    const sent = env.fcm.getSentMessages();
    assert.equal(sent.length, 2);
    for (const item of sent) {
      assert.ok(item.message.notification.title);
      assert.ok(item.message.notification.body);
      assert.equal(item.message.data.event_type, 'DEVICE_MESSAGE_ACK');
      assert.equal(item.message.data.device_id, 'dev-1');
      assert.equal(item.message.data.family_id, 'fam-1');
      assert.equal(item.message.data.record_id, 'msg-10');
    }
    assert.ok(env.supabase.tables.device_messages.get('msg-10').fcm_notified_at);
  });

  it('T1-F2-03: DEVICE_MESSAGE_REPLY includes reply text in FCM body/data and wakes background handler', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({
      id: 'msg-11',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Tắt game',
    });

    const parent = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'background' });
    await parent.registerPushToken('tok-and-1', 'Pixel 8');

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.acknowledgeMessage('msg-11', 'Cho con thêm 5 phút', { invokeEdgeFn: true });

    const sent = env.fcm.getSentToToken('tok-and-1');
    assert.equal(sent.length, 1);
    assert.equal(sent[0].message.notification.body, 'Cho con thêm 5 phút');
    assert.equal(sent[0].message.data.reply_text, 'Cho con thêm 5 phút');
    assert.equal(sent[0].message.android.priority, 'HIGH');
    assert.equal(sent[0].message.android.notification.channel_id, 'vfam_admin_alerts');

    await waitFor(() => parent.systemNotifications.length === 1);
    assert.equal(parent.systemNotifications[0].channelId, 'vfam_admin_alerts');
    assert.ok(parent.persistedDedupKeys.has('ack_msg_msg-11'));
  });

  it('T1-F2-04: Terminated Parent App opens and routes from FCM tap (getInitialMessage)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({
      id: 'msg-12',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Chuẩn bị ăn tối',
    });

    const parent = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'terminated' });
    await parent.registerPushToken('tok-and-term', 'Pixel 8');

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.acknowledgeMessage('msg-12', 'Con xuống ngay', { invokeEdgeFn: true });

    await waitFor(() => parent.pendingNotificationsTray.length === 1);
    const route = await parent.tapNotificationFromTray('msg-12');
    assert.equal(route.via, 'getInitialMessage');
    assert.equal(route.screen, 'message_history');
    assert.equal(route.deviceId, 'dev-1');
    assert.equal(route.messageId, 'msg-12');
    assert.equal(parent.activeDeviceId, 'dev-1');
    assert.ok(parent.persistedDedupKeys.has('ack_msg_msg-12'));
  });

  it('T1-F2-05: iOS Enterprise APNs envelope & native push configuration contract', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({
      id: 'msg-13',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Đi ngủ',
    });

    const pIos = env.createParentClient({ userId: 'parent-1', platform: 'ios', lifecycleState: 'background' });
    await pIos.registerPushToken('tok-ios-1', 'iPhone Enterprise');

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.acknowledgeMessage('msg-13', 'Dạ vâng', { invokeEdgeFn: true });

    const sent = env.fcm.getSentToToken('tok-ios-1');
    assert.equal(sent.length, 1);
    const apns = sent[0].message.apns;
    assert.equal(apns.headers['apns-priority'], '10');
    assert.equal(apns.headers['apns-push-type'], 'alert');
    assert.equal(apns.payload.aps.sound, 'default');
    assert.equal(apns.payload.aps.badge, 1);
    assert.equal(apns.payload.aps['content-available'], 1);

    // Validate iOS Enterprise native config contract parser
    const validIosCheck = validateIosPushConfigFiles({
      googleServiceInfo: '<key>BUNDLE_ID</key><string>com.dhtthni.quanlytaptrung</string>',
      pbxproj: 'GoogleService-Info.plist in Resources; CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;',
      infoPlist: '<key>UIBackgroundModes</key><array><string>remote-notification</string></array>',
      entitlements: '<key>aps-environment</key><string>production</string>',
      appDelegate: 'FirebaseApp.configure(); UNUserNotificationCenter.current().delegate = self; application.registerForRemoteNotifications()',
    });
    assert.equal(validIosCheck.ok, true);

    // Bare filename in PBXFileReference without PBXResourcesBuildPhase ('in Resources') must fail
    const missingResourcesPhase = validateIosPushConfigFiles({
      googleServiceInfo: '<key>BUNDLE_ID</key><string>com.dhtthni.quanlytaptrung</string>',
      pbxproj: 'GoogleService-Info.plist; CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;',
      infoPlist: '<key>UIBackgroundModes</key><array><string>remote-notification</string></array>',
      entitlements: '<key>aps-environment</key><string>production</string>',
      appDelegate: 'FirebaseApp.configure(); UNUserNotificationCenter.current().delegate = self; application.registerForRemoteNotifications()',
    });
    assert.equal(missingResourcesPhase.ok, false);

    const invalidIosCheck = validateIosPushConfigFiles({
      googleServiceInfo: '<key>BUNDLE_ID</key><string>com.wrong</string>',
      pbxproj: '',
      infoPlist: '<dict></dict>',
      entitlements: null,
      appDelegate: 'GeneratedPluginRegistrant.register(with: self)',
    });
    assert.equal(invalidIosCheck.ok, false);
    assert.equal(invalidIosCheck.errors.length, 6);
  });

  // ---- F3: Child time_requests (Realtime) ----
  it('T1-F3-01: Child submits time request via create_time_request RPC (resolving family_id)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const child = env.createChildAgent({ deviceId: dev.id });
    const res = await child.submitTimeRequest(15, 'Làm bài tập', { invokeEdgeFn: false });

    assert.equal(res.status, 200);
    assert.equal(res.body.device_id, 'dev-1');
    assert.equal(res.body.family_id, 'fam-1');
    assert.equal(res.body.requested_minutes, 15);
    assert.equal(res.body.reason, 'Làm bài tập');
    assert.equal(res.body.status, 'pending');
    assert.ok(res.body.id);
    assert.ok(res.body.created_at);
    assert.equal(env.supabase.tables.time_requests.get(res.body.id).family_id, 'fam-1');
  });

  it('T1-F3-02: Realtime INSERT on time_requests delivers live notification to foreground Parent', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.connectRealtime();
    const res = await child.submitTimeRequest(30, 'Học online', { invokeEdgeFn: false });

    await waitFor(() => parent.pendingTimeRequests.length === 1);
    assert.equal(parent.pendingTimeRequests[0].id, res.body.id);
    assert.equal(parent.pendingTimeRequests[0].requested_minutes, 30);
    assert.equal(parent.pendingTimeRequests[0].reason, 'Học online');
    // Deduped against WS TIME_REQUEST broadcast
    assert.equal(parent.inAppAlerts.length, 1);
  });

  it('T1-F3-03: Parent approves time_request -> DB, Realtime, and Child quota updated', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, is_locked: true, extra_time_minutes: 0 });

    const child = env.createChildAgent({ deviceId: dev.id });
    child.localLockState.isLocked = true;
    await child.connectRealtime();
    const reqRes = await child.submitTimeRequest(15, 'Xin thêm', { invokeEdgeFn: false });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    const resolveRes = await parent.resolveTimeRequest(reqRes.body.id, 'approved', 15);

    assert.equal(resolveRes.status, 200);
    assert.equal(resolveRes.body.status, 'approved');
    assert.equal(resolveRes.body.resolved_minutes, 15);
    assert.ok(resolveRes.body.resolved_at);

    const dbDev = env.supabase.tables.devices.get('dev-1');
    assert.equal(dbDev.extra_time_minutes, 15);
    assert.equal(dbDev.is_locked, false);

    await waitFor(() => child.localLockState.isLocked === false && child.localLockState.extraTimeMinutes === 15);
    assert.equal(child.localLockState.isLocked, false);
    assert.equal(child.localLockState.extraTimeMinutes, 15);
  });

  it('T1-F3-04: Parent rejects time_request -> status updated without granting minutes', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, is_locked: true, extra_time_minutes: 10 });

    const child = env.createChildAgent({ deviceId: dev.id });
    child.localLockState = { isLocked: true, extraTimeMinutes: 10 };
    await child.connectRealtime();
    const reqRes = await child.submitTimeRequest(30, 'Chơi game', { invokeEdgeFn: false });

    const parent = env.createParentClient({ userId: 'parent-1' });
    const resolveRes = await parent.resolveTimeRequest(reqRes.body.id, 'rejected', 0);

    assert.equal(resolveRes.status, 200);
    assert.equal(resolveRes.body.status, 'rejected');
    assert.equal(resolveRes.body.resolved_minutes, 0);

    const dbDev = env.supabase.tables.devices.get('dev-1');
    assert.equal(dbDev.extra_time_minutes, 10);
    assert.equal(dbDev.is_locked, true);
    assert.equal(child.localLockState.isLocked, true);
    assert.equal(child.localLockState.extraTimeMinutes, 10);
  });

  it('T1-F3-05: Child create_time_request error propagation & UI-thread safety', async () => {
    // Unpaired device causes RPC 400 error; client must NOT fake success=true and must marshal callback to main thread
    const dev = env.supabase.seedDevice({ id: 'dev-unpaired', family_id: null });
    const child = env.createChildAgent({ deviceId: dev.id });

    let uiCallback = null;
    const res = await child.submitTimeRequest(15, 'Xin thêm', {
      invokeEdgeFn: false,
      onUiResult: (info) => {
        uiCallback = info;
      },
    });

    assert.equal(res.ok, false);
    assert.equal(res.status, 400);
    assert.ok(uiCallback);
    assert.equal(uiCallback.success, false);
    assert.equal(uiCallback.thread, 'main');
  });

  // ---- F4: Child time_requests (FCM) ----
  it('T1-F4-01: TIME_REQUEST triggers FCM HTTP v1 push via notify-family-parents', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    env.supabase.seedFamilyMember({ family_id: fam.id, user_id: 'parent-2', role: 'parent' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const p1 = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'background' });
    const p2 = env.createParentClient({ userId: 'parent-2', platform: 'ios', lifecycleState: 'background' });
    await p1.registerPushToken('tok-1');
    await p2.registerPushToken('tok-2');

    const child = env.createChildAgent({ deviceId: dev.id });
    const reqRes = await child.submitTimeRequest(20, 'Đọc sách', { invokeEdgeFn: true });

    const sent = env.fcm.getSentMessages();
    assert.equal(sent.length, 2);
    for (const s of sent) {
      assert.equal(s.message.data.event_type, 'TIME_REQUEST');
      assert.equal(s.message.data.device_id, 'dev-1');
      assert.equal(s.message.data.family_id, 'fam-1');
      assert.equal(s.message.data.record_id, reqRes.body.id);
    }
    assert.ok(env.supabase.tables.time_requests.get(reqRes.body.id).fcm_notified_at);
  });

  it('T1-F4-02: DB pg_net trigger fallback delivers FCM even if Child skips Edge Function call', async () => {
    await env.close();
    env = await createE2EEnv({ enablePgNetTriggers: true });

    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const parent = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'terminated' });
    await parent.registerPushToken('tok-pgnet-1');

    const child = env.createChildAgent({ deviceId: dev.id });
    const reqRes = await child.submitTimeRequest(15, 'Fallback trigger', { invokeEdgeFn: false });

    await waitFor(() => env.fcm.getSentToToken('tok-pgnet-1').length === 1);
    const sent = env.fcm.getSentToToken('tok-pgnet-1');
    assert.equal(sent.length, 1);
    assert.equal(sent[0].message.data.record_id, reqRes.body.id);
    assert.ok(env.supabase.tables.time_requests.get(reqRes.body.id).fcm_notified_at);
  });

  it('T1-F4-03: Foreground Parent suppresses duplicate OS notification when Realtime + FCM both arrive', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const parent = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'foreground' });
    await parent.registerPushToken('tok-fg-1');
    await parent.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id });
    const reqRes = await child.submitTimeRequest(15, 'Xin thêm', { invokeEdgeFn: true });

    await waitFor(() => env.fcm.getSentToToken('tok-fg-1').length === 1);
    await waitFor(() => parent.inAppAlerts.length === 1);
    // Slight settle window to confirm second channel does not create duplicate
    await new Promise((r) => setTimeout(r, 30));
    assert.equal(parent.inAppAlerts.length, 1);
    assert.equal(parent.systemNotifications.length, 1);
    assert.ok(parent.persistedDedupKeys.has(`time_req_${reqRes.body.id}`));
  });

  it('T1-F4-04: Background Parent receives TIME_REQUEST FCM and displays Android notification', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const parent = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'background' });
    await parent.registerPushToken('tok-bg-and');

    const child = env.createChildAgent({ deviceId: dev.id });
    const reqRes = await child.submitTimeRequest(15, 'Học bài', { invokeEdgeFn: true });

    await waitFor(() => parent.systemNotifications.length === 1);
    assert.equal(parent.systemNotifications[0].channelId, 'vfam_admin_alerts');

    const route = await parent.tapNotificationFromTray(reqRes.body.id);
    assert.equal(route.via, 'onMessageOpenedApp');
    assert.equal(route.screen, 'time_request_approval');
    assert.equal(route.deviceId, 'dev-1');
    assert.equal(route.requestId, reqRes.body.id);
  });

  it('T1-F4-05: Terminated iOS Parent receives APNs alert and resumes into approval flow', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const pIos = env.createParentClient({ userId: 'parent-1', platform: 'ios', lifecycleState: 'terminated' });
    await pIos.registerPushToken('tok-ios-term');

    const child = env.createChildAgent({ deviceId: dev.id });
    const reqRes = await child.submitTimeRequest(20, 'Làm bài kiểm tra', { invokeEdgeFn: true });

    const sent = env.fcm.getSentToToken('tok-ios-term');
    assert.equal(sent.length, 1);
    assert.equal(sent[0].message.apns.headers['apns-priority'], '10');
    assert.equal(sent[0].message.apns.headers['apns-push-type'], 'alert');
    assert.equal(sent[0].message.apns.payload.aps.sound, 'default');
    assert.equal(sent[0].message.apns.payload.aps.badge, 1);

    await waitFor(() => pIos.pendingNotificationsTray.length === 1);
    const route = await pIos.tapNotificationFromTray(reqRes.body.id);
    assert.equal(route.via, 'getInitialMessage');
    assert.equal(route.screen, 'time_request_approval');
    assert.equal(route.deviceId, 'dev-1');
    assert.equal(route.requestId, reqRes.body.id);
  });
});
