import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..", "..");

const migrationPath = path.join(
  repoRoot,
  "backend",
  "supabase",
  "migrations",
  "20261120_notifications_telemetry_usage_sync.sql"
);
const fcmSharedPath = path.join(
  repoRoot,
  "backend",
  "supabase",
  "functions",
  "_shared",
  "fcm.mjs"
);
const notifySharedPath = path.join(
  repoRoot,
  "backend",
  "supabase",
  "functions",
  "_shared",
  "notify_parents.mjs"
);
const notifyEntryPath = path.join(
  repoRoot,
  "backend",
  "supabase",
  "functions",
  "notify-family-parents",
  "index.ts"
);
const sendCmdEntryPath = path.join(
  repoRoot,
  "backend",
  "supabase",
  "functions",
  "send-fcm-command",
  "index.ts"
);

const sql = fs.readFileSync(migrationPath, "utf8");

function extractFunctionBlock(fullSql, fnName) {
  const escaped = fnName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const regex = new RegExp(
    `CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\.${escaped}\\b[\\s\\S]*?\\$\\$\\s*LANGUAGE\\s+plpgsql[^;]*;`,
    "i"
  );
  const match = fullSql.match(regex);
  assert.ok(match, `Expected function public.${fnName} to exist in migration`);
  return match[0];
}

test("R1: device_messages and time_requests columns and REPLICA IDENTITY FULL", () => {
  assert.match(
    sql,
    /ALTER\s+TABLE\s+public\.device_messages[\s\S]*?ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+title\s+TEXT\s+DEFAULT\s+'Lời nhắc từ Ba Mẹ'/i
  );
  assert.match(
    sql,
    /ALTER\s+TABLE\s+public\.device_messages[\s\S]*?ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+child_reply\s+TEXT/i
  );
  assert.match(
    sql,
    /ALTER\s+TABLE\s+public\.device_messages[\s\S]*?ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+fcm_notified_at\s+TIMESTAMPTZ/i
  );
  assert.match(
    sql,
    /ALTER\s+TABLE\s+public\.time_requests[\s\S]*?ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+fcm_notified_at\s+TIMESTAMPTZ/i
  );

  for (const tbl of [
    "device_messages",
    "time_requests",
    "devices",
    "daily_app_usage",
    "daily_usage_summaries",
  ]) {
    assert.match(
      sql,
      new RegExp(`ALTER\\s+TABLE\\s+public\\.${tbl}\\s+REPLICA\\s+IDENTITY\\s+FULL\\s*;`, "i"),
      `Expected REPLICA IDENTITY FULL on public.${tbl}`
    );
  }
});

test("R1: parent_push_tokens table, RLS, and upsert_parent_push_token RPC", () => {
  assert.match(
    sql,
    /CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+public\.parent_push_tokens[\s\S]*?user_id\s+UUID\s+NOT\s+NULL\s+REFERENCES\s+auth\.users\(id\)\s+ON\s+DELETE\s+CASCADE[\s\S]*?platform\s+TEXT\s+NOT\s+NULL\s+CHECK\s*\(\s*platform\s+IN\s*\(\s*'android'\s*,\s*'ios'\s*\)\s*\)[\s\S]*?UNIQUE\s*\(\s*user_id\s*,\s*fcm_token\s*\)/i
  );
  assert.match(
    sql,
    /ALTER\s+TABLE\s+public\.parent_push_tokens\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY\s*;/i
  );
  assert.match(
    sql,
    /CREATE\s+POLICY\s+"Parents can manage own push tokens"\s+ON\s+public\.parent_push_tokens[\s\S]*?USING\s*\(\s*user_id\s*=\s*auth\.uid\(\)\s*\)[\s\S]*?WITH\s+CHECK\s*\(\s*user_id\s*=\s*auth\.uid\(\)\s*\)/i
  );
  assert.match(
    sql,
    /GRANT\s+ALL\s+ON\s+public\.parent_push_tokens\s+TO\s+authenticated\s*,\s*service_role\s*;/i
  );

  const upsertFn = extractFunctionBlock(sql, "upsert_parent_push_token");
  assert.match(upsertFn, /SECURITY\s+DEFINER/i);
  assert.match(upsertFn, /auth\.uid\(\)/i);
  assert.match(upsertFn, /DELETE\s+FROM\s+public\.parent_push_tokens[\s\S]*?user_id\s*<>\s*v_user_id/i);
  assert.match(
    sql,
    /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.upsert_parent_push_token\(TEXT,\s*TEXT,\s*TEXT\)\s+TO\s+authenticated\s*,\s*service_role\s*;/i
  );
});

