import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ActivityType {
  lock,
  unlock,
  extraTime,
  pairing,
  sync,
}

class ActivityRecord {
  final String id;
  final ActivityType type;
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final bool isSuccess;

  ActivityRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    this.isSuccess = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'subtitle': subtitle,
        'timestamp': timestamp.toIso8601String(),
        'isSuccess': isSuccess,
      };

  factory ActivityRecord.fromJson(Map<String, dynamic> json) => ActivityRecord(
        id: json['id'] as String,
        type: ActivityType.values.byName(json['type'] as String),
        title: json['title'] as String,
        subtitle: json['subtitle'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        isSuccess: (json['isSuccess'] as bool?) ?? true,
      );
}

class ActivityHistoryService {
  static const String _storageKey = 'mdm_parent_activity_history';

  /// Thêm một bản ghi lịch sử tương tác
  static Future<void> logActivity({
    required ActivityType type,
    required String title,
    required String subtitle,
    bool isSuccess = true,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = await getActivities();

      final newRecord = ActivityRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: type,
        title: title,
        subtitle: subtitle,
        timestamp: DateTime.now(),
        isSuccess: isSuccess,
      );

      // Thêm lên đầu danh sách và giới hạn 50 mục gần nhất
      final updatedList = [newRecord, ...currentList].take(50).toList();
      final jsonList = updatedList.map((e) => e.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving activity history: $e');
    }
  }

  /// Lấy toàn bộ danh sách lịch sử tương tác
  static Future<List<ActivityRecord>> getActivities() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString == null || jsonString.isEmpty) {
        return _getInitialDefaultActivities();
      }
      final decoded = jsonDecode(jsonString) as List<dynamic>;
      return decoded.map((e) => ActivityRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error loading activity history: $e');
      return _getInitialDefaultActivities();
    }
  }

  /// Xóa sạch lịch sử
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  static List<ActivityRecord> _getInitialDefaultActivities() {
    return [
      ActivityRecord(
        id: '1',
        type: ActivityType.pairing,
        title: 'Ghép Nối Thiết Bị Thành Công',
        subtitle: 'Thiết bị con đã bắt tay an toàn với hệ thống MDM Supabase',
        timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
        isSuccess: true,
      ),
    ];
  }
}
