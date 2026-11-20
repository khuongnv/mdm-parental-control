import { connectWebSocket, WS_OPEN } from './rfc6455_ws.mjs';
import { SimFcmServer } from './sim_fcm.mjs';
import { SimSupabaseServer } from './sim_supabase.mjs';

export async function waitFor(predicate, { timeoutMs = 2000, intervalMs = 10, message = 'Condition timed out' } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() <= deadline) {
    const val = await predicate();
    if (val) return val;
    await new Promise((r) => setTimeout(r, intervalMs));
  }
  throw new Error(message);
}

export async function createE2EEnv({
  policiesShape = 'object',
  enablePgNetTriggers = false,
  projectId = 'mdm-parental-control',
} = {}) {
  const fcm = new SimFcmServer({ projectId });
  await fcm.start();
  const supabase = new SimSupabaseServer({
    fcmServer: fcm,
    policiesShape,
    enablePgNetTriggers,
  });
  await supabase.start();

  const clients = [];
  const track = (c) => {
    clients.push(c);
    return c;
  };

  return {
    fcm,
    supabase,
    createChildAgent(opts) {
      return track(
        new TargetNodeAgent({
          supabaseUrl: supabase.baseUrl,
          wsUrl: supabase.wsUrl,
          anonKey: supabase.anonKey,
          ...opts,
        })
      );
    },
    createParentClient({ userId, email, ...opts }) {
      const jwt = supabase.issueToken({ sub: userId, role: 'authenticated', email });
      return track(
        new AdminNodeClient({
          userId,
          jwt,
          supabaseUrl: supabase.baseUrl,
          wsUrl: supabase.wsUrl,
          anonKey: supabase.anonKey,
          fcmServer: fcm,
          ...opts,
        })
      );
    },
    async close() {
      for (const c of clients) {
        if (typeof c.disconnectRealtime === 'function') c.disconnectRealtime();
        if (typeof c._unsubFcm === 'function') c._unsubFcm();
      }
      await supabase.stop();
      await fcm.stop();
    },
  };
}

const IGNORED_SYSTEM_PACKAGES = new Set([
  'com.android.systemui',
  'com.sec.android.app.launcher',
  'com.google.android.apps.nexuslauncher',
  'com.android.launcher',
  'com.android.launcher3',
  'com.miui.home',
  'com.oppo.launcher',
  'com.huawei.android.launcher',
]);

export function clampPct(val) {
  const n = Math.round(Number(val));
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.min(100, n));
}

export function getLocalDateParts(timestampMs, timeZone = 'Asia/Ho_Chi_Minh') {
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  });
  const parts = {};
  for (const p of fmt.formatToParts(new Date(timestampMs))) {
    if (p.type !== 'literal') parts[p.type] = p.value;
  }
  const hour = Number(parts.hour === '24' ? '00' : parts.hour);
  const minute = Number(parts.minute);
  const second = Number(parts.second);
  return {
    dateStr: `${parts.year}-${parts.month}-${parts.day}`,
    hour,
    minute,
    second,
  };
}

export function getNextLocalMidnightMs(timestampMs, timeZone = 'Asia/Ho_Chi_Minh') {
  const { hour, minute, second } = getLocalDateParts(timestampMs, timeZone);
  const msIntoDay = (hour * 3600 + minute * 60 + second) * 1000 + (timestampMs % 1000);
  const remaining = 86400000 - msIntoDay;
  return timestampMs + remaining;
}

export function parseNestedPolicies(deviceRow) {
  if (!deviceRow || deviceRow.policies == null) return null;
  if (Array.isArray(deviceRow.policies)) {
    return deviceRow.policies.length > 0 && typeof deviceRow.policies[0] === 'object'
      ? deviceRow.policies[0]
      : null;
  }
  if (typeof deviceRow.policies === 'object') {
    return deviceRow.policies;
  }
  return null;
}

export class TargetNodeAgent {
  constructor({
    deviceId,
    supabaseUrl,
    wsUrl,
    anonKey,
    timezone = 'Asia/Ho_Chi_Minh',
    agentVersion = '1.6.0',
  }) {
    this.deviceId = deviceId;
    this.supabaseUrl = supabaseUrl;
    this.wsUrl = wsUrl;
    this.anonKey = anonKey;
    this.timezone = timezone;
    this.agentVersion = agentVersion;

    // Persistent storage across service kills/restarts (Room + SharedPreferences)
    this.persistedRoom = new Map(); // `${packageName}|${date}` -> { packageName, appName, category, date, durationMs }
    this.persistedSession = null; // { packageName, appName, category, sessionStartMs }
    this.localLockState = { isLocked: false, extraTimeMinutes: 0 };

    // Volatile runtime state
    this.ws = null;
    this.isServiceRunning = true;
    this.receivedEvents = [];
    this.suspendedPackages = new Set();
    this._joinRefCounter = 0;
  }

  _headers() {
    return {
      'Content-Type': 'application/json',
      apikey: this.anonKey,
      Authorization: `Bearer ${this.anonKey}`,
    };
  }

