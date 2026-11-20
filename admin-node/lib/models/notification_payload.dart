import 'dart:convert';

int _monotonicNotificationCounter = 0;

/// Copy builder output for local tray notifications & in-app HUDs.
class NotificationCopy {
  final String title;
  final String body;

  const NotificationCopy({
    required this.title,
    required this.body,
  });
}

/// Pure Dart representation of notification payloads arriving from
/// FCM HTTP v1 `data`, Supabase Broadcast, or Postgres Changes.
class ParentNotificationPayload {
  final String eventType;
  final String? deviceId;
  final String? familyId;
  final String? recordId;
  final String? deviceName;
  final int? requestedMinutes;
  final String? reason;
  final String? messageText;
  final String? childReply;
  final String? title;
  final String? body;
  final bool? isLocked;
  final String? timestamp;

  const ParentNotificationPayload({
    required this.eventType,
    this.deviceId,
    this.familyId,
    this.recordId,
    this.deviceName,
    this.requestedMinutes,
    this.reason,
    this.messageText,
    this.childReply,
    this.title,
    this.body,
    this.isLocked,
    this.timestamp,
  });

  static String? _readNonEmptyString(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    return str.isEmpty ? null : str;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  static bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return null;
  }

  factory ParentNotificationPayload.fromMap(
    Map<String, dynamic> raw, {
    String? fallbackEventType,
  }) {
    final map = (raw['payload'] is Map)
        ? Map<String, dynamic>.from(raw['payload'] as Map)
        : raw;

    final deviceId = _readNonEmptyString(map['device_id']);
    final familyId = _readNonEmptyString(map['family_id']);
    final recordId = _readNonEmptyString(
      map['record_id'] ?? map['request_id'] ?? map['message_id'] ?? map['id'],
    );
    final deviceName = _readNonEmptyString(map['device_name']);
    final requestedMinutes = _parseInt(map['requested_minutes']);
    final reason = _readNonEmptyString(map['reason']);
    final messageText = _readNonEmptyString(map['message_text']);
    final childReply = _readNonEmptyString(map['child_reply'] ?? map['reply_text']);
    final title = _readNonEmptyString(map['title']);
    final body = _readNonEmptyString(map['body']);
    final isLocked = _parseBool(map['is_locked']);
    final timestamp = _readNonEmptyString(map['timestamp'] ?? map['created_at'] ?? map['acknowledged_at']);

    String eventType = _readNonEmptyString(map['event_type'])?.toUpperCase() ?? '';
    if (eventType.isEmpty && fallbackEventType != null) {
      eventType = fallbackEventType.toUpperCase();
    }
    if (eventType.isEmpty) {
      if (requestedMinutes != null || map.containsKey('requested_minutes') || reason != null) {
        eventType = 'TIME_REQUEST';
      } else if (childReply != null) {
        eventType = 'DEVICE_MESSAGE_REPLY';
      } else if (map['is_acknowledged'] != null || messageText != null || map.containsKey('message_id')) {
        eventType = 'DEVICE_MESSAGE_ACK';
      } else if (isLocked != null) {
        eventType = 'PANIC_LOCKDOWN';
      } else {
        eventType = 'UNKNOWN';
      }
    }

    if (eventType == 'DEVICE_MESSAGE_ACK' && childReply != null) {
      eventType = 'DEVICE_MESSAGE_REPLY';
    }

    return ParentNotificationPayload(
      eventType: eventType,
      deviceId: deviceId,
      familyId: familyId,
      recordId: recordId,
      deviceName: deviceName,
      requestedMinutes: requestedMinutes,
      reason: reason,
      messageText: messageText,
      childReply: childReply,
      title: title,
      body: body,
      isLocked: isLocked,
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'event_type': eventType,
      if (deviceId != null) 'device_id': deviceId,
      if (familyId != null) 'family_id': familyId,
      if (recordId != null) 'record_id': recordId,
      if (deviceName != null) 'device_name': deviceName,
      if (requestedMinutes != null) 'requested_minutes': requestedMinutes,
      if (reason != null) 'reason': reason,
      if (messageText != null) 'message_text': messageText,
      if (childReply != null) 'child_reply': childReply,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (isLocked != null) 'is_locked': isLocked,
      if (timestamp != null) 'timestamp': timestamp,
    };
  }

  String toJsonString() => jsonEncode(toMap());

  static ParentNotificationPayload? fromJsonString(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) {
        return ParentNotificationPayload.fromMap(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Legacy plain string fallback ('ack_message', 'time_request', 'panic_lockdown')
      switch (rawJson.trim()) {
        case 'time_request':
          return const ParentNotificationPayload(eventType: 'TIME_REQUEST');
        case 'ack_message':
          return const ParentNotificationPayload(eventType: 'DEVICE_MESSAGE_ACK');
        case 'panic_lockdown':
          return const ParentNotificationPayload(eventType: 'PANIC_LOCKDOWN');
      }
    }
    return null;
  }