test("R1: create_time_request, acknowledge_device_message, and get_unread_device_messages RPCs", () => {
  assert.match(
    sql,
    /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.create_time_request\(UUID,\s*INT,\s*TEXT\)\s*;/i
  );
  const createReqFn = extractFunctionBlock(sql, "create_time_request");
  assert.match(createReqFn, /p_reason\s+TEXT\s+DEFAULT\s+''/i);
  assert.match(createReqFn, /SECURITY\s+DEFINER/i);
  assert.match(createReqFn, /SELECT\s+family_id\s+INTO\s+v_family_id\s+FROM\s+public\.devices/i);
  assert.match(createReqFn, /p_requested_minutes\s*<=\s*0/i);
  for (const key of [
    "'id'",
    "'device_id'",
    "'family_id'",
    "'requested_minutes'",
    "'reason'",
    "'status'",
    "'created_at'",
    "'success'",
    "'request_id'",
  ]) {
    assert.ok(createReqFn.includes(key), `create_time_request must return ${key}`);
  }
  assert.match(
    sql,
    /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.create_time_request\(UUID,\s*INT,\s*TEXT\)\s+TO\s+authenticated\s*,\s*service_role\s*,\s*anon\s*;/i
  );

  const ackFn = extractFunctionBlock(sql, "acknowledge_device_message");
  assert.match(ackFn, /SECURITY\s+DEFINER/i);
  assert.match(ackFn, /NULLIF\(TRIM\(p_reply_text\),\s*''\)/i);
  assert.match(ackFn, /ORDER\s+BY\s+sent_at\s+DESC\s+LIMIT\s+1/i);
  assert.match(ackFn, /updated_count/i);
  for (const key of [
    "'id'",
    "'device_id'",
    "'family_id'",
    "'title'",
    "'message_text'",
    "'child_reply'",
    "'is_acknowledged'",
    "'acknowledged_at'",
    "'updated_count'",
  ]) {
    assert.ok(ackFn.includes(key), `acknowledge_device_message must return ${key}`);
  }
  assert.match(
    sql,
    /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.acknowledge_device_message\(UUID,\s*UUID,\s*TEXT\)\s+TO\s+authenticated\s*,\s*service_role\s*,\s*anon\s*;/i
  );

  const unreadFn = extractFunctionBlock(sql, "get_unread_device_messages");
  assert.match(unreadFn, /SECURITY\s+DEFINER/i);
  assert.match(unreadFn, /ORDER\s+BY\s+m\.sent_at\s+DESC/i);
  assert.match(
    sql,
    /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.get_unread_device_messages\(UUID\)\s+TO\s+authenticated\s*,\s*service_role\s*,\s*anon\s*;/i
  );
});

test("R1: pg_net trigger safety (no hardcoded secrets, pg_proc guard, EXCEPTION handler)", () => {
  const triggerFn = extractFunctionBlock(sql, "notify_family_parents_via_pg_net");
  assert.match(triggerFn, /SECURITY\s+DEFINER/i);
  assert.match(triggerFn, /FROM\s+pg_proc\s+p[\s\S]*?JOIN\s+pg_namespace\s+n[\s\S]*?n\.nspname\s*=\s*'net'[\s\S]*?p\.proname\s*=\s*'http_post'/i);
  assert.match(triggerFn, /current_setting\('app\.settings\.supabase_url',\s*true\)/i);
  assert.match(triggerFn, /vault\.decrypted_secrets/i);
  assert.match(triggerFn, /EXCEPTION\s+WHEN\s+OTHERS\s+THEN/i);
  assert.doesNotMatch(triggerFn, /https:\/\/[a-z0-9-]+\.supabase\.co/i);
  assert.doesNotMatch(triggerFn, /eyJ[A-Za-z0-9_-]{10,}/);

  assert.match(
    sql,
    /CREATE\s+TRIGGER\s+tr_notify_parents_on_time_request[\s\S]*?AFTER\s+INSERT\s+ON\s+public\.time_requests[\s\S]*?NEW\.status\s*=\s*'pending'\s+AND\s+NEW\.fcm_notified_at\s+IS\s+NULL/i
  );
  assert.match(
    sql,
    /CREATE\s+TRIGGER\s+tr_notify_parents_on_device_message_ack[\s\S]*?AFTER\s+UPDATE\s+ON\s+public\.device_messages[\s\S]*?NEW\.is_acknowledged\s*=\s*true[\s\S]*?NEW\.fcm_notified_at\s+IS\s+NULL/i
  );
});