  async connectRealtime() {
    if (this.ws && this.ws.readyState === WS_OPEN) return;
    this.ws = await connectWebSocket(`${this.wsUrl}?apikey=${encodeURIComponent(this.anonKey)}&vsn=1.0.0`);
    this.ws.on('error', () => {});
    const topic = `realtime:device:${this.deviceId}`;
    const ref = String(++this._joinRefCounter);

    this.ws.on('message', (text) => {
      try {
        const msg = JSON.parse(text);
        const event = msg.event;
        const payload = msg.payload || {};
        this.receivedEvents.push(msg);

        if (event === 'broadcast') {
          const inner = payload.payload || payload;
          const bEvent = payload.event || inner.event;
          if (bEvent === 'TIME_REQUEST_RESOLVED') {
            const status = inner.status;
            const granted = Number(inner.granted_minutes ?? inner.resolved_minutes ?? 0);
            if (status === 'approved') {
              this.localLockState.isLocked = false;
              this.localLockState.extraTimeMinutes += granted;
              this.suspendedPackages.clear();
            }
          } else if (bEvent === 'PANIC_LOCKDOWN') {
            this.localLockState.isLocked = Boolean(inner.is_locked);
          }
        } else if (event === 'postgres_changes') {
          const data = payload.data || {};
          if (data.table === 'time_requests' && data.eventType === 'UPDATE') {
            const rec = data.new || {};
            const granted = Number(rec.resolved_minutes ?? rec.granted_minutes ?? 0);
            if (rec.status === 'approved') {
              this.localLockState.isLocked = false;
              this.localLockState.extraTimeMinutes += granted;
              this.suspendedPackages.clear();
            }
          }
        }
      } catch {
        // Ignore malformed frame
      }
    });

    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('TargetNode WS join timeout')), 3000);
      const onMsg = (text) => {
        const msg = JSON.parse(text);
        if (msg.event === 'phx_reply' && msg.ref === ref) {
          clearTimeout(timeout);
          this.ws.off('message', onMsg);
          resolve();
        }
      };
      this.ws.on('message', onMsg);
      this.ws.send(
        JSON.stringify({
          topic,
          event: 'phx_join',
          ref,
          join_ref: ref,
          payload: {
            config: {
              broadcast: { self: false },
              presence: { key: this.deviceId },
              postgres_changes: [
                { event: 'UPDATE', schema: 'public', table: 'devices', filter: `id=eq.${this.deviceId}` },
                { event: 'INSERT', schema: 'public', table: 'device_messages', filter: `device_id=eq.${this.deviceId}` },
                { event: 'UPDATE', schema: 'public', table: 'time_requests', filter: `device_id=eq.${this.deviceId}` },
              ],
            },
          },
        })
      );
    });
  }

  disconnectRealtime() {
    if (this.ws) {
      this.ws.terminate();
      this.ws = null;
    }
  }

  async sendBroadcast(eventName, dataPayload) {
    if (!this.ws || this.ws.readyState !== WS_OPEN) return false;
    const topic = `realtime:device:${this.deviceId}`;
    const ref = String(++this._joinRefCounter);
    this.ws.send(
      JSON.stringify({
        topic,
        event: 'broadcast',
        ref,
        payload: {
          type: 'broadcast',
          event: eventName,
          payload: dataPayload,
        },
      })
    );
    return true;
  }

  async trackPresence(presencePayload) {
    if (!this.ws || this.ws.readyState !== WS_OPEN) return false;
    const topic = `realtime:device:${this.deviceId}`;
    const ref = String(++this._joinRefCounter);
    this.ws.send(
      JSON.stringify({
        topic,
        event: 'presence',
        ref,
        payload: {
          type: 'track',
          event: 'presence',
          payload: presencePayload,
        },
      })
    );
    return true;
  }

  // ---- Usage Tracking Engine (Room v2 + Persistent Session State Machine) ----
  _accumulateSegment(packageName, appName, category, startMs, endMs) {
    if (!packageName || IGNORED_SYSTEM_PACKAGES.has(packageName)) return;
    if (endMs <= startMs) return;

    let cursor = startMs;
    while (cursor < endMs) {
      const { dateStr } = getLocalDateParts(cursor, this.timezone);
      const nextMidnight = getNextLocalMidnightMs(cursor, this.timezone);
      const segEnd = Math.min(endMs, nextMidnight);
      const deltaMs = segEnd - cursor;
      if (deltaMs > 0) {
        const key = `${packageName}|${dateStr}`;
        const existing = this.persistedRoom.get(key);
        if (existing) {
          existing.durationMs += deltaMs;
          existing.appName = appName || existing.appName;
          existing.category = category || existing.category;
        } else {
          this.persistedRoom.set(key, {
            packageName,
            appName: appName || packageName,
            category: category || 'Other',
            date: dateStr,
            durationMs: deltaMs,
          });
        }
      }
      cursor = segEnd;
    }
  }

  _closeActiveSession(endMs) {
    if (!this.persistedSession) return;
    const sess = this.persistedSession;
    if (endMs <= sess.sessionStartMs) return;
    this.persistedSession = null;
    this._accumulateSegment(sess.packageName, sess.appName, sess.category, sess.sessionStartMs, endMs);
  }

  processUsageEvent({ type, packageName = null, appName = null, category = 'Other', timestampMs }) {
    if (type === 'SCREEN_OFF') {
      this._closeActiveSession(timestampMs);
      return;
    }
    if (type === 'ACTIVITY_RESUMED') {
      if (!packageName || IGNORED_SYSTEM_PACKAGES.has(packageName)) {
        this._closeActiveSession(timestampMs);
        return;
      }
      if (this.persistedSession && this.persistedSession.packageName === packageName) {
        return; // Already tracking this foreground app
      }
      this._closeActiveSession(timestampMs);
      this.persistedSession = {
        packageName,
        appName: appName || packageName,
        category: category || 'Other',
        sessionStartMs: timestampMs,
      };
      return;
    }
    if (type === 'ACTIVITY_PAUSED' || type === 'ACTIVITY_STOPPED') {
      if (this.persistedSession && (!packageName || this.persistedSession.packageName === packageName)) {
        this._closeActiveSession(timestampMs);
      }
    }
  }

  simulateKillAndRestart() {
    this.disconnectRealtime();
    this.isServiceRunning = false;
    this.receivedEvents = [];
    // Note: persistedRoom and persistedSession remain intact on disk!
    this.isServiceRunning = true;
  }

  enforceQuotaIfExceeded(dateStr, dailyLimitMinutes) {
    const summary = this.getLocalDaySummary(dateStr);
    const effectiveLimitSec = Math.max(0, (dailyLimitMinutes + this.localLockState.extraTimeMinutes) * 60);
    if (summary.totalSeconds > effectiveLimitSec) {
      this.localLockState.isLocked = true;
      for (const app of summary.apps) {
        this.suspendedPackages.add(app.package_name);
      }
      return true;
    }
    return false;
  }

  getLocalDaySummary(dateStr) {
    const apps = [];
    let totalSeconds = 0;
    for (const row of this.persistedRoom.values()) {
      if (row.date === dateStr) {
        const sec = Math.floor(row.durationMs / 1000);
        apps.push({
          package_name: row.packageName,
          app_name: row.appName,
          app_category: row.category,
          duration_seconds: sec,
        });
        totalSeconds += sec;
      }
    }
    return {
      usageDate: dateStr,
      totalSeconds: Math.min(86400, totalSeconds),
      apps,
    };
  }

  async syncDailyUsage(dateStr) {
    const summary = this.getLocalDaySummary(dateStr);
    const resp = await fetch(`${this.supabaseUrl}/rest/v1/rpc/sync_device_daily_usage`, {
      method: 'POST',
      headers: this._headers(),
      body: JSON.stringify({
        p_device_id: this.deviceId,
        p_usage_date: summary.usageDate,
        p_total_seconds: summary.totalSeconds,
        p_apps: summary.apps,
        p_timezone: this.timezone,
      }),
    });
    const json = await resp.json();
    return { ok: resp.ok, status: resp.status, body: json, payload: summary };
  }

  // ---- Extended Telemetry Collector ----
  collectTelemetry(rawOs = {}) {
    const brightnessMax = rawOs.brightnessMax ?? 255;
    const rawBrightness = rawOs.brightnessRaw ?? 128;
    const screenBrightness = clampPct((Number(rawBrightness) / Number(brightnessMax)) * 100);

    const normalizeVol = (val, max = 100) => clampPct((Number(val) / Number(max)) * 100);

    let screenMode = 'unknown';
    let isScreenOn = true;
    if (rawOs.isDoze) {
      screenMode = 'doze';
      isScreenOn = false;
    } else if (rawOs.isScreenOn === false) {
      screenMode = 'off';
      isScreenOn = false;
    } else if (rawOs.isKeyguardLocked) {
      screenMode = 'on_locked';
      isScreenOn = true;
    } else if (rawOs.isScreenOn !== undefined) {
      screenMode = 'on_unlocked';
      isScreenOn = true;
    }

    const ringerMode = ['normal', 'vibrate', 'silent'].includes(rawOs.ringerMode)
      ? rawOs.ringerMode
      : 'normal';

    const mediaVol = normalizeVol(rawOs.mediaVolume ?? 50, rawOs.mediaVolumeMax ?? 100);
    const ringVol = normalizeVol(rawOs.ringVolume ?? 50, rawOs.ringVolumeMax ?? 100);
    const notifVol = normalizeVol(rawOs.notificationVolume ?? 50, rawOs.notificationVolumeMax ?? 100);
    const alarmVol = normalizeVol(rawOs.alarmVolume ?? 80, rawOs.alarmVolumeMax ?? 100);
    const isMediaMuted = rawOs.isMediaMuted !== undefined ? Boolean(rawOs.isMediaMuted) : mediaVol === 0;

    return {
      device_id: this.deviceId,
      battery_level: clampPct(rawOs.batteryLevel ?? 100),
      is_charging: Boolean(rawOs.isCharging),
      current_app: rawOs.currentAppName ?? 'Màn hình chính',
      current_app_name: rawOs.currentAppName ?? 'Màn hình chính',
      current_package_name: rawOs.currentPackageName ?? null,
      agent_version: this.agentVersion,
      screen_brightness: screenBrightness,
      is_auto_brightness: Boolean(rawOs.isAutoBrightness),
      screen_mode: screenMode,
      is_screen_on: isScreenOn,
      is_dark_mode: Boolean(rawOs.isDarkMode),
      media_volume: mediaVol,
      ring_volume: ringVol,
      notification_volume: notifVol,
      alarm_volume: alarmVol,
      ringer_mode: ringerMode,
      is_media_muted: isMediaMuted,
      timestamp: new Date().toISOString(),
    };
  }

  async syncTelemetry(rawOs = {}) {
    const snap = this.collectTelemetry(rawOs);
    await this.sendBroadcast('TELEMETRY_UPDATE', snap);
    await this.trackPresence({ status: 'online', ...snap });

    const resp = await fetch(`${this.supabaseUrl}/rest/v1/rpc/update_device_telemetry`, {
      method: 'POST',
      headers: this._headers(),
      body: JSON.stringify({
        p_device_id: this.deviceId,
        p_battery_level: snap.battery_level,
        p_is_charging: snap.is_charging,
        p_current_app: snap.current_app_name,
        p_agent_version: snap.agent_version,
        p_current_package_name: snap.current_package_name,
        p_screen_brightness: snap.screen_brightness,
        p_is_auto_brightness: snap.is_auto_brightness,
        p_screen_mode: snap.screen_mode,
        p_is_screen_on: snap.is_screen_on,
        p_is_dark_mode: snap.is_dark_mode,
        p_media_volume: snap.media_volume,
        p_ring_volume: snap.ring_volume,
        p_notification_volume: snap.notification_volume,
        p_alarm_volume: snap.alarm_volume,
        p_ringer_mode: snap.ringer_mode,
        p_is_media_muted: snap.is_media_muted,
      }),
    });
    const body = await resp.json();
    return { ok: resp.ok, status: resp.status, body, snapshot: snap };
  }

  // ---- Messages & Time Requests ----
  async fetchUnreadMessages() {
    const resp = await fetch(`${this.supabaseUrl}/rest/v1/rpc/get_unread_device_messages`, {
      method: 'POST',
      headers: this._headers(),
      body: JSON.stringify({ p_device_id: this.deviceId }),
    });
    return { ok: resp.ok, status: resp.status, body: await resp.json() };
  }

  async acknowledgeMessage(messageId = null, replyText = null, { invokeEdgeFn = true } = {}) {
    const resp = await fetch(`${this.supabaseUrl}/rest/v1/rpc/acknowledge_device_message`, {
      method: 'POST',
      headers: this._headers(),
      body: JSON.stringify({
        p_device_id: this.deviceId,
        p_message_id: messageId,
        p_reply_text: replyText,
      }),
    });
    const rpcBody = await resp.json();
    if (resp.ok && rpcBody.updated_count > 0) {
      await this.sendBroadcast('ACK_MESSAGE', {
        message_id: rpcBody.id,
        device_id: this.deviceId,
        status: 'acknowledged',
        reply_text: rpcBody.child_reply,
        timestamp: new Date().toISOString(),
      });
      if (invokeEdgeFn) {
        await fetch(`${this.supabaseUrl}/functions/v1/notify-family-parents`, {
          method: 'POST',
          headers: this._headers(),
          body: JSON.stringify({
            device_id: this.deviceId,
            event_type: rpcBody.child_reply ? 'DEVICE_MESSAGE_REPLY' : 'DEVICE_MESSAGE_ACK',
            record_id: rpcBody.id,
            body: rpcBody.child_reply || rpcBody.message_text,
          }),
        });
      }
    }
    return { ok: resp.ok, status: resp.status, body: rpcBody };
  }

  async submitTimeRequest(requestedMinutes, reason = '', { invokeEdgeFn = true, onUiResult = null } = {}) {
    let success = false;
    let body = null;
    let status = 0;

    try {
      const resp = await fetch(`${this.supabaseUrl}/rest/v1/rpc/create_time_request`, {
        method: 'POST',
        headers: this._headers(),
        body: JSON.stringify({
          p_device_id: this.deviceId,
          p_requested_minutes: requestedMinutes,
          p_reason: reason,
        }),
      });
      status = resp.status;
      body = await resp.json();
      success = resp.ok;
    } catch (err) {
      body = { error: err.message };
      success = false;
    }

    if (onUiResult) {
      // Simulate Dispatchers.Main marshaling check
      await new Promise((resolve) => {
        queueMicrotask(() => {
          onUiResult({ success, body, thread: 'main' });
          resolve();
        });
      });
    }

    if (success) {
      await this.sendBroadcast('TIME_REQUEST', {
        request_id: body.id,
        device_id: this.deviceId,
        requested_minutes: body.requested_minutes,
        reason: body.reason,
        timestamp: new Date().toISOString(),
      });
      if (invokeEdgeFn) {
        await fetch(`${this.supabaseUrl}/functions/v1/notify-family-parents`, {
          method: 'POST',
          headers: this._headers(),
          body: JSON.stringify({
            device_id: this.deviceId,
            event_type: 'TIME_REQUEST',
            record_id: body.id,
            data: {
              requested_minutes: body.requested_minutes,
              reason: body.reason,
            },
          }),
        });
      }
    }

    return { ok: success, status, body };
  }
}

