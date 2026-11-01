import 'dart:async';
import 'mdm_supabase_service.dart';

/// Adapter duy trì tính tương thích ngược, chuyển tiếp toàn bộ sang MdmSupabaseService
class MdmApiService {
  final MdmSupabaseService _supabase = MdmSupabaseService();

  MdmApiService({String baseUrl = ''});

  Future<Map<String, dynamic>> claimDevice(String otp, {String familyName = 'Gia Đình'}) {
    return _supabase.claimDevice(otp, familyName: familyName);
  }

  void triggerPanicLockdown(String deviceId, bool lockState) {
    _supabase.triggerPanicLockdown(deviceId, lockState);
  }

  void grantExtraTime(String deviceId, int minutes) {
    _supabase.grantExtraTime(deviceId, minutes);
  }

  void connectSignalR(String familyId, {Function(bool)? onPanicLockdown}) {
    // Với Supabase, lắng nghe trực tiếp qua Realtime stream/broadcast
  }

  void dispose() {}
}
