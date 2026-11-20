import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { createE2EEnv, waitFor } from '../harness/sim_clients.mjs';

describe('Tier 1 — Extended Telemetry F5–F7 (R2)', () => {
  let env;

  beforeEach(async () => {
    env = await createE2EEnv();
  });

  afterEach(async () => {
    await env.close();
  });

  // ---- F5: target-node Extended Telemetry Collection ----
  it('T1-F5-01: Collects complete extended telemetry snapshot (brightness, screen mode, volumes, battery, app)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id });

    const res = await child.syncTelemetry({
      batteryLevel: 82,
      isCharging: true,
      brightnessRaw: 153,
      brightnessMax: 255,
      isAutoBrightness: false,
      isScreenOn: true,
      isKeyguardLocked: false,
      isDarkMode: true,
      mediaVolume: 70,
      ringVolume: 80,
      notificationVolume: 50,
      alarmVolume: 90,
      ringerMode: 'normal',
      currentAppName: 'YouTube',
      currentPackageName: 'com.google.android.youtube',
    });

    assert.equal(res.status, 200);
    const snap = res.snapshot;
    assert.equal(snap.battery_level, 82);
    assert.equal(snap.is_charging, true);
    assert.equal(snap.screen_brightness, 60);
    assert.equal(snap.is_auto_brightness, false);
    assert.equal(snap.screen_mode, 'on_unlocked');
    assert.equal(snap.is_screen_on, true);
    assert.equal(snap.is_dark_mode, true);
    assert.equal(snap.media_volume, 70);
    assert.equal(snap.ring_volume, 80);
    assert.equal(snap.notification_volume, 50);
    assert.equal(snap.alarm_volume, 90);
    assert.equal(snap.ringer_mode, 'normal');
    assert.equal(snap.is_media_muted, false);
    assert.equal(snap.current_app_name, 'YouTube');
    assert.equal(snap.current_package_name, 'com.google.android.youtube');
  });

  it('T1-F5-02: Screen mode state detection (on_unlocked, on_locked, doze, off)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id });

    const unlocked = child.collectTelemetry({ isScreenOn: true, isKeyguardLocked: false, isDoze: false });
    const locked = child.collectTelemetry({ isScreenOn: true, isKeyguardLocked: true, isDoze: false });
    const doze = child.collectTelemetry({ isScreenOn: false, isKeyguardLocked: true, isDoze: true });
    const off = child.collectTelemetry({ isScreenOn: false, isKeyguardLocked: false, isDoze: false });

    assert.deepEqual([unlocked.screen_mode, unlocked.is_screen_on], ['on_unlocked', true]);
    assert.deepEqual([locked.screen_mode, locked.is_screen_on], ['on_locked', true]);
    assert.deepEqual([doze.screen_mode, doze.is_screen_on], ['doze', false]);
    assert.deepEqual([off.screen_mode, off.is_screen_on], ['off', false]);
  });

  it('T1-F5-03: Ringer mode & media mute collection (normal, vibrate, silent, is_media_muted)', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id });

    const c1 = child.collectTelemetry({ ringerMode: 'vibrate', mediaVolume: 0 });
    assert.equal(c1.ringer_mode, 'vibrate');
    assert.equal(c1.media_volume, 0);
    assert.equal(c1.is_media_muted, true);

    const c2 = child.collectTelemetry({ ringerMode: 'silent', mediaVolume: 45 });
    assert.equal(c2.ringer_mode, 'silent');
    assert.equal(c2.media_volume, 45);
    assert.equal(c2.is_media_muted, false);
  });

  it('T1-F5-04: Auto-brightness flag and normalized 0..100 brightness percentage', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });
    const child = env.createChildAgent({ deviceId: dev.id });

    const snap = child.collectTelemetry({
      isAutoBrightness: true,
      brightnessRaw: 255,
      brightnessMax: 255,
    });
    assert.equal(snap.is_auto_brightness, true);
    assert.equal(snap.screen_brightness, 100);
  });

  it('T1-F5-05: Unified snake_case telemetry emission across WS Broadcast, Presence, and RPC', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    const capturedFrames = [];
    parent.ws.on('message', (txt) => capturedFrames.push(JSON.parse(txt)));

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.connectRealtime();
    await child.syncTelemetry({
      batteryLevel: 73,
      isCharging: false,
      brightnessRaw: 102,
      brightnessMax: 255,
      isAutoBrightness: true,
      isScreenOn: true,
      isKeyguardLocked: false,
      isDarkMode: true,
      mediaVolume: 35,
      ringVolume: 65,
      notificationVolume: 55,
      alarmVolume: 95,
      ringerMode: 'vibrate',
      currentAppName: 'Duolingo',
      currentPackageName: 'com.duolingo',
    });

    await waitFor(() =>
      capturedFrames.some((f) => f.event === 'broadcast' && f.payload?.event === 'TELEMETRY_UPDATE') &&
      capturedFrames.some((f) => f.event === 'presence_state') &&
      capturedFrames.some((f) => f.event === 'postgres_changes' && f.payload?.data?.table === 'devices')
    );

    const bcast = capturedFrames.find((f) => f.event === 'broadcast' && f.payload?.event === 'TELEMETRY_UPDATE').payload.payload;
    const pgUpdate = capturedFrames.find((f) => f.event === 'postgres_changes' && f.payload?.data?.table === 'devices').payload.data.new;

    for (const key of [
      'battery_level',
      'is_charging',
      'screen_brightness',
      'is_auto_brightness',
      'screen_mode',
      'is_screen_on',
      'is_dark_mode',
      'media_volume',
      'ring_volume',
      'notification_volume',
      'alarm_volume',
      'ringer_mode',
      'is_media_muted',
      'current_package_name',
    ]) {
      assert.equal(bcast[key], pgUpdate[key], `Mismatch on ${key} between WS broadcast and DB RPC`);
    }
  });

  // ---- F6: Backend Extended Telemetry Schema & RPCs ----
  it('T1-F6-01: devices table schema includes all 11 extended telemetry columns with defaults', async () => {
    const resp = await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/create_device_pairing`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_name: 'dev-new',
        p_model: 'Pixel 7',
        p_os_version: '14',
        p_agent_version: '1.6.0',
      }),
    });
    assert.equal(resp.status, 200);
    const created = await resp.json();
    const row = env.supabase.tables.devices.get(created[0].device_id);

    assert.ok('screen_brightness' in row);
    assert.equal(row.is_auto_brightness, false);
    assert.equal(row.screen_mode, 'unknown');
    assert.equal(row.is_screen_on, true);
    assert.equal(row.is_dark_mode, false);
    assert.ok('media_volume' in row);
    assert.ok('ring_volume' in row);
    assert.ok('notification_volume' in row);
    assert.ok('alarm_volume' in row);
    assert.equal(row.ringer_mode, 'normal');
    assert.equal(row.is_media_muted, false);
  });

  it('T1-F6-02: update_device_telemetry RPC persists all extended fields and sets status=active', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, status: 'paused' });

    const resp = await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/update_device_telemetry`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_battery_level: 65,
        p_is_charging: false,
        p_current_app: 'Chrome',
        p_agent_version: '1.6.0',
        p_current_package_name: 'com.android.chrome',
        p_screen_brightness: 45,
        p_is_auto_brightness: true,
        p_screen_mode: 'on_unlocked',
        p_is_screen_on: true,
        p_is_dark_mode: true,
        p_media_volume: 30,
        p_ring_volume: 50,
        p_notification_volume: 40,
        p_alarm_volume: 80,
        p_ringer_mode: 'vibrate',
        p_is_media_muted: false,
      }),
    });
    assert.equal(resp.status, 200);
    const json = await resp.json();
    assert.equal(json.success, true);

    const dbRow = env.supabase.tables.devices.get('dev-1');
    assert.equal(dbRow.status, 'active');
    assert.equal(dbRow.battery_level, 65);
    assert.equal(dbRow.current_package_name, 'com.android.chrome');
    assert.equal(dbRow.screen_brightness, 45);
    assert.equal(dbRow.is_auto_brightness, true);
    assert.equal(dbRow.screen_mode, 'on_unlocked');
    assert.equal(dbRow.is_dark_mode, true);
    assert.equal(dbRow.media_volume, 30);
    assert.equal(dbRow.ring_volume, 50);
    assert.equal(dbRow.notification_volume, 40);
    assert.equal(dbRow.alarm_volume, 80);
    assert.equal(dbRow.ringer_mode, 'vibrate');
  });

  it('T1-F6-03: get_family_details RPC returns extended telemetry per child device', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      screen_brightness: 55,
      is_auto_brightness: true,
      screen_mode: 'on_unlocked',
      is_screen_on: true,
      is_dark_mode: true,
      media_volume: 40,
      ring_volume: 70,
      notification_volume: 60,
      alarm_volume: 85,
      ringer_mode: 'normal',
      is_media_muted: false,
      current_package_name: 'com.duolingo',
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    const res = await parent.fetchFamilyDetails(fam.id);
    assert.equal(res.status, 200);
    const d = res.body.devices[0];
    assert.equal(d.screen_brightness, 55);
    assert.equal(d.is_auto_brightness, true);
    assert.equal(d.screen_mode, 'on_unlocked');
    assert.equal(d.is_dark_mode, true);
    assert.equal(d.media_volume, 40);
    assert.equal(d.ring_volume, 70);
    assert.equal(d.notification_volume, 60);
    assert.equal(d.alarm_volume, 85);
    assert.equal(d.ringer_mode, 'normal');
    assert.equal(d.is_media_muted, false);
    assert.equal(d.current_package_name, 'com.duolingo');
  });

  it('T1-F6-04: devices table Realtime UPDATE publishes extended telemetry changes', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    let pgDeviceUpdate = null;
    parent.ws.on('message', (txt) => {
      const m = JSON.parse(txt);
      if (m.event === 'postgres_changes' && m.payload?.data?.table === 'devices') {
        pgDeviceUpdate = m.payload.data.new;
      }
    });

    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/update_device_telemetry`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_screen_brightness: 90,
        p_screen_mode: 'on_locked',
        p_media_volume: 15,
      }),
    });

    await waitFor(() => pgDeviceUpdate !== null);
    assert.equal(pgDeviceUpdate.screen_brightness, 90);
    assert.equal(pgDeviceUpdate.screen_mode, 'on_locked');
    assert.equal(pgDeviceUpdate.media_volume, 15);
  });

  it('T1-F6-05: Overloaded legacy 5-arg update_device_telemetry signature dropped cleanly', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      screen_brightness: 66,
      media_volume: 42,
      ringer_mode: 'vibrate',
    });

    const resp = await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/update_device_telemetry`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_battery_level: 55,
        p_is_charging: true,
        p_current_app: 'Docs',
        p_agent_version: '1.5.4',
      }),
    });
    assert.equal(resp.status, 200);
    const dbRow = env.supabase.tables.devices.get(dev.id);
    assert.equal(dbRow.battery_level, 55);
    assert.equal(dbRow.is_charging, true);
    assert.equal(dbRow.current_app_name, 'Docs');
    // Extended columns intact via COALESCE
    assert.equal(dbRow.screen_brightness, 66);
    assert.equal(dbRow.media_volume, 42);
    assert.equal(dbRow.ringer_mode, 'vibrate');
  });

  // ---- F7: admin-node Extended Telemetry Display ----
  it('T1-F7-01: Parent initial load (getFamilyDevices) parses and renders extended telemetry', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      battery_level: 77,
      screen_brightness: 64,
      is_auto_brightness: true,
      screen_mode: 'on_unlocked',
      is_dark_mode: true,
      media_volume: 55,
      ring_volume: 70,
      notification_volume: 40,
      alarm_volume: 85,
      ringer_mode: 'normal',
      is_media_muted: false,
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    const view = parent.getTelemetryView('dev-1');

    assert.equal(view.batteryText, '77%');
    assert.equal(view.brightnessText, '64%');
    assert.equal(view.isAutoBrightness, true);
    assert.equal(view.screenModeLabel, 'Đang mở khóa');
    assert.equal(view.isDarkMode, true);
    assert.equal(view.mediaVolumeText, '55%');
    assert.equal(view.ringVolumeText, '70%');
    assert.equal(view.notificationVolumeText, '40%');
    assert.equal(view.alarmVolumeText, '85%');
    assert.equal(view.ringerModeLabel, 'Bình thường');
  });

  it('T1-F7-02: Live telemetry updates via Realtime TELEMETRY_UPDATE broadcast', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      screen_brightness: 64,
      media_volume: 55,
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.connectRealtime();
    await child.sendBroadcast('TELEMETRY_UPDATE', {
      device_id: 'dev-1',
      screen_brightness: 20,
      screen_mode: 'off',
      is_screen_on: false,
      media_volume: 0,
      is_media_muted: true,
      ringer_mode: 'silent',
    });

    await waitFor(() => parent.getTelemetryView('dev-1').brightnessText === '20%');
    const view = parent.getTelemetryView('dev-1');
    assert.equal(view.screenModeLabel, 'Tắt màn hình');
    assert.equal(view.mediaVolumeText, '0%');
    assert.equal(view.isMediaMuted, true);
    assert.equal(view.ringerModeLabel, 'Im lặng');
  });

  it('T1-F7-03: Live telemetry updates via Realtime Presence sync', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);

    const child = env.createChildAgent({ deviceId: dev.id });
    await child.connectRealtime();
    await child.trackPresence({
      device_id: 'dev-1',
      status: 'online',
      screen_brightness: 88,
      screen_mode: 'on_locked',
      ring_volume: 0,
      ringer_mode: 'vibrate',
    });

    await waitFor(() => parent.getTelemetryView('dev-1').brightnessText === '88%');
    const view = parent.getTelemetryView('dev-1');
    assert.equal(parent.devices.get('dev-1').isOnline, true);
    assert.equal(view.screenMode, 'on_locked');
    assert.equal(view.ringerMode, 'vibrate');
  });

  it('T1-F7-04: Background/periodic refresh via devices UPDATE & _syncPendingEvents', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    const dev = env.supabase.seedDevice({ id: 'dev-1', family_id: fam.id, is_dark_mode: true });

    const parent = env.createParentClient({ userId: 'parent-1' });
    await parent.loadFamilyDashboard(fam.id);
    parent.disconnectRealtime();

    // Child updates DB while parent was paused/disconnected
    await fetch(`${env.supabase.baseUrl}/rest/v1/rpc/update_device_telemetry`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: env.supabase.anonKey },
      body: JSON.stringify({
        p_device_id: dev.id,
        p_alarm_volume: 95,
        p_notification_volume: 25,
        p_is_dark_mode: false,
      }),
    });

    await parent.syncPendingEvents();
    const view = parent.getTelemetryView('dev-1');
    assert.equal(view.alarmVolumeText, '95%');
    assert.equal(view.notificationVolumeText, '25%');
    assert.equal(view.isDarkMode, false);
  });

  it('T1-F7-05: Family Management Sheet renders extended telemetry from get_family_details', async () => {
    const fam = env.supabase.seedFamily({ id: 'fam-1', created_by: 'parent-1' });
    env.supabase.seedDevice({
      id: 'dev-1',
      family_id: fam.id,
      battery_level: 61,
      screen_brightness: 72,
      screen_mode: 'on_unlocked',
      media_volume: 44,
      ringer_mode: 'normal',
    });

    const parent = env.createParentClient({ userId: 'parent-1' });
    const res = await parent.fetchFamilyDetails(fam.id);
    assert.equal(res.status, 200);
    assert.equal(res.body.devices.length, 1);

    const view = parent.getTelemetryView('dev-1');
    assert.equal(view.batteryText, '61%');
    assert.equal(view.brightnessText, '72%');
    assert.equal(view.screenModeLabel, 'Đang mở khóa');
    assert.equal(view.mediaVolumeText, '44%');
  });
});
