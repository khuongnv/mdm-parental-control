import fs from 'node:fs';
import path from 'node:path';

function readIfExists(filePath) {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch {
    return null;
  }
}

function readAllFilesByExt(rootDir, ext) {
  let combined = '';
  if (!fs.existsSync(rootDir)) return combined;
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (entry.isFile() && entry.name.endsWith(ext)) {
        combined += `\n// FILE: ${path.relative(rootDir, full)}\n` + fs.readFileSync(full, 'utf8');
      }
    }
  };
  walk(rootDir);
  return combined;
}

export function validateIosPushConfigFiles({
  infoPlist,
  entitlements,
  appDelegate,
  pbxproj,
  googleServiceInfo,
}) {
  const errors = [];

  if (!googleServiceInfo || !googleServiceInfo.includes('com.dhtthni.quanlytaptrung')) {
    errors.push('GoogleService-Info.plist missing or wrong BUNDLE_ID (expected com.dhtthni.quanlytaptrung)');
  }
  if (!pbxproj || !pbxproj.includes('GoogleService-Info.plist in Resources')) {
    errors.push('project.pbxproj does not include GoogleService-Info.plist in Resources build phase');
  }
  if (!infoPlist || !infoPlist.includes('UIBackgroundModes') || !infoPlist.includes('remote-notification')) {
    errors.push('Info.plist missing UIBackgroundModes -> remote-notification');
  }
  if (!entitlements || !entitlements.includes('aps-environment')) {
    errors.push('Runner.entitlements missing aps-environment key');
  }
  if (!pbxproj || !pbxproj.includes('CODE_SIGN_ENTITLEMENTS')) {
    errors.push('project.pbxproj missing CODE_SIGN_ENTITLEMENTS');
  }
  if (
    !appDelegate ||
    !appDelegate.includes('FirebaseApp.configure') ||
    !appDelegate.includes('UNUserNotificationCenter') ||
    !appDelegate.includes('registerForRemoteNotifications')
  ) {
    errors.push('AppDelegate.swift missing FirebaseApp.configure / UNUserNotificationCenter / registerForRemoteNotifications');
  }

  return { ok: errors.length === 0, errors };
}