test("R2: devices extended telemetry columns, DROP FUNCTION overload guard, COALESCE, and get_family_details", () => {
  for (const col of [
    "screen_brightness",
    "is_auto_brightness",
    "screen_mode",
    "is_screen_on",
    "is_dark_mode",
    "media_volume",
    "ring_volume",
    "notification_volume",
    "alarm_volume",
    "ringer_mode",
    "is_media_muted",
  ]) {
    assert.match(
      sql,
      new RegExp(`ADD\\s+COLUMN\\s+IF\\s+NOT\\s+EXISTS\\s+${col}\\b`, "i"),
      `Expected column ${col} added to public.devices`
    );
  }

  const dropIdx = sql.search(
    /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.update_device_telemetry\(\s*UUID\s*,\s*INT\s*,\s*BOOLEAN\s*,\s*TEXT\s*,\s*TEXT\s*\)\s*;/i
  );
  const createIdx = sql.search(
    /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.update_device_telemetry\s*\(/i
  );
  assert.ok(dropIdx !== -1, "Must DROP prior 5-arg update_device_telemetry signature");
  assert.ok(createIdx > dropIdx, "DROP FUNCTION must appear before CREATE FUNCTION");

  const telemetryFn = extractFunctionBlock(sql, "update_device_telemetry");
  assert.match(telemetryFn, /COALESCE\(v_battery,\s*battery_level\)/i);
  assert.match(telemetryFn, /COALESCE\(p_is_charging,\s*is_charging\)/i);
  assert.match(telemetryFn, /COALESCE\(v_brightness,\s*screen_brightness\)/i);
  assert.match(telemetryFn, /COALESCE\(v_media_vol,\s*media_volume\)/i);
  assert.match(telemetryFn, /LEAST\(100,\s*GREATEST\(0,/i);

  const familyFn = extractFunctionBlock(sql, "get_family_details");
  for (const key of [
    "'id'",
    "'device_name'",
    "'custom_name'",
    "'model'",
    "'status'",
    "'battery_level'",
    "'is_charging'",
    "'is_locked'",
    "'extra_time_minutes'",
    "'current_app_name'",
    "'last_seen_at'",
    "'agent_version'",
    "'current_package_name'",
    "'screen_brightness'",
    "'is_auto_brightness'",
    "'screen_mode'",
    "'is_screen_on'",
    "'is_dark_mode'",
    "'media_volume'",
    "'ring_volume'",
    "'notification_volume'",
    "'alarm_volume'",
    "'ringer_mode'",
    "'is_media_muted'",
    "'today_usage_seconds'",
    "'today_usage_date'",
    "'updated_at'",
  ]) {
    assert.ok(familyFn.includes(key), `get_family_details must include ${key}`);
  }
});

test("R3: daily_app_usage, summaries columns, devices today_usage, sync_device_daily_usage (no UTC CURRENT_DATE)", () => {
  assert.match(
    sql,
    /CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+public\.daily_app_usage[\s\S]*?UNIQUE\s*\(\s*device_id\s*,\s*usage_date\s*,\s*package_name\s*\)/i
  );
  assert.match(
    sql,
    /ALTER\s+TABLE\s+public\.daily_app_usage\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY\s*;/i
  );
  assert.match(
    sql,
    /CREATE\s+POLICY\s+"Parents can view daily app usage"\s+ON\s+public\.daily_app_usage[\s\S]*?WHERE\s+d\.id\s*=\s*public\.daily_app_usage\.device_id[\s\S]*?is_member_of_family\(d\.family_id\)\s+OR\s+f\.created_by\s*=\s*auth\.uid\(\)/i
  );

  assert.match(
    sql,
    /ALTER\s+TABLE\s+public\.daily_usage_summaries[\s\S]*?ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+total_screen_time_seconds[\s\S]*?ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+app_breakdown[\s\S]*?ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+local_timezone/i
  );
  assert.match(
    sql,
    /ALTER\s+TABLE\s+public\.devices[\s\S]*?ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+today_usage_seconds\s+INT\s+NOT\s+NULL\s+DEFAULT\s+0[\s\S]*?ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS\s+today_usage_date\s+DATE/i
  );
  assert.doesNotMatch(
    sql,
    /today_usage_date\s+DATE\s+[^;]*CURRENT_DATE/i,
    "devices.today_usage_date must NOT default to UTC CURRENT_DATE"
  );

  const syncFn = extractFunctionBlock(sql, "sync_device_daily_usage");
  assert.match(syncFn, /SECURITY\s+DEFINER/i);
  assert.doesNotMatch(syncFn, /\bCURRENT_DATE\b/i, "sync_device_daily_usage must NEVER use bare UTC CURRENT_DATE");
  assert.match(syncFn, /jsonb_typeof\(p_apps\)\s*=\s*'array'/i);
  assert.match(syncFn, /duration_seconds\s+NUMERIC/i);
  assert.match(syncFn, /SUM\(\s*ROUND\(\s*GREATEST\(/i);
  assert.match(syncFn, /GROUP\s+BY\s+TRIM\(x\.package_name\)/i);
  assert.match(syncFn, /DELETE\s+FROM\s+public\.daily_app_usage[\s\S]*?package_name\s+NOT\s+IN/i);
  assert.match(syncFn, /today_usage_date\s+IS\s+NULL\s+OR\s+v_usage_date\s*>=\s*today_usage_date/i);
  assert.match(
    sql,
    /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.sync_device_daily_usage\(UUID,\s*DATE,\s*INT,\s*JSONB,\s*TEXT\)\s+TO\s+authenticated\s*,\s*service_role\s*,\s*anon\s*;/i
  );
});

test("Realtime publication block idempotently publishes all 8 required tables", () => {
  const secIdx = sql.search(/SECTION 4:\s*IDEMPOTENT SUPABASE REALTIME PUBLICATION/i);
  assert.ok(secIdx !== -1, "Expected Realtime publication section");
  const pubBlock = sql.slice(secIdx);
  assert.match(pubBlock, /pg_publication_tables/i);
  for (const tbl of [
    "devices",
    "policies",
    "app_rules",
    "pairing_sessions",
    "time_requests",
    "device_messages",
    "daily_usage_summaries",
    "daily_app_usage",
  ]) {
    assert.ok(pubBlock.includes(`'${tbl}'`), `Expected ${tbl} in supabase_realtime publication block`);
  }
});

test("Edge Functions and _shared ESM helpers use Web-standard APIs only (Deno + Node compatible)", () => {
  const fcmCode = fs.readFileSync(fcmSharedPath, "utf8");
  const notifyCode = fs.readFileSync(notifySharedPath, "utf8");
  const notifyEntry = fs.readFileSync(notifyEntryPath, "utf8");
  const sendCmdEntry = fs.readFileSync(sendCmdEntryPath, "utf8");

  for (const [name, code] of [
    ["_shared/fcm.mjs", fcmCode],
    ["_shared/notify_parents.mjs", notifyCode],
  ]) {
    assert.doesNotMatch(code, /node:/, `${name} must not import node:* modules`);
    assert.doesNotMatch(code, /\bBuffer\b/, `${name} must not use Node Buffer`);
    assert.doesNotMatch(code, /\bprocess\.env\b/, `${name} must not use Node process.env`);
    assert.doesNotMatch(code, /\bunescape\s*\(/, `${name} must not use deprecated unescape()`);
  }

  assert.match(notifyEntry, /\.\.\/_shared\/notify_parents\.mjs/);
  assert.match(notifyEntry, /\.\.\/_shared\/fcm\.mjs/);
  assert.match(sendCmdEntry, /\.\.\/_shared\/fcm\.mjs/);
});
