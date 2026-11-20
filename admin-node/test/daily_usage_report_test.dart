import 'package:flutter_test/flutter_test.dart';
import 'package:mdm_admin_app/models/daily_usage_report.dart';

void main() {
  group('DailyUsageReport & AppUsageItem Tests', () {
    test('Reconciles rows correctly', () {
      final appRows = [
        {
          'package_name': 'com.google.android.youtube',
          'app_name': 'YouTube',
          'app_category': 'entertainment',
          'duration_seconds': 2400,
        },
        {
          'package_name': 'com.zing.zalo',
          'app_name': 'Zalo',
          'app_category': 'social',
          'duration_seconds': 600,
        },
      ];

      final report = DailyUsageReport.reconcile(
        usageDate: '2026-11-20',
        appUsageRows: appRows,
      );

      expect(report.totalSeconds, 3000);
      expect(report.apps.length, 2);
      expect(report.apps.first.appName, 'YouTube');
      expect(report.apps.first.shareOf(report.totalSeconds), closeTo(0.8, 0.01));
    });

    test('formatUsageDuration formats seconds, minutes and hours', () {
      expect(formatUsageDuration(0), '0m');
      expect(formatUsageDuration(45), '45s');
      expect(formatUsageDuration(120), '2m');
      expect(formatUsageDuration(150), '2m 30s');
      expect(formatUsageDuration(3600), '1h 0m');
      expect(formatUsageDuration(4500), '1h 15m');
    });

    test('computeQuotaProgress calculates ratio and clamps to 1.0', () {
      expect(computeQuotaProgress(1800, 60), 0.5);
      expect(computeQuotaProgress(3600, 60), 1.0);
      expect(computeQuotaProgress(7200, 60), 1.0);
      expect(computeQuotaProgress(0, 60, isLocked: true), 1.0);
    });

    test('computeRemainingSeconds calculates remaining seconds', () {
      expect(computeRemainingSeconds(1800, 60), 1800);
      expect(computeRemainingSeconds(3600, 60), 0);
      expect(computeRemainingSeconds(5000, 60), 0);
    });
  });
}
