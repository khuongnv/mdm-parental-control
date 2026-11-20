import http from 'node:http';
import crypto from 'node:crypto';
import { attachWebSocketServer } from './rfc6455_ws.mjs';

const VALID_SCREEN_MODES = new Set(['on_unlocked', 'on_locked', 'doze', 'off', 'unknown']);
const VALID_RINGER_MODES = new Set(['normal', 'vibrate', 'silent']);
const REALTIME_TABLES = new Set([
  'devices',
  'policies',
  'app_rules',
  'pairing_sessions',
  'time_requests',
  'device_messages',
  'family_invites',
  'daily_app_usage',
  'daily_usage_summaries',
]);

function base64UrlEncode(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function base64UrlDecode(str) {
  const padded = str.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((str.length + 3) % 4);
  return Buffer.from(padded, 'base64').toString('utf8');
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8').trim();
      if (!raw) return resolve(null);
      try {
        resolve(JSON.parse(raw));
      } catch (err) {
        reject(err);
      }
    });
    req.on('error', reject);
  });
}

function sendJson(res, status, data, extraHeaders = {}) {
  const text = data === undefined ? '' : JSON.stringify(data);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(text),
    ...extraHeaders,
  });
  res.end(text);
}

function parseFilterValue(raw) {
  if (raw === 'null') return null;
  if (raw === 'true') return true;
  if (raw === 'false') return false;
  return raw;
}

function matchFilterExpr(row, col, expr) {
  if (!row) return false;
  const val = row[col];
  if (expr.startsWith('eq.')) {
    return String(val) === expr.slice(3);
  }
  if (expr.startsWith('neq.')) {
    return String(val) !== expr.slice(4);
  }
  if (expr.startsWith('gte.')) {
    return val != null && String(val) >= expr.slice(4);
  }
  if (expr.startsWith('gt.')) {
    return val != null && String(val) > expr.slice(3);
  }
  if (expr.startsWith('lte.')) {
    return val != null && String(val) <= expr.slice(4);
  }
  if (expr.startsWith('lt.')) {
    return val != null && String(val) < expr.slice(3);
  }
  if (expr.startsWith('is.')) {
    const target = parseFilterValue(expr.slice(3));
    return val === target;
  }
  if (expr.startsWith('in.(') && expr.endsWith(')')) {
    const items = expr.slice(4, -1).split(',').map((s) => s.trim());
    return items.includes(String(val));
  }
  return true;
}

export class SimSupabaseServer {
  constructor({
    fcmServer = null,
    jwtSecret = 'e2e-sim-jwt-secret',
    policiesShape = 'object',
    enablePgNetTriggers = false,
  } = {}) {
    this.fcmServer = fcmServer;
    this.jwtSecret = jwtSecret;
    this.policiesShape = policiesShape;
    this.enablePgNetTriggers = enablePgNetTriggers;

    this.anonKey = this.issueToken({ sub: null, role: 'anon' });
    this.serviceRoleKey = this.issueToken({ sub: null, role: 'service_role' });

    this.server = null;
    this.wsManager = null;
    this.baseUrl = null;
    this.wsUrl = null;

    // Mutex lock map for atomic operations (e.g. fcm_notified_at)
    this._notifiedLock = new Set();

    // Relational tables
    this.tables = {
      families: new Map(),
      family_members: new Map(),
      devices: new Map(),
      policies: new Map(),
      app_rules: new Map(),
      pairing_sessions: new Map(),
      family_invites: new Map(),
      time_requests: new Map(),
      device_messages: new Map(),
      parent_push_tokens: new Map(),
      daily_app_usage: new Map(),
      daily_usage_summaries: new Map(),
    };

    // Realtime connections & channel state
    this.wsSessions = new Map(); // ws -> { user, subscriptions: Map<topic, subConfig> }
    this.presenceState = new Map(); // topic -> Map<presenceKey, metas[]>
    this.pgNetInvocations = [];
  }

