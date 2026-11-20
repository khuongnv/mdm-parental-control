import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { createE2EEnv, waitFor, parseNestedPolicies } from '../harness/sim_clients.mjs';

describe('Tier 2 — Boundary & Corner Cases F5–F10 (R2 & R3)', () => {
  let env;

  beforeEach(async () => {
    env = await createE2EEnv();
  });

  afterEach(async () => {
    await env.close();
  });

  // ---- F5 Boundary Cases (5) ----
  it('T2-F5-01: Out-of-range brightness & volume values clamped strictly to 0..100', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id });

    const snapLow = child.collectTelemetry({
      brightnessRaw: -5,
      brightnessMax: 255,
      mediaVolume: -10,
      ringVolume: -1,
    });
    const snapHigh = child.collectTelemetry({
      brightnessRaw: 300,
      brightnessMax: 255,
      mediaVolume: 150,
      ringVolume: 20,
      ringVolumeMax: 15,
      notificationVolume: 999,
      alarmVolume: 101,
    });

    for (const val of [snapLow.screen_brightness, snapLow.media_volume, snapLow.ring_volume]) {
      assert.equal(val, 0);
    }
    for (const val of [
      snapHigh.screen_brightness,
      snapHigh.media_volume,
      snapHigh.ring_volume,
      snapHigh.notification_volume,
      snapHigh.alarm_volume,
    ]) {
      assert.equal(val, 100);
    }
  });

  it('T2-F5-02: Minimum 0% vs Maximum 100% all channels emitted explicitly (not treated as null)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id });

    const rMin = await child.syncTelemetry({
      batteryLevel: 0,
      brightnessRaw: 0,
      mediaVolume: 0,
      ringVolume: 0,
      notificationVolume: 0,
      alarmVolume: 0,
      ringerMode: 'silent',
    });
    assert.equal(rMin.status, 200);
    assert.equal(rMin.snapshot.battery_level, 0);
    assert.equal(rMin.snapshot.screen_brightness, 0);
    assert.equal(rMin.snapshot.media_volume, 0);
    assert.equal(rMin.snapshot.is_media_muted, true);

    const rMax = await child.syncTelemetry({
      batteryLevel: 100,
      brightnessRaw: 255,
      mediaVolume: 100,
      ringVolume: 100,
      notificationVolume: 100,
      alarmVolume: 100,
      ringerMode: 'normal',
    });
    assert.equal(rMax.status, 200);
    assert.equal(rMax.snapshot.battery_level, 100);
    assert.equal(rMax.snapshot.screen_brightness, 100);
    assert.equal(rMax.snapshot.media_volume, 100);
    assert.equal(rMax.snapshot.is_media_muted, false);
  });

  it('T2-F5-03: Unknown / Doze screen mode and missing foreground package fallback', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id });

    const r = await child.syncTelemetry({
      isDoze: true,
      currentPackageName: null,
      currentAppName: 'Màn hình nghỉ',
    });
    assert.equal(r.status, 200);
    assert.equal(r.snapshot.screen_mode, 'doze');
    assert.equal(r.snapshot.is_screen_on, false);
    assert.equal(r.snapshot.current_package_name, null);
  });

  it('T2-F5-04: All three ringer_mode enum values (normal, vibrate, silent)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id });

    for (const mode of ['normal', 'vibrate', 'silent']) {
      const res = await child.syncTelemetry({ ringerMode: mode });
      assert.equal(res.status, 200);
      assert.equal(res.snapshot.ringer_mode, mode);
    }
  });

  it('T2-F5-05: Adaptive battery/screen-off throttling does not emit stale is_screen_on=true when screen turns off', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id });

    await child.syncTelemetry({ isScreenOn: true, isKeyguardLocked: false });
    assert.equal(env.supabase.tables.devices.get(dev.id).is_screen_on, true);

    await child.syncTelemetry({ isScreenOn: false, isDoze: false });
    assert.equal(env.supabase.tables.devices.get(dev.id).screen_mode, 'off');
    assert.equal(env.supabase.tables.devices.get(dev.id).is_screen_on, false);
  });

  // ---- F6 Boundary Cases (5) ----
  it('T2-F6-01: Partial COALESCE update preserves all previously stored extended telemetry', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      screen_brightness: 75,
      is_auto_brightness: true,
      screen_mode: 'on_unlocked',
      is_dark_mode: true,
      media_volume: 40,
      ring_volume: 60,
      notification_volume: 50,
      alarm_volume: 80,
      ringer_mode: 'vibrate',
      is_media_muted: false,
    });

    const resp = await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/update_device_telemetry`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_battery_level: 50,
        p_is_charging: true,
        p_current_app: 'YouTube',
        p_agent_version: '1.6.0',
      }),
    });
    assert.equal(resp.status, 200);

    const row = env.supabase.tables.devices.get(dev.id);
    assert.equal(row.battery_level, 50);
    assert.equal(row.is_charging, true);
    assert.equal(row.current_app_name, 'YouTube');
    assert.equal(row.screen_brightness, 75);
    assert.equal(row.is_auto_brightness, true);
    assert.equal(row.screen_mode, 'on_unlocked');
    assert.equal(row.is_dark_mode, true);
    assert.equal(row.media_volume, 40);
    assert.equal(row.ring_volume, 60);
    assert.equal(row.notification_volume, 50);
    assert.equal(row.alarm_volume, 80);
    assert.equal(row.ringer_mode, 'vibrate');
  });

  it('T2-F6-02: Explicit 0 and false values override previous non-zero/true values (not treated as NULL by COALESCE)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      screen_brightness: 80,
      media_volume: 70,
      is_screen_on: true,
      is_auto_brightness: true,
      is_media_muted: false,
    });

    const resp = await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/update_device_telemetry`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_screen_brightness: 0,
        p_media_volume: 0,
        p_is_screen_on: false,
        p_is_auto_brightness: false,
        p_is_media_muted: true,
      }),
    });
    assert.equal(resp.status, 200);
    const row = env.supabase.tables.devices.get(dev.id);
    assert.equal(row.screen_brightness, 0);
    assert.equal(row.media_volume, 0);
    assert.equal(row.is_screen_on, false);
    assert.equal(row.is_auto_brightness, false);
    assert.equal(row.is_media_muted, true);
  });

  it('T2-F6-03: Out-of-range telemetry percentage (-10 or 150) clamped to 0..100 per M1 SQL', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, screen_brightness: 50, media_volume: 50 });

    const r1 = await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/update_device_telemetry`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({ p_device_id: dev.id, p_screen_brightness: 150 }),
    });
    const r2 = await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/update_device_telemetry`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({ p_device_id: dev.id, p_media_volume: -10 }),
    });

    assert.equal(r1.status, 200);
    assert.equal(r2.status, 200);
    const b1 = await r1.json();
    const b2 = await r2.json();
    assert.equal(b1.success, true);
    assert.equal(b2.success, true);
    assert.equal(env.supabase.tables.devices.get(dev.id).screen_brightness, 100);
    assert.equal(env.supabase.tables.devices.get(dev.id).media_volume, 0);
  });

  it('T2-F6-04: Invalid screen_mode normalizes to unknown and invalid ringer_mode preserves existing via COALESCE', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      screen_mode: 'on_unlocked',
      ringer_mode: 'vibrate',
    });

    const r1 = await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/update_device_telemetry`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({ p_device_id: dev.id, p_screen_mode: 'invalid_mode' }),
    });
    const r2 = await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/update_device_telemetry`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({ p_device_id: dev.id, p_ringer_mode: 'loud' }),
    });

    assert.equal(r1.status, 200);
    assert.equal(r2.status, 200);
    assert.equal(env.supabase.tables.devices.get(dev.id).screen_mode, 'unknown');
    assert.equal(env.supabase.tables.devices.get(dev.id).ringer_mode, 'vibrate');
  });

  it('T2-F6-05: Non-existent p_device_id passed to update_device_telemetry returns 200 { success: false }', async () => {
    const resp = await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/update_device_telemetry`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: '00000000-0000-0000-0000-000000000999',
        p_battery_level: 50,
      }),
    });
    assert.equal(resp.status, 200);
    const body = await resp.json();
    assert.equal(body.success, false);
    assert.equal(body.message, 'Device not found');
    assert.equal(env.supabase.tables.devices.size, 0);
  });

  // ---- F7 Boundary Cases (5) ----
  it('T2-F7-01: Parent handles null / missing extended telemetry fields from legacy child', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      battery_level: 90,
      screen_brightness: null,
      screen_mode: null,
      media_volume: null,
      ringer_mode: null,
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    const view = parent.getTelemetryView('dev-1');

    assert.equal(view.batteryText, '90%');
    assert.equal(view.brightnessText, '--%');
    assert.equal(view.mediaVolumeText, '--%');
    assert.equal(view.screenModeLabel, 'Không rõ');
    assert.equal(view.ringerModeLabel, 'Bình thường');
  });

  it('T2-F7-02: All 5 screen_mode and 3 ringer_mode labels render distinctly', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    const screenLabels = new Set();
    for (const sm of ['on_unlocked', 'on_locked', 'doze', 'off', 'unknown']) {
      parent._mergeDeviceTelemetry('dev-1', { screen_mode: sm });
      screenLabels.add(parent.getTelemetryView('dev-1').screenModeLabel);
    }
    assert.equal(screenLabels.size, 5);

    const ringerLabels = new Set();
    for (const rm of ['normal', 'vibrate', 'silent']) {
      parent._mergeDeviceTelemetry('dev-1', { ringer_mode: rm });
      ringerLabels.add(parent.getTelemetryView('dev-1').ringerModeLabel);
    }
    assert.equal(ringerLabels.size, 3);
  });

  it('T2-F7-03: 0% brightness and 0% muted media volume render 0% (not hidden as --%)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      screen_brightness: 0,
      media_volume: 0,
      is_media_muted: true,
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    const view = parent.getTelemetryView('dev-1');

    assert.equal(view.brightnessText, '0%');
    assert.equal(view.mediaVolumeText, '0%');
    assert.equal(view.isMediaMuted, true);
  });

  it('T2-F7-04: Multi-device family switching keeps telemetry isolated per child device', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev1 = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, battery_level: 90, screen_brightness: 80, ringer_mode: 'normal' });
    const dev2 = env.supabase.seedDevice({ id: 'dev-2', family_id: fam.id, battery_level: 15, screen_brightness: 10, ringer_mode: 'silent' });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    parent.selectDevice(dev2.id);

    const child1 = env.createChildAgent({ deviceId: dev1.id });
    await child1.connectRealtime();
    await child1.sendBroadcast('TELEMETRY_UPDATE', { device_id: 'dev-1', battery_level: 89 });

    await waitFor(() => parent.getTelemetryView('dev-1').batteryText === '89%');
    const v2 = parent.getTelemetryView('dev-2');
    assert.equal(v2.batteryText, '15%');
    assert.equal(v2.brightnessText, '10%');
    assert.equal(v2.ringerMode, 'silent');
  });

  it('T2-F7-05: Partial WS TELEMETRY_UPDATE payload preserves previously rendered extended fields', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      battery_level: 60,
      screen_brightness: 60,
      media_volume: 70,
      alarm_volume: 85,
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.connectRealtime();
    await child.sendBroadcast('TELEMETRY_UPDATE', {
      device_id: 'dev-1',
      battery_level: 58,
      screen_brightness: 40,
    });

    await waitFor(() => parent.getTelemetryView('dev-1').brightnessText === '40%');
    const v = parent.getTelemetryView('dev-1');
    assert.equal(v.batteryText, '58%');
    assert.equal(v.mediaVolumeText, '70%');
    assert.equal(v.alarmVolumeText, '85%');
  });

  // ---- F8 Boundary Cases (6) ----
  it('T2-F8-01: Midnight rollover 23:55 -> 00:05 in Asia/Ho_Chi_Minh (UTC+7) splits usage across two local dates', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id, timezone: 'Asia/Ho_Chi_Minh' });

    const tStart = Date.parse('2026-11-20T23:55:00+07:00');
    const tEnd = Date.parse('2026-11-21T00:05:00+07:00');
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.google.android.youtube', appName: 'YouTube', category: 'Video', timestampMs: tStart });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.google.android.youtube', timestampMs: tEnd });

    const rDay1 = await child.syncDailyUsage('2026-11-20');
    const rDay2 = await child.syncDailyUsage('2026-11-21');

    assert.equal(rDay1.body.total_screen_time_seconds, 300);
    assert.equal(rDay2.body.total_screen_time_seconds, 300);
    assert.equal(rDay1.body.total_screen_time_seconds + rDay2.body.total_screen_time_seconds, 600);
  });

  it('T2-F8-02: UTC vs Asia/Ho_Chi_Minh date divergence (2026-11-20T17:01Z == 2026-11-21 00:01 ICT)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id, timezone: 'Asia/Ho_Chi_Minh' });

    const tUtc = Date.parse('2026-11-20T17:01:00Z');
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.duolingo', appName: 'Duolingo', category: 'Education', timestampMs: tUtc });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.duolingo', timestampMs: tUtc + 60000 });

    const res = await child.syncDailyUsage('2026-11-21');
    assert.equal(res.status, 200);
    assert.equal(res.body.usage_date, '2026-11-21');
    assert.equal(res.body.local_timezone, 'Asia/Ho_Chi_Minh');
    assert.equal(res.body.total_screen_time_seconds, 60);
  });

  it('T2-F8-03: Zero-usage day (0 seconds) and extreme 24-hour boundary (86400 seconds)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id });

    const rZero = await child.syncDailyUsage('2026-11-22');
    assert.equal(rZero.status, 200);
    assert.equal(rZero.body.total_screen_time_seconds, 0);

    // 25h raw duration gets capped at 86400s max per day
    child.persistedRoom.set('com.yt|2026-11-23', {
      packageName: 'com.yt',
      appName: 'YouTube',
      category: 'Video',
      date: '2026-11-23',
      durationMs: 90000 * 1000,
    });
    const rMax = await child.syncDailyUsage('2026-11-23');
    assert.equal(rMax.status, 200);
    assert.equal(rMax.body.total_screen_time_seconds, 86400);
  });

  it('T2-F8-04: Rapid app switching accumulates without negative or double-counted durations', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id });

    const t0 = Date.parse('2026-11-20T12:00:00+07:00');
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.app.a', appName: 'AppA', timestampMs: t0 });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.app.a', timestampMs: t0 + 2000 });
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.app.b', appName: 'AppB', timestampMs: t0 + 2000 });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.app.b', timestampMs: t0 + 3000 });
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.app.a', appName: 'AppA', timestampMs: t0 + 3000 });
    // Out-of-order PAUSED before sessionStartMs ignored without clearing the active session, followed by valid PAUSED at +5000
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.app.a', timestampMs: t0 + 2500 });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.app.a', timestampMs: t0 + 5000 });

    const summary = child.getLocalDaySummary('2026-11-20');
    assert.equal(summary.apps.find((a) => a.package_name === 'com.app.a').duration_seconds, 4);
    assert.equal(summary.apps.find((a) => a.package_name === 'com.app.b').duration_seconds, 1);
    assert.equal(summary.totalSeconds, 5);
  });

  it('T2-F8-05: Offline usage accumulated across 3 hours syncs complete local snapshot on reconnect', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id });

    const t0 = Date.parse('2026-11-20T09:00:00+07:00');
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.app.a', appName: 'AppA', timestampMs: t0 });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.app.a', timestampMs: t0 + 3600 * 1000 });
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.app.b', appName: 'AppB', timestampMs: t0 + 4000 * 1000 });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.app.b', timestampMs: t0 + 5800 * 1000 });

    const res = await child.syncDailyUsage('2026-11-20');
    assert.equal(res.status, 200);
    assert.equal(res.body.total_screen_time_seconds, 5400);
  });

  it('T2-F8-06: Multi-day Room composite PK (packageName, date) retains prior day rows independently', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id, timezone: 'Asia/Ho_Chi_Minh' });

    const d1 = Date.parse('2026-11-19T15:00:00+07:00');
    const d2 = Date.parse('2026-11-20T15:00:00+07:00');
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.google.android.youtube', appName: 'YouTube', timestampMs: d1 });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.google.android.youtube', timestampMs: d1 + 1200 * 1000 });
    child.processUsageEvent({ type: 'ACTIVITY_RESUMED', packageName: 'com.google.android.youtube', appName: 'YouTube', timestampMs: d2 });
    child.processUsageEvent({ type: 'ACTIVITY_PAUSED', packageName: 'com.google.android.youtube', timestampMs: d2 + 600 * 1000 });

    assert.equal(child.getLocalDaySummary('2026-11-19').totalSeconds, 1200);
    assert.equal(child.getLocalDaySummary('2026-11-20').totalSeconds, 600);
  });

  // ---- F9 Boundary Cases (5) ----
  it('T2-F9-01: Out-of-order / stale snapshot smaller than already-synced day total does not regress total', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const postSync = (sec) =>
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

    await postSync(3600);
    await postSync(1800); // stale retry!

    const summary = [...env.supabase.tables.daily_usage_summaries.values()][0];
    assert.equal(summary.total_screen_time_seconds, 3600);
    assert.equal(env.supabase.tables.devices.get(dev.id).today_usage_seconds, 3600);
  });

  it('T2-F9-02: Empty p_apps = [] with p_total_seconds = 0 succeeds cleanly', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const resp = await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_usage_date: '2026-11-20',
        p_total_seconds: 0,
        p_apps: [],
        p_timezone: 'Asia/Ho_Chi_Minh',
      }),
    });
    assert.equal(resp.status, 200);
    const summary = [...env.supabase.tables.daily_usage_summaries.values()][0];
    assert.equal(summary.total_screen_time_seconds, 0);
    assert.deepEqual(summary.app_breakdown, []);
    assert.deepEqual(summary.top_apps, []);
    assert.deepEqual(summary.category_breakdown, {});
    assert.equal(env.supabase.tables.devices.get(dev.id).today_usage_seconds, 0);
  });

  it('T2-F9-03: Syncing yesterday (2026-11-19) after devices.today_usage_date is already 2026-11-20 preserves today counter', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      today_usage_date: '2026-11-20',
      today_usage_seconds: 300,
    });

    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_usage_date: '2026-11-19',
        p_total_seconds: 7200,
        p_apps: [{ package_name: 'com.yt', app_name: 'YouTube', app_category: 'Video', duration_seconds: 7200 }],
      }),
    });

    const dbDev = env.supabase.tables.devices.get(dev.id);
    assert.equal(dbDev.today_usage_date, '2026-11-20');
    assert.equal(dbDev.today_usage_seconds, 300);

    const histSummary = [...env.supabase.tables.daily_usage_summaries.values()].find((s) => s.summary_date === '2026-11-19');
    assert.equal(histSummary.total_screen_time_seconds, 7200);
  });

  it('T2-F9-04: p_total_seconds mismatch vs sum of p_apps uses GREATEST(p_total_seconds, SUM)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_usage_date: '2026-11-20',
        p_total_seconds: 1200,
        p_apps: [
          { package_name: 'com.a', app_name: 'A', app_category: 'Other', duration_seconds: 900 },
          { package_name: 'com.b', app_name: 'B', app_category: 'Other', duration_seconds: 600 },
        ],
      }),
    });

    const summary = [...env.supabase.tables.daily_usage_summaries.values()][0];
    assert.equal(summary.total_screen_time_seconds, 1500);
  });

  it('T2-F9-05: Large p_apps array (50+ apps) with Vietnamese diacritics, quotes, and emojis over >65KB WS', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, today_usage_date: '2026-11-20' });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    // 450 apps produces > 65535 byte Realtime postgres_changes payload (exercises RFC 6455 64-bit len 127)
    const apps = Array.from({ length: 450 }, (_, i) => ({
      package_name: `com.vn.long.educational.package.number.${i}`,
      app_name: `Ứng dụng "Học Tập" '${i}' 📚`,
      app_category: 'Education',
      duration_seconds: 10,
    }));

    const resp = await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_usage_date: '2026-11-20',
        p_total_seconds: 4500,
        p_apps: apps,
      }),
    });
    assert.equal(resp.status, 200);
    assert.equal(env.supabase.tables.daily_app_usage.size, 450);
    const summary = [...env.supabase.tables.daily_usage_summaries.values()][0];
    assert.equal(summary.app_breakdown.length, 450);
    assert.equal(summary.app_breakdown[0].app_name, `Ứng dụng "Học Tập" '0' 📚`);

    await waitFor(() => parent.getUsageView('dev-1').perAppBreakdown.length === 450);
    assert.equal(parent.getUsageView('dev-1').usedSeconds, 4500);
  });

  // ---- F10 Boundary Cases (6) ----
  it('T2-F10-01: Nested policies parsed identically across Map, 1-element List, empty List, and null', async () => {
    assert.equal(parseNestedPolicies({ policies: { daily_screen_time_limit_mins: 90 } }).daily_screen_time_limit_mins, 90);
    assert.equal(parseNestedPolicies({ policies: [{ daily_screen_time_limit_mins: 90 }] }).daily_screen_time_limit_mins, 90);
    assert.equal(parseNestedPolicies({ policies: [] }), null);
    assert.equal(parseNestedPolicies({ policies: null }), null);

    // Also verify end-to-end against SimSupabaseServer in 'array' mode
    await env.close();
    env = await createE2EEnv({ policiesShape: 'array' });
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, policy: { daily_screen_time_limit_mins: 90 } });
    env.supabase.seedDevice({ id: 'dev-2', family_id: fam.id, policy: null });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    assert.equal(parent.getUsageView('dev-1').policy.dailyScreenTimeLimitMins, 90);
    assert.equal(parent.getUsageView('dev-2').policy.dailyScreenTimeLimitMins, 120);
  });

  it('T2-F10-02: Quota exceeded (used > limit) clamps progress bar to 1.0 without overflow', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      today_usage_date: '2026-11-20',
      policy: { daily_screen_time_limit_mins: 60 },
    });

    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_usage_date: '2026-11-20',
        p_total_seconds: 4800,
        p_apps: [{ package_name: 'com.yt', app_name: 'YouTube', app_category: 'Video', duration_seconds: 4800 }],
      }),
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    const view = parent.getUsageView('dev-1');
    assert.equal(view.progressRatio, 1.0);
    assert.equal(view.remainingText, '0m');
    assert.equal(view.isOverLimit, true);
  });

  it('T2-F10-03: Zero limit (daily_screen_time_limit_mins=0) avoids division-by-zero NaN/Infinity', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      today_usage_date: '2026-11-20',
      policy: { daily_screen_time_limit_mins: 0 },
    });

    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_usage_date: '2026-11-20',
        p_total_seconds: 300,
        p_apps: [{ package_name: 'com.yt', app_name: 'YouTube', app_category: 'Video', duration_seconds: 300 }],
      }),
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    const view = parent.getUsageView('dev-1');
    assert.equal(Number.isFinite(view.progressRatio), true);
    assert.equal(view.progressRatio, 1.0);
    assert.equal(view.remainingText, '0m');
  });

  it('T2-F10-04: Midnight rollover resets Parent UI displayed usage at 00:01 child local time', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      today_usage_date: '2026-11-20',
      today_usage_seconds: 6600,
    });

    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_usage_date: '2026-11-20',
        p_total_seconds: 6600,
        p_apps: [{ package_name: 'com.yt', app_name: 'YouTube', app_category: 'Video', duration_seconds: 6600 }],
      }),
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    assert.equal(parent.getUsageView('dev-1').usedSeconds, 6600);

    // Child rolls into 2026-11-21 with 0s
    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_usage_date: '2026-11-21',
        p_total_seconds: 0,
        p_apps: [],
      }),
    });

    await waitFor(() => parent.getUsageView('dev-1').usageDate === '2026-11-21');
    const view = parent.getUsageView('dev-1');
    assert.equal(view.usedSeconds, 0);
    assert.equal(view.progressRatio, 0);
    assert.deepEqual(view.perAppBreakdown, []);
  });

  it('T2-F10-05: Sub-minute app durations (15s, 45s) displayed accurately without rounding to 0m invisibility', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, today_usage_date: '2026-11-20' });

    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_usage_date: '2026-11-20',
        p_total_seconds: 60,
        p_apps: [
          { package_name: 'com.cam', app_name: 'Camera', app_category: 'Tools', duration_seconds: 45 },
          { package_name: 'com.calc', app_name: 'Calculator', app_category: 'Tools', duration_seconds: 15 },
        ],
      }),
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    const view = parent.getUsageView('dev-1');
    assert.equal(view.usedText, '1m');
    assert.equal(view.perAppBreakdown[0].durationLabel, '45 giây');
    assert.equal(view.perAppBreakdown[1].durationLabel, '15 giây');
  });

  it('T2-F10-06: Empty daily_usage_summaries & daily_app_usage for newly paired device + live first-sync perAppBreakdown', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    env.supabase.seedDevice({ id: 'dev-new', family_id: fam.id, today_usage_seconds: 0, today_usage_date: null });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    const view = parent.getUsageView('dev-new');

    assert.equal(view.usedText, '0m');
    assert.equal(view.progressRatio, 0);
    assert.equal(view.emptyStateText, 'Chưa có dữ liệu sử dụng hôm nay');

    // Regression: transitioning today_usage_date from null -> '2026-11-20' via live Realtime must NOT wipe perAppBreakdown
    const child = env.createChildAgent({ deviceId: 'dev-new', timezone: 'Asia/Ho_Chi_Minh' });
    child.persistedRoom.set('com.google.android.youtube|2026-11-20', {
      packageName: 'com.google.android.youtube',
      appName: 'YouTube',
      category: 'Video',
      date: '2026-11-20',
      durationMs: 600 * 1000,
    });
    await child.syncDailyUsage('2026-11-20');

    await waitFor(() => parent.getUsageView('dev-new').usedSeconds === 600);
    const updatedView = parent.getUsageView('dev-new');
    assert.equal(updatedView.usageDate, '2026-11-20');
    assert.equal(updatedView.usedSeconds, 600);
    assert.equal(updatedView.perAppBreakdown.length, 1);
    assert.equal(updatedView.perAppBreakdown[0].appName, 'YouTube');
  });
});
