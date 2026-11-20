import 'package:flutter_test/flutter_test.dart';
import 'package:mdm_admin_app/models/device_telemetry_snapshot.dart';

void main() {
  group('DeviceTelemetrySnapshot Tests', () {
    test('Parses full telemetry map correctly', () {
      final map = {
        'battery_level': 85,
        'is_charging': true,
        'current_app_name': 'YouTube Kids',
        'current_package_name': 'com.google.android.apps.youtube.kids',
        'agent_version': '1.3.5',
        'screen_brightness': 70,
        'is_auto_brightness': true,
        'screen_mode': 'on_unlocked',
        'is_screen_on': true,
        'is_dark_mode': true,
        'media_volume': 60,
        'ring_volume': 80,
        'notification_volume': 75,
        'alarm_volume': 90,
        'ringer_mode': 'normal',
        'is_media_muted': false,
      };

      final snapshot = DeviceTelemetrySnapshot.fromMap(map);

      expect(snapshot.batteryLevel, 85);
      expect(snapshot.isCharging, isTrue);
      expect(snapshot.currentAppName, 'YouTube Kids');
      expect(snapshot.currentPackageName, 'com.google.android.apps.youtube.kids');
      expect(snapshot.agentVersion, '1.3.5');
      expect(snapshot.screenBrightness, 70);
      expect(snapshot.isAutoBrightness, isTrue);
      expect(snapshot.screenMode, 'on_unlocked');
      expect(snapshot.screenModeLabel, 'Đang mở');
      expect(snapshot.isScreenOn, isTrue);
      expect(snapshot.isDarkMode, isTrue);
      expect(snapshot.mediaVolume, 60);
      expect(snapshot.ringVolume, 80);
      expect(snapshot.notificationVolume, 75);
      expect(snapshot.alarmVolume, 90);
      expect(snapshot.ringerMode, 'normal');
      expect(snapshot.ringerModeLabel, 'Bình thường');
      expect(snapshot.isMediaMuted, isFalse);
      expect(snapshot.hasExtendedTelemetry, isTrue);
    });

    test('mergeFrom preserves existing values when partial map is missing keys', () {
      final initial = DeviceTelemetrySnapshot.fromMap({
        'battery_level': 50,
        'screen_brightness': 60,
        'media_volume': 40,
        'ringer_mode': 'vibrate',
      });

      final updated = initial.mergeFrom({
        'battery_level': 52,
        'is_charging': true,
      });

      expect(updated.batteryLevel, 52);
      expect(updated.isCharging, isTrue);
      expect(updated.screenBrightness, 60);
      expect(updated.mediaVolume, 40);
      expect(updated.ringerMode, 'vibrate');
      expect(updated.ringerModeLabel, 'Rung');
    });

    test('Clamps percentages to 0..100 range', () {
      final snapshot = DeviceTelemetrySnapshot.fromMap({
        'battery_level': 150,
        'screen_brightness': -20,
        'media_volume': 200,
      });

      expect(snapshot.batteryLevel, 100);
      expect(snapshot.screenBrightness, 0);
      expect(snapshot.mediaVolume, 100);
    });
  });
}
