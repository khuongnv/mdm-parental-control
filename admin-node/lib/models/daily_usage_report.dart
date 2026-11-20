import 'dart:math' as math;

/// Exact per-application daily usage record (R3).
class AppUsageItem {
  final String packageName;
  final String appName;
  final String appCategory;
  final int durationSeconds;

  const AppUsageItem({
    required this.packageName,
    required this.appName,
    required this.appCategory,
    required this.durationSeconds,
  });

  double shareOf(int totalSeconds) {
    if (totalSeconds <= 0 || durationSeconds <= 0) return 0.0;
    return (durationSeconds / totalSeconds).clamp(0.0, 1.0);
  }

  static int _parseSeconds(dynamic rawSeconds, dynamic rawMinutes) {
    if (rawSeconds is int) return math.max(0, rawSeconds);
    if (rawSeconds is num) return math.max(0, rawSeconds.round());
    if (rawSeconds != null) {
      final parsed = num.tryParse(rawSeconds.toString().trim());
      if (parsed != null) return math.max(0, parsed.round());
    }
    if (rawMinutes is num) return math.max(0, (rawMinutes * 60).round());
    if (rawMinutes != null) {
      final parsed = num.tryParse(rawMinutes.toString().trim());
      if (parsed != null) return math.max(0, (parsed * 60).round());
    }
    return 0;
  }

  factory AppUsageItem.fromMap(Map<String, dynamic> map) {
    final pkg = (map['package_name'] ?? '').toString().trim();
    final rawName = (map['app_name'] ?? '').toString().trim();
    final name = rawName.isNotEmpty ? rawName : (pkg.isNotEmpty ? pkg : 'Ứng dụng');
    final rawCategory = (map['app_category'] ?? map['category'] ?? '').toString().trim();
    final category = rawCategory.isNotEmpty ? rawCategory : 'other';
    final seconds = _parseSeconds(map['duration_seconds'], map['minutes']);

    return AppUsageItem(
      packageName: pkg.isNotEmpty ? pkg : name,
      appName: name,
      appCategory: category,
      durationSeconds: seconds,
    );
  }
}

/// Reconciled daily screen-time report for a child device (R3).
class DailyUsageReport {
  final String usageDate;
  final int totalSeconds;
  final List<AppUsageItem> apps;
  final Map<String, int> categorySeconds;
  final String? localTimezone;

  const DailyUsageReport({
    required this.usageDate,
    required this.totalSeconds,
    required this.apps,
    this.categorySeconds = const <String, int>{},
    this.localTimezone,
  });

  factory DailyUsageReport.empty(String usageDate) {
    return DailyUsageReport(
      usageDate: usageDate,
      totalSeconds: 0,
      apps: const <AppUsageItem>[],
      categorySeconds: const <String, int>{},
    );
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.round();
    return num.tryParse(v.toString().trim())?.round();
  }

  static List<AppUsageItem> _parseAppList(dynamic rawList) {
    if (rawList is! List) return const <AppUsageItem>[];
    final items = <AppUsageItem>[];
    for (final entry in rawList) {
      if (entry is Map) {
        final item = AppUsageItem.fromMap(Map<String, dynamic>.from(entry));
        if (item.durationSeconds > 0 || item.packageName.isNotEmpty) {
          items.add(item);
        }
      }
    }
    return items;
  }

  /// Reconciles `daily_app_usage`, `daily_usage_summaries`, and `devices` cached
  /// daily usage fields in exact seconds, guarding against stale `today_usage_date`.
  factory DailyUsageReport.reconcile({
    required String usageDate,
    Map<String, dynamic>? summaryRow,
    List<Map<String, dynamic>>? appUsageRows,
    Map<String, dynamic>? deviceRow,
  }) {
    List<AppUsageItem> parsedApps = <AppUsageItem>[];
    if (appUsageRows != null && appUsageRows.isNotEmpty) {
      parsedApps = _parseAppList(appUsageRows);
    } else if (summaryRow != null) {
      final breakdown = _parseAppList(summaryRow['app_breakdown']);
      if (breakdown.isNotEmpty) {
        parsedApps = breakdown;
      } else {
        parsedApps = _parseAppList(summaryRow['top_apps']);
      }
    }

    // Deduplicate by packageName keeping highest duration, then sort descending.
    final dedupByPkg = <String, AppUsageItem>{};
    for (final item in parsedApps) {
      final existing = dedupByPkg[item.packageName];
      if (existing == null || item.durationSeconds > existing.durationSeconds) {
        dedupByPkg[item.packageName] = item;
      }
    }
    final sortedApps = dedupByPkg.values.toList()
      ..sort((a, b) {
        final cmp = b.durationSeconds.compareTo(a.durationSeconds);
        if (cmp != 0) return cmp;
        return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
      });

    var appsSum = 0;
    final catMap = <String, int>{};
    for (final app in sortedApps) {
      appsSum += app.durationSeconds;
      catMap[app.appCategory] = (catMap[app.appCategory] ?? 0) + app.durationSeconds;
    }

    int summarySeconds = 0;
    if (summaryRow != null) {
      final summaryDate = summaryRow['summary_date']?.toString().trim();
      if (summaryDate == null || summaryDate.isEmpty || summaryDate == usageDate) {
        final rawSec = _parseInt(summaryRow['total_screen_time_seconds']);
        if (rawSec != null && rawSec > 0) {
          summarySeconds = rawSec;
        } else {
          final rawMins = _parseInt(summaryRow['total_screen_time_mins']) ?? 0;
          summarySeconds = math.max(0, rawMins * 60);
        }
      }
    }

    int deviceCacheSeconds = 0;
    if (deviceRow != null) {
      final cachedDate = deviceRow['today_usage_date']?.toString().trim();
      if (cachedDate == usageDate) {
        deviceCacheSeconds = math.max(0, _parseInt(deviceRow['today_usage_seconds']) ?? 0);
      }
    }

    final totalSeconds = math.max(
      0,
      math.max(summarySeconds, math.max(appsSum, deviceCacheSeconds)),
    );

    return DailyUsageReport(
      usageDate: usageDate,
      totalSeconds: totalSeconds,
      apps: List<AppUsageItem>.unmodifiable(sortedApps),
      categorySeconds: Map<String, int>.unmodifiable(catMap),
      localTimezone: summaryRow?['local_timezone']?.toString(),
    );
  }
}

/// Formats a DateTime in local calendar `yyyy-MM-dd` matching `target-node`.
String formatLocalDateYmd([DateTime? dt]) {
  final local = (dt ?? DateTime.now()).toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Formats exact duration seconds for Vietnamese UI without minute-truncation loss.
String formatUsageDuration(int totalSeconds) {
  if (totalSeconds <= 0) return '0m';
  if (totalSeconds < 60) return '${totalSeconds}s';
  if (totalSeconds < 3600) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  return '${h}h ${m}m';
}

/// Computes normalized quota progress `[0.0, 1.0]`.
double computeQuotaProgress(
  int usedSeconds,
  int allowedMinutes, {
  bool isLocked = false,
}) {
  if (isLocked) return 1.0;
  if (allowedMinutes <= 0 || usedSeconds <= 0) return 0.0;
  final allowedSeconds = allowedMinutes * 60;
  return (usedSeconds / allowedSeconds).clamp(0.0, 1.0);
}

/// Computes remaining allowed seconds for the day (`>= 0`).
int computeRemainingSeconds(int usedSeconds, int allowedMinutes) {
  if (allowedMinutes <= 0) return 0;
  final allowedSeconds = allowedMinutes * 60;
  return math.max(0, allowedSeconds - math.max(0, usedSeconds));
}
