import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class MdmApiService {
  final String baseUrl;
  WebSocketChannel? _channel;

  MdmApiService({this.baseUrl = 'http://localhost:5000'});

  /// Bước 2: Phụ huynh claim quyền kiểm soát máy con qua mã OTP
  Future<Map<String, dynamic>> claimDevice(String otp, {String familyName = 'Gia Đình'}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/pairing/claim'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'otp': otp, 'familyName': familyName}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Claim thất bại: ${response.body}');
    }
  }

  /// Khởi tạo kết nối thời gian thực SignalR qua WebSocket native protocol (< 3s latency)
  void connectSignalR(String familyId, {Function(bool)? onPanicLockdown}) {
    final wsUrl = baseUrl.replaceFirst('http', 'ws');
    final uri = Uri.parse('$wsUrl/hubs/mdm');

    try {
      _channel = WebSocketChannel.connect(uri);

      // SignalR Handshake protocol JSON
      _channel?.sink.add('{"protocol":"json","version":1}\u001e');

      // Đăng ký nhóm gia đình
      final registerMsg = {
        "type": 1,
        "target": "RegisterParent",
        "arguments": [familyId]
      };
      _channel?.sink.add('${jsonEncode(registerMsg)}\u001e');

      _channel?.stream.listen((message) {
        if (message is String) {
          final cleanMessages = message.split('\u001e').where((m) => m.trim().isNotEmpty);
          for (final raw in cleanMessages) {
            try {
              final data = jsonDecode(raw);
              if (data['target'] == 'ReceivePanicLockdown' && data['arguments'] != null) {
                final isLocked = data['arguments'][0] as bool;
                onPanicLockdown?.call(isLocked);
              }
            } catch (_) {}
          }
        }
      });
    } catch (e) {
      // Fallback
    }
  }

  /// Kích hoạt lệnh Khóa khẩn cấp tức thì tới máy con
  void triggerPanicLockdown(String deviceId, bool lockState) {
    final msg = {
      "type": 1,
      "target": "TriggerPanicLockdown",
      "arguments": [deviceId, lockState]
    };
    _channel?.sink.add('${jsonEncode(msg)}\u001e');
  }

  /// Cấp thêm thời gian sử dụng nhanh (+15m, +30m)
  void grantExtraTime(String deviceId, int minutes) {
    final msg = {
      "type": 1,
      "target": "GrantExtraTime",
      "arguments": [deviceId, minutes]
    };
    _channel?.sink.add('${jsonEncode(msg)}\u001e');
  }

  void dispose() {
    _channel?.sink.close();
  }
}
