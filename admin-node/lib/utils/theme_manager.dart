import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quản lý trạng thái Theme (Hệ thống / Sáng / Tối AMOLED) chuẩn Apple Music
class ThemeManager extends ChangeNotifier {
  static const String _prefKey = 'app_theme_mode';
  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;

  /// Khởi tạo và nạp cấu hình theme đã lưu từ SharedPreferences
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString(_prefKey);
      if (modeStr == 'system') {
        _themeMode = ThemeMode.system;
      } else if (modeStr == 'light') {
        _themeMode = ThemeMode.light;
      } else {
        _themeMode = ThemeMode.dark; // Mặc định là Tối AMOLED
      }
      notifyListeners();
    } catch (e) {
      debugPrint('ThemeManager init error: $e');
    }
  }

  /// Thay đổi theme và lưu vĩnh viễn vào bộ nhớ máy
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      String val = 'dark';
      if (mode == ThemeMode.system) val = 'system';
      if (mode == ThemeMode.light) val = 'light';
      await prefs.setString(_prefKey, val);
    } catch (e) {
      debugPrint('Error saving theme: $e');
    }
  }
}

/// Global singleton instance
final ThemeManager themeManager = ThemeManager();
