import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart' hide AppleNotification;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_payload.dart';
import 'notification_deduplicator.dart';
import 'system_notification_service.dart';
import 'mdm_supabase_service.dart';

/// Top-level FCM Background Message Handler (R1)
@pragma('vm:entry-point')
Future<void> fcmBackgroundMessageHandler(RemoteMessage message) async {
  debugPrint('📥 FCM Background message received: ${message.messageId}, data: ${message.data}');
  try {
    final payload = ParentNotificationPayload.fromMap(message.data);
    final dedupKey = payload.dedupKey ??
        (payload.recordId != null && payload.recordId!.isNotEmpty
            ? '${payload.eventType}:${payload.recordId}'
            : 'fcm:${message.messageId}');
    final acquired = await NotificationDeduplicator.instance.tryAcquire(dedupKey);
    if (!acquired) {
      debugPrint('⏭️ FCM background message already processed ($dedupKey), skipping duplicate tray notification');
      return;
    }
    final copy = payload.buildCopy();
    await SystemNotificationService().showNotification(
      id: payload.notificationId,
      title: copy.title,
      body: copy.body,
      payload: message.data['record_id']?.toString(),
    );
  } catch (e) {
    debugPrint('⚠️ Error in fcmBackgroundMessageHandler: $e');
  }
}

/// Centralized FCM Push Notification Service for Parent Admin App (R1).
///
/// Encapsulates permission request, token registration via `upsert_parent_push_token`,
/// persistent deduplication using `NotificationDeduplicator` (`SharedPreferences`),
/// and message routing to local notification center and in-app HUDs.
class FcmNotificationService {
  FcmNotificationService._internal();
  static final FcmNotificationService instance = FcmNotificationService._internal();

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  StreamSubscription<String>? _tokenRefreshSub;

  void Function(Map<String, dynamic> data)? onNotificationTapped;
  void Function(RemoteMessage message)? onForegroundMessage;

  Future<void> initialize() async {
    try {
      if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) return;
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      FirebaseMessaging.onBackgroundMessage(fcmBackgroundMessageHandler);
      debugPrint('⚡ FcmNotificationService background handler registered');
    } catch (e) {
      debugPrint('⚠️ FcmNotificationService.initialize error: $e');
    }
  }

  Future<void> startListening({
    void Function(Map<String, dynamic> data)? onTapped,
    void Function(RemoteMessage message)? onForeground,
  }) async {
    onNotificationTapped = onTapped;
    onForegroundMessage = onForeground;

    try {
      if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) return;
      if (Firebase.apps.isEmpty) return;

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await registerToken(token);
      }

      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) {
        registerToken(newToken);
      });

      _foregroundSub?.cancel();
      _foregroundSub = FirebaseMessaging.onMessage.listen((msg) {
        onForegroundMessage?.call(msg);
      });

      _openedAppSub?.cancel();
      _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        onNotificationTapped?.call(msg.data);
      });

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        onNotificationTapped?.call(initialMessage.data);
      }
    } catch (e) {
      debugPrint('⚠️ FcmNotificationService.startListening error: $e');
    }
  }

  Future<void> registerToken(String token) async {
    final platform = Platform.isIOS ? 'ios' : (Platform.isMacOS ? 'macos' : 'android');
    await MdmSupabaseService.registerParentPushToken(
      token,
      platform: platform,
      deviceLabel: 'Parent ${Platform.operatingSystem}',
    );
  }

  void dispose() {
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
    _tokenRefreshSub?.cancel();
  }
}