export class AdminNodeClient {
  constructor({
    userId,
    jwt,
    supabaseUrl,
    wsUrl,
    anonKey,
    fcmServer = null,
    platform = 'android',
    lifecycleState = 'foreground',
  }) {
    this.userId = userId;
    this.jwt = jwt;
    this.supabaseUrl = supabaseUrl;
    this.wsUrl = wsUrl;
    this.anonKey = anonKey;
    this.fcmServer = fcmServer;
    this.platform = platform;
    this.lifecycleState = lifecycleState; // 'foreground' | 'background' | 'terminated'

    // Persistent storage surviving restart()
    this.persistedDedupKeys = new Set();
    this.fcmToken = null;
    this._unsubFcm = null;

    // UI & Realtime state
    this.ws = null;
    this.activeChannels = new Set();
    this.channelSubscriptionsCount = 0;
    this.devices = new Map(); // deviceId -> device state
    this.policiesByDevice = new Map();
    this.usageByDevice = new Map(); // deviceId -> { date, totalSeconds, apps }
    this.activeDeviceId = null;
    this.activeFamilyId = null;
    this.inAppAlerts = [];
    this.systemNotifications = [];
    this.pendingNotificationsTray = [];
    this.navigationRoute = null;
    this.messageHistory = [];
    this.pendingTimeRequests = [];
    this._refCounter = 0;
  }

