/// Extended telemetry snapshot for a child device (R2).
///
/// Supports full parsing via `fromMap` and safe partial updates via `mergeFrom`
/// so Presence / Broadcast payloads carrying a subset of keys never erase
/// previously known values.
class DeviceTelemetrySnapshot {
  static const Set<String> validScreenModes = <String>{
    'on_unlocked',
    'on_locked',
    'doze',
    'off',
    'unknown',
  };

  static const Set<String> validRingerModes = <String>{
    'normal',
    'vibrate',
    'silent',
  };

  final int? batteryLevel;
  final bool isCharging;
  final String? currentAppName;
  final String? currentPackageName;
  final String? agentVersion;

  final int? screenBrightness;
  final bool isAutoBrightness;
  final String screenMode;
  final bool isScreenOn;
  final bool isDarkMode;

  final int? mediaVolume;
  final int? ringVolume;
  final int? notificationVolume;
  final int? alarmVolume;
  final String ringerMode;
  final bool isMediaMuted;

  const DeviceTelemetrySnapshot({
    this.batteryLevel,
    this.isCharging = false,
    this.currentAppName,
    this.currentPackageName,
    this.agentVersion,
    this.screenBrightness,
    this.isAutoBrightness = false,
    this.screenMode = 'unknown',
    this.isScreenOn = true,
    this.isDarkMode = false,
    this.mediaVolume,
    this.ringVolume,
    this.notificationVolume,
    this.alarmVolume,
    this.ringerMode = 'normal',
    this.isMediaMuted = false,
  });

