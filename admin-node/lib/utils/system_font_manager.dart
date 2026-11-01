import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Quản lý nạp font chữ hệ thống nguyên bản từ thiết bị Android (Samsung One UI, Pixel, v.v.)
/// Đảm bảo giao diện chữ đồng nhất 100% với native Jetpack Compose.
class SystemFontManager {
  static const MethodChannel _channel = MethodChannel('vn.hanoi.khuongnv.vfam.admin/system_font');

  static String _fontFamily = 'sans-serif';
  static bool _loaded = false;

  static String get fontFamily => _fontFamily;
  static bool get isLoaded => _loaded;

  /// Tự động đọc và nạp font hệ thống Android gốc vào Flutter FontLoader
  static Future<void> init() async {
    if (kIsWeb) return;

    try {
      final dynamic rawData = await _channel.invokeMethod('getSystemFontData');
      if (rawData is Map) {
        final Uint8List? regularBytes = rawData['regular'];
        final Uint8List? boldBytes = rawData['bold'];

        if (regularBytes != null && regularBytes.isNotEmpty) {
          final fontLoader = FontLoader('AndroidSystemFont');
          fontLoader.addFont(Future.value(ByteData.view(regularBytes.buffer)));
          if (boldBytes != null && boldBytes.isNotEmpty) {
            fontLoader.addFont(Future.value(ByteData.view(boldBytes.buffer)));
          }
          await fontLoader.load();
          _fontFamily = 'AndroidSystemFont';
          _loaded = true;
          debugPrint('>>> Đã nạp thành công Android System Font vào Flutter Engine: AndroidSystemFont');
        }
      }
    } catch (e) {
      debugPrint('>>> Không thể nạp font hệ thống Android: $e');
      _fontFamily = 'sans-serif';
    }
  }
}