  _headers() {
    return {
      'Content-Type': 'application/json',
      apikey: this.anonKey,
      Authorization: `Bearer ${this.jwt}`,
    };
  }

  setLifecycleState(state) {
    this.lifecycleState = state;
    if (state === 'terminated') {
      this.disconnectRealtime();
    }
  }

  async registerPushToken(fcmToken, deviceLabel = null) {
    this.fcmToken = fcmToken;
    const resp = await fetch(`${this.supabaseUrl}/rest/v1/rpc/upsert_parent_push_token`, {
      method: 'POST',
      headers: this._headers(),
      body: JSON.stringify({
        p_fcm_token: fcmToken,
        p_platform: this.platform,
        p_device_label: deviceLabel,
      }),
    });
    if (this._unsubFcm) this._unsubFcm();
    if (this.fcmServer) {
      this._unsubFcm = this.fcmServer.onTokenPush(fcmToken, (msg) => this._handleIncomingFcm(msg));
    }
    return { ok: resp.ok, status: resp.status, body: await resp.json() };
  }

  _recordNotification(dedupKey, notifObj) {
    if (dedupKey && this.persistedDedupKeys.has(dedupKey)) {
      return false;
    }
    if (dedupKey) {
      this.persistedDedupKeys.add(dedupKey);
    }
    if (this.lifecycleState === 'foreground') {
      this.inAppAlerts.push(notifObj);
      this.systemNotifications.push({ ...notifObj, channelId: 'vfam_admin_alerts' });
    } else if (this.lifecycleState === 'background') {
      this.systemNotifications.push({ ...notifObj, channelId: 'vfam_admin_alerts' });
      this.pendingNotificationsTray.push(notifObj);
    } else {
      this.pendingNotificationsTray.push(notifObj);
    }
    return true;
  }

