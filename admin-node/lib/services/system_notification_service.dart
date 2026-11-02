import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Dịch vụ quản lý thông báo hệ thống (System Notification Center) cho ứng dụng VFam Admin
class SystemNotificationService {
  static final SystemNotificationService _instance = SystemNotificationService._internal();
  factory SystemNotificationService() => _instance;
  SystemNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  static const String channelId = 'vfam_admin_alerts';
  static const String channelName = 'Thông Báo VFam Phụ Huynh';
  static const String channelDesc = 'Thông báo phản hồi, yêu cầu xin thêm giờ và cảnh báo từ máy con';

  /// Khởi tạo plugin thông báo hệ thống và tạo Notification Channel
  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _notificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('🔔 System notification clicked: ${response.payload}');
      },
    );

    // Tạo Notification Channel ưu tiên cao cho Android 8.0+
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDesc,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );

      // Yêu cầu cấp quyền POST_NOTIFICATIONS trên Android 13+
      await androidImplementation.requestNotificationsPermission();
    }

    _isInitialized = true;
    debugPrint('⚡ SystemNotificationService initialized successfully');
  }

  /// Hiển thị thông báo trên Trung tâm thông báo hệ thống (Status Bar / Notification Tray)
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
        ),
        icon: '@mipmap/ic_launcher',
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      await _notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint('⚠️ Error displaying system notification: $e');
    }
  }

  /// Thông báo: Bé đã phản hồi xác nhận tin nhắn nhắc nhở
  Future<void> showAckNotification({
    required String deviceName,
    required String message,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await showNotification(
      id: id,
      title: 'Bé Đã Phản Hồi! 👍',
      body: '$deviceName: "$message"',
      payload: 'ack_message',
    );
  }

  /// Thông báo: Bé gửi yêu cầu xin thêm thời gian sử dụng
  Future<void> showTimeRequestNotification({
    required String deviceName,
    required int requestedMinutes,
    required String reason,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await showNotification(
      id: id,
      title: '🙋 $deviceName Xin Thêm Giờ Chơi!',
      body: 'Xin thêm +$requestedMinutes phút. Lý do: "$reason"',
      payload: 'time_request',
    );
  }

  /// Thông báo: Cảnh báo thiết bị / Khóa khẩn cấp
  Future<void> showLockdownNotification({
    required String deviceName,
    required bool isLocked,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await showNotification(
      id: id,
      title: isLocked ? '🚨 $deviceName Đã Bị Khóa!' : '🔓 $deviceName Đã Được Mở Khóa',
      body: isLocked
          ? 'Chế độ khóa khẩn cấp đang được kích hoạt.'
          : 'Thiết bị đã trở lại trạng thái bình thường.',
      payload: 'panic_lockdown',
    );
  }
}