  issueToken({ sub = crypto.randomUUID(), role = 'authenticated', email = null } = {}) {
    const header = base64UrlEncode(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
    const payload = base64UrlEncode(
      JSON.stringify({
        sub,
        role,
        email,
        iat: Math.floor(Date.now() / 1000),
        exp: Math.floor(Date.now() / 1000) + 86400,
      })
    );
    const sig = base64UrlEncode(
      crypto.createHmac('sha256', this.jwtSecret).update(`${header}.${payload}`).digest()
    );
    return `${header}.${payload}.${sig}`;
  }

  decodeToken(token) {
    if (!token || typeof token !== 'string') return null;
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const [h, p, s] = parts;
    const expected = base64UrlEncode(
      crypto.createHmac('sha256', this.jwtSecret).update(`${h}.${p}`).digest()
    );
    if (s !== expected) return null;
    try {
      return JSON.parse(base64UrlDecode(p));
    } catch {
      return null;
    }
  }

  _resolveAuth(req, searchParams = null) {
    const authHeader = String(req.headers.authorization || '');
    const apiKeyHeader = String(req.headers.apikey || '');
    const token = authHeader.startsWith('Bearer ')
      ? authHeader.slice(7).trim()
      : apiKeyHeader || searchParams?.get('apikey') || '';
    const claims = this.decodeToken(token);
    if (!claims) {
      return { role: 'anon', userId: null };
    }
    return { role: claims.role || 'anon', userId: claims.sub || null };
  }

  async start() {
    if (this.server) return this.baseUrl;
    this.server = http.createServer((req, res) => {
      this._handleHttp(req, res).catch((err) => {
        sendJson(res, 500, { error: err.message, code: 'INTERNAL_ERROR' });
      });
    });

    this.wsManager = attachWebSocketServer(this.server, {
      path: '/realtime/v1/websocket',
      onConnection: (ws, req, parsedUrl) => this._handleWsConnection(ws, req, parsedUrl),
    });

    await new Promise((resolve) => {
      this.server.listen(0, '127.0.0.1', resolve);
    });
    const addr = this.server.address();
    this.baseUrl = `http://127.0.0.1:${addr.port}`;
    this.wsUrl = `ws://127.0.0.1:${addr.port}/realtime/v1/websocket`;
    return this.baseUrl;
  }

  async stop() {
    if (this.wsManager) {
      this.wsManager.detach();
      this.wsManager = null;
    }
    this.wsSessions.clear();
    if (this.server) {
      const srv = this.server;
      this.server = null;
      await new Promise((resolve) => srv.close(resolve));
    }
  }

  // ---- Seed Helpers (test setup convenience) ----
  seedFamily({ id = crypto.randomUUID(), name = 'Gia đình Mẫu', created_by = crypto.randomUUID() } = {}) {
    const now = new Date().toISOString();
    const row = { id, name, created_by, created_at: now, updated_at: now };
    this.tables.families.set(id, row);
    this.seedFamilyMember({ family_id: id, user_id: created_by, role: 'owner', display_name: 'Phụ huynh' });
    return structuredClone(row);
  }

  seedFamilyMember({
    id = crypto.randomUUID(),
    family_id,
    user_id,
    role = 'parent',
    display_name = 'Phụ huynh',
  }) {
    for (const existing of this.tables.family_members.values()) {
      if (existing.family_id === family_id && existing.user_id === user_id) {
        return structuredClone(existing);
      }
    }
    const row = { id, family_id, user_id, role, display_name, joined_at: new Date().toISOString() };
    this.tables.family_members.set(id, row);
    return structuredClone(row);
  }

  seedDevice({
    id = crypto.randomUUID(),
    family_id = null,
    device_name = 'Child Tablet',
    custom_name = null,
    model = 'Galaxy Tab A9',
    os_version = '14',
    agent_version = '1.6.0',
    fcm_token = null,
    status = family_id ? 'active' : 'pending_pairing',
    is_locked = false,
    extra_time_minutes = 0,
    battery_level = 100,
    is_charging = false,
    current_app_name = 'Màn hình chính',
    current_package_name = null,
    screen_brightness = null,
    is_auto_brightness = false,
    screen_mode = 'unknown',
    is_screen_on = true,
    is_dark_mode = false,
    media_volume = null,
    ring_volume = null,
    notification_volume = null,
    alarm_volume = null,
    ringer_mode = 'normal',
    is_media_muted = false,
    today_usage_seconds = 0,
    today_usage_date = null,
    policy = {},
  } = {}) {
    const now = new Date().toISOString();
    const row = {
      id,
      family_id,
      device_name,
      custom_name,
      model,
      os_version,
      agent_version,
      fcm_token,
      status,
      is_unpaired: false,
      last_seen_at: now,
      created_at: now,
      updated_at: now,
      is_locked,
      extra_time_minutes,
      battery_level,
      is_charging,
      current_app_name,
      current_package_name,
      screen_brightness,
      is_auto_brightness,
      screen_mode,
      is_screen_on,
      is_dark_mode,
      media_volume,
      ring_volume,
      notification_volume,
      alarm_volume,
      ringer_mode,
      is_media_muted,
      today_usage_seconds,
      today_usage_date,
    };
    this.tables.devices.set(id, row);
    if (policy !== null) {
      this.seedPolicy({ device_id: id, ...policy });
    }
    return structuredClone(row);
  }

  seedPolicy({
    id = crypto.randomUUID(),
    device_id,
    daily_screen_time_limit_mins = 120,
    bedtime_start = '22:00:00',
    bedtime_end = '06:00:00',
    is_bedtime_enabled = true,
    emergency_whitelist = [],
    version = 1,
    rule_type = 'daily',
    weekly_screen_time_limit_mins = 840,
    weekday_limits = {},
    auto_reset_hour = 0,
  }) {
    const row = {
      id,
      device_id,
      daily_screen_time_limit_mins,
      bedtime_start,
      bedtime_end,
      is_bedtime_enabled,
      emergency_whitelist,
      version,
      rule_type,
      weekly_screen_time_limit_mins,
      weekday_limits,
      auto_reset_hour,
      updated_at: new Date().toISOString(),
    };
    this.tables.policies.set(id, row);
    return structuredClone(row);
  }

  seedDeviceMessage({
    id = crypto.randomUUID(),
    device_id,
    family_id,
    sender_id = null,
    template_key = 'custom',
    title = 'Thông báo từ phụ huynh',
    message_text,
    is_acknowledged = false,
    acknowledged_at = null,
    child_reply = null,
    fcm_notified_at = null,
    sent_at = new Date().toISOString(),
  }) {
    const row = {
      id,
      device_id,
      family_id,
      sender_id,
      template_key,
      title,
      message_text,
      is_acknowledged,
      acknowledged_at,
      child_reply,
      fcm_notified_at,
      sent_at,
    };
    this.tables.device_messages.set(id, row);
    return structuredClone(row);
  }

  // ---- RLS Helpers ----
  _getUserFamilyIds(userId) {
    const famIds = new Set();
    if (!userId) return famIds;
    for (const f of this.tables.families.values()) {
      if (f.created_by === userId) famIds.add(f.id);
    }
    for (const m of this.tables.family_members.values()) {
      if (m.user_id === userId) famIds.add(m.family_id);
    }
    return famIds;
  }

  _canAccessRow(auth, table, row) {
    if (auth.role === 'service_role') return true;
    if (auth.role === 'authenticated' && auth.userId) {
      const famIds = this._getUserFamilyIds(auth.userId);
      if (table === 'families') return famIds.has(row.id);
      if (table === 'parent_push_tokens') return row.user_id === auth.userId;
      if (table === 'family_members' || table === 'devices' || table === 'device_messages' || table === 'time_requests') {
        return famIds.has(row.family_id);
      }
      if (table === 'policies' || table === 'daily_app_usage' || table === 'daily_usage_summaries') {
        const dev = this.tables.devices.get(row.device_id);
        return Boolean(dev && famIds.has(dev.family_id));
      }
      return true;
    }
    // anon role (Child agent without parent JWT): block parent-private tables
    if (table === 'parent_push_tokens' || table === 'daily_app_usage' || table === 'daily_usage_summaries') {
      return false;
    }
    return true;
  }

  // ---- HTTP Router ----
  async _handleHttp(req, res) {
    const parsed = new URL(req.url || '/', this.baseUrl || 'http://127.0.0.1');
    const pathname = parsed.pathname;
    const auth = this._resolveAuth(req, parsed.searchParams);

    if (pathname.startsWith('/rest/v1/rpc/')) {
      if (req.method !== 'POST') {
        return sendJson(res, 405, { message: 'Method not allowed' });
      }
      const fnName = pathname.slice('/rest/v1/rpc/'.length);
      const body = (await readJsonBody(req)) || {};
      return this._handleRpc(fnName, body, auth, res);
    }

    if (pathname.startsWith('/rest/v1/')) {
      const table = pathname.slice('/rest/v1/'.length);
      if (!this.tables[table]) {
        return sendJson(res, 404, { message: `relation "public.${table}" does not exist`, code: '42P01' });
      }
      return this._handlePostgrest(req, res, table, parsed.searchParams, auth);
    }

    if (pathname === '/functions/v1/notify-family-parents' && req.method === 'POST') {
      const body = (await readJsonBody(req)) || {};
      const result = await this.invokeNotifyFamilyParents(body);
      return sendJson(res, result.status, result.body);
    }

    if (pathname === '/functions/v1/send-fcm-command' && req.method === 'POST') {
      const body = (await readJsonBody(req)) || {};
      const result = await this.invokeSendFcmCommand(body);
      return sendJson(res, result.status, result.body);
    }

    return sendJson(res, 404, { error: 'Not found' });
  }

  async _handlePostgrest(req, res, table, searchParams, auth) {
    const store = this.tables[table];
    const filters = [];
    let orderCol = null;
    let orderAsc = true;
    let limit = null;
    let selectParam = '*';

    for (const [k, v] of searchParams.entries()) {
      if (k === 'select') selectParam = v;
      else if (k === 'order') {
        const [col, dir] = v.split('.');
        orderCol = col;
        orderAsc = dir !== 'desc';
      } else if (k === 'limit') {
        limit = Number(v);
      } else {
        filters.push([k, v]);
      }
    }

    if (req.method === 'GET') {
      let rows = [];
      for (const row of store.values()) {
        if (!this._canAccessRow(auth, table, row)) continue;
        let match = true;
        for (const [col, expr] of filters) {
          if (!Object.prototype.hasOwnProperty.call(row, col) && !(col in row)) {
            return sendJson(res, 400, {
              code: '42703',
              message: `column ${table}.${col} does not exist`,
            });
          }
          if (!matchFilterExpr(row, col, expr)) {
            match = false;
            break;
          }
        }
        if (match) rows.push(structuredClone(row));
      }

      if (orderCol) {
        if (rows.length > 0 && !(orderCol in rows[0])) {
          return sendJson(res, 400, {
            code: '42703',
            message: `column ${table}.${orderCol} does not exist`,
          });
        }
        rows.sort((a, b) => {
          const av = a[orderCol];
          const bv = b[orderCol];
          if (av === bv) return 0;
          if (av == null) return 1;
          if (bv == null) return -1;
          return (av < bv ? -1 : 1) * (orderAsc ? 1 : -1);
        });
      }
      if (limit != null && !Number.isNaN(limit)) {
        rows = rows.slice(0, limit);
      }

      if (table === 'devices' && selectParam.includes('policies(')) {
        for (const dev of rows) {
          const matchedPolicies = [];
          for (const pol of this.tables.policies.values()) {
            if (pol.device_id === dev.id) matchedPolicies.push(structuredClone(pol));
          }
          if (this.policiesShape === 'array') {
            dev.policies = matchedPolicies;
          } else {
            dev.policies = matchedPolicies[0] ?? null;
          }
        }
      }

      return sendJson(res, 200, rows);
    }

    if (req.method === 'POST') {
      const body = await readJsonBody(req);
      const items = Array.isArray(body) ? body : [body];
      const PARENT_ONLY_POST_TABLES = new Set([
        'families',
        'family_members',
        'policies',
        'app_rules',
        'family_invites',
        'parent_push_tokens',
        'daily_app_usage',
        'daily_usage_summaries',
      ]);
      const staged = [];
      for (const item of items) {
        if (!item || typeof item !== 'object') {
          return sendJson(res, 400, { message: 'Invalid insert payload' });
        }
        if (table === 'time_requests' && !item.family_id) {
          return sendJson(res, 400, {
            code: '23502',
            message: 'null value in column "family_id" of relation "time_requests" violates not-null constraint',
          });
        }
        if (table === 'time_requests' && !(item.requested_minutes > 0)) {
          return sendJson(res, 400, {
            code: '23514',
            message: 'new row for relation "time_requests" violates check constraint "time_requests_requested_minutes_check"',
          });
        }
        const id = item.id || crypto.randomUUID();
        const now = new Date().toISOString();
        const row = {
          ...(table === 'device_messages'
            ? {
                sender_id: auth.userId,
                template_key: null,
                title: null,
                is_acknowledged: false,
                acknowledged_at: null,
                child_reply: null,
                fcm_notified_at: null,
                sent_at: now,
              }
            : {}),
          ...(table === 'time_requests'
            ? {
                reason: '',
                status: 'pending',
                resolved_by: null,
                resolved_minutes: 0,
                fcm_notified_at: null,
                created_at: now,
                resolved_at: null,
              }
            : {}),
          ...item,
          id,
        };

        if (auth.role === 'anon' && PARENT_ONLY_POST_TABLES.has(table)) {
          return sendJson(res, 403, {
            code: '42501',
            message: `new row violates row-level security policy for table "${table}"`,
          });
        }
        if (auth.role === 'authenticated') {
          const allowed =
            table === 'families'
              ? Boolean(auth.userId && row.created_by === auth.userId)
              : Boolean(auth.userId && this._canAccessRow(auth, table, row));
          if (!allowed) {
            return sendJson(res, 403, {
              code: '42501',
              message: `new row violates row-level security policy for table "${table}"`,
            });
          }
        } else if (!this._canAccessRow(auth, table, row)) {
          return sendJson(res, 403, {
            code: '42501',
            message: `new row violates row-level security policy for table "${table}"`,
          });
        }
        staged.push([id, row]);
      }

      const inserted = [];
      for (const [id, row] of staged) {
        store.set(id, row);
        inserted.push(structuredClone(row));
        this._emitPostgresChange(table, 'INSERT', row, null);
      }
      const prefer = String(req.headers.prefer || '');
      if (prefer.includes('return=representation')) {
        return sendJson(res, 201, Array.isArray(body) ? inserted : inserted);
      }
      return sendJson(res, 201, inserted);
    }

    if (req.method === 'PATCH') {
      const patch = (await readJsonBody(req)) || {};
      const updated = [];
      for (const [id, row] of store.entries()) {
        if (!this._canAccessRow(auth, table, row)) continue;
        let match = true;
        for (const [col, expr] of filters) {
          if (!matchFilterExpr(row, col, expr)) {
            match = false;
            break;
          }
        }
        if (!match) continue;
        const oldRow = structuredClone(row);
        const newRow = { ...row, ...patch, updated_at: patch.updated_at || new Date().toISOString() };
        store.set(id, newRow);
        updated.push(structuredClone(newRow));
        this._emitPostgresChange(table, 'UPDATE', newRow, oldRow);
      }
      return sendJson(res, 200, updated);
    }

    if (req.method === 'DELETE') {
      const deleted = [];
      for (const [id, row] of [...store.entries()]) {
        if (!this._canAccessRow(auth, table, row)) continue;
        let match = true;
        for (const [col, expr] of filters) {
          if (!matchFilterExpr(row, col, expr)) {
            match = false;
            break;
          }
        }
        if (!match) continue;
        store.delete(id);
        deleted.push(structuredClone(row));
        this._emitPostgresChange(table, 'DELETE', null, row);
      }
      return sendJson(res, 200, deleted);
    }

    return sendJson(res, 405, { message: 'Method not allowed' });
  }

  // ---- RPC Implementations ----
  _handleRpc(fnName, body, auth, res) {
    switch (fnName) {
      case 'create_device_pairing':
        return this._rpcCreateDevicePairing(body, res);
      case 'claim_device_pairing':
        return this._rpcClaimDevicePairing(body, auth, res);
      case 'create_time_request':
        return this._rpcCreateTimeRequest(body, res);
      case 'resolve_time_request':
        return this._rpcResolveTimeRequest(body, auth, res);
      case 'acknowledge_device_message':
        return this._rpcAcknowledgeDeviceMessage(body, res);
      case 'get_unread_device_messages':
        return this._rpcGetUnreadDeviceMessages(body, res);
      case 'upsert_parent_push_token':
        return this._rpcUpsertParentPushToken(body, auth, res);
      case 'update_device_telemetry':
        return this._rpcUpdateDeviceTelemetry(body, res);
      case 'get_family_details':
        return this._rpcGetFamilyDetails(body, auth, res);
      case 'sync_device_daily_usage':
        return this._rpcSyncDeviceDailyUsage(body, res);
      default:
        return sendJson(res, 404, { code: 'PGRST202', message: `Could not find function public.${fnName}` });
    }
  }

  _rpcCreateDevicePairing(body, res) {
    const dev = this.seedDevice({
      device_name: body.p_device_name || 'Child Device',
      model: body.p_model || 'Android',
      os_version: body.p_os_version || '14',
      agent_version: body.p_agent_version || '1.6.0',
      family_id: null,
      status: 'pending_pairing',
    });
    const sessionId = crypto.randomUUID();
    const otp = String(Math.floor(100000 + Math.random() * 900000));
    const qrToken = crypto.randomBytes(16).toString('hex');
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    this.tables.pairing_sessions.set(sessionId, {
      id: sessionId,
      device_id: dev.id,
      otp_code: otp,
      qr_token: qrToken,
      is_claimed: false,
      claimed_by: null,
      claimed_at: null,
      expires_at: expiresAt,
      created_at: new Date().toISOString(),
    });
    return sendJson(res, 200, [{ device_id: dev.id, otp_code: otp, qr_token: qrToken, expires_at: expiresAt }]);
  }

  _rpcClaimDevicePairing(body, auth, res) {
    const { p_otp_code, p_family_id } = body;
    for (const sess of this.tables.pairing_sessions.values()) {
      if (sess.otp_code === p_otp_code && !sess.is_claimed) {
        sess.is_claimed = true;
        sess.claimed_by = auth.userId;
        sess.claimed_at = new Date().toISOString();
        const dev = this.tables.devices.get(sess.device_id);
        if (dev) {
          const oldDev = structuredClone(dev);
          dev.family_id = p_family_id;
          dev.status = 'active';
          dev.updated_at = new Date().toISOString();
          this._emitPostgresChange('devices', 'UPDATE', dev, oldDev);
        }
        return sendJson(res, 200, { success: true, device_id: sess.device_id, family_id: p_family_id });
      }
    }
    return sendJson(res, 400, { message: 'Invalid or expired OTP code' });
  }

  _rpcCreateTimeRequest(body, res) {
    const { p_device_id, p_requested_minutes, p_reason = '' } = body;
    const mins = Number(p_requested_minutes);
    if (!Number.isInteger(mins) || mins <= 0) {
      return sendJson(res, 400, {
        code: '23514',
        message: 'p_requested_minutes must be > 0',
      });
    }
    const dev = this.tables.devices.get(p_device_id);
    if (!dev || !dev.family_id) {
      return sendJson(res, 400, {
        code: 'P0001',
        message: 'Thiết bị chưa được ghép nối vào gia đình',
      });
    }
    const now = new Date().toISOString();
    const row = {
      id: body.p_request_id || crypto.randomUUID(),
      device_id: p_device_id,
      family_id: dev.family_id,
      requested_minutes: mins,
      reason: p_reason == null ? '' : String(p_reason),
      status: 'pending',
      resolved_by: null,
      resolved_minutes: 0,
      fcm_notified_at: null,
      created_at: now,
      resolved_at: null,
    };
    this.tables.time_requests.set(row.id, row);
    this._emitPostgresChange('time_requests', 'INSERT', row, null);

    if (this.enablePgNetTriggers) {
      const triggerPayload = {
        device_id: row.device_id,
        family_id: row.family_id,
        event_type: 'TIME_REQUEST',
        record_id: row.id,
        title: `Yêu cầu thêm ${row.requested_minutes} phút`,
        body: row.reason || `Thiết bị xin thêm ${row.requested_minutes} phút`,
        data: {
          requested_minutes: String(row.requested_minutes),
          reason: row.reason || '',
        },
      };
      this.pgNetInvocations.push(triggerPayload);
      // Asynchronous pg_net dispatch
      queueMicrotask(() => {
        this.invokeNotifyFamilyParents(triggerPayload).catch(() => {});
      });
    }

    return sendJson(res, 200, structuredClone(row));
  }

  _rpcResolveTimeRequest(body, auth, res) {
    const { p_request_id, p_status, p_granted_minutes = 0 } = body;
    const reqRow = this.tables.time_requests.get(p_request_id);
    if (!reqRow) {
      return sendJson(res, 404, { message: 'Time request not found' });
    }
    if (auth.role !== 'service_role') {
      const famIds = this._getUserFamilyIds(auth.userId);
      if (!auth.userId || !famIds.has(reqRow.family_id)) {
        return sendJson(res, 403, { code: '42501', message: 'Permission denied for this family' });
      }
    }
    if (!['approved', 'rejected', 'expired'].includes(p_status)) {
      return sendJson(res, 400, { message: `Invalid status: ${p_status}` });
    }

    const oldReq = structuredClone(reqRow);
    reqRow.status = p_status;
    reqRow.resolved_by = auth.userId;
    reqRow.resolved_minutes = p_status === 'approved' ? Number(p_granted_minutes || 0) : 0;
    reqRow.resolved_at = new Date().toISOString();
    this._emitPostgresChange('time_requests', 'UPDATE', reqRow, oldReq);

    if (p_status === 'approved' && reqRow.resolved_minutes > 0) {
      const dev = this.tables.devices.get(reqRow.device_id);
      if (dev) {
        const oldDev = structuredClone(dev);
        dev.extra_time_minutes = Number(dev.extra_time_minutes || 0) + reqRow.resolved_minutes;
        dev.is_locked = false;
        dev.updated_at = new Date().toISOString();
        this._emitPostgresChange('devices', 'UPDATE', dev, oldDev);
      }
    }

    return sendJson(res, 200, structuredClone(reqRow));
  }

  _rpcAcknowledgeDeviceMessage(body, res) {
    const { p_device_id, p_message_id = null, p_reply_text = null } = body;
    let target = null;
    if (p_message_id) {
      const m = this.tables.device_messages.get(p_message_id);
      if (m && m.device_id === p_device_id) {
        target = m;
      }
    } else {
      const candidates = [];
      for (const m of this.tables.device_messages.values()) {
        if (m.device_id === p_device_id && !m.is_acknowledged) {
          candidates.push(m);
        }
      }
      candidates.sort((a, b) => (a.sent_at > b.sent_at ? -1 : a.sent_at < b.sent_at ? 1 : 0));
      target = candidates[0] || null;
    }

    if (!target || target.is_acknowledged) {
      return sendJson(res, 200, {
        id: target?.id ?? null,
        device_id: p_device_id,
        family_id: target?.family_id ?? null,
        message_text: target?.message_text ?? null,
        child_reply: target?.child_reply ?? null,
        is_acknowledged: target?.is_acknowledged ?? false,
        acknowledged_at: target?.acknowledged_at ?? null,
        updated_count: 0,
      });
    }

    const trimmedReply =
      p_reply_text != null && String(p_reply_text).trim().length > 0 ? String(p_reply_text).trim() : null;

    const oldRow = structuredClone(target);
    target.is_acknowledged = true;
    target.acknowledged_at = new Date().toISOString();
    target.child_reply = trimmedReply;

    this._emitPostgresChange('device_messages', 'UPDATE', target, oldRow);

    if (this.enablePgNetTriggers) {
      const triggerPayload = {
        device_id: target.device_id,
        family_id: target.family_id,
        event_type: trimmedReply ? 'DEVICE_MESSAGE_REPLY' : 'DEVICE_MESSAGE_ACK',
        record_id: target.id,
        title: trimmedReply ? 'Phản hồi từ thiết bị con' : 'Con đã xem tin nhắn',
        body: trimmedReply || target.message_text,
        data: {
          reply_text: trimmedReply || '',
        },
      };
      this.pgNetInvocations.push(triggerPayload);
      queueMicrotask(() => {
        this.invokeNotifyFamilyParents(triggerPayload).catch(() => {});
      });
    }

    return sendJson(res, 200, {
      id: target.id,
      device_id: target.device_id,
      family_id: target.family_id,
      message_text: target.message_text,
      child_reply: target.child_reply,
      is_acknowledged: target.is_acknowledged,
      acknowledged_at: target.acknowledged_at,
      updated_count: 1,
    });
  }

  _rpcGetUnreadDeviceMessages(body, res) {
    const { p_device_id } = body;
    const rows = [];
    for (const m of this.tables.device_messages.values()) {
      if (m.device_id === p_device_id && !m.is_acknowledged) {
        rows.push({
          id: m.id,
          device_id: m.device_id,
          family_id: m.family_id,
          template_key: m.template_key,
          title: m.title,
          message_text: m.message_text,
          sent_at: m.sent_at,
        });
      }
    }
    rows.sort((a, b) => (a.sent_at > b.sent_at ? -1 : a.sent_at < b.sent_at ? 1 : 0));
    return sendJson(res, 200, rows);
  }

  _rpcUpsertParentPushToken(body, auth, res) {
    if (!auth.userId || auth.role === 'anon') {
      return sendJson(res, 401, { message: 'Authentication required for upsert_parent_push_token' });
    }
    const { p_fcm_token, p_platform, p_device_label = null } = body;
    if (!p_fcm_token || !['android', 'ios', 'web'].includes(p_platform)) {
      return sendJson(res, 400, { message: 'Invalid p_fcm_token or p_platform' });
    }

    const now = new Date().toISOString();
    for (const existing of this.tables.parent_push_tokens.values()) {
      if (existing.user_id === auth.userId && existing.fcm_token === p_fcm_token) {
        existing.platform = p_platform;
        existing.device_label = p_device_label;
        existing.updated_at = now;
        return sendJson(res, 200, structuredClone(existing));
      }
    }

    const row = {
      id: crypto.randomUUID(),
      user_id: auth.userId,
      fcm_token: p_fcm_token,
      platform: p_platform,
      device_label: p_device_label,
      updated_at: now,
    };
    this.tables.parent_push_tokens.set(row.id, row);
    return sendJson(res, 200, structuredClone(row));
  }

  _rpcUpdateDeviceTelemetry(body, res) {
    const dev = this.tables.devices.get(body.p_device_id);
    if (!dev) {
      return sendJson(res, 200, {
        success: false,
        device_id: body.p_device_id ?? null,
        message: 'Device not found',
      });
    }

    const clampPctParam = (val) => {
      if (val === undefined || val === null) return null;
      const num = Number(val);
      if (!Number.isFinite(num)) {
        return { invalid: true };
      }
      return Math.min(100, Math.max(0, Math.trunc(num)));
    };

    const clamped = {};
    for (const param of [
      'p_battery_level',
      'p_screen_brightness',
      'p_media_volume',
      'p_ring_volume',
      'p_notification_volume',
      'p_alarm_volume',
    ]) {
      const c = clampPctParam(body[param]);
      if (c && typeof c === 'object' && c.invalid) {
        return sendJson(res, 400, {
          code: '22P02',
          message: `invalid input syntax for type integer: "${body[param]}"`,
        });
      }
      clamped[param] = c;
    }

    let normalizedScreenMode = null;
    if (body.p_screen_mode !== undefined && body.p_screen_mode !== null) {
      const candidate = String(body.p_screen_mode).trim().toLowerCase();
      normalizedScreenMode = VALID_SCREEN_MODES.has(candidate) ? candidate : 'unknown';
    }

    let normalizedRingerMode = null;
    if (body.p_ringer_mode !== undefined && body.p_ringer_mode !== null) {
      const candidate = String(body.p_ringer_mode).trim().toLowerCase();
      normalizedRingerMode = VALID_RINGER_MODES.has(candidate) ? candidate : null;
    }

    const coalesce = (val, current) => (val !== undefined && val !== null ? val : current);
    const nonBlank = (val) => {
      if (val === undefined || val === null) return null;
      const t = String(val).trim();
      return t.length > 0 ? t : null;
    };
    const oldDev = structuredClone(dev);
    const now = new Date().toISOString();

    dev.battery_level = coalesce(clamped.p_battery_level, dev.battery_level);
    dev.is_charging = coalesce(body.p_is_charging, dev.is_charging);
    dev.current_app_name = coalesce(nonBlank(body.p_current_app), dev.current_app_name);
    dev.agent_version = coalesce(nonBlank(body.p_agent_version), dev.agent_version);
    dev.current_package_name = coalesce(nonBlank(body.p_current_package_name), dev.current_package_name);
    dev.screen_brightness = coalesce(clamped.p_screen_brightness, dev.screen_brightness);
    dev.is_auto_brightness = coalesce(body.p_is_auto_brightness, dev.is_auto_brightness);
    dev.screen_mode = coalesce(normalizedScreenMode, dev.screen_mode);
    dev.is_screen_on = coalesce(body.p_is_screen_on, dev.is_screen_on);
    dev.is_dark_mode = coalesce(body.p_is_dark_mode, dev.is_dark_mode);
    dev.media_volume = coalesce(clamped.p_media_volume, dev.media_volume);
    dev.ring_volume = coalesce(clamped.p_ring_volume, dev.ring_volume);
    dev.notification_volume = coalesce(clamped.p_notification_volume, dev.notification_volume);
    dev.alarm_volume = coalesce(clamped.p_alarm_volume, dev.alarm_volume);
    dev.ringer_mode = coalesce(normalizedRingerMode, dev.ringer_mode);
    dev.is_media_muted = coalesce(body.p_is_media_muted, dev.is_media_muted);
    dev.status = dev.status === 'revoked' ? 'revoked' : 'active';
    dev.last_seen_at = now;
    dev.updated_at = now;

    this._emitPostgresChange('devices', 'UPDATE', dev, oldDev);

    return sendJson(res, 200, {
      success: true,
      device_id: dev.id,
      battery_level: dev.battery_level,
      is_charging: dev.is_charging,
      current_app_name: dev.current_app_name,
      current_package_name: dev.current_package_name,
      agent_version: dev.agent_version,
      screen_brightness: dev.screen_brightness,
      is_auto_brightness: dev.is_auto_brightness,
      screen_mode: dev.screen_mode,
      is_screen_on: dev.is_screen_on,
      is_dark_mode: dev.is_dark_mode,
      media_volume: dev.media_volume,
      ring_volume: dev.ring_volume,
      notification_volume: dev.notification_volume,
      alarm_volume: dev.alarm_volume,
      ringer_mode: dev.ringer_mode,
      is_media_muted: dev.is_media_muted,
    });
  }

  _rpcGetFamilyDetails(body, auth, res) {
    const familyId = body.p_family_id;
    const family = this.tables.families.get(familyId);
    if (!family) {
      return sendJson(res, 404, { message: 'Family not found' });
    }
    if (auth.role !== 'service_role') {
      const famIds = this._getUserFamilyIds(auth.userId);
      if (!auth.userId || !famIds.has(familyId)) {
        return sendJson(res, 403, { code: '42501', message: 'Not a member of this family' });
      }
    }

    const members = [];
    for (const m of this.tables.family_members.values()) {
      if (m.family_id === familyId) members.push(structuredClone(m));
    }

    const devices = [];
    for (const d of this.tables.devices.values()) {
      if (d.family_id === familyId) {
        devices.push({
          id: d.id,
          device_name: d.device_name,
          custom_name: d.custom_name,
          model: d.model,
          status: d.status,
          battery_level: d.battery_level,
          is_charging: d.is_charging,
          is_locked: d.is_locked,
          extra_time_minutes: d.extra_time_minutes,
          current_app_name: d.current_app_name,
          current_package_name: d.current_package_name,
          agent_version: d.agent_version,
          screen_brightness: d.screen_brightness,
          is_auto_brightness: d.is_auto_brightness,
          screen_mode: d.screen_mode,
          is_screen_on: d.is_screen_on,
          is_dark_mode: d.is_dark_mode,
          media_volume: d.media_volume,
          ring_volume: d.ring_volume,
          notification_volume: d.notification_volume,
          alarm_volume: d.alarm_volume,
          ringer_mode: d.ringer_mode,
          is_media_muted: d.is_media_muted,
          today_usage_seconds: d.today_usage_seconds,
          today_usage_date: d.today_usage_date,
          last_seen_at: d.last_seen_at,
        });
      }
    }

    return sendJson(res, 200, {
      family: structuredClone(family),
      members,
      devices,
    });
  }

  _rpcSyncDeviceDailyUsage(body, res) {
    const {
      p_device_id,
      p_usage_date,
      p_total_seconds,
      p_apps = [],
      p_timezone = 'Asia/Ho_Chi_Minh',
    } = body;

    const dev = this.tables.devices.get(p_device_id);
    if (!dev) {
      return sendJson(res, 404, { message: 'Device not found' });
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(String(p_usage_date || ''))) {
      return sendJson(res, 400, { message: 'Invalid p_usage_date format (expected YYYY-MM-DD)' });
    }
    const incomingTotal = Math.max(0, Math.floor(Number(p_total_seconds ?? 0)));
    const appsInput = Array.isArray(p_apps) ? p_apps : [];
    const now = new Date().toISOString();

    for (const app of appsInput) {
      if (!app || !app.package_name) continue;
      const incomingSec = Math.max(0, Math.floor(Number(app.duration_seconds || 0)));
      let existingRow = null;
      for (const r of this.tables.daily_app_usage.values()) {
        if (r.device_id === p_device_id && r.usage_date === p_usage_date && r.package_name === app.package_name) {
          existingRow = r;
          break;
        }
      }
      if (existingRow) {
        const oldRow = structuredClone(existingRow);
        existingRow.app_name = app.app_name || existingRow.app_name;
        existingRow.app_category = app.app_category || existingRow.app_category;
        existingRow.duration_seconds = Math.max(existingRow.duration_seconds, incomingSec);
        existingRow.updated_at = now;
        this._emitPostgresChange('daily_app_usage', 'UPDATE', existingRow, oldRow);
      } else {
        const newRow = {
          id: crypto.randomUUID(),
          device_id: p_device_id,
          usage_date: p_usage_date,
          package_name: app.package_name,
          app_name: app.app_name || app.package_name,
          app_category: app.app_category || 'Other',
          duration_seconds: incomingSec,
          updated_at: now,
        };
        this.tables.daily_app_usage.set(newRow.id, newRow);
        this._emitPostgresChange('daily_app_usage', 'INSERT', newRow, null);
      }
    }

    // Gather all rows for (device_id, usage_date)
    const dayApps = [];
    for (const r of this.tables.daily_app_usage.values()) {
      if (r.device_id === p_device_id && r.usage_date === p_usage_date) {
        dayApps.push({
          package_name: r.package_name,
          app_name: r.app_name,
          app_category: r.app_category,
          duration_seconds: r.duration_seconds,
        });
      }
    }
    dayApps.sort((a, b) => b.duration_seconds - a.duration_seconds);

    const sumAppsSeconds = dayApps.reduce((acc, a) => acc + a.duration_seconds, 0);
    const categoryBreakdown = {};
    for (const a of dayApps) {
      const cat = a.app_category || 'Other';
      categoryBreakdown[cat] = (categoryBreakdown[cat] || 0) + a.duration_seconds;
    }

    let summaryRow = null;
    for (const s of this.tables.daily_usage_summaries.values()) {
      if (s.device_id === p_device_id && s.summary_date === p_usage_date) {
        summaryRow = s;
        break;
      }
    }

    const prevSummarySeconds = summaryRow ? summaryRow.total_screen_time_seconds : 0;
    const finalTotalSeconds = Math.min(86400, Math.max(prevSummarySeconds, incomingTotal, sumAppsSeconds));
    const finalTotalMins = Math.floor(finalTotalSeconds / 60);
    const topApps = dayApps.slice(0, 5);

    if (summaryRow) {
      const oldSummary = structuredClone(summaryRow);
      summaryRow.total_screen_time_seconds = finalTotalSeconds;
      summaryRow.total_screen_time_mins = finalTotalMins;
      summaryRow.app_breakdown = dayApps;
      summaryRow.top_apps = topApps;
      summaryRow.category_breakdown = categoryBreakdown;
      summaryRow.local_timezone = p_timezone || summaryRow.local_timezone || 'Asia/Ho_Chi_Minh';
      summaryRow.updated_at = now;
      this._emitPostgresChange('daily_usage_summaries', 'UPDATE', summaryRow, oldSummary);
    } else {
      summaryRow = {
        id: crypto.randomUUID(),
        device_id: p_device_id,
        summary_date: p_usage_date,
        total_screen_time_seconds: finalTotalSeconds,
        total_screen_time_mins: finalTotalMins,
        app_breakdown: dayApps,
        top_apps: topApps,
        category_breakdown: categoryBreakdown,
        local_timezone: p_timezone || 'Asia/Ho_Chi_Minh',
        updated_at: now,
      };
      this.tables.daily_usage_summaries.set(summaryRow.id, summaryRow);
      this._emitPostgresChange('daily_usage_summaries', 'INSERT', summaryRow, null);
    }

    // Preserve today's counter when syncing historical dates
    if (!dev.today_usage_date || p_usage_date >= dev.today_usage_date) {
      const oldDev = structuredClone(dev);
      dev.today_usage_date = p_usage_date;
      dev.today_usage_seconds = finalTotalSeconds;
      dev.updated_at = now;
      this._emitPostgresChange('devices', 'UPDATE', dev, oldDev);
    }

    return sendJson(res, 200, {
      success: true,
      device_id: p_device_id,
      usage_date: p_usage_date,
      total_screen_time_seconds: finalTotalSeconds,
      total_screen_time_mins: finalTotalMins,
      app_count: dayApps.length,
      local_timezone: summaryRow.local_timezone,
    });
  }

  // ---- Edge Functions ----
  async _getFcmAccessToken() {
    if (!this.fcmServer) return null;
    const assertion = this.issueToken({ sub: 'supabase-edge-fn', role: 'service_role' });
    const resp = await fetch(`${this.fcmServer.baseUrl}/oauth2/v4/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }).toString(),
    });
    if (!resp.ok) {
      throw new Error(`OAuth2 token exchange failed: ${resp.status}`);
    }
    const json = await resp.json();
    return json.access_token;
  }

  async invokeNotifyFamilyParents(body) {
    const { device_id, family_id = null, event_type, record_id = null, title, body: bodyText, data = {} } = body || {};
    if (!device_id || !event_type) {
      return { status: 400, body: { success: false, error: 'device_id and event_type are required' } };
    }

    const dev = this.tables.devices.get(device_id);
    if (!dev || !dev.family_id) {
      return { status: 404, body: { success: false, error: 'Device not found or not paired to a family' } };
    }

    // Authoritative family_id from devices table (reject mismatched/spoofed family_id per M1)
    const authoritativeFamilyId = dev.family_id;
    const suppliedFamilyId = family_id !== undefined && family_id !== null ? String(family_id).trim() : '';
    if (suppliedFamilyId && suppliedFamilyId !== authoritativeFamilyId) {
      return {
        status: 403,
        body: { success: false, error: 'family_id does not match paired device' },
      };
    }

    // Atomic idempotency check via fcm_notified_at
    if (record_id) {
      const lockKey = `${event_type}:${record_id}`;
      if (this._notifiedLock.has(lockKey)) {
        return {
          status: 200,
          body: {
            success: true,
            sent: 0,
            failed: 0,
            stale_tokens_removed: 0,
            deduplicated: true,
            skipped: true,
            record_id,
            event_type,
          },
        };
      }
      this._notifiedLock.add(lockKey);
      try {
        if (event_type === 'TIME_REQUEST') {
          const reqRow = this.tables.time_requests.get(record_id);
          if (!reqRow || reqRow.device_id !== device_id || reqRow.family_id !== authoritativeFamilyId) {
            return {
              status: 200,
              body: {
                success: true,
                sent: 0,
                failed: 0,
                stale_tokens_removed: 0,
                deduplicated: false,
                skipped: true,
                reason: 'record_not_found',
                record_id,
                event_type,
              },
            };
          }
          if (reqRow.fcm_notified_at !== null) {
            return {
              status: 200,
              body: {
                success: true,
                sent: 0,
                failed: 0,
                stale_tokens_removed: 0,
                deduplicated: true,
                skipped: true,
                record_id,
                event_type,
              },
            };
          }
          reqRow.fcm_notified_at = new Date().toISOString();
        } else if (event_type === 'DEVICE_MESSAGE_ACK' || event_type === 'DEVICE_MESSAGE_REPLY') {
          const msgRow = this.tables.device_messages.get(record_id);
          if (!msgRow || msgRow.device_id !== device_id || msgRow.family_id !== authoritativeFamilyId) {
            return {
              status: 200,
              body: {
                success: true,
                sent: 0,
                failed: 0,
                stale_tokens_removed: 0,
                deduplicated: false,
                skipped: true,
                reason: 'record_not_found',
                record_id,
                event_type,
              },
            };
          }
          if (msgRow.fcm_notified_at !== null) {
            return {
              status: 200,
              body: {
                success: true,
                sent: 0,
                failed: 0,
                stale_tokens_removed: 0,
                deduplicated: true,
                skipped: true,
                record_id,
                event_type,
              },
            };
          }
          msgRow.fcm_notified_at = new Date().toISOString();
        }
      } finally {
        this._notifiedLock.delete(lockKey);
      }
    }

    // Collect family parents: family_members UNION families.created_by
    const parentUserIds = new Set();
    const family = this.tables.families.get(authoritativeFamilyId);
    if (family?.created_by) parentUserIds.add(family.created_by);
    for (const m of this.tables.family_members.values()) {
      if (m.family_id === authoritativeFamilyId) parentUserIds.add(m.user_id);
    }

    const tokensMap = new Map(); // fcm_token -> tokenRow
    for (const t of this.tables.parent_push_tokens.values()) {
      if (parentUserIds.has(t.user_id) && !tokensMap.has(t.fcm_token)) {
        tokensMap.set(t.fcm_token, t);
      }
    }

    if (tokensMap.size === 0) {
      return {
        status: 200,
        body: {
          success: true,
          sent: 0,
          failed: 0,
          stale_tokens_removed: 0,
          deduplicated: false,
          skipped: true,
          reason: 'no_push_tokens',
        },
      };
    }

    const deviceLabel = dev.custom_name || dev.device_name || 'Thiết bị con';
    let resolvedTitle = title;
    let resolvedBody = bodyText;
    const stringData = {
      event_type: String(event_type),
      device_id: String(device_id),
      family_id: String(authoritativeFamilyId),
      device_name: String(deviceLabel),
    };
    if (record_id) stringData.record_id = String(record_id);

    if (event_type === 'TIME_REQUEST' && record_id) {
      const reqRow = this.tables.time_requests.get(record_id);
      if (reqRow) {
        if (!resolvedTitle) resolvedTitle = `${deviceLabel} xin thêm ${reqRow.requested_minutes} phút`;
        if (!resolvedBody) resolvedBody = reqRow.reason || `Xin thêm ${reqRow.requested_minutes} phút sử dụng`;
        stringData.requested_minutes = String(reqRow.requested_minutes);
        stringData.reason = String(reqRow.reason || '');
      }
    } else if ((event_type === 'DEVICE_MESSAGE_ACK' || event_type === 'DEVICE_MESSAGE_REPLY') && record_id) {
      const msgRow = this.tables.device_messages.get(record_id);
      if (msgRow) {
        if (!resolvedTitle) {
          resolvedTitle = msgRow.child_reply
            ? `${deviceLabel} đã phản hồi tin nhắn`
            : `${deviceLabel} đã xác nhận tin nhắn`;
        }
        if (!resolvedBody) {
          resolvedBody = msgRow.child_reply || msgRow.message_text || 'Đã xác nhận đã đọc';
        }
        if (msgRow.child_reply) stringData.reply_text = String(msgRow.child_reply);
      }
    }

    if (!resolvedTitle) resolvedTitle = `Thông báo từ ${deviceLabel}`;
    if (!resolvedBody) resolvedBody = event_type;

    if (data && typeof data === 'object') {
      for (const [k, v] of Object.entries(data)) {
        if (v !== undefined && v !== null) {
          stringData[k] = String(v);
        }
      }
    }

    const accessToken = await this._getFcmAccessToken();
    let sentCount = 0;
    let failedCount = 0;
    let cleanedTokens = 0;

    for (const tokenRow of tokensMap.values()) {
      const fcmMessage = {
        token: tokenRow.fcm_token,
        notification: {
          title: String(resolvedTitle),
          body: String(resolvedBody),
        },
        data: stringData,
      };

      if (tokenRow.platform === 'ios') {
        fcmMessage.apns = {
          headers: {
            'apns-priority': '10',
            'apns-push-type': 'alert',
          },
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
              'content-available': 1,
            },
          },
        };
      } else {
        fcmMessage.android = {
          priority: 'HIGH',
          notification: {
            channel_id: 'vfam_admin_alerts',
            sound: 'default',
          },
        };
      }

      const fcmResp = await fetch(
        `${this.fcmServer.baseUrl}/v1/projects/${this.fcmServer.projectId}/messages:send`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify({ message: fcmMessage }),
        }
      );

      if (fcmResp.ok) {
        sentCount++;
      } else {
        failedCount++;
        if (fcmResp.status === 404 || fcmResp.status === 410) {
          for (const [tid, trow] of [...this.tables.parent_push_tokens.entries()]) {
            if (trow.fcm_token === tokenRow.fcm_token) {
              this.tables.parent_push_tokens.delete(tid);
              cleanedTokens++;
            }
          }
        }
      }
    }

    return {
      status: 200,
      body: {
        success: true,
        event_type,
        device_id,
        family_id: authoritativeFamilyId,
        record_id: record_id || null,
        total_tokens: tokensMap.size,
        sent: sentCount,
        failed: failedCount,
        stale_tokens_removed: cleanedTokens,
        deduplicated: false,
      },
    };
  }

  async invokeSendFcmCommand(body) {
    const { device_id, action, ...rest } = body || {};
    const dev = this.tables.devices.get(device_id);
    if (!dev || !dev.fcm_token) {
      return { status: 404, body: { error: 'Device or device fcm_token not found' } };
    }
    const accessToken = await this._getFcmAccessToken();
    const stringData = { action: String(action || ''), device_id: String(device_id) };
    for (const [k, v] of Object.entries(rest)) {
      if (v !== undefined && v !== null) stringData[k] = String(v);
    }
    const resp = await fetch(
      `${this.fcmServer.baseUrl}/v1/projects/${this.fcmServer.projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token: dev.fcm_token,
            data: stringData,
            android: { priority: 'HIGH', direct_boot_ok: true },
          },
        }),
      }
    );
    return { status: resp.ok ? 200 : resp.status, body: await resp.json() };
  }

  // ---- Phoenix Realtime WebSocket ----
  _handleWsConnection(ws, _req, parsedUrl) {
    ws.on('error', () => {});
    const token = parsedUrl.searchParams.get('apikey') || '';
    const claims = this.decodeToken(token);
    const user = claims ? { role: claims.role || 'anon', userId: claims.sub || null } : { role: 'anon', userId: null };
    const session = { ws, user, subscriptions: new Map() };
    this.wsSessions.set(ws, session);

    ws.on('message', (rawText) => {
      let parsed;
      try {
        parsed = JSON.parse(rawText);
      } catch {
        return;
      }
      const isArrayFormat = Array.isArray(parsed);
      const joinRef = isArrayFormat ? parsed[0] : parsed.join_ref ?? null;
      const ref = isArrayFormat ? parsed[1] : parsed.ref ?? null;
      const topic = isArrayFormat ? parsed[2] : parsed.topic;
      const event = isArrayFormat ? parsed[3] : parsed.event;
      const payload = isArrayFormat ? parsed[4] || {} : parsed.payload || {};

      const reply = (status, response = {}) => {
        const msg = isArrayFormat
          ? [joinRef, ref, topic, 'phx_reply', { status, response }]
          : { topic, event: 'phx_reply', payload: { status, response }, ref, join_ref: joinRef };
        if (ws.readyState === 1) ws.send(JSON.stringify(msg));
      };

      if (event === 'heartbeat' && topic === 'phoenix') {
        return reply('ok', {});
      }

      if (event === 'phx_join') {
        const config = payload.config || {};
        session.subscriptions.set(topic, {
          isArrayFormat,
          joinRef,
          config,
          presenceKey: config.presence?.key || null,
        });
        const pgChanges = Array.isArray(config.postgres_changes)
          ? config.postgres_changes.map((c, idx) => ({ id: idx + 1, ...c }))
          : [];
        reply('ok', { postgres_changes: pgChanges });

        // Send initial presence_state if topic has presence entries
        const presMap = this.presenceState.get(topic);
        if (presMap && presMap.size > 0) {
          const stateObj = {};
          for (const [k, metas] of presMap.entries()) {
            stateObj[k] = { metas };
          }
          this._sendToWs(ws, isArrayFormat, topic, 'presence_state', stateObj);
        }
        return;
      }

      if (event === 'phx_leave') {
        this._cleanupPresenceForSession(session, topic);
        session.subscriptions.delete(topic);
        return reply('ok', {});
      }

      if (event === 'broadcast') {
        const bEvent = payload.event || payload.payload?.event;
        const bPayload = payload.payload || payload;
        const selfAllowed = Boolean(session.subscriptions.get(topic)?.config?.broadcast?.self);
        for (const [otherWs, otherSess] of this.wsSessions.entries()) {
          if (!otherSess.subscriptions.has(topic)) continue;
          if (otherWs === ws && !selfAllowed) continue;
          const fmt = otherSess.subscriptions.get(topic).isArrayFormat;
          this._sendToWs(otherWs, fmt, topic, 'broadcast', {
            type: 'broadcast',
            event: bEvent,
            payload: bPayload,
          });
        }
        return reply('ok', {});
      }

      if (event === 'presence') {
        const sub = session.subscriptions.get(topic);
        const key = payload.key || sub?.presenceKey || session.user.userId || 'anon';
        if (!this.presenceState.has(topic)) this.presenceState.set(topic, new Map());
        const presMap = this.presenceState.get(topic);

        if (payload.type === 'track') {
          const meta = { ...(payload.payload || {}), phx_ref: crypto.randomBytes(4).toString('hex') };
          const prev = presMap.get(key) || [];
          presMap.set(key, [meta]);
          this._broadcastPresenceDiff(topic, {
            joins: { [key]: { metas: [meta] } },
            leaves: prev.length ? { [key]: { metas: prev } } : {},
          });
        } else if (payload.type === 'untrack') {
          const prev = presMap.get(key) || [];
          presMap.delete(key);
          if (prev.length) {
            this._broadcastPresenceDiff(topic, {
              joins: {},
              leaves: { [key]: { metas: prev } },
            });
          }
        }
        return reply('ok', {});
      }
    });

    ws.on('close', () => {
      for (const topic of session.subscriptions.keys()) {
        this._cleanupPresenceForSession(session, topic);
      }
      this.wsSessions.delete(ws);
    });
  }

  _cleanupPresenceForSession(session, topic) {
    const sub = session.subscriptions.get(topic);
    const key = sub?.presenceKey;
    if (!key) return;
    const presMap = this.presenceState.get(topic);
    if (presMap && presMap.has(key)) {
      const prev = presMap.get(key);
      presMap.delete(key);
      this._broadcastPresenceDiff(topic, {
        joins: {},
        leaves: { [key]: { metas: prev } },
      });
    }
  }

  _broadcastPresenceDiff(topic, diff) {
    const presMap = this.presenceState.get(topic);
    const fullState = {};
    if (presMap) {
      for (const [k, metas] of presMap.entries()) {
        fullState[k] = { metas };
      }
    }
    for (const [otherWs, otherSess] of this.wsSessions.entries()) {
      const sub = otherSess.subscriptions.get(topic);
      if (!sub) continue;
      this._sendToWs(otherWs, sub.isArrayFormat, topic, 'presence_diff', diff);
      this._sendToWs(otherWs, sub.isArrayFormat, topic, 'presence_state', fullState);
    }
  }

  _sendToWs(ws, isArrayFormat, topic, event, payload) {
    if (ws.readyState !== 1) return;
    const msg = isArrayFormat ? [null, null, topic, event, payload] : { topic, event, payload, ref: null };
    ws.send(JSON.stringify(msg));
  }

  _emitPostgresChange(table, eventType, newRow, oldRow) {
    if (!REALTIME_TABLES.has(table)) return;
    const commitTimestamp = new Date().toISOString();
    const recordClone = newRow ? structuredClone(newRow) : {};
    const oldClone = oldRow ? structuredClone(oldRow) : {};

    for (const [ws, sess] of this.wsSessions.entries()) {
      if (ws.readyState !== 1) continue;
      const targetRow = eventType === 'DELETE' ? oldRow : newRow;
      if (!this._canAccessRow(sess.user, table, targetRow)) continue;

      for (const [topic, sub] of sess.subscriptions.entries()) {
        const filters = sub.config?.postgres_changes || [];
        for (const subFilter of filters) {
          const schema = subFilter.schema || 'public';
          if (schema !== 'public' || subFilter.table !== table) continue;
          const wantEvent = String(subFilter.event || '*').toUpperCase();
          if (wantEvent !== '*' && wantEvent !== eventType) continue;

          if (subFilter.filter) {
            const eqIdx = subFilter.filter.indexOf('=');
            if (eqIdx > 0) {
              const col = subFilter.filter.slice(0, eqIdx);
              const expr = subFilter.filter.slice(eqIdx + 1);
              // REPLICA IDENTITY FULL ensures oldRow + newRow both have all columns
              const matchesNew = newRow ? matchFilterExpr(newRow, col, expr) : false;
              const matchesOld = oldRow ? matchFilterExpr(oldRow, col, expr) : false;
              if (!matchesNew && !matchesOld) continue;
            }
          }

          this._sendToWs(ws, sub.isArrayFormat, topic, 'postgres_changes', {
            data: {
              schema: 'public',
              table,
              commit_timestamp: commitTimestamp,
              eventType,
              new: recordClone,
              old: oldClone,
              errors: null,
            },
          });
        }
      }
    }
  }
}
