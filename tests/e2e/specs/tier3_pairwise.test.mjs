import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { createE2EEnv, waitFor } from '../harness/sim_clients.mjs';

describe('Tier 3 — Cross-Feature Pairwise Combinations (14 Tests)', () => {
  let env;

  beforeEach(async () => {
    env = await createE2EEnv();
  });

  afterEach(async () => {
    await env.close();
  });

  it('T3-01: Offline Usage + Midnight Split + Morning Sync + time_requests FCM (F8 + F9 + F4)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const parent = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'terminated' });
    await parent.registerPushToken('tok-t3-01');

    const child = env.createChildAgent({ deviceId: dev.id, timezone: 'Asia/Ho_Chi_Minh' });
    const tStart = Date.parse('2026-11-20T23:50:00+07:00');
    const tEnd = Date.parse('2026-11-21T00:10:00+07:00');
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.yt', appName: 'YouTube', category: 'Video', timestampMs: tStart });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.yt', timestampMs: tEnd });

    await child.syncDailyUsage('2026-11-20');
    await child.syncDailyUsage('2026-11-21');
    const reqRes = await child.submitTimeRequest(15, 'Xem tiếp bài giảng', { invokeEdgeFn: true });

    const dbDev = env.supabase.tables.devices.get(dev.id);
    assert.equal(dbDev.today_usage_date, '2026-11-21');
    assert.equal(dbDev.today_usage_seconds, 600);
    assert.equal(reqRes.status, 200);
    assert.equal(env.fcm.getSentToToken('tok-t3-01').length, 1);
    assert.equal(env.fcm.getSentToToken('tok-t3-01')[0].message.data.event_type, 'TIME_REQUEST');
  });

  it('T3-02: Multi-Device Telemetry + Active Device Switch + Realtime ACK (F5 + F7 + F1)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev1 = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, device_name: 'Máy 1', screen_brightness: 80 });
    const dev2 = env.supabase.seedDevice({ id: 'dev-2', family_id: fam.id, device_name: 'Máy 2', screen_brightness: 70 });
    env.supabase.seedDeviceMessage({ id: 'msg-m2', device_id: dev2.id, family_id: fam.id, message_text: 'Đi ngủ' });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    parent.selectDevice(dev1.id);

    const child2 = env.createChildAgent({ deviceId: dev2.id });
    await child2.connectRealtime();
    await child2.syncTelemetry({ brightnessRaw: 77, brightnessMax: 255, ringerMode: 'silent' });
    await child2.acknowledgeMessage('msg-m2', 'Con đi ngủ đây', { invokeEdgeFn: false });

    await waitFor(() => parent.inAppAlerts.length === 1);
    assert.equal(parent.inAppAlerts[0].deviceId, 'dev-2');
    assert.equal(parent.inAppAlerts[0].replyText, 'Con đi ngủ đây');

    parent.selectDevice(dev2.id);
    assert.equal(parent.getTelemetryView('dev-2').brightnessText, '30%');
    assert.equal(parent.getTelemetryView('dev-2').ringerModeLabel, 'Im lặng');
    assert.equal(parent.getTelemetryView('dev-1').brightnessText, '80%');
  });

  it('T3-03: Panic Lockdown + Extended Telemetry + Usage Quota Bar (F5 + F7 + F10)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      today_usage_date: '2026-11-20',
      screen_brightness: 80,
      media_volume: 65,
      policy: { daily_screen_time_limit_mins: 120 },
    });

    const child = env.createChildAgent({ deviceId: dev.id });
    child.persistedRoom.set('com.yt|2026-11-20', {
      packageName: 'com.yt',
      appName: 'YouTube',
      category: 'Video',
      date: '2026-11-20',
      durationMs: 4500 * 1000,
    });
    await child.syncDailyUsage('2026-11-20');

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    // Panic lockdown & child screen turns off
    await fetch(`${env.supabase.baseUrl}/rest/v1/devices?id=eq.dev-1`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.serviceRoleKey, Authorization: `Bearer ${env.supabase.serviceRoleKey}` },
      body: JSON.stringify({ is_locked: true }),
    });
    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/update_device_telemetry`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({ p_device_id: dev.id, p_screen_mode: 'off', p_is_screen_on: false }),
    });
    child.persistedRoom.get('com.yt|2026-11-20').durationMs = 4560 * 1000;
    await child.syncDailyUsage('2026-11-20');

    await waitFor(() => parent.getUsageView('dev-1').usedSeconds === 4560 && parent.devices.get('dev-1').is_locked === true);
    const tView = parent.getTelemetryView('dev-1');
    assert.equal(tView.screenMode, 'off');
    assert.equal(tView.isScreenOn, false);
    assert.equal(tView.brightnessText, '80%');
    assert.equal(tView.mediaVolumeText, '65%');
    assert.equal(Math.round(parent.getUsageView('dev-1').progressRatio * 1000), 633);
  });

  it('T3-04: device_messages Reply + FCM Dedup + Foreground Realtime (F1 + F2)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({ id: 'msg-combo', device_id: dev.id, family_id: fam.id, message_text: 'Nghe lời bố mẹ' });

    const parent = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'foreground' });
    await parent.registerPushToken('tok-combo');
    await parent.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.connectRealtime();
    await child.acknowledgeMessage('msg-combo', 'Con hiểu rồi', { invokeEdgeFn: true });

    await waitFor(() => parent.inAppAlerts.length === 1);
    // Second invoke attempts to re-send FCM -> blocked by fcm_notified_at
    const secondEdge = await fetch(`${env.supabase.baseUrl}/functions/v1/notify-family-parents`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({ device_id: dev.id, event_type: 'DEVICE_MESSAGE_REPLY', record_id: 'msg-combo' }),
    }).then((r) => r.json());

    assert.equal(secondEdge.deduplicated, true);
    assert.equal(secondEdge.sent, 0);
    assert.equal(parent.inAppAlerts.length, 1);
    assert.equal(parent.inAppAlerts[0].replyText, 'Con hiểu rồi');
  });

  it('T3-05: Parent time_request Approval + Extra Time + Usage Progress Recalculation (F3 + F10)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      is_locked: true,
      today_usage_date: '2026-11-20',
      policy: { daily_screen_time_limit_mins: 60 },
    });
    const child = env.createChildAgent({ deviceId: dev.id });
    child.persistedRoom.set('com.yt|2026-11-20', { packageName: 'com.yt', appName: 'YouTube', category: 'Video', date: '2026-11-20', durationMs: 3600 * 1000 });
    await child.syncDailyUsage('2026-11-20');

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    assert.equal(parent.getUsageView('dev-1').progressRatio, 1.0);

    const reqRes = await child.submitTimeRequest(30, 'Làm bài', { invokeEdgeFn: false });
    await parent.resolveTimeRequest(reqRes.body.id, 'approved', 30);

    await waitFor(() => parent.devices.get('dev-1').extra_time_minutes === 30);
    const view = parent.getUsageView('dev-1');
    assert.equal(parent.devices.get('dev-1').is_locked, false);
    assert.equal(view.totalLimitMins, 90);
    assert.equal(view.remainingText, '30m');
    assert.ok(Math.abs(view.progressRatio - 3600 / 5400) < 0.001);
  });

  it('T3-06: Legacy 5-arg Telemetry + New Extended Telemetry + get_family_details (F5 + F6 + F7)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id });

    await child.syncTelemetry({
      batteryLevel: 72,
      brightnessRaw: 179,
      brightnessMax: 255,
      alarmVolume: 90,
      ringerMode: 'vibrate',
    });

    // Legacy 5-arg heartbeat arrives
    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/update_device_telemetry`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_battery_level: 68,
        p_is_charging: true,
        p_current_app: 'Zoom',
        p_agent_version: '1.5.4',
      }),
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    const details = await parent.fetchFamilyDetails(fam.id);
    assert.equal(details.status, 200);
    const d = details.body.devices[0];
    assert.equal(d.battery_level, 68);
    assert.equal(d.is_charging, true);
    assert.equal(d.current_app_name, 'Zoom');
    assert.equal(d.screen_brightness, 70);
    assert.equal(d.alarm_volume, 90);
    assert.equal(d.ringer_mode, 'vibrate');
  });

  it('T3-07: Co-Admin Join + Push Token Registration + Multi-Platform FCM Fan-Out (F2 + F4)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-owner' });
    env.supabase.seedFamilyMember({ family_id: fam.id, user_id: 'parent-coadmin', role: 'parent' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({ id: 'msg-co', device_id: dev.id, family_id: fam.id, message_text: 'Chào con' });

    const pOwner = env.createParentClient({ userId: 'parent-owner', platform: 'android' });
    const pCo = env.createParentClient({ userId: 'parent-coadmin', platform: 'ios' });
    await pOwner.registerPushToken('tok-and');
    await pCo.registerPushToken('tok-ios');

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.submitTimeRequest(15, 'Học nhóm', { invokeEdgeFn: true });
    await child.acknowledgeMessage('msg-co', 'Dạ chào mẹ', { invokeEdgeFn: true });

    assert.equal(env.fcm.getSentToToken('tok-and').length, 2);
    assert.equal(env.fcm.getSentToToken('tok-ios').length, 2);
    assert.equal(env.fcm.getSentToToken('tok-and')[0].message.android.notification.channel_id, 'vfam_admin_alerts');
    assert.equal(env.fcm.getSentToToken('tok-ios')[0].message.apns.headers['apns-priority'], '10');
  });

  it('T3-08: Child Screen-Off Event + Telemetry Sync + Usage Session Close (F5 + F8 + F9)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id, timezone: 'Asia/Ho_Chi_Minh' });

    const t0 = Date.parse('2026-11-20T18:00:00+07:00');
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.yt', appName: 'YouTube', category: 'Video', timestampMs: t0 });
    child.processUsageEvent({ type: 'SCREEN_OFF', timestampMs: t0 + 120 * 1000 });

    await child.syncTelemetry({ isScreenOn: false, brightnessRaw: 191, brightnessMax: 255 });
    await child.syncDailyUsage('2026-11-20');

    const dbDev = env.supabase.tables.devices.get(dev.id);
    assert.equal(dbDev.screen_mode, 'off');
    assert.equal(dbDev.is_screen_on, false);
    assert.equal(dbDev.today_usage_seconds, 120);
  });

  it('T3-09: Nested policies Object + Weekday Limits + Usage Sync (F8 + F9 + F10)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      today_usage_date: '2026-11-21',
      policy: {
        rule_type: 'weekly',
        daily_screen_time_limit_mins: 120,
        weekday_limits: { sat: 180, sun: 180 },
      },
    });
    const child = env.createChildAgent({ deviceId: dev.id });
    child.persistedRoom.set('com.duo|2026-11-21', { packageName: 'com.duo', appName: 'Duolingo', category: 'Education', date: '2026-11-21', durationMs: 5400 * 1000 });
    await child.syncDailyUsage('2026-11-21');

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    const view = parent.getUsageView('dev-1');
    assert.equal(view.policy.ruleType, 'weekly');
    assert.equal(view.policy.weekdayLimits.sat, 180);
    assert.equal(view.totalLimitMins, 180);
    assert.equal(view.progressRatio, 0.5);
    assert.equal(view.usedText, '1h 30m');
    assert.equal(view.perAppBreakdown[0].appName, 'Duolingo');
  });

  it('T3-10: Stale Token Cleanup + Active Token Delivery + Realtime Sync (F2 + F1)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({ id: 'msg-reinstall', device_id: dev.id, family_id: fam.id, message_text: 'Check' });

    const pOld = env.createParentClient({ userId: 'parent-1', platform: 'android' });
    await pOld.registerPushToken('tok-old');
    env.fcm.setTokenError('tok-old', 404, 'UNREGISTERED');

    const pNew = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'foreground' });
    await pNew.registerPushToken('tok-new');
    await pNew.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.acknowledgeMessage('msg-reinstall', 'Đã cài lại', { invokeEdgeFn: true });

    await waitFor(() => pNew.inAppAlerts.length === 1);
    assert.equal(pNew.inAppAlerts.length, 1);
    assert.equal(env.fcm.getSentToToken('tok-new').length, 1);
    const tokens = [...env.supabase.tables.parent_push_tokens.values()].map((t) => t.fcm_token);
    assert.deepEqual(tokens, ['tok-new']);
  });

  it('T3-11: Foreground-to-Background Transition During Pending device_messages + time_requests (F1 + F2 + F3 + F4)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({ id: 'msg-1', device_id: dev.id, family_id: fam.id, message_text: 'Làm bài' });

    const parent = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'foreground' });
    await parent.registerPushToken('tok-trans');
    await parent.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.acknowledgeMessage('msg-1', 'Dạ con làm', { invokeEdgeFn: true });
    await waitFor(() => parent.inAppAlerts.length === 1);

    // Parent backgrounds app
    parent.setLifecycleState('background');
    const reqRes = await child.submitTimeRequest(20, 'Xin thêm', { invokeEdgeFn: true });

    await waitFor(() => parent.pendingNotificationsTray.length === 1);
    const route = await parent.tapNotificationFromTray(reqRes.body.id);
    assert.equal(route.screen, 'time_request_approval');
    assert.equal(parent.messageHistory.length, 1);
    assert.equal(parent.inAppAlerts.length, 1);
  });

  it('T3-12: Local Quota Exhaustion Auto-Lock + time_request + Unlock + Extended Telemetry (F3 + F5 + F8 + F10)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      today_usage_date: '2026-11-20',
      policy: { daily_screen_time_limit_mins: 30 },
    });

    const child = env.createChildAgent({ deviceId: dev.id, timezone: 'Asia/Ho_Chi_Minh' });
    child.persistedRoom.set('com.tiktok|2026-11-20', { packageName: 'com.tiktok', appName: 'TikTok', category: 'Social', date: '2026-11-20', durationMs: 1790 * 1000 });
    const t0 = Date.parse('2026-11-20T20:00:00+07:00');
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.tiktok', appName: 'TikTok', category: 'Social', timestampMs: t0 });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.tiktok', timestampMs: t0 + 15000 }); // 1805s > 1800s

    assert.equal(child.enforceQuotaIfExceeded('2026-11-20', 30), true);
    assert.equal(child.localLockState.isLocked, true);
    await child.syncDailyUsage('2026-11-20');

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    assert.equal(parent.getUsageView('dev-1').usedSeconds, 1805);
    assert.equal(parent.getUsageView('dev-1').isOverLimit, true);

    await child.connectRealtime();
    const reqRes = await child.submitTimeRequest(15, 'Xin thêm', { invokeEdgeFn: false });
    await parent.resolveTimeRequest(reqRes.body.id, 'approved', 15);

    await waitFor(() => child.localLockState.isLocked === false);
    assert.equal(parent.getUsageView('dev-1').totalLimitMins, 45);
  });

  it('T3-13: Parent App Restart / Channel Cleanup + Re-subscription prevents callback multiplication (F1 + F7 + F10)', async () => {
    const fam1 = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const fam2 = env.supabase.seedFamily({ id: 'fam-2', created_by: 'parent-1' });
    const dev1 = env.supabase.seedDevice({ id: 'dev-1', family_id: fam1.id, today_usage_date: '2026-11-20' });
    env.supabase.seedDevice({ id: 'dev-2', family_id: fam2.id, today_usage_date: '2026-11-20' });
    env.supabase.seedDeviceMessage({ id: 'msg-sw', device_id: dev1.id, family_id: fam1.id, message_text: 'Hello' });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam1.id);

    // Exercise RFC 6455 Ping/Pong liveness on active socket before switching families
    let pongPayload = null;
    parent.ws.on('pong', (buf) => {
      pongPayload = buf.toString('utf8');
    });
    parent.ws.ping('hb-check');
    await waitFor(() => pongPayload === 'hb-check');

    // Regression: abrupt client ws.terminate() immediately clears wsManager.clients & wsSessions and emits presence_diff leaves
    const child1 = env.createChildAgent({ deviceId: dev1.id });
    await child1.connectRealtime();
    let leaveDiff = null;
    parent.ws.on('message', (txt) => {
      const m = JSON.parse(txt);
      if (m.event === 'presence_diff' && m.payload?.leaves && Object.keys(m.payload.leaves).length > 0) {
        leaveDiff = m.payload;
      }
    });
    await child1.trackPresence({ device_id: dev1.id, status: 'online' });
    await waitFor(() => parent.devices.get('dev-1').isOnline === true);
    assert.equal(env.supabase.wsSessions.size, 2);
    assert.equal(env.supabase.wsManager.clients.size, 2);

    child1.disconnectRealtime(); // calls ws.terminate() without CLOSE frame
    await waitFor(
      () => leaveDiff !== null && env.supabase.wsSessions.size === 1 && env.supabase.wsManager.clients.size === 1
    );
    assert.ok(leaveDiff.leaves[dev1.id]);

    await parent.loadFamilyDashboard(fam2.id);
    await parent.loadFamilyDashboard(fam1.id);

    // Only active channels for fam-1 remain (2 channels: family + dev-1) and zero leaked sockets
    assert.equal(parent.activeChannels.size, 2);
    assert.equal(env.supabase.wsSessions.size, 1);
    assert.equal(env.supabase.wsManager.clients.size, 1);

    await child1.syncTelemetry({ batteryLevel: 55, brightnessRaw: 128 });
    await child1.acknowledgeMessage('msg-sw', 'OK ạ', { invokeEdgeFn: false });

    await waitFor(() => parent.inAppAlerts.length === 1);
    assert.equal(parent.inAppAlerts.length, 1);
    assert.equal(parent.getTelemetryView('dev-1').batteryText, '55%');
  });

  it('T3-14: Unread Messages Fetch + Multi-Message Batch ACK on Child Reconnect (F1 + F2)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({ id: 'msg-A', device_id: dev.id, family_id: fam.id, message_text: 'Tin A', sent_at: '2026-11-20T09:00:00Z' });
    env.supabase.seedDeviceMessage({ id: 'msg-B', device_id: dev.id, family_id: fam.id, message_text: 'Tin B', sent_at: '2026-11-20T09:05:00Z' });

    const parent = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'foreground' });
    await parent.registerPushToken('tok-batch');
    await parent.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id });
    const unread = await child.fetchUnreadMessages();
    assert.deepEqual(unread.body.map((m) => m.id), ['msg-B', 'msg-A']);

    await child.acknowledgeMessage('msg-A', null, { invokeEdgeFn: true });
    await child.acknowledgeMessage('msg-B', 'Con đã đọc', { invokeEdgeFn: true });

    await waitFor(() => parent.inAppAlerts.length === 2);
    assert.equal(env.fcm.getSentToToken('tok-batch').length, 2);
    assert.equal(env.fcm.getSentToToken('tok-batch')[0].message.data.record_id, 'msg-A');
    assert.equal(env.fcm.getSentToToken('tok-batch')[1].message.data.record_id, 'msg-B');
  });
});
