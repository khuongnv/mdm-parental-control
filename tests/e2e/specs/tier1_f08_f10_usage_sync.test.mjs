import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { createE2EEnv, waitFor } from '../harness/sim_clients.mjs';

describe('Tier 1 — Accurate Usage Tracking & Sync F8–F10 (R3)', () => {
  let env;

  beforeEach(async () => {
    env = await createE2EEnv();
  });

  afterEach(async () => {
    await env.close();
  });

  // ---- F8: target-node Accurate Usage Tracking & Sync ----
  it('T1-F8-01: Accurate foreground session accumulation in exact seconds (no / 60 truncation)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id, timezone: 'Asia/Ho_Chi_Minh' });

    const t1Start = Date.parse('2026-11-20T10:00:00+07:00');
    const t1End = Date.parse('2026-11-20T10:00:45+07:00'); // 45s
    const t2Start = Date.parse('2026-11-20T10:05:00+07:00');
    const t2End = Date.parse('2026-11-20T10:05:50+07:00'); // 50s

    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.example.game', appName: 'FunGame', category: 'Games', timestampMs: t1Start });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.example.game', timestampMs: t1End });
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.example.game', appName: 'FunGame', category: 'Games', timestampMs: t2Start });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.example.game', timestampMs: t2End });

    const res = await child.syncDailyUsage('2026-11-20');
    assert.equal(res.status, 200);
    assert.equal(res.payload.totalSeconds, 95);
    assert.equal(res.payload.apps[0].duration_seconds, 95);
    assert.equal(res.body.total_screen_time_seconds, 95);
  });

  it('T1-F8-02: Persisted session state machine survives service restart / OS kill', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id, timezone: 'Asia/Ho_Chi_Minh' });

    const tStart = Date.parse('2026-11-20T14:00:00+07:00');
    const tPause = Date.parse('2026-11-20T14:05:00+07:00'); // 300s

    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.google.android.youtube', appName: 'YouTube', category: 'Video', timestampMs: tStart });
    // OS kills service at 14:03:00 and WorkManager restarts at 14:03:10
    child.simulateKillAndRestart();
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.google.android.youtube', timestampMs: tPause });

    const res = await child.syncDailyUsage('2026-11-20');
    assert.equal(res.status, 200);
    assert.equal(res.body.total_screen_time_seconds, 300);
    assert.equal(res.payload.apps[0].duration_seconds, 300);
  });

  it('T1-F8-03: SCREEN_OFF closes active foreground session immediately', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id, timezone: 'Asia/Ho_Chi_Minh' });

    const tStart = Date.parse('2026-11-20T16:00:00+07:00');
    const tScreenOff = Date.parse('2026-11-20T16:02:15+07:00'); // 135s

    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.zhiliaoapp.musically', appName: 'TikTok', category: 'Social', timestampMs: tStart });
    child.processUsageEvent({ type: 'SCREEN_OFF', timestampMs: tScreenOff });

    const res = await child.syncDailyUsage('2026-11-20');
    assert.equal(res.status, 200);
    assert.equal(res.body.total_screen_time_seconds, 135);
  });

  it('T1-F8-04: Launcher and system UI packages filtered from tracked screen time', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id, timezone: 'Asia/Ho_Chi_Minh' });

    const t0 = Date.parse('2026-11-20T11:00:00+07:00');
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.sec.android.app.launcher', appName: 'One UI Home', timestampMs: t0 });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.sec.android.app.launcher', timestampMs: t0 + 120000 });
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.android.systemui', appName: 'System UI', timestampMs: t0 + 120000 });
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.duolingo', appName: 'Duolingo', category: 'Education', timestampMs: t0 + 150000 });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.duolingo', timestampMs: t0 + 210000 }); // 60s

    const res = await child.syncDailyUsage('2026-11-20');
    assert.equal(res.status, 200);
    assert.equal(res.payload.apps.length, 1);
    assert.equal(res.payload.apps[0].package_name, 'com.duolingo');
    assert.equal(res.payload.totalSeconds, 60);
  });

  it('T1-F8-05: Periodic checkpoint sync + UsageSyncWorker pushes local Room totals to Backend', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id, timezone: 'Asia/Ho_Chi_Minh' });

    child.persistedRoom.set('com.duolingo|2026-11-20', {
      packageName: 'com.duolingo',
      appName: 'Duolingo',
      category: 'Education',
      date: '2026-11-20',
      durationMs: 1800 * 1000,
    });
    child.persistedRoom.set('com.google.android.youtube|2026-11-20', {
      packageName: 'com.google.android.youtube',
      appName: 'YouTube',
      category: 'Video',
      date: '2026-11-20',
      durationMs: 900 * 1000,
    });

    const res = await child.syncDailyUsage('2026-11-20');
    assert.equal(res.status, 200);
    assert.equal(res.body.total_screen_time_seconds, 2700);
    assert.equal(res.body.local_timezone, 'Asia/Ho_Chi_Minh');
    assert.equal(res.body.app_count, 2);
  });

  // ---- F9: Backend Accurate Usage Schema & RPCs ----
  it('T1-F9-01: sync_device_daily_usage upserts daily_app_usage, daily_usage_summaries, and devices', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const resp = await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_usage_date: '2026-11-20',
        p_total_seconds: 3690,
        p_apps: [
          { package_name: 'com.yt', app_name: 'YouTube', app_category: 'Video', duration_seconds: 2400 },
          { package_name: 'com.duo', app_name: 'Duolingo', app_category: 'Education', duration_seconds: 1290 },
        ],
        p_timezone: 'Asia/Ho_Chi_Minh',
      }),
    });
    assert.equal(resp.status, 200);

    const appRows = [...env.supabase.tables.daily_app_usage.values()];
    assert.equal(appRows.length, 2);
    assert.equal(appRows.find((r) => r.package_name === 'com.yt').duration_seconds, 2400);
    assert.equal(appRows.find((r) => r.package_name === 'com.duo').duration_seconds, 1290);

    const summary = [...env.supabase.tables.daily_usage_summaries.values()][0];
    assert.equal(summary.total_screen_time_seconds, 3690);
    assert.equal(summary.total_screen_time_mins, 61);
    assert.equal(summary.local_timezone, 'Asia/Ho_Chi_Minh');
    assert.equal(summary.app_breakdown.length, 2);
    assert.equal(summary.top_apps.length, 2);
    assert.equal(summary.category_breakdown.Video, 2400);

    const dbDev = env.supabase.tables.devices.get(dev.id);
    assert.equal(dbDev.today_usage_seconds, 3690);
    assert.equal(dbDev.today_usage_date, '2026-11-20');
  });

  it('T1-F9-02: Idempotent repeated sync updates existing (device_id, usage_date, package_name) rows without duplicating', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const callSync = (ytSec, totalSec) =>
      fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
        body: JSON.stringify({
          p_device_id: dev.id,
          p_usage_date: '2026-11-20',
          p_total_seconds: totalSec,
          p_apps: [
            { package_name: 'com.yt', app_name: 'YouTube', app_category: 'Video', duration_seconds: ytSec },
            { package_name: 'com.duo', app_name: 'Duolingo', app_category: 'Education', duration_seconds: 1290 },
          ],
          p_timezone: 'Asia/Ho_Chi_Minh',
        }),
      });

    await callSync(2400, 3690);
    await callSync(2700, 3990);

    assert.equal(env.supabase.tables.daily_app_usage.size, 2);
    const ytRow = [...env.supabase.tables.daily_app_usage.values()].find((r) => r.package_name === 'com.yt');
    assert.equal(ytRow.duration_seconds, 2700);
    const summary = [...env.supabase.tables.daily_usage_summaries.values()][0];
    assert.equal(summary.total_screen_time_seconds, 3990);
    assert.equal(env.supabase.tables.devices.get(dev.id).today_usage_seconds, 3990);
  });

  it('T1-F9-03: daily_usage_summaries and daily_app_usage are in supabase_realtime publication', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, today_usage_date: '2026-11-20' });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    const tablesSeen = new Set();
    parent.ws.on('message', (txt) => {
      const m = JSON.parse(txt);
      if (m.event === 'postgres_changes') {
        tablesSeen.add(m.payload?.data?.table);
      }
    });

    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_usage_date: '2026-11-20',
        p_total_seconds: 600,
        p_apps: [{ package_name: 'com.duo', app_name: 'Duolingo', app_category: 'Education', duration_seconds: 600 }],
      }),
    });

    await waitFor(() => tablesSeen.has('daily_usage_summaries') && tablesSeen.has('daily_app_usage'));
    assert.ok(tablesSeen.has('daily_usage_summaries'));
    assert.ok(tablesSeen.has('daily_app_usage'));
  });

  it('T1-F9-04: RLS enforces parent family isolation on daily_app_usage and daily_usage_summaries', async () => {
    const fam1 = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-A' });
    const fam2 = env.supabase.seedFamily({ id: 'fam-2', created_by: 'parent-B' });
    const dev1 = env.supabase.seedDevice({ id: 'dev-1', family_id: fam1.id });
    env.supabase.seedDevice({ id: 'dev-2', family_id: fam2.id });

    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev1.id,
        p_usage_date: '2026-11-20',
        p_total_seconds: 1200,
        p_apps: [{ package_name: 'com.yt', app_name: 'YouTube', app_category: 'Video', duration_seconds: 1200 }],
      }),
    });

    const jwtA = env.supabase.issueToken({ sub: 'parent-A', role: 'authenticated' });
    const jwtB = env.supabase.issueToken({ sub: 'parent-B', role: 'authenticated' });

    const rB1 = await fetch(`${env.supabase.baseUrl}/rest/v1/daily_app_usage?device_id=eq.dev-1`, {
      headers: { apikey: env.supabase.anonKey, Authorization: `Bearer ${jwtB}` },
    }).then((r) => r.json());
    const rB2 = await fetch(`${env.supabase.baseUrl}/rest/v1/daily_usage_summaries?device_id=eq.dev-1`, {
      headers: { apikey: env.supabase.anonKey, Authorization: `Bearer ${jwtB}` },
    }).then((r) => r.json());
    const rA = await fetch(`${env.supabase.baseUrl}/rest/v1/daily_app_usage?device_id=eq.dev-1`, {
      headers: { apikey: env.supabase.anonKey, Authorization: `Bearer ${jwtA}` },
    }).then((r) => r.json());

    assert.deepEqual(rB1, []);
    assert.deepEqual(rB2, []);
    assert.equal(rA.length, 1);
  });

  it('T1-F9-05: app_breakdown preserves all apps beyond top 5 while top_apps caps at 5', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const apps = Array.from({ length: 8 }, (_, idx) => ({
      package_name: `com.app.${idx + 1}`,
      app_name: `App ${idx + 1}`,
      app_category: 'Other',
      duration_seconds: (idx + 1) * 100,
    }));

    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_usage_date: '2026-11-20',
        p_total_seconds: 3600,
        p_apps: apps,
      }),
    });

    const summary = [...env.supabase.tables.daily_usage_summaries.values()][0];
    assert.equal(summary.app_breakdown.length, 8);
    assert.equal(summary.top_apps.length, 5);
    assert.equal(summary.top_apps[0].duration_seconds, 800);
    assert.equal(summary.top_apps[4].duration_seconds, 400);
    assert.equal(env.supabase.tables.daily_app_usage.size, 8);
  });

  // ---- F10: admin-node Usage Time & Policy Display ----
  it('T1-F10-01: Parent displays exact total daily screen time, remaining quota, and real progress bar', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      extra_time_minutes: 30,
      today_usage_date: '2026-11-20',
      policy: { daily_screen_time_limit_mins: 120 },
    });

    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_usage_date: '2026-11-20',
        p_total_seconds: 4500,
        p_apps: [{ package_name: 'com.yt', app_name: 'YouTube', app_category: 'Video', duration_seconds: 4500 }],
      }),
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    const view = parent.getUsageView('dev-1');

    assert.equal(view.usedSeconds, 4500);
    assert.equal(view.usedText, '1h 15m');
    assert.equal(view.limitText, '2h 30m');
    assert.equal(view.remainingText, '1h 15m');
    assert.equal(view.progressRatio, 0.5);
  });

  it('T1-F10-02: Parent displays full per-app breakdown matching child daily_app_usage', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, today_usage_date: '2026-11-20' });

    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_usage_date: '2026-11-20',
        p_total_seconds: 5490,
        p_apps: [
          { package_name: 'com.yt', app_name: 'YouTube', app_category: 'Video', duration_seconds: 3600 },
          { package_name: 'com.duo', app_name: 'Duolingo', app_category: 'Education', duration_seconds: 1845 },
          { package_name: 'com.chrome', app_name: 'Chrome', app_category: 'Browser', duration_seconds: 45 },
        ],
      }),
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    const view = parent.getUsageView('dev-1');

    assert.equal(view.perAppBreakdown.length, 3);
    assert.equal(view.perAppBreakdown[0].appName, 'YouTube');
    assert.equal(view.perAppBreakdown[0].durationLabel, '1h 0m');
    assert.equal(view.perAppBreakdown[1].appName, 'Duolingo');
    assert.equal(view.perAppBreakdown[1].durationSeconds, 1845);
    assert.equal(view.perAppBreakdown[2].appName, 'Chrome');
    assert.equal(view.perAppBreakdown[2].durationLabel, '45 giây');
  });

  it('T1-F10-03: _selectDevice correctly parses nested policies from select(*, policies(*))', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      policy: {
        daily_screen_time_limit_mins: 90,
        bedtime_start: '21:30:00',
        bedtime_end: '06:30:00',
        is_bedtime_enabled: true,
        weekday_limits: { sat: 120 },
      },
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    parent.selectDevice('dev-1');
    const view = parent.getUsageView('dev-1');

    assert.equal(view.policy.dailyScreenTimeLimitMins, 90);
    assert.equal(view.policy.bedtimeStart, '21:30:00');
    assert.equal(view.policy.bedtimeEnd, '06:30:00');
    assert.equal(view.policy.isBedtimeEnabled, true);
  });

  it('T1-F10-04: Realtime usage updates live while Parent keeps dashboard open', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      today_usage_date: '2026-11-20',
      policy: { daily_screen_time_limit_mins: 120 },
    });

    const syncUsage = (sec) =>
      fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
        body: JSON.stringify({
          p_device_id: dev.id,
          p_usage_date: '2026-11-20',
          p_total_seconds: sec,
          p_apps: [{ package_name: 'com.yt', app_name: 'YouTube', app_category: 'Video', duration_seconds: sec }],
        }),
      });

    await syncUsage(1800);
    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    assert.equal(parent.getUsageView('dev-1').progressRatio, 0.25);

    await syncUsage(3600);
    await waitFor(() => parent.getUsageView('dev-1').usedSeconds === 3600);

    const view = parent.getUsageView('dev-1');
    assert.equal(view.usedText, '1h 0m');
    assert.equal(view.progressRatio, 0.5);
    assert.equal(view.perAppBreakdown[0].durationSeconds, 3600);
  });

  it('T1-F10-05: Parent queries usage using child today_usage_date / local timezone (Asia/Ho_Chi_Minh)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      today_usage_date: '2026-11-21',
    });

    // Historical 2026-11-20 had 5000s, while child's local 2026-11-21 has 600s
    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_usage_date: '2026-11-20',
        p_total_seconds: 5000,
        p_apps: [{ package_name: 'com.yt', app_name: 'YouTube', app_category: 'Video', duration_seconds: 5000 }],
      }),
    });
    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_usage_date: '2026-11-21',
        p_total_seconds: 600,
        p_apps: [{ package_name: 'com.duo', app_name: 'Duolingo', app_category: 'Education', duration_seconds: 600 }],
      }),
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    const view = parent.getUsageView('dev-1');

    assert.equal(view.usageDate, '2026-11-21');
    assert.equal(view.usedSeconds, 600);
    assert.equal(view.usedText, '10m');
  });
});
