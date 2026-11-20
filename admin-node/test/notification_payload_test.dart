import 'package:flutter_test/flutter_test.dart';
import 'package:mdm_admin_app/models/notification_payload.dart';

void main() {
  group('ParentNotificationPayload Tests', () {
    test('Parses time request FCM payload and builds copy', () {
      final payloadMap = {
        'event_type': 'TIME_REQUEST',
        'device_id': 'dev_123',
        'device_name': 'Bé Nam',
        'requested_minutes': 30,
        'reason': 'Con làm xong bài tập rồi',
        'record_id': 'req_999',
      };

      final payload = ParentNotificationPayload.fromMap(payloadMap);

      expect(payload.isTimeRequest, isTrue);
      expect(payload.dedupKey, 'req:req_999');

      final copy = payload.buildCopy();
      expect(copy.title, contains('Bé Nam Xin Thêm Giờ'));
      expect(copy.body, contains('+30 phút'));
      expect(copy.body, contains('Con làm xong bài tập'));
      expect(payload.notificationId, isPositive);
    });

    test('Parses ack message FCM payload and builds copy', () {
      final payloadMap = {
        'event_type': 'DEVICE_MESSAGE_ACK',
        'device_id': 'dev_123',
        'device_name': 'Bé Nam',
        'message_text': 'Mau đi ngủ đi con',
        'child_reply': 'Dạ con nghe rồi!',
        'record_id': 'msg_888',
      };

      final payload = ParentNotificationPayload.fromMap(payloadMap);

      expect(payload.isAckMessage, isTrue);
      expect(payload.dedupKey, 'reply:msg_888:Dạ con nghe rồi!');

      final copy = payload.buildCopy();
      expect(copy.title, contains('Bé Nam Đã Trả Lời'));
      expect(copy.body, contains('Dạ con nghe rồi!'));
      expect(payload.notificationId, isPositive);
    });
  });
}
