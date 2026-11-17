import 'package:flutter_test/flutter_test.dart';
import 'package:mdm_admin_app/services/github_release_updater.dart';

void main() {
  group('ParentAppUpdater.isNewerVersion Tests', () {
    test('Same version on iOS does not trigger update', () {
      expect(ParentAppUpdater.isNewerVersion('admin-ios-v1.5.0', '1.5.0'), isFalse);
    });

    test('Same version with build number does not trigger update', () {
      expect(ParentAppUpdater.isNewerVersion('admin-ios-v1.5.0', '1.5.0+11'), isFalse);
    });

    test('Same version on Android does not trigger update', () {
      expect(ParentAppUpdater.isNewerVersion('admin-android-v1.5.0', '1.5.0'), isFalse);
    });

    test('Older remote version does not trigger update', () {
      expect(ParentAppUpdater.isNewerVersion('admin-ios-v1.4.9', '1.5.0'), isFalse);
    });

    test('Newer remote patch version triggers update', () {
      expect(ParentAppUpdater.isNewerVersion('admin-ios-v1.5.1', '1.5.0'), isTrue);
    });

    test('Newer remote minor version triggers update', () {
      expect(ParentAppUpdater.isNewerVersion('admin-ios-v1.6.0', '1.5.0'), isTrue);
    });

    test('Newer remote major version triggers update', () {
      expect(ParentAppUpdater.isNewerVersion('admin-android-v2.0.0', '1.5.0'), isTrue);
    });

    test('Old hardcoded 1.3.4 vs 1.5.0 release', () {
      // Confirms why old code was triggering update:
      expect(ParentAppUpdater.isNewerVersion('admin-ios-v1.5.0', '1.3.4'), isTrue);
      // With our fix, when app is at 1.5.1:
      expect(ParentAppUpdater.isNewerVersion('admin-ios-v1.5.1', ParentAppUpdater.appVersion), isFalse);
    });
  });
}
