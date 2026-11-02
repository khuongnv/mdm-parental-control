import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MdmSupabaseService {
  static const String defaultUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ueamgqbxgyzxruzzjofm.supabase.co',
  );
  static const String defaultAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVlYW1ncWJ4Z3l6eHJ1enpqb2ZtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM1MjQyMjAsImV4cCI6MjEwOTEwMDIyMH0.D7qTyUR-_fAMZMrjZejKuX06ZycZsMMq-9zKBpBGFFc',
  );

  static SupabaseClient get client => Supabase.instance.client;

  /// Khởi tạo Supabase SDK
  static Future<void> initialize({String? url, String? anonKey}) async {
    // ignore: deprecated_member_use
    await Supabase.initialize(
      url: url ?? defaultUrl,
      // ignore: deprecated_member_use
      anonKey: anonKey ?? defaultAnonKey,
      realtimeClientOptions: const RealtimeClientOptions(
        eventsPerSecond: 10,
      ),
    );
    debugPrint('⚡ Supabase initialized successfully: ${url ?? defaultUrl}');
  }

  /// Đảm bảo người dùng đã có phiên xác thực (hỗ trợ Anonymous auth nếu chưa đăng nhập)
  Future<String> ensureAuthenticatedUser() async {
    final current = client.auth.currentUser;
    if (current != null) {
      return current.id;
    }
    try {
      final authResponse = await client.auth.signInAnonymously();
      if (authResponse.user == null) {
        throw Exception('Không thể tạo phiên xác thực phụ huynh');
      }
      return authResponse.user!.id;
    } on AuthApiException catch (e) {
      if (e.code == 'anonymous_provider_disabled' || e.statusCode == '422') {
        throw Exception(
          'Dự án Supabase chưa bật tính năng "Anonymous sign-ins".\n'
          'Vui lòng truy cập Supabase Dashboard -> Authentication -> Providers -> Anonymous và bật "Enable".'
        );
      }
      rethrow;
    }
  }

  /// Lấy hoặc tạo Family mặc định cho phụ huynh
  Future<String> getOrCreateFamily({String familyName = 'Gia Đình Tôi'}) async {
    await ensureAuthenticatedUser();

    final families = await client.from('families').select('id, name').limit(1);
    if (families.isNotEmpty) {
      return families.first['id'] as String;
    }

    // Gọi Stored Procedure tạo family và gán quyền owner
    final newFamilyId = await client.rpc('create_or_join_family', params: {
      'p_family_name': familyName,
    });

    return newFamilyId.toString();
  }

  /// Phụ huynh nhận quyền kiểm soát máy con bằng mã OTP 6 số (Claim Pairing)
  Future<Map<String, dynamic>> claimDevice(String otpCode, {String familyName = 'Gia Đình Tôi'}) async {
    final familyId = await getOrCreateFamily(familyName: familyName);

    final response = await client.rpc('claim_device_pairing', params: {
      'p_otp_code': otpCode.trim(),
      'p_family_id': familyId,
    });

    if (response is List && response.isNotEmpty) {
      final result = response.first as Map<String, dynamic>;
      if (result['success'] == true) {
        final deviceId = result['device_id']?.toString();
        if (deviceId != null) {
          try {
            final channel = client.channel('device:$deviceId');
            channel.subscribe((status, [error]) async {
              if (status == RealtimeSubscribeStatus.subscribed) {
                await channel.sendBroadcastMessage(
                  event: 'PAIRING_SUCCESS',
                  payload: {
                    'device_id': deviceId,
                    'family_id': familyId,
                    'message': 'Ghép nối thiết bị thành công',
                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                  },
                );
              }
            });
          } catch (e) {
            debugPrint('⚠️ Error sending realtime pairing broadcast: $e');
          }
        }
        return result;
      } else {
        throw Exception(result['message'] ?? 'Ghép nối thất bại');
      }
    } else if (response is Map<String, dynamic>) {
      if (response['success'] == true) {
        final deviceId = response['device_id']?.toString();
        if (deviceId != null) {
          try {
            final channel = client.channel('device:$deviceId');
            channel.subscribe((status, [error]) async {
              if (status == RealtimeSubscribeStatus.subscribed) {
                await channel.sendBroadcastMessage(
                  event: 'PAIRING_SUCCESS',
                  payload: {
                    'device_id': deviceId,
                    'family_id': familyId,
                    'message': 'Ghép nối thiết bị thành công',
                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                  },
                );
              }
            });
          } catch (e) {
            debugPrint('⚠️ Error sending realtime pairing broadcast: $e');
          }
        }
        return response;
      } else {
        throw Exception(response['message'] ?? 'Ghép nối thất bại');
      }
    }

    throw Exception('Phản hồi không hợp lệ từ máy chủ');
  }

  /// Lấy danh sách thiết bị con của gia đình
  Future<List<Map<String, dynamic>>> getFamilyDevices() async {
    final familyId = await getOrCreateFamily();
    final data = await client
        .from('devices')
        .select('*, policies(*)')
        .eq('family_id', familyId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  /// Lắng nghe cập nhật danh sách thiết bị thời gian thực (Postgres Changes)
  Stream<List<Map<String, dynamic>>> streamFamilyDevices(String familyId) {
    return client
        .from('devices')
        .stream(primaryKey: ['id'])
        .eq('family_id', familyId)
        .map((list) => List<Map<String, dynamic>>.from(list));
  }

  /// Kích hoạt Khóa Khẩn Cấp tức thì qua Broadcast và cập nhật DB
  Future<void> triggerPanicLockdown(String deviceId, bool isLocked) async {
    // 1. Cập nhật trạng thái trực tiếp vào bảng devices
    await client.from('devices').update({
      'is_locked': isLocked,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', deviceId);

    // 2. Phát thông điệp Broadcast qua Realtime Channel
    try {
      final channel = client.channel('device:$deviceId');
      channel.subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await channel.sendBroadcastMessage(
            event: 'PANIC_LOCKDOWN',
            payload: {
              'device_id': deviceId,
              'is_locked': isLocked,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            },
          );
        }
      });
    } catch (e) {
      debugPrint('⚠️ Error sending realtime broadcast: $e');
    }
  }

  /// Cấp thêm thời gian sử dụng nhanh (+15m, +30m, +60m)
  Future<void> grantExtraTime(String deviceId, int extraMinutes) async {
    // 1. Lấy số phút thưởng hiện tại để cộng dồn
    int currentExtra = 0;
    try {
      final dev = await client.from('devices').select('extra_time_minutes').eq('id', deviceId).maybeSingle();
      if (dev != null && dev['extra_time_minutes'] != null) {
        currentExtra = (dev['extra_time_minutes'] as num).toInt();
      }
    } catch (_) {}

    final newExtra = currentExtra + extraMinutes;

    // 2. Cập nhật số phút thưởng vào bảng devices
    await client.from('devices').update({
      'extra_time_minutes': newExtra,
      'is_locked': false, // Thưởng giờ tự động mở khóa nếu đang bị khóa
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', deviceId);

    // 3. Phát thông điệp Broadcast
    try {
      final channel = client.channel('device:$deviceId');
      channel.subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await channel.sendBroadcastMessage(
            event: 'GRANT_EXTRA_TIME',
            payload: {
              'device_id': deviceId,
              'extra_minutes': extraMinutes,
              'total_extra_minutes': newExtra,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            },
          );
        }
      });
    } catch (e) {
      debugPrint('⚠️ Error sending extra time broadcast: $e');
    }
  }

  /// Lắng nghe Presence (Online/Offline) của máy con
  RealtimeChannel subscribeDevicePresence(String deviceId, {required Function(bool isOnline, Map<String, dynamic>? meta) onStatusChanged}) {
    final channel = client.channel('device:$deviceId');

    channel.onPresenceSync((_) {
      final presenceList = channel.presenceState();
      final isOnline = presenceList.isNotEmpty;
      Map<String, dynamic>? meta;
      if (isOnline && presenceList.first.presences.isNotEmpty) {
        meta = presenceList.first.presences.first.payload;
      }
      onStatusChanged(isOnline, meta);
    });

    channel.subscribe();
    return channel;
  }

  /// Đổi tên gợi nhớ cho máy con (P2-ADMIN-01)
  Future<void> renameDevice(String deviceId, String customName) async {
    try {
      await client.from('devices').update({
        'custom_name': customName.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', deviceId);
    } catch (_) {
      // Fallback if custom_name not yet migrated
      await client.from('devices').update({
        'device_name': customName.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', deviceId);
    }

    try {
      final channel = client.channel('device:$deviceId');
      channel.subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await channel.sendBroadcastMessage(
            event: 'DEVICE_RENAMED',
            payload: {
              'device_id': deviceId,
              'custom_name': customName.trim(),
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            },
          );
        }
      });
    } catch (e) {
      debugPrint('⚠️ Error sending rename broadcast: $e');
    }
  }

  /// Thưởng / Phạt thời gian động (+/- deltaMinutes) (P2-CHILD-01 & P2-ADMIN)
  Future<void> adjustScreenTime(String deviceId, int deltaMinutes, {String? reason}) async {
    int currentExtra = 0;
    try {
      final dev = await client.from('devices').select('extra_time_minutes').eq('id', deviceId).maybeSingle();
      if (dev != null && dev['extra_time_minutes'] != null) {
        currentExtra = (dev['extra_time_minutes'] as num).toInt();
      }
    } catch (_) {}

    final newExtra = (currentExtra + deltaMinutes).clamp(0, 9999);

    await client.from('devices').update({
      'extra_time_minutes': newExtra,
      if (deltaMinutes > 0) 'is_locked': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', deviceId);

    try {
      final channel = client.channel('device:$deviceId');
      channel.subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await channel.sendBroadcastMessage(
            event: 'ADJUST_SCREEN_TIME',
            payload: {
              'device_id': deviceId,
              'delta_minutes': deltaMinutes,
              'total_extra_minutes': newExtra,
              'reason': reason ?? (deltaMinutes >= 0 ? 'Thưởng giờ chơi' : 'Phạt trừ giờ chơi'),
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            },
          );
        }
      });
    } catch (e) {
      debugPrint('⚠️ Error sending adjust screen time broadcast: $e');
    }
  }

  /// Hủy quyền quản lý thiết bị (P2-ADMIN-03)
  Future<void> revokeDeviceManagement(String deviceId) async {
    try {
      await client.rpc('revoke_device_management', params: {
        'p_device_id': deviceId,
      });
    } catch (_) {
      // Fallback direct update
      await client.from('devices').update({
        'family_id': null,
        'status': 'revoked',
        'is_locked': false,
        'extra_time_minutes': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', deviceId);
    }

    try {
      final channel = client.channel('device:$deviceId');
      channel.subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await channel.sendBroadcastMessage(
            event: 'DEVICE_UNPAIRED',
            payload: {
              'device_id': deviceId,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            },
          );
        }
      });
    } catch (e) {
      debugPrint('⚠️ Error sending unpair broadcast: $e');
    }
  }

  /// Gửi tin nhắn / Mẫu câu nhắc nhở tới máy con (P2-ADMIN-06)
  Future<void> sendRemoteMessage(
    String deviceId, {
    required String title,
    required String body,
    String? templateKey,
  }) async {
    String messageId = DateTime.now().millisecondsSinceEpoch.toString();

    // 1. Lưu vào bảng device_messages (để lưu vết lịch sử trong DB)
    try {
      final familyId = await getOrCreateFamily();
      final inserted = await client.from('device_messages').insert({
        'device_id': deviceId,
        'family_id': familyId,
        'template_key': templateKey ?? 'custom',
        'message_text': body,
      }).select('id').maybeSingle();
      if (inserted != null && inserted['id'] != null) {
        messageId = inserted['id'] as String;
      }
    } catch (e) {
      debugPrint('⚠️ Error saving to device_messages: $e');
    }

    // 2. Broadcast tới máy con qua Phoenix Realtime
    try {
      final channel = client.channel('device:$deviceId');
      final payload = {
        'message_id': messageId,
        'device_id': deviceId,
        'title': title,
        'body': body,
        'template_key': templateKey ?? 'custom',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Gửi ngay nếu channel đã sẵn sàng
      channel.sendBroadcastMessage(
        event: 'REMOTE_MESSAGE',
        payload: payload,
      );

      // Đăng ký callback nếu chưa kết nối xong
      channel.subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await channel.sendBroadcastMessage(
            event: 'REMOTE_MESSAGE',
            payload: payload,
          );
        }
      });
    } catch (e) {
      debugPrint('⚠️ Error sending remote message broadcast: $e');
    }
  }

  /// Tạo mã mời Co-Admin 6 số / QR (P2-ADMIN-04)
  Future<Map<String, dynamic>> createFamilyInvite({String role = 'parent'}) async {
    final familyId = await getOrCreateFamily();
    try {
      final res = await client.rpc('create_family_invite', params: {
        'p_family_id': familyId,
        'p_role': role,
      });
      if (res is Map<String, dynamic>) return res;
    } catch (_) {}

    // Fallback code
    final code = 'FAM-${(1000 + DateTime.now().millisecond).toString()}';
    return {
      'invite_code': code,
      'family_id': familyId,
      'expires_at': DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
    };
  }

  /// Nhập mã tham gia gia đình Co-Admin (P2-ADMIN-04)
  Future<Map<String, dynamic>> joinFamilyByCode(String code) async {
    await ensureAuthenticatedUser();
    try {
      final res = await client.rpc('join_family_by_code', params: {
        'p_invite_code': code.trim(),
      });
      if (res is Map<String, dynamic>) return res;
    } catch (e) {
      throw Exception('Mã mời không hợp lệ hoặc đã hết hạn: $e');
    }
    return {'success': true, 'message': 'Tham gia gia đình thành công'};
  }

  /// Cập nhật quy tắc giới hạn giờ (Ngày / Tuần & Hạn mức) (P2-ADMIN-05)
  Future<void> updateDevicePolicy(
    String deviceId, {
    required String ruleType,
    required int dailyLimitMins,
    int? weeklyLimitMins,
    Map<String, int>? weekdayLimits,
  }) async {
    final updateData = <String, dynamic>{
      'daily_screen_time_limit_mins': dailyLimitMins,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      final policyMap = <String, dynamic>{
        ...updateData,
        'rule_type': ruleType,
      };
      if (weeklyLimitMins != null) {
        policyMap['weekly_screen_time_limit_mins'] = weeklyLimitMins;
      }
      if (weekdayLimits != null) {
        policyMap['weekday_limits'] = weekdayLimits;
      }
      await client.from('policies').update(policyMap).eq('device_id', deviceId);
    } catch (_) {
      // Fallback if extra columns not yet in DB
      await client.from('policies').update(updateData).eq('device_id', deviceId);
    }

    try {
      final channel = client.channel('device:$deviceId');
      channel.subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await channel.sendBroadcastMessage(
            event: 'APPLY_POLICY_UPDATE',
            payload: {
              'device_id': deviceId,
              'daily_limit_mins': dailyLimitMins,
              'rule_type': ruleType,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            },
          );
        }
      });
    } catch (_) {}
  }

  /// Duyệt hoặc từ chối yêu cầu xin thêm giờ của bé (P2-CHILD-02)
  Future<void> resolveTimeRequest(
    String deviceId, {
    required bool approve,
    int grantedMinutes = 15,
  }) async {
    if (approve) {
      await grantExtraTime(deviceId, grantedMinutes);
    }

    try {
      final channel = client.channel('device:$deviceId');
      channel.subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await channel.sendBroadcastMessage(
            event: 'TIME_REQUEST_RESOLVED',
            payload: {
              'device_id': deviceId,
              'status': approve ? 'approved' : 'rejected',
              'granted_minutes': approve ? grantedMinutes : 0,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            },
          );
        }
      });
    } catch (_) {}
  }
}
