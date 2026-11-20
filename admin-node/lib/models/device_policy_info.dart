/// Parsed policy configuration for a child device (R3).
///
/// Handles both `Map` (1-to-1 unique FK) and `List` shapes returned by PostgREST
/// for `devices.select('*, policies(*)')`, plus legacy top-level fields.
class DevicePolicyInfo {
  final int dailyScreenTimeLimitMins;
  final String ruleType;
  final int? weeklyScreenTimeLimitMins;
  final Map<String, int> weekdayLimits;

  const DevicePolicyInfo({
    this.dailyScreenTimeLimitMins = 120,
    this.ruleType = 'daily',
    this.weeklyScreenTimeLimitMins,
    this.weekdayLimits = const <String, int>{},
  });

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  static Map<String, int> _parseWeekdayLimits(dynamic raw) {
    if (raw is! Map) return const <String, int>{};
    final result = <String, int>{};
    raw.forEach((key, value) {
      final parsed = _parseInt(value);
      if (parsed != null) {
        result[key.toString()] = parsed;
      }
    });
    return Map<String, int>.unmodifiable(result);
  }

  factory DevicePolicyInfo.fromDeviceMap(Map<String, dynamic> dev) {
    Map<String, dynamic>? policyMap;
    final rawPolicies = dev['policies'];

    if (rawPolicies is Map) {
      policyMap = Map<String, dynamic>.from(rawPolicies);
    } else if (rawPolicies is List) {
      for (final item in rawPolicies) {
        if (item is Map) {
          policyMap = Map<String, dynamic>.from(item);
          break;
        }
      }
    }

    final parsedDaily = _parseInt(
      policyMap?['daily_screen_time_limit_mins'] ?? dev['daily_screen_time_limit_mins'],
    );
    final dailyLimitMins = (parsedDaily != null && parsedDaily > 0) ? parsedDaily : 120;

    final rawRuleType =
        (policyMap?['rule_type'] ?? dev['rule_type'])?.toString().trim().toLowerCase();
    final ruleType = rawRuleType == 'weekly' ? 'weekly' : 'daily';

    final weeklyLimitMins = _parseInt(
      policyMap?['weekly_screen_time_limit_mins'] ?? dev['weekly_screen_time_limit_mins'],
    );
    final weekdayLimits = _parseWeekdayLimits(
      policyMap?['weekday_limits'] ?? dev['weekday_limits'],
    );

    return DevicePolicyInfo(
      dailyScreenTimeLimitMins: dailyLimitMins,
      ruleType: ruleType,
      weeklyScreenTimeLimitMins: weeklyLimitMins,
      weekdayLimits: weekdayLimits,
    );
  }

  /// Resolves extra time minutes for today, resetting stale values from prior
  /// local calendar days to 0 (matching `target-node` midnight reset behavior).
  static int resolveEffectiveExtraMinutes(
    Map<String, dynamic> dev, {
    DateTime? now,
  }) {
    int rawExtra = _parseInt(dev['extra_time_minutes']) ?? 0;
    if (rawExtra <= 0) return 0;

    final updatedAtStr = dev['updated_at']?.toString();
    if (updatedAtStr != null && updatedAtStr.trim().isNotEmpty) {
      try {
        final updatedLocal = DateTime.parse(updatedAtStr).toLocal();
        final currentLocal = (now ?? DateTime.now()).toLocal();
        if (updatedLocal.year != currentLocal.year ||
            updatedLocal.month != currentLocal.month ||
            updatedLocal.day != currentLocal.day) {
          return 0;
        }
      } catch (_) {}
    }

    return rawExtra;
  }
}
