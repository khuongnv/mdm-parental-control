import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { createE2EEnv, waitFor } from '../harness/sim_clients.mjs';

describe('Tier 4 — Real-World End-to-End Journeys (7 Scenarios)', () => {
  let env;

  beforeEach(async () => {
    env = await createE2EEnv();
  });

  afterEach(async () => {
    await env.close();
  });

  it('T4-01: School-night homework & bedtime journey (foreground Android Parent + active Child)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      device_name: 'Galaxy Tab A9',
      today_usage_date: '2026-11-20',
      policy: { daily_screen_time_limit_mins: 120 },
    });

    const parent = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'foreground' });
    await parent.registerPushToken('tok-hw-and');
    await parent.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id, timezone: 'Asia/Ho_Chi_Minh' });
    await child.connectRealtime();

    // Step 1: Child opens Duolingo (1800s) and Chrome (600s) + extended telemetry
    const t0 = Date.parse('2026-11-20T19:00:00+07:00');
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.duolingo', appName: 'Duolingo', category: 'Education', timestampMs: t0 });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.duolingo', timestampMs: t0 + 1800 * 1000 });
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.android.chrome', appName: 'Chrome', category: 'Browser', timestampMs: t0 + 1800 * 1000 });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.android.chrome', timestampMs: t0 + 2400 * 1000 });

    await child.syncTelemetry({
      batteryLevel: 85,
      brightnessRaw: 166,
      brightnessMax: 255,
      isAutoBrightness: true,
      mediaVolume: 40,
      ringerMode: 'normal',
      isScreenOn: true,
      isKeyguardLocked: false,
      currentAppName: 'Chrome',
      currentPackageName: 'com.android.chrome',
    });
    await child.syncDailyUsage('2026-11-20');

    // Step 2: Parent verifies live 40m / 120m (33.3%), per-app breakdown, and telemetry
    await waitFor(() => parent.getUsageView('dev-1').usedSeconds === 2400 && parent.getTelemetryView('dev-1').brightnessText === '65%');
    const uView = parent.getUsageView('dev-1');
    assert.equal(uView.usedText, '40m');
    assert.ok(Math.abs(uView.progressRatio - 1 / 3) < 0.01);
    assert.equal(uView.perAppBreakdown.find((a) => a.appName === 'Duolingo').durationLabel, '30m');
    assert.equal(uView.perAppBreakdown.find((a) => a.appName === 'Chrome').durationLabel, '10m');
    assert.equal(parent.getTelemetryView('dev-1').isAutoBrightness, true);
    assert.equal(parent.getTelemetryView('dev-1').mediaVolumeText, '40%');

    // Step 3: Parent sends bedtime message, child replies
    const msgRow = env.supabase.seedDeviceMessage({
      id: 'msg-hw-1',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Đến giờ nghỉ ngơi',
    });
    await child.acknowledgeMessage(msgRow.id, 'Con làm nốt 1 bài rồi tắt', { invokeEdgeFn: true });
    await waitFor(() => parent.inAppAlerts.length === 1);
    assert.equal(parent.inAppAlerts[0].replyText, 'Con làm nốt 1 bài rồi tắt');

    // Step 4: Child sends time request -> Parent approves +10m -> Child unlocks
    child.localLockState.isLocked = true;
    const reqRes = await child.submitTimeRequest(10, 'Nộp bài', { invokeEdgeFn: true });
    await waitFor(() => parent.inAppAlerts.length === 2);
    await parent.resolveTimeRequest(reqRes.body.id, 'approved', 10);
    await waitFor(() => child.localLockState.isLocked === false);
    assert.equal(parent.getUsageView('dev-1').totalLimitMins, 130);
  });

  it('T4-02: Commute / app-killed journey on iOS Enterprise Parent (com.dhtthni.quanlytaptrung)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'mother-ios' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      is_locked: true,
      policy: { daily_screen_time_limit_mins: 60 },
    });

    const mother = env.createParentClient({ userId: 'mother-ios', platform: 'ios', lifecycleState: 'terminated' });
    await mother.registerPushToken('tok-ios-commute', 'iPhone Enterprise');

    const child = env.createChildAgent({ deviceId: dev.id });
    const reqRes = await child.submitTimeRequest(20, 'Xem bài giảng Toán', { invokeEdgeFn: true });

    const sent = env.fcm.getSentToToken('tok-ios-commute');
    assert.equal(sent.length, 1);
    assert.equal(sent[0].message.apns.headers['apns-priority'], '10');
    assert.equal(sent[0].message.apns.payload.aps.sound, 'default');
    assert.equal(sent[0].message.apns.payload.aps.badge, 1);

    // Mother taps notification to cold-launch app
    await waitFor(() => mother.pendingNotificationsTray.length === 1);
    const route = await mother.tapNotificationFromTray(reqRes.body.id);
    assert.equal(route.via, 'getInitialMessage');
    assert.equal(route.screen, 'time_request_approval');
    assert.equal(route.deviceId, 'dev-1');

    // Mother loads dashboard, rejects request, sends follow-up message; child replies in foreground
    await mother.loadFamilyDashboard(fam.id);
    await mother.resolveTimeRequest(reqRes.body.id, 'rejected', 0);
    assert.equal(env.supabase.tables.devices.get('dev-1').extra_time_minutes, 0);

    const followMsg = env.supabase.seedDeviceMessage({
      id: 'msg-commute',
      device_id: dev.id,
      family_id: fam.id,
      message_text: 'Tối về mẹ mở cho nhé',
    });
    await child.acknowledgeMessage(followMsg.id, 'Dạ vâng', { invokeEdgeFn: true });

    await waitFor(() => mother.inAppAlerts.length === 1);
    assert.equal(mother.inAppAlerts.length, 1);
    assert.equal(mother.inAppAlerts[0].replyText, 'Dạ vâng');
  });

  it('T4-03: Two-parent, two-child household (Android Owner backgrounded + iOS Co-Admin foregrounded)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'father-and' });
    env.supabase.seedFamilyMember({ family_id: fam.id, user_id: 'mother-ios', role: 'parent' });

    const dev1 = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, device_name: 'Bé An', today_usage_date: '2026-11-20' });
    const dev2 = env.supabase.seedDevice({ id: 'dev-2', family_id: fam.id, device_name: 'Bé Bình', today_usage_date: '2026-11-20' });
    env.supabase.seedDeviceMessage({ id: 'msg-b2', device_id: dev2.id, family_id: fam.id, message_text: 'Ăn cơm chưa?' });

    const father = env.createParentClient({ userId: 'father-and', platform: 'android', lifecycleState: 'background' });
    const mother = env.createParentClient({ userId: 'mother-ios', platform: 'ios', lifecycleState: 'foreground' });
    await father.registerPushToken('tok-father-and');
    await mother.registerPushToken('tok-mother-ios');

    await mother.loadFamilyDashboard(fam.id);
    mother.selectDevice(dev1.id);

    const child1 = env.createChildAgent({ deviceId: dev1.id });
    const child2 = env.createChildAgent({ deviceId: dev2.id });

    await child1.syncTelemetry({
      batteryLevel: 18,
      brightnessRaw: 51,
      brightnessMax: 255,
      ringerMode: 'silent',
      mediaVolume: 0,
    });
    child1.persistedRoom.set('com.roblox|2026-11-20', { packageName: 'com.roblox', appName: 'Roblox', category: 'Games', date: '2026-11-20', durationMs: 5400 * 1000 });
    child1.persistedRoom.set('org.khanacademy|2026-11-20', { packageName: 'org.khanacademy', appName: 'Khan Academy', category: 'Education', date: '2026-11-20', durationMs: 1200 * 1000 });
    await child1.syncDailyUsage('2026-11-20');

    const reqRes = await child2.submitTimeRequest(15, 'Chơi thêm', { invokeEdgeFn: true });
    await child2.acknowledgeMessage('msg-b2', 'Con ăn cơm xong rồi', { invokeEdgeFn: true });

    await waitFor(() => mother.inAppAlerts.length === 2 && mother.getUsageView('dev-1').usedSeconds === 6600);
    assert.equal(mother.getUsageView('dev-1').usedText, '1h 50m');
    assert.equal(mother.getTelemetryView('dev-1').batteryText, '18%');
    assert.equal(mother.getTelemetryView('dev-1').brightnessText, '20%');
    assert.equal(mother.getTelemetryView('dev-1').isMediaMuted, true);

    // Father received both high-priority FCM pushes on vfam_admin_alerts in background
    assert.equal(env.fcm.getSentToToken('tok-father-and').length, 2);
    const route = await father.tapNotificationFromTray(reqRes.body.id);
    assert.equal(route.deviceId, 'dev-2');
  });

  it('T4-04: Full-day offline tablet -> midnight rollover -> morning reconnect sync', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id, timezone: 'Asia/Ho_Chi_Minh' });

    // Offline usage on 2026-11-20 evening (3600s) + midnight split 23:55..00:05 (300s + 300s)
    const tEve = Date.parse('2026-11-20T19:00:00+07:00');
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.yt', appName: 'YouTube', category: 'Video', timestampMs: tEve });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.yt', timestampMs: tEve + 3600 * 1000 });

    const tMidStart = Date.parse('2026-11-20T23:55:00+07:00');
    const tMidEnd = Date.parse('2026-11-21T00:05:00+07:00');
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.yt', appName: 'YouTube', category: 'Video', timestampMs: tMidStart });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.yt', timestampMs: tMidEnd });

    // Morning reconnect at 07:30+07:00 on 2026-11-21
    await child.syncDailyUsage('2026-11-20');
    await child.syncDailyUsage('2026-11-21');
    await child.syncTelemetry({ batteryLevel: 100, isCharging: true, brightnessRaw: 217, brightnessMax: 255 });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    const todayView = parent.getUsageView('dev-1');
    assert.equal(todayView.usageDate, '2026-11-21');
    assert.equal(todayView.usedSeconds, 300);
    assert.equal(todayView.usedText, '5m');

    const hist = await parent.fetchDeviceUsage('dev-1', '2026-11-20');
    assert.equal(hist.totalSeconds, 3900);
  });

  it('T4-05: Child service kill recovery + SCREEN_OFF close + accurate telemetry & usage continuity', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, today_usage_date: '2026-11-20' });
    const child = env.createChildAgent({ deviceId: dev.id, timezone: 'Asia/Ho_Chi_Minh' });

    const tStart = Date.parse('2026-11-20T15:00:00+07:00');
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.zhiliaoapp.musically', appName: 'TikTok', category: 'Social', timestampMs: tStart });
    await child.syncTelemetry({ batteryLevel: 70, brightnessRaw: 242, brightnessMax: 255, mediaVolume: 100 });

    // OS kills service at 180s, WorkManager restarts 15s later, child continues to 300s, then SCREEN_OFF
    child.simulateKillAndRestart();
    child.processUsageEvent({ type: 'SCREEN_OFF', timestampMs: tStart + 300 * 1000 });
    await child.syncTelemetry({ isScreenOn: false, brightnessRaw: 242, brightnessMax: 255, mediaVolume: 100 });
    await child.syncDailyUsage('2026-11-20');

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    assert.equal(parent.getUsageView('dev-1').usedSeconds, 300);
    assert.equal(parent.getUsageView('dev-1').usedText, '5m');
    assert.equal(parent.getTelemetryView('dev-1').screenMode, 'off');
    assert.equal(parent.getTelemetryView('dev-1').mediaVolumeText, '100%');
  });

  it('T4-06: Token rotation & stale device cleanup lifecycle', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    env.supabase.seedDeviceMessage({ id: 'msg-rot', device_id: dev.id, family_id: fam.id, message_text: 'Test' });

    const oldParent = env.createParentClient({ userId: 'parent-1', platform: 'android' });
    await oldParent.registerPushToken('tok-old-android');
    env.fcm.setTokenError('tok-old-android', 404, 'UNREGISTERED');

    const newParent = env.createParentClient({ userId: 'parent-1', platform: 'ios', lifecycleState: 'background' });
    await newParent.registerPushToken('tok-ios-new');

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.submitTimeRequest(15, 'Xin thêm', { invokeEdgeFn: true });

    assert.equal(env.fcm.getSentToToken('tok-ios-new').length, 1);
    assert.equal(env.supabase.tables.parent_push_tokens.size, 1);

    // Second notification sends cleanly with zero 404 errors
    env.fcm.clear();
    await child.acknowledgeMessage('msg-rot', 'Dạ', { invokeEdgeFn: true });
    assert.equal(env.fcm.getSentToToken('tok-ios-new').length, 1);
    assert.equal(env.fcm.getRejectedMessages().length, 0);
  });

  it('T4-07: Dual-channel race (pg_net + client retry) & network flapping resilience', async () => {
    await env.close();
    env = await createE2EEnv({ enablePgNetTriggers: true });

    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, today_usage_date: '2026-11-20' });

    const parent = env.createParentClient({ userId: 'parent-1', platform: 'android', lifecycleState: 'background' });
    await parent.registerPushToken('tok-flap');

    const child = env.createChildAgent({ deviceId: dev.id, timezone: 'Asia/Ho_Chi_Minh' });
    const reqRes = await child.submitTimeRequest(15, 'Mạng yếu', { invokeEdgeFn: true });

    // Child WS drops and reconnects after 5s, pushing telemetry and usage
    child.disconnectRealtime();
    await child.connectRealtime();
    await child.syncTelemetry({ batteryLevel: 62, brightnessRaw: 128, screenMode: 'on_unlocked' });
    child.persistedRoom.set('com.duo|2026-11-20', { packageName: 'com.duo', appName: 'Duolingo', category: 'Education', date: '2026-11-20', durationMs: 900 * 1000 });
    await child.syncDailyUsage('2026-11-20');

    // Parent returns foreground and loads/catches up
    parent.setLifecycleState('foreground');
    await parent.loadFamilyDashboard(fam.id);
    await parent.syncPendingEvents();

    await waitFor(() => env.fcm.getSentToToken('tok-flap').length === 1);
    assert.equal(env.fcm.getSentToToken('tok-flap').length, 1);
    assert.equal(parent.systemNotifications.length, 1);
    assert.equal(parent.getUsageView('dev-1').usedSeconds, 900);
    assert.equal(parent.getTelemetryView('dev-1').batteryText, '62%');
    assert.ok(parent.persistedDedupKeys.has(`time_req_${reqRes.body.id}`));
  });
});