export function verifyRepoContracts(repoRoot) {
  const checks = [];
  const addCheck = (id, category, passed, details) => {
    checks.push({ id, category, passed: Boolean(passed), details });
  };

  // ---- 1. Backend SQL Migrations & Edge Functions ----
  const migrationsDir = path.join(repoRoot, 'backend', 'supabase', 'migrations');
  let combinedSql = '';
  if (fs.existsSync(migrationsDir)) {
    const files = fs.readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();
    for (const f of files) {
      combinedSql += `\n-- FILE: ${f}\n` + fs.readFileSync(path.join(migrationsDir, f), 'utf8');
    }
  }

  addCheck(
    'BE-R1-01',
    'backend',
    combinedSql.includes('parent_push_tokens') && combinedSql.includes('upsert_parent_push_token'),
    'parent_push_tokens table and upsert_parent_push_token RPC in migrations'
  );
  addCheck(
    'BE-R1-02',
    'backend',
    combinedSql.includes('acknowledge_device_message') &&
      combinedSql.includes('get_unread_device_messages') &&
      combinedSql.includes('child_reply'),
    'acknowledge_device_message, get_unread_device_messages, and child_reply column in migrations'
  );
  addCheck(
    'BE-R1-03',
    'backend',
    combinedSql.includes('fcm_notified_at') && combinedSql.includes('REPLICA IDENTITY FULL'),
    'fcm_notified_at idempotency column and REPLICA IDENTITY FULL in migrations'
  );
  addCheck(
    'BE-R2-01',
    'backend',
    [
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
    ].every((col) => combinedSql.includes(col)),
    'All 11 extended telemetry columns present in backend migrations'
  );
  addCheck(
    'BE-R2-02',
    'backend',
    /DROP\s+FUNCTION\s+IF\s+EXISTS\s+public\.update_device_telemetry/i.test(combinedSql) &&
      combinedSql.includes('COALESCE('),
    'Legacy update_device_telemetry overload dropped and recreated with COALESCE'
  );
  addCheck(
    'BE-R3-01',
    'backend',
    combinedSql.includes('daily_app_usage') &&
      combinedSql.includes('total_screen_time_seconds') &&
      combinedSql.includes('sync_device_daily_usage') &&
      combinedSql.includes('today_usage_seconds'),
    'daily_app_usage, total_screen_time_seconds, today_usage_seconds, and sync_device_daily_usage RPC'
  );

  const notifyParentsTs = readIfExists(
    path.join(repoRoot, 'backend', 'supabase', 'functions', 'notify-family-parents', 'index.ts')
  );
  const sharedFcmMjs = readIfExists(
    path.join(repoRoot, 'backend', 'supabase', 'functions', '_shared', 'fcm.mjs')
  );
  const sharedNotifyParentsMjs = readIfExists(
    path.join(repoRoot, 'backend', 'supabase', 'functions', '_shared', 'notify_parents.mjs')
  );
  const combinedNotifyParents = [notifyParentsTs, sharedFcmMjs, sharedNotifyParentsMjs].filter(Boolean).join('\n');
  addCheck(
    'BE-FN-01',
    'backend',
    Boolean(
      notifyParentsTs &&
        combinedNotifyParents.includes('fcm_notified_at') &&
        combinedNotifyParents.includes('parent_push_tokens') &&
        combinedNotifyParents.includes('vfam_admin_alerts') &&
        combinedNotifyParents.includes('apns-priority')
    ),
    'notify-family-parents Edge Function implements atomic fcm_notified_at, Android channel, and APNs headers'
  );

  const sendFcmCommandTs = readIfExists(
    path.join(repoRoot, 'backend', 'supabase', 'functions', 'send-fcm-command', 'index.ts')
  );
  const combinedSendFcm = [sendFcmCommandTs, sharedFcmMjs].filter(Boolean).join('\n');
  addCheck(
    'BE-FN-02',
    'backend',
    Boolean(
      sendFcmCommandTs &&
        combinedSendFcm.includes('apns-push-type') &&
        combinedSendFcm.includes('content-available')
    ),
    'send-fcm-command Edge Function includes iOS APNs push headers (apns-push-type)'
  );

  // ---- 2. Target Node (Android DO Kotlin) ----
  const targetGoogleServices = readIfExists(path.join(repoRoot, 'target-node', 'app', 'google-services.json'));
  addCheck(
    'TN-CFG-01',
    'target-node',
    Boolean(targetGoogleServices && targetGoogleServices.includes('vn.hanoi.khuongnv.vfam.child')),
    'target-node google-services.json matches vn.hanoi.khuongnv.vfam.child'
  );

  const targetManifest = readIfExists(
    path.join(repoRoot, 'target-node', 'app', 'src', 'main', 'AndroidManifest.xml')
  );
  addCheck(
    'TN-CFG-02',
    'target-node',
    Boolean(
      targetManifest &&
        targetManifest.includes('PACKAGE_USAGE_STATS') &&
        targetManifest.includes('MdmDeviceAdminReceiver') &&
        targetManifest.includes('MdmFirebaseMessagingService') &&
        targetManifest.includes('NotificationActionReceiver')
    ),
    'target-node AndroidManifest declares usage stats, DO receiver, FCM service, and action receiver'
  );

  const targetPkgDir = path.join(
    repoRoot,
    'target-node',
    'app',
    'src',
    'main',
    'java',
    'com',
    'mdm',
    'parentalcontrol',
    'child'
  );
  const mdmSupabaseKt = readIfExists(path.join(targetPkgDir, 'network', 'MdmSupabaseClient.kt')) || '';
  const telemetryCollectorKt = readIfExists(path.join(targetPkgDir, 'service', 'DeviceTelemetryCollector.kt')) || '';
  const entitiesKt = readIfExists(path.join(targetPkgDir, 'data', 'local', 'Entities.kt')) || '';
  const usageSyncWorkerKt = readIfExists(path.join(targetPkgDir, 'service', 'UsageSyncWorker.kt')) || '';

  addCheck(
    'TN-R1-01',
    'target-node',
    mdmSupabaseKt.includes('create_time_request') &&
      mdmSupabaseKt.includes('acknowledge_device_message') &&
      mdmSupabaseKt.includes('notify-family-parents'),
    'target-node MdmSupabaseClient uses create_time_request, acknowledge_device_message, and notify-family-parents'
  );
  addCheck(
    'TN-R2-01',
    'target-node',
    (telemetryCollectorKt.includes('screen_brightness') || telemetryCollectorKt.includes('screenBrightness')) &&
      mdmSupabaseKt.includes('p_screen_brightness'),
    'target-node collects (DeviceTelemetryCollector) and uploads (MdmSupabaseClient) extended telemetry'
  );
  addCheck(
    'TN-R3-01',
    'target-node',
    entitiesKt.includes('primaryKeys') &&
      (mdmSupabaseKt.includes('sync_device_daily_usage') || usageSyncWorkerKt.includes('sync_device_daily_usage')),
    'target-node Room uses composite primaryKeys (packageName, date) and sync_device_daily_usage'
  );

  // ---- 3. Admin Node (Flutter Android + iOS Enterprise) ----
  const pubspec = readIfExists(path.join(repoRoot, 'admin-node', 'pubspec.yaml')) || '';
  addCheck(
    'AN-CFG-01',
    'admin-node',
    pubspec.includes('firebase_core') && pubspec.includes('firebase_messaging'),
    'admin-node pubspec.yaml declares firebase_core and firebase_messaging'
  );

  const adminGoogleServices = readIfExists(path.join(repoRoot, 'admin-node', 'android', 'app', 'google-services.json')) || '';
  const adminManifest =
    readIfExists(path.join(repoRoot, 'admin-node', 'android', 'app', 'src', 'main', 'AndroidManifest.xml')) || '';
  const adminBuildGradle =
    readIfExists(path.join(repoRoot, 'admin-node', 'android', 'app', 'build.gradle.kts')) || '';
  addCheck(
    'AN-AND-01',
    'admin-node',
    adminGoogleServices.includes('vn.hanoi.khuongnv.vfam.admin') &&
      adminManifest.includes('com.google.firebase.messaging.default_notification_channel_id') &&
      adminManifest.includes('vfam_admin_alerts') &&
      adminManifest.includes('POST_NOTIFICATIONS') &&
      adminBuildGradle.includes('com.google.gms.google-services'),
    'admin-node Android google-services.json, google-services plugin, POST_NOTIFICATIONS, and default_notification_channel_id = vfam_admin_alerts'
  );

  const iosValidation = validateIosPushConfigFiles({
    infoPlist: readIfExists(path.join(repoRoot, 'admin-node', 'ios', 'Runner', 'Info.plist')),
    entitlements: readIfExists(path.join(repoRoot, 'admin-node', 'ios', 'Runner', 'Runner.entitlements')),
    appDelegate: readIfExists(path.join(repoRoot, 'admin-node', 'ios', 'Runner', 'AppDelegate.swift')),
    pbxproj: readIfExists(path.join(repoRoot, 'admin-node', 'ios', 'Runner.xcodeproj', 'project.pbxproj')),
    googleServiceInfo: readIfExists(path.join(repoRoot, 'admin-node', 'ios', 'Runner', 'GoogleService-Info.plist')),
  });
  addCheck('AN-IOS-01', 'admin-node', iosValidation.ok, iosValidation.errors.join('; ') || 'iOS Enterprise APNs/FCM config valid');

  const adminLibDir = path.join(repoRoot, 'admin-node', 'lib');
  const adminAllDart = readAllFilesByExt(adminLibDir, '.dart');
  const adminMainDart = readIfExists(path.join(adminLibDir, 'main.dart')) || '';
  const adminSupabaseServiceDart =
    readIfExists(path.join(adminLibDir, 'services', 'mdm_supabase_service.dart')) || '';
  const adminFcmServiceDart =
    readIfExists(path.join(adminLibDir, 'services', 'fcm_notification_service.dart')) || '';

  addCheck(
    'AN-R1-01',
    'admin-node',
    Boolean(
      adminFcmServiceDart &&
        adminAllDart.includes('upsert_parent_push_token') &&
        adminAllDart.includes('fcm_notification_service') &&
        /shared_preferences|SharedPreferences/i.test(adminFcmServiceDart + adminAllDart) &&
        /dedup|processed|seen/i.test(adminFcmServiceDart + adminAllDart)
    ),
    'admin-node implements fcm_notification_service, upsert_parent_push_token, and persistent dedup'
  );

  addCheck(
    'AN-R2-01',
    'admin-node',
    adminAllDart.includes('screen_brightness') && adminAllDart.includes('ringer_mode'),
    'admin-node parses and displays extended telemetry (screen_brightness, ringer_mode)'
  );

  addCheck(
    'AN-R3-01',
    'admin-node',
    !adminMainDart.includes('isEmergencyLocked ? 1.0 : 0.35') &&
      (adminMainDart.includes('daily_usage_summaries') ||
        adminSupabaseServiceDart.includes('daily_usage_summaries')),
    'admin-node replaces hardcoded 0.35 progress bar and queries daily_usage_summaries'
  );

  const failed = checks.filter((c) => !c.passed);
  return {
    ok: failed.length === 0,
    total: checks.length,
    passed: checks.length - failed.length,
    failed: failed.length,
    checks,
  };
}