  static int? _parsePercent(dynamic value) {
    if (value == null) return null;
    int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is num) {
      parsed = value.round();
    } else {
      parsed = int.tryParse(value.toString().trim());
    }
    if (parsed == null) return null;
    return parsed.clamp(0, 100);
  }

  static bool _parseBool(dynamic value, {required bool fallback}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return fallback;
  }

  static String? _parseNonEmptyString(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  static String _normalizeScreenMode(dynamic value) {
    final s = value?.toString().trim().toLowerCase() ?? '';
    return validScreenModes.contains(s) ? s : 'unknown';
  }

  static String _normalizeRingerMode(dynamic value) {
    final s = value?.toString().trim().toLowerCase() ?? '';
    return validRingerModes.contains(s) ? s : 'normal';
  }

  factory DeviceTelemetrySnapshot.fromMap(Map<String, dynamic> map) {
    final screenMode = _normalizeScreenMode(map['screen_mode']);
    final isScreenOn = map['is_screen_on'] != null
        ? _parseBool(map['is_screen_on'], fallback: true)
        : (screenMode != 'off' && screenMode != 'doze');

    return DeviceTelemetrySnapshot(
      batteryLevel: _parsePercent(map['battery_level']),
      isCharging: _parseBool(map['is_charging'], fallback: false),
      currentAppName: _parseNonEmptyString(map['current_app_name'] ?? map['current_app']),
      currentPackageName: _parseNonEmptyString(map['current_package_name']),
      agentVersion: _parseNonEmptyString(map['agent_version']),
      screenBrightness: _parsePercent(map['screen_brightness']),
      isAutoBrightness: _parseBool(map['is_auto_brightness'], fallback: false),
      screenMode: screenMode,
      isScreenOn: isScreenOn,
      isDarkMode: _parseBool(map['is_dark_mode'], fallback: false),
      mediaVolume: _parsePercent(map['media_volume']),
      ringVolume: _parsePercent(map['ring_volume']),
      notificationVolume: _parsePercent(map['notification_volume']),
      alarmVolume: _parsePercent(map['alarm_volume']),
      ringerMode: _normalizeRingerMode(map['ringer_mode']),
      isMediaMuted: _parseBool(map['is_media_muted'], fallback: false),
    );
  }

  /// Merges a partial telemetry map onto this snapshot, preserving existing
  /// non-null fields whenever [partial] omits a key or supplies null.
  DeviceTelemetrySnapshot mergeFrom(Map<String, dynamic> partial) {
    final hasAppName =
        (partial.containsKey('current_app_name') && partial['current_app_name'] != null) ||
            (partial.containsKey('current_app') && partial['current_app'] != null);
    final nextScreenMode = (partial.containsKey('screen_mode') && partial['screen_mode'] != null)
        ? _normalizeScreenMode(partial['screen_mode'])
        : screenMode;
    final nextIsScreenOn = (partial.containsKey('is_screen_on') && partial['is_screen_on'] != null)
        ? _parseBool(partial['is_screen_on'], fallback: isScreenOn)
        : ((partial.containsKey('screen_mode') && partial['screen_mode'] != null)
            ? (nextScreenMode != 'off' && nextScreenMode != 'doze')
            : isScreenOn);

    return DeviceTelemetrySnapshot(
      batteryLevel: (partial.containsKey('battery_level') && partial['battery_level'] != null)
          ? (_parsePercent(partial['battery_level']) ?? batteryLevel)
          : batteryLevel,
      isCharging: (partial.containsKey('is_charging') && partial['is_charging'] != null)
          ? _parseBool(partial['is_charging'], fallback: isCharging)
          : isCharging,
      currentAppName: hasAppName
          ? _parseNonEmptyString(partial['current_app_name'] ?? partial['current_app'])
          : currentAppName,
      currentPackageName: (partial.containsKey('current_package_name') && partial['current_package_name'] != null)
          ? _parseNonEmptyString(partial['current_package_name'])
          : currentPackageName,
      agentVersion: (partial.containsKey('agent_version') && partial['agent_version'] != null)
          ? _parseNonEmptyString(partial['agent_version'])
          : agentVersion,
      screenBrightness: (partial.containsKey('screen_brightness') && partial['screen_brightness'] != null)
          ? (_parsePercent(partial['screen_brightness']) ?? screenBrightness)
          : screenBrightness,
      isAutoBrightness: (partial.containsKey('is_auto_brightness') && partial['is_auto_brightness'] != null)
          ? _parseBool(partial['is_auto_brightness'], fallback: isAutoBrightness)
          : isAutoBrightness,
      screenMode: nextScreenMode,
      isScreenOn: nextIsScreenOn,
      isDarkMode: (partial.containsKey('is_dark_mode') && partial['is_dark_mode'] != null)
          ? _parseBool(partial['is_dark_mode'], fallback: isDarkMode)
          : isDarkMode,
      mediaVolume: (partial.containsKey('media_volume') && partial['media_volume'] != null)
          ? (_parsePercent(partial['media_volume']) ?? mediaVolume)
          : mediaVolume,
      ringVolume: (partial.containsKey('ring_volume') && partial['ring_volume'] != null)
          ? (_parsePercent(partial['ring_volume']) ?? ringVolume)
          : ringVolume,
      notificationVolume: (partial.containsKey('notification_volume') && partial['notification_volume'] != null)
          ? (_parsePercent(partial['notification_volume']) ?? notificationVolume)
          : notificationVolume,
      alarmVolume: (partial.containsKey('alarm_volume') && partial['alarm_volume'] != null)
          ? (_parsePercent(partial['alarm_volume']) ?? alarmVolume)
          : alarmVolume,
      ringerMode: (partial.containsKey('ringer_mode') && partial['ringer_mode'] != null)
          ? _normalizeRingerMode(partial['ringer_mode'])
          : ringerMode,
      isMediaMuted: (partial.containsKey('is_media_muted') && partial['is_media_muted'] != null)
          ? _parseBool(partial['is_media_muted'], fallback: isMediaMuted)
          : isMediaMuted,
    );
  }

  String get screenModeLabel {
    switch (screenMode) {
      case 'on_unlocked':
        return 'Đang mở';
      case 'on_locked':
        return 'Màn hình khóa';
      case 'doze':
        return 'Chế độ nghỉ';
      case 'off':
        return 'Tắt màn hình';
      default:
        return isScreenOn ? 'Đang bật' : 'Tắt màn hình';
    }
  }

  String get ringerModeLabel {
    switch (ringerMode) {
      case 'vibrate':
        return 'Rung';
      case 'silent':
        return 'Im lặng';
      case 'normal':
      default:
        return 'Bình thường';
    }
  }

  bool get hasExtendedTelemetry =>
      screenBrightness != null ||
      screenMode != 'unknown' ||
      mediaVolume != null ||
      ringVolume != null ||
      notificationVolume != null ||
      alarmVolume != null;
}