  _handleIncomingFcm(fcmMessage) {
    const data = fcmMessage.data || {};
    const eventType = data.event_type;
    const recordId = data.record_id;
    const deviceId = data.device_id;

    let dedupKey = null;
    if (eventType === 'TIME_REQUEST' && recordId) {
      dedupKey = `time_req_${recordId}`;
    } else if ((eventType === 'DEVICE_MESSAGE_ACK' || eventType === 'DEVICE_MESSAGE_REPLY') && recordId) {
      dedupKey = `ack_msg_${recordId}`;
    }

    const notif = {
      source: 'fcm',
      eventType,
      deviceId,
      recordId,
      title: fcmMessage.notification?.title || '',
      body: fcmMessage.notification?.body || '',
      data,
    };

    if (this.lifecycleState === 'terminated') {
      // OS tray holds it until tapped (getInitialMessage)
      this.pendingNotificationsTray.push({ ...notif, _fcmMessage: fcmMessage, _dedupKey: dedupKey });
      return;
    }

    this._recordNotification(dedupKey, notif);
  }

  async tapNotificationFromTray(recordId = null) {
    const idx = recordId
      ? this.pendingNotificationsTray.findIndex((n) => n.recordId === recordId || n.data?.record_id === recordId)
      : 0;
    if (idx === -1) return null;
    const item = this.pendingNotificationsTray.splice(idx, 1)[0];
    const wasTerminated = this.lifecycleState === 'terminated';
    this.lifecycleState = 'foreground';

    if (item._dedupKey) {
      this.persistedDedupKeys.add(item._dedupKey);
    }
    if (item.deviceId) {
      this.activeDeviceId = item.deviceId;
    }
    if (item.eventType === 'TIME_REQUEST') {
      this.navigationRoute = {
        screen: 'time_request_approval',
        deviceId: item.deviceId,
        requestId: item.recordId,
        via: wasTerminated ? 'getInitialMessage' : 'onMessageOpenedApp',
      };
    } else {
      this.navigationRoute = {
        screen: 'message_history',
        deviceId: item.deviceId,
        messageId: item.recordId,
        via: wasTerminated ? 'getInitialMessage' : 'onMessageOpenedApp',
      };
    }
    return this.navigationRoute;
  }

  async restartAndReconnect(familyId) {
    this.disconnectRealtime();
    this.inAppAlerts = [];
    this.systemNotifications = [];
    // Keep persistedDedupKeys & fcmToken!
    this.lifecycleState = 'foreground';
    if (familyId) {
      await this.loadFamilyDashboard(familyId);
      await this.syncPendingEvents();
    }
  }

  async loadFamilyDashboard(familyId) {
    this.activeFamilyId = familyId;
    // Cleanly tear down existing channels first to prevent channel leaks
    this.disconnectRealtime();

    const resp = await fetch(
      `${this.supabaseUrl}/rest/v1/devices?family_id=eq.${encodeURIComponent(familyId)}&select=*,policies(*)`,
      { method: 'GET', headers: this._headers() }
    );
    const rows = await resp.json();
    this.devices.clear();
    this.policiesByDevice.clear();

    for (const dev of rows) {
      this.devices.set(dev.id, dev);
      const parsedPolicy = parseNestedPolicies(dev);
      this.policiesByDevice.set(dev.id, parsedPolicy);
    }

    if (!this.activeDeviceId || !this.devices.has(this.activeDeviceId)) {
      this.activeDeviceId = rows[0]?.id ?? null;
    }

    // Load exact daily usage for each device using child's today_usage_date
    for (const dev of rows) {
      await this.fetchDeviceUsage(dev.id, dev.today_usage_date);
    }

    await this._subscribeRealtime(familyId, rows.map((d) => d.id));
    return rows;
  }

  async fetchDeviceUsage(deviceId, usageDate = null) {
    const dev = this.devices.get(deviceId);
    const targetDate = usageDate || dev?.today_usage_date || getLocalDateParts(Date.now(), 'Asia/Ho_Chi_Minh').dateStr;

    const sumResp = await fetch(
      `${this.supabaseUrl}/rest/v1/daily_usage_summaries?device_id=eq.${encodeURIComponent(deviceId)}&summary_date=eq.${encodeURIComponent(targetDate)}&limit=1`,
      { method: 'GET', headers: this._headers() }
    );
    const sumRows = await sumResp.json();
    const summary = Array.isArray(sumRows) && sumRows[0] ? sumRows[0] : null;

    const appsResp = await fetch(
      `${this.supabaseUrl}/rest/v1/daily_app_usage?device_id=eq.${encodeURIComponent(deviceId)}&usage_date=eq.${encodeURIComponent(targetDate)}&order=duration_seconds.desc`,
      { method: 'GET', headers: this._headers() }
    );
    const appRows = await appsResp.json();

    const totalSeconds = summary
      ? Number(summary.total_screen_time_seconds ?? summary.total_screen_time_mins * 60)
      : Number(dev?.today_usage_seconds ?? 0);

    const apps = Array.isArray(appRows) && appRows.length > 0
      ? appRows
      : Array.isArray(summary?.app_breakdown)
        ? summary.app_breakdown
        : [];

    this.usageByDevice.set(deviceId, {
      date: targetDate,
      totalSeconds,
      apps,
    });
    return this.usageByDevice.get(deviceId);
  }