  /// Composite deduplication key so two-step ACK -> child_reply updates
  /// on the same `device_messages.id` are never suppressed.
  String? get dedupKey {
    final id = recordId?.trim();
    if (id == null || id.isEmpty) return null;
    switch (eventType) {
      case 'TIME_REQUEST':
        return 'req:$id';
      case 'DEVICE_MESSAGE_ACK':
      case 'DEVICE_MESSAGE_REPLY':
        final reply = childReply?.trim();
        if (reply != null && reply.isNotEmpty) {
          return 'reply:$id:$reply';
        }
        return 'ack:$id';
      default:
        return '${eventType.toLowerCase()}:$id';
    }
  }

  bool get isTimeRequest => eventType == 'TIME_REQUEST';
  bool get isAckOrReply =>
      eventType == 'DEVICE_MESSAGE_ACK' || eventType == 'DEVICE_MESSAGE_REPLY';
  bool get isAckMessage => isAckOrReply;

  int get notificationId => deterministicNotificationId(
        eventType: eventType,
        recordId: recordId,
        deviceId: deviceId,
      );

  NotificationCopy buildCopy({String? resolvedDeviceName}) {
    if (isTimeRequest) {
      return formatTimeRequestNotification(this, resolvedDeviceName: resolvedDeviceName);
    }
    if (isAckOrReply) {
      return formatAckNotification(this, resolvedDeviceName: resolvedDeviceName);
    }
    return NotificationCopy(
      title: title?.trim().isNotEmpty == true ? title!.trim() : 'Thông Báo Máy Con',
      body: body?.trim().isNotEmpty == true ? body!.trim() : 'Có cập nhật mới từ máy con.',
    );
  }
}

/// Deterministic positive 31-bit notification ID using FNV-1a when `recordId` is
/// present, or a collision-free monotonic fallback when `recordId` is absent.
int deterministicNotificationId({
  required String eventType,
  String? recordId,
  String? deviceId,
}) {
  final rec = recordId?.trim() ?? '';
  if (rec.isNotEmpty) {
    final input = '$eventType:$rec:${deviceId?.trim() ?? ''}';
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final positive = hash & 0x7FFFFFFF;
    return positive == 0 ? 1 : positive;
  }

  _monotonicNotificationCounter = (_monotonicNotificationCounter + 1) & 0x3FFFFFFF;
  final fallback =
      ((DateTime.now().microsecondsSinceEpoch ^ _monotonicNotificationCounter) &
          0x7FFFFFFF);
  return fallback == 0 ? 1 : fallback;
}

NotificationCopy formatAckNotification(
  ParentNotificationPayload payload, {
  String? resolvedDeviceName,
}) {
  final name = (resolvedDeviceName != null && resolvedDeviceName.trim().isNotEmpty)
      ? resolvedDeviceName.trim()
      : (payload.deviceName?.trim().isNotEmpty == true
          ? payload.deviceName!.trim()
          : 'Thiết bị con');

  final reply = payload.childReply?.trim();
  final msgText = payload.messageText?.trim();

  if (reply != null && reply.isNotEmpty) {
    final body = (msgText != null && msgText.isNotEmpty)
        ? '"$reply" (Lời nhắc: "$msgText")'
        : '"$reply"';
    return NotificationCopy(
      title: '💬 $name Đã Trả Lời!',
      body: body,
    );
  }

  final body = (msgText != null && msgText.isNotEmpty)
      ? 'Đã xác nhận: "$msgText"'
      : '$name đã xác nhận đã xem lời nhắc.';
  return NotificationCopy(
    title: '👍 $name Đã Xác Nhận!',
    body: body,
  );
}

NotificationCopy formatTimeRequestNotification(
  ParentNotificationPayload payload, {
  String? resolvedDeviceName,
}) {
  final name = (resolvedDeviceName != null && resolvedDeviceName.trim().isNotEmpty)
      ? resolvedDeviceName.trim()
      : (payload.deviceName?.trim().isNotEmpty == true
          ? payload.deviceName!.trim()
          : 'Thiết bị con');
  final mins = payload.requestedMinutes ?? 15;
  final reason = payload.reason?.trim().isNotEmpty == true
      ? payload.reason!.trim()
      : 'Con xin thêm giờ chơi';

  return NotificationCopy(
    title: '🙋 $name Xin Thêm Giờ Chơi!',
    body: 'Xin thêm +$mins phút. Lý do: "$reason"',
  );
}