  async _subscribeRealtime(familyId, deviceIds) {
    this.ws = await connectWebSocket(`${this.wsUrl}?apikey=${encodeURIComponent(this.jwt)}&vsn=1.0.0`);
    this.ws.on('error', () => {});
    this.ws.on('message', (text) => this._handleRealtimeFrame(text));

    const joinTopic = async (topic, config) => {
      const ref = String(++this._refCounter);
      this.activeChannels.add(topic);
      this.channelSubscriptionsCount++;
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error(`Join timeout ${topic}`)), 3000);
        const onReply = (raw) => {
          const m = JSON.parse(raw);
          if (m.event === 'phx_reply' && m.ref === ref) {
            clearTimeout(timer);
            this.ws?.off('message', onReply);
            resolve();
          }
        };
        this.ws.on('message', onReply);
        this.ws.send(JSON.stringify({ topic, event: 'phx_join', ref, join_ref: ref, payload: { config } }));
      });
    };

    // Family-wide postgres_changes channel across all child devices
    await joinTopic(`realtime:family:${familyId}`, {
      postgres_changes: [
        { event: '*', schema: 'public', table: 'device_messages', filter: `family_id=eq.${familyId}` },
        { event: '*', schema: 'public', table: 'time_requests', filter: `family_id=eq.${familyId}` },
        { event: 'UPDATE', schema: 'public', table: 'devices', filter: `family_id=eq.${familyId}` },
      ],
    });

    // Per-device broadcast, presence, and usage subscriptions
    for (const devId of deviceIds) {
      await joinTopic(`realtime:device:${devId}`, {
        broadcast: { self: false },
        presence: { key: `parent-${this.userId}` },
        postgres_changes: [
          { event: '*', schema: 'public', table: 'daily_usage_summaries', filter: `device_id=eq.${devId}` },
          { event: '*', schema: 'public', table: 'daily_app_usage', filter: `device_id=eq.${devId}` },
        ],
      });
    }
  }

  disconnectRealtime() {
    this.activeChannels.clear();
    if (this.ws) {
      this.ws.terminate();
      this.ws = null;
    }
  }

  _mergeDeviceTelemetry(deviceId, patch) {
    const current = this.devices.get(deviceId) || { id: deviceId };
    const merged = { ...current };
    for (const [k, v] of Object.entries(patch)) {
      if (v !== undefined && v !== null) {
        merged[k] = v;
      }
    }
    this.devices.set(deviceId, merged);
    return merged;
  }

  _handleRealtimeFrame(rawText) {
    let msg;
    try {
      msg = JSON.parse(rawText);
    } catch {
      return;
    }
    const { topic, event, payload } = msg;
    if (!payload) return;

    if (event === 'broadcast') {
      const inner = payload.payload || payload;
      const bEvent = payload.event || inner.event;
      const devId = inner.device_id || (topic.startsWith('realtime:device:') ? topic.slice('realtime:device:'.length) : null);

      if (bEvent === 'TELEMETRY_UPDATE' && devId) {
        this._mergeDeviceTelemetry(devId, inner);
      } else if (bEvent === 'ACK_MESSAGE') {
        const msgId = inner.message_id;
        const dev = devId ? this.devices.get(devId) : null;
        this._recordNotification(`ack_msg_${msgId}`, {
          source: 'ws_broadcast',
          eventType: inner.reply_text ? 'DEVICE_MESSAGE_REPLY' : 'DEVICE_MESSAGE_ACK',
          deviceId: devId,
          deviceName: dev?.custom_name || dev?.device_name || devId,
          recordId: msgId,
          replyText: inner.reply_text || null,
        });
      } else if (bEvent === 'TIME_REQUEST') {
        const reqId = inner.request_id;
        if (reqId) {
          const dev = devId ? this.devices.get(devId) : null;
          this._recordNotification(`time_req_${reqId}`, {
            source: 'ws_broadcast',
            eventType: 'TIME_REQUEST',
            deviceId: devId,
            deviceName: dev?.custom_name || dev?.device_name || devId,
            recordId: reqId,
            requestedMinutes: inner.requested_minutes,
            reason: inner.reason,
          });
        }
      }
    } else if (event === 'presence_state' || event === 'presence_diff') {
      const devId = topic.startsWith('realtime:device:') ? topic.slice('realtime:device:'.length) : null;
      const processEntries = (entries) => {
        for (const [key, val] of Object.entries(entries || {})) {
          const meta = val?.metas?.[0];
          if (meta && !key.startsWith('parent-')) {
            this._mergeDeviceTelemetry(meta.device_id || devId || key, { ...meta, isOnline: true });
          }
        }
      };
      if (event === 'presence_state') processEntries(payload);
      if (event === 'presence_diff') processEntries(payload.joins);
    } else if (event === 'postgres_changes') {
      const data = payload.data || {};
      const table = data.table;
      const rec = data.new || {};
      if (table === 'devices') {
        const prev = this.devices.get(rec.id);
        this._mergeDeviceTelemetry(rec.id, rec);
        const curU = this.usageByDevice.get(rec.id);
        if (rec.today_usage_date && prev && prev.today_usage_date !== rec.today_usage_date) {
          if (!curU || curU.date !== rec.today_usage_date) {
            this.usageByDevice.set(rec.id, {
              date: rec.today_usage_date,
              totalSeconds: Number(rec.today_usage_seconds ?? 0),
              apps: [],
            });
          } else {
            curU.totalSeconds = Number(rec.today_usage_seconds ?? curU.totalSeconds);
          }
        } else if (rec.today_usage_seconds !== undefined && curU) {
          if (!rec.today_usage_date || rec.today_usage_date === curU.date) {
            curU.totalSeconds = Number(rec.today_usage_seconds);
          }
        }
      } else if (table === 'device_messages' && data.eventType === 'UPDATE' && rec.is_acknowledged) {
        this.messageHistory.push(rec);
        const dev = this.devices.get(rec.device_id);
        this._recordNotification(`ack_msg_${rec.id}`, {
          source: 'postgres_changes',
          eventType: rec.child_reply ? 'DEVICE_MESSAGE_REPLY' : 'DEVICE_MESSAGE_ACK',
          deviceId: rec.device_id,
          deviceName: dev?.custom_name || dev?.device_name || rec.device_id,
          recordId: rec.id,
          replyText: rec.child_reply || null,
        });
      } else if (table === 'time_requests' && data.eventType === 'INSERT') {
        this.pendingTimeRequests.push(rec);
        const dev = this.devices.get(rec.device_id);
        this._recordNotification(`time_req_${rec.id}`, {
          source: 'postgres_changes',
          eventType: 'TIME_REQUEST',
          deviceId: rec.device_id,
          deviceName: dev?.custom_name || dev?.device_name || rec.device_id,
          recordId: rec.id,
          requestedMinutes: rec.requested_minutes,
          reason: rec.reason,
        });
      } else if (table === 'daily_usage_summaries') {
        const cur = this.usageByDevice.get(rec.device_id);
        if (!cur || !cur.date || rec.summary_date >= cur.date) {
          this.usageByDevice.set(rec.device_id, {
            date: rec.summary_date,
            totalSeconds: Number(rec.total_screen_time_seconds ?? 0),
            apps: Array.isArray(rec.app_breakdown) ? rec.app_breakdown : [],
          });
        }
      } else if (table === 'daily_app_usage') {
        const cur = this.usageByDevice.get(rec.device_id);
        if (cur && cur.date === rec.usage_date) {
          const idx = cur.apps.findIndex((a) => a.package_name === rec.package_name);
          const entry = {
            package_name: rec.package_name,
            app_name: rec.app_name,
            app_category: rec.app_category,
            duration_seconds: rec.duration_seconds,
          };
          if (idx >= 0) cur.apps[idx] = entry;
          else cur.apps.push(entry);
        }
      }
    }
  }

  async syncPendingEvents() {
    if (!this.activeFamilyId) return;
    const devResp = await fetch(
      `${this.supabaseUrl}/rest/v1/devices?family_id=eq.${encodeURIComponent(this.activeFamilyId)}&select=*,policies(*)`,
      { method: 'GET', headers: this._headers() }
    );
    const devs = await devResp.json();
    for (const d of devs) {
      this._mergeDeviceTelemetry(d.id, d);
      await this.fetchDeviceUsage(d.id, d.today_usage_date);
    }

    const msgResp = await fetch(
      `${this.supabaseUrl}/rest/v1/device_messages?family_id=eq.${encodeURIComponent(this.activeFamilyId)}&is_acknowledged=eq.true&order=acknowledged_at.desc`,
      { method: 'GET', headers: this._headers() }
    );
    const msgs = await msgResp.json();
    if (Array.isArray(msgs)) {
      for (const m of msgs) {
        this._recordNotification(`ack_msg_${m.id}`, {
          source: 'sync_pending',
          eventType: m.child_reply ? 'DEVICE_MESSAGE_REPLY' : 'DEVICE_MESSAGE_ACK',
          deviceId: m.device_id,
          recordId: m.id,
          replyText: m.child_reply || null,
        });
      }
    }

    const reqResp = await fetch(
      `${this.supabaseUrl}/rest/v1/time_requests?family_id=eq.${encodeURIComponent(this.activeFamilyId)}&status=eq.pending`,
      { method: 'GET', headers: this._headers() }
    );
    const reqs = await reqResp.json();
    if (Array.isArray(reqs)) {
      for (const r of reqs) {
        this._recordNotification(`time_req_${r.id}`, {
          source: 'sync_pending',
          eventType: 'TIME_REQUEST',
          deviceId: r.device_id,
          recordId: r.id,
          requestedMinutes: r.requested_minutes,
          reason: r.reason,
        });
      }
    }
  }

  async fetchFamilyDetails(familyId) {
    const resp = await fetch(`${this.supabaseUrl}/rest/v1/rpc/get_family_details`, {
      method: 'POST',
      headers: this._headers(),
      body: JSON.stringify({ p_family_id: familyId }),
    });
    const body = await resp.json();
    if (resp.ok && Array.isArray(body.devices)) {
      for (const d of body.devices) {
        this._mergeDeviceTelemetry(d.id, d);
      }
    }
    return { ok: resp.ok, status: resp.status, body };
  }

  async resolveTimeRequest(requestId, status, grantedMinutes = 0) {
    const resp = await fetch(`${this.supabaseUrl}/rest/v1/rpc/resolve_time_request`, {
      method: 'POST',
      headers: this._headers(),
      body: JSON.stringify({
        p_request_id: requestId,
        p_status: status,
        p_granted_minutes: grantedMinutes,
      }),
    });
    const body = await resp.json();
    return { ok: resp.ok, status: resp.status, body };
  }

  selectDevice(deviceId) {
    this.activeDeviceId = deviceId;
    return this.devices.get(deviceId) || null;
  }

  // ---- View Formatting (R2 & R3 UI Projections) ----
  getTelemetryView(deviceId = this.activeDeviceId) {
    const d = this.devices.get(deviceId);
    if (!d) return null;

    const screenModeLabels = {
      on_unlocked: 'Đang mở khóa',
      on_locked: 'Đang khóa màn hình',
      doze: 'Chế độ nghỉ (Doze)',
      off: 'Tắt màn hình',
      unknown: 'Không rõ',
    };
    const ringerModeLabels = {
      normal: 'Bình thường',
      vibrate: 'Rung',
      silent: 'Im lặng',
    };

    const fmtPct = (v) => (v !== null && v !== undefined ? `${v}%` : '--%');
    const truncatePreview = (s, max = 120) => (s && s.length > max ? `${s.slice(0, max)}…` : s || '');

    return {
      deviceId: d.id,
      batteryText: fmtPct(d.battery_level),
      isCharging: Boolean(d.is_charging),
      brightnessText: fmtPct(d.screen_brightness),
      isAutoBrightness: Boolean(d.is_auto_brightness),
      screenMode: d.screen_mode ?? 'unknown',
      screenModeLabel: screenModeLabels[d.screen_mode ?? 'unknown'] || 'Không rõ',
      isScreenOn: d.is_screen_on ?? true,
      isDarkMode: Boolean(d.is_dark_mode),
      mediaVolumeText: fmtPct(d.media_volume),
      ringVolumeText: fmtPct(d.ring_volume),
      notificationVolumeText: fmtPct(d.notification_volume),
      alarmVolumeText: fmtPct(d.alarm_volume),
      ringerMode: d.ringer_mode ?? 'normal',
      ringerModeLabel: ringerModeLabels[d.ringer_mode ?? 'normal'] || 'Bình thường',
      isMediaMuted: Boolean(d.is_media_muted),
      currentAppName: d.current_app_name || '',
      currentPackageName: d.current_package_name || null,
      formatReplyPreview: (txt) => truncatePreview(txt, 140),
    };
  }

  getUsageView(deviceId = this.activeDeviceId) {
    const d = this.devices.get(deviceId);
    const pol = this.policiesByDevice.get(deviceId);
    const usage = this.usageByDevice.get(deviceId) || { date: null, totalSeconds: 0, apps: [] };

    let baseLimitMins = pol?.daily_screen_time_limit_mins ?? 120;
    if (pol?.rule_type === 'weekly' && pol?.weekday_limits && typeof pol.weekday_limits === 'object') {
      const targetDateStr =
        usage.date || d?.today_usage_date || getLocalDateParts(Date.now(), 'Asia/Ho_Chi_Minh').dateStr;
      if (/^\d{4}-\d{2}-\d{2}$/.test(targetDateStr)) {
        const dayIdx = new Date(`${targetDateStr}T00:00:00Z`).getUTCDay();
        const dayKey = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'][dayIdx];
        if (pol.weekday_limits[dayKey] != null) {
          baseLimitMins = Number(pol.weekday_limits[dayKey]);
        }
      }
    }
    const extraMins = d?.extra_time_minutes ?? 0;
    const totalLimitMins = Math.max(0, baseLimitMins + extraMins);
    const effectiveLimitSeconds = totalLimitMins * 60;
    const usedSeconds = Math.max(0, Number(usage.totalSeconds ?? 0));

    let progressRatio = 0;
    if (effectiveLimitSeconds === 0) {
      progressRatio = usedSeconds > 0 ? 1.0 : 0.0;
    } else {
      progressRatio = Math.min(1.0, Math.max(0.0, usedSeconds / effectiveLimitSeconds));
    }

    const remainingSeconds = Math.max(0, effectiveLimitSeconds - usedSeconds);
    const formatDuration = (sec) => {
      if (sec <= 0) return '0m';
      if (sec < 60) return `${sec} giây`;
      const h = Math.floor(sec / 3600);
      const m = Math.floor((sec % 3600) / 60);
      if (h > 0) return `${h}h ${m}m`;
      return `${m}m`;
    };

    const perAppBreakdown = (usage.apps || []).map((a) => ({
      packageName: a.package_name,
      appName: a.app_name || a.package_name,
      appCategory: a.app_category || 'Other',
      durationSeconds: Number(a.duration_seconds || 0),
      durationLabel: formatDuration(Number(a.duration_seconds || 0)),
    }));

    return {
      deviceId,
      usageDate: usage.date,
      usedSeconds,
      baseLimitMins,
      extraMins,
      totalLimitMins,
      effectiveLimitSeconds,
      remainingSeconds,
      progressRatio,
      isOverLimit: usedSeconds > effectiveLimitSeconds || (effectiveLimitSeconds === 0 && usedSeconds > 0),
      usedText: formatDuration(usedSeconds),
      limitText: formatDuration(effectiveLimitSeconds),
      remainingText: remainingSeconds === 0 ? '0m' : formatDuration(remainingSeconds),
      emptyStateText: usedSeconds === 0 && perAppBreakdown.length === 0 ? 'Chưa có dữ liệu sử dụng hôm nay' : null,
      perAppBreakdown,
      policy: pol
        ? {
            dailyScreenTimeLimitMins: pol.daily_screen_time_limit_mins ?? 120,
            bedtimeStart: pol.bedtime_start ?? null,
            bedtimeEnd: pol.bedtime_end ?? null,
            isBedtimeEnabled: Boolean(pol.is_bedtime_enabled),
            ruleType: pol.rule_type ?? 'daily',
            weekdayLimits: pol.weekday_limits ?? {},
          }
        : {
            dailyScreenTimeLimitMins: 120,
            bedtimeStart: null,
            bedtimeEnd: null,
            isBedtimeEnabled: false,
            ruleType: 'daily',
            weekdayLimits: {},
          },
    };
  }
}
