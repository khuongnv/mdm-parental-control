import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/mdm_supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/activity_history_service.dart';
import 'services/github_release_updater.dart';
import 'services/system_notification_service.dart';
import 'widgets/apple_notification.dart';
import 'widgets/qr_pairing_sheet.dart';
import 'utils/system_font_manager.dart';
import 'utils/theme_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Nạp font chữ hệ thống Android gốc (Samsung One UI, Pixel, v.v.)
  await SystemFontManager.init();
  // Nạp cấu hình theme (Hệ thống / Sáng / Tối AMOLED)
  await themeManager.init();
  // Khởi tạo dịch vụ thông báo trung tâm hệ thống (System Notification Center)
  try {
    await SystemNotificationService().initialize();
  } catch (e) {
    debugPrint('SystemNotification init error: $e');
  }
  try {
    await MdmSupabaseService.initialize();
  } catch (e) {
    debugPrint('Supabase init error: $e');
  }
  // Khởi động dịch vụ chạy ngầm duy trì socket liên tục khi khóa màn hình
  try {
    const MethodChannel('vn.hanoi.khuongnv.vfam.admin/updater').invokeMethod('startBackgroundService');
  } catch (e) {
    debugPrint('Start background service error: $e');
  }
  runApp(const MdmParentApp());
}

/// Tiện ích hỗ trợ lấy màu sắc ngữ cảnh theo Theme (Sáng / Tối)
extension ThemeHelper on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get surfaceColor => isDark ? AppleTheme.glassSurface : AppleTheme.lightSurface;
  Color get surfaceVariantColor => isDark ? AppleTheme.darkSurfaceVariant : AppleTheme.lightSurfaceVariant;
  Color get backgroundColor => isDark ? AppleTheme.darkBackground : AppleTheme.lightBackground;
  Color get textPrimaryColor => isDark ? AppleTheme.textPrimaryDark : AppleTheme.textPrimaryLight;
  Color get textSecondaryColor => AppleTheme.textSecondary;
  Color get borderColor => isDark ? AppleTheme.glassBorder : AppleTheme.lightBorder;
  Color get hairlineDividerColor => isDark ? AppleTheme.hairlineDivider : AppleTheme.lightHairlineDivider;
}

/// Hệ màu và kiểu dáng chuẩn Apple Music UI/UX Design System
class AppleTheme {
  // Bảng màu Accent Apple Music
  static const Color appleRed = Color(0xFFFA2D55); // Apple Music Red
  static const Color appleBlue = Color(0xFF007AFF); // iOS System Blue
  static const Color appleGreen = Color(0xFF34C759); // iOS System Green
  static const Color appleAmber = Color(0xFFFF9500); // iOS System Orange
  static const Color applePurple = Color(0xFFAF52DE); // iOS System Purple

  // Nền đen sâu chuẩn AMOLED (Dark Theme)
  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF1C1C1E); // iOS secondarySystemBackground
  static const Color darkSurfaceVariant = Color(0xFF2C2C2E); // iOS tertiarySystemBackground
  static const Color darkSurfaceElevated = Color(0xFF2C2C2E);
  static const Color glassSurface = Color(0xEE1E1E22);
  static const Color glassBorder = Color(0x33FFFFFF);
  static const Color hairlineDivider = Color(0xFF38383A);

  // Nền sáng chuẩn iOS (Light Theme)
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFF2F2F7); // iOS .systemGray6
  static const Color lightSurfaceVariant = Color(0xFFE5E5EA); // iOS .systemGray5
  static const Color lightBorder = Color(0xFFE5E5EA);
  static const Color lightHairlineDivider = Color(0xFFE5E5EA);

  // Màu văn bản phân cấp
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textPrimaryLight = Color(0xFF000000);
  static const Color textSecondary = Color(0xFF8E8E93); // Gray93
  static const Color textPrimary = Color(0xFFFFFFFF); // Giữ tương thích ngược

  static Color surface(BuildContext context) => context.surfaceColor;
  static Color surfaceVariant(BuildContext context) => context.surfaceVariantColor;
  static Color border(BuildContext context) => context.borderColor;
  static Color textPrimaryOf(BuildContext context) => context.textPrimaryColor;
  static Color background(BuildContext context) => context.backgroundColor;
  static Color hairline(BuildContext context) => context.hairlineDividerColor;

  static ThemeData buildDarkTheme() {
    const fontFam = AppleTypography.fontFamily;
    const fontFallback = AppleTypography.fontFamilyFallback;

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      fontFamily: fontFam,
      fontFamilyFallback: fontFallback,
      typography: Typography.material2021(platform: TargetPlatform.android),
      textTheme: const TextTheme(
        displayLarge: AppleTypography.displayLarge,
        headlineLarge: AppleTypography.headlineLarge,
        titleLarge: AppleTypography.titleLarge,
        bodyLarge: AppleTypography.bodyLarge,
        bodyMedium: AppleTypography.bodyMedium,
        labelSmall: AppleTypography.labelSmall,
      ).apply(
        bodyColor: textPrimaryDark,
        displayColor: textPrimaryDark,
        fontFamily: fontFam,
        fontFamilyFallback: fontFallback,
      ),
      colorScheme: const ColorScheme.dark(
        primary: appleRed,
        secondary: appleBlue,
        surface: glassSurface,
        surfaceContainerHighest: darkSurfaceVariant,
        onSurface: textPrimaryDark,
        onSurfaceVariant: textSecondary,
      ),
      cardTheme: CardThemeData(
        color: glassSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: glassBorder, width: 0.75),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: glassSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: glassBorder, width: 0.75),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: AppleTypography.titleLarge.copyWith(color: textPrimaryDark),
      ),
      useMaterial3: true,
    );
  }

  static ThemeData buildLightTheme() {
    const fontFam = AppleTypography.fontFamily;
    const fontFallback = AppleTypography.fontFamilyFallback;

    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      fontFamily: fontFam,
      fontFamilyFallback: fontFallback,
      typography: Typography.material2021(platform: TargetPlatform.android),
      textTheme: const TextTheme(
        displayLarge: AppleTypography.displayLarge,
        headlineLarge: AppleTypography.headlineLarge,
        titleLarge: AppleTypography.titleLarge,
        bodyLarge: AppleTypography.bodyLarge,
        bodyMedium: AppleTypography.bodyMedium,
        labelSmall: AppleTypography.labelSmall,
      ).apply(
        bodyColor: textPrimaryLight,
        displayColor: textPrimaryLight,
        fontFamily: fontFam,
        fontFamilyFallback: fontFallback,
      ),
      colorScheme: const ColorScheme.light(
        primary: appleRed,
        secondary: appleBlue,
        surface: lightSurface,
        surfaceContainerHighest: lightSurfaceVariant,
        onSurface: textPrimaryLight,
        onSurfaceVariant: textSecondary,
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: lightBorder, width: 0.75),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: lightBorder, width: 0.75),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: lightBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        titleTextStyle: AppleTypography.titleLarge.copyWith(color: textPrimaryLight),
      ),
      useMaterial3: true,
    );
  }
}

/// Hệ Typography SF Pro Display đóng gói trực tiếp chuẩn Apple Music UI
class AppleTypography {
  static const String fontFamily = 'SFProDisplay';
  static const List<String> fontFamilyFallback = [
    'SFProDisplay',
    'sans-serif',
    'sans-serif-medium',
    'Roboto',
  ];

  // Large Title (displayLarge) cho header: 34sp Bold, letterSpacing 0.37sp, lineHeight 41sp
  static const TextStyle displayLarge = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.37,
    height: 41 / 34,
  );

  // Section headers (headlineLarge): 22sp SemiBold, letterSpacing 0.35sp, lineHeight 28sp
  static const TextStyle headlineLarge = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.35,
    height: 28 / 22,
  );

  // Sub-headers or stats (titleLarge): 20sp SemiBold, letterSpacing 0.38sp, lineHeight 25sp
  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.38,
    height: 25 / 20,
  );

  // List item primary text (bodyLarge): 17sp, letterSpacing -0.41sp, lineHeight 22sp
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.41,
    height: 22 / 17,
  );

  // List item secondary text (bodyMedium): 15sp, letterSpacing -0.24sp, lineHeight 20sp
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.24,
    height: 20 / 15,
    color: AppleTheme.textSecondary,
  );

  // Small labels/captions (labelSmall): 12sp Medium, letterSpacing 0sp, lineHeight 16sp
  static const TextStyle labelSmall = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 16 / 12,
    color: AppleTheme.textSecondary,
  );
}

class MdmParentApp extends StatelessWidget {
  const MdmParentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeManager,
      builder: (context, _) {
        return MaterialApp(
          title: 'VFam Admin',
          debugShowCheckedModeBanner: false,
          themeMode: themeManager.themeMode,
          theme: AppleTheme.buildLightTheme(),
          darkTheme: AppleTheme.buildDarkTheme(),
          home: const MainNavigationScreen(),
        );
      },
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final GlobalKey<_DashboardTabState> _dashboardKey = GlobalKey<_DashboardTabState>();
  final GlobalKey<_HistoryTabState> _historyKey = GlobalKey<_HistoryTabState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.backgroundColor,
      // Cho phép nội dung cuộn bên dưới thanh điều hướng nổi
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DashboardTab(
            key: _dashboardKey,
            onActionLogged: () => _historyKey.currentState?.refresh(),
          ),
          HistoryTab(key: _historyKey),
          const SettingsTab(),
        ],
      ),
      bottomNavigationBar: _buildFloatingBottomNavBar(),
    );
  }

  /// Thanh điều hướng nổi Liquid Glass chuẩn Apple Music
  Widget _buildFloatingBottomNavBar() {
    final isDark = context.isDark;
    return SafeArea(
      top: false,
      bottom: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? AppleTheme.glassSurface : AppleTheme.lightSurface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: context.borderColor, width: 0.75),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, Icons.shield_rounded, Icons.shield_outlined, 'Giám Sát'),
            _buildNavItem(1, Icons.auto_awesome_rounded, Icons.auto_awesome_outlined, 'Lịch Sử'),
            _buildNavItem(2, Icons.settings_rounded, Icons.settings_outlined, 'Cài Đặt'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _currentIndex = index);
          if (index == 1) _historyKey.currentState?.refresh();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? AppleTheme.appleRed.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppleTheme.appleRed.withValues(alpha: 0.28) : Colors.transparent,
              width: 0.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? activeIcon : inactiveIcon,
                color: isSelected ? AppleTheme.appleRed : AppleTheme.textSecondary,
                size: 22,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppleTypography.fontFamily,
                  fontFamilyFallback: AppleTypography.fontFamilyFallback,
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppleTheme.appleRed : AppleTheme.textSecondary,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// TAB 1: GIÁM SÁT THỜI GIAN THỰC (APPLE STYLE DASHBOARD)
// ==============================================================================

class DashboardTab extends StatefulWidget {
  final VoidCallback onActionLogged;

  const DashboardTab({super.key, required this.onActionLogged});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final MdmSupabaseService _supabaseService = MdmSupabaseService();

  List<Map<String, dynamic>> familyDevices = [];
  Map<String, dynamic>? activeDevice;
  bool isEmergencyLocked = false;
  bool isOnline = true;
  int extraTimeMinutes = 0;
  bool isLoading = true;
  String? errorMessage;

  // Live Telemetry (P2-ADMIN-02)
  String? currentAppName;
  int? batteryLevel;
  bool isCharging = false;
  int dailyLimitMinutes = 120;
  String quotaMode = 'daily';

  RealtimeChannel? _deviceRealtimeChannel;

  @override
  void initState() {
    super.initState();
    _loadDeviceData();
  }

  @override
  void dispose() {
    _deviceRealtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadDeviceData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final devices = await _supabaseService.getFamilyDevices();
      if (mounted) {
        setState(() {
          familyDevices = devices;
          isLoading = false;
        });

        if (devices.isNotEmpty) {
          final currentId = activeDevice?['id'];
          final match = devices.firstWhere(
            (d) => d['id'] == currentId,
            orElse: () => devices.first,
          );
          _selectDevice(match);
        } else {
          setState(() {
            activeDevice = null;
            isOnline = false;
            currentAppName = null;
            batteryLevel = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString().replaceFirst('Exception: ', '');
          isLoading = false;
        });
      }
    }
  }

  void _selectDevice(Map<String, dynamic> dev) {
    setState(() {
      activeDevice = dev;
      isEmergencyLocked = dev['is_locked'] == true;
      extraTimeMinutes = (dev['extra_time_minutes'] as num?)?.toInt() ?? 0;
      currentAppName = dev['current_app_name'] as String?;
      batteryLevel = (dev['battery_level'] as num?)?.toInt();
      isCharging = dev['is_charging'] == true;
      dailyLimitMinutes = (dev['daily_screen_time_limit_mins'] as num?)?.toInt() ?? 120;
      quotaMode = (dev['rule_type'] as String?) ?? 'daily';
    });

    final deviceId = dev['id'] as String;
    _subscribeToActiveDevice(deviceId);
  }

  void _subscribeToActiveDevice(String deviceId) {
    _deviceRealtimeChannel?.unsubscribe();

    final channel = MdmSupabaseService.client.channel('device:$deviceId');

    // 1. Presence tracking
    channel.onPresenceSync((_) {
      final presenceList = channel.presenceState();
      final online = presenceList.isNotEmpty;
      Map<String, dynamic>? meta;
      if (online && presenceList.first.presences.isNotEmpty) {
        meta = presenceList.first.presences.first.payload;
      }
      if (mounted) {
        setState(() {
          isOnline = online;
          if (meta != null) {
            if (meta['battery_level'] != null) {
              batteryLevel = (meta['battery_level'] as num).toInt();
              activeDevice?['battery_level'] = batteryLevel;
            }
            if (meta['is_charging'] != null) {
              isCharging = meta['is_charging'] == true;
              activeDevice?['is_charging'] = isCharging;
            }
            final appName = meta['current_app'] ?? meta['current_app_name'];
            if (appName != null) {
              currentAppName = appName.toString();
              activeDevice?['current_app_name'] = currentAppName;
            }
            if (meta['agent_version'] != null) {
              activeDevice?['agent_version'] = meta['agent_version'];
            }
            final idx = familyDevices.indexWhere((d) => d['id'] == deviceId);
            if (idx != -1) {
              if (batteryLevel != null) familyDevices[idx]['battery_level'] = batteryLevel;
              familyDevices[idx]['is_charging'] = isCharging;
              if (currentAppName != null) familyDevices[idx]['current_app_name'] = currentAppName;
              if (meta['agent_version'] != null) familyDevices[idx]['agent_version'] = meta['agent_version'];
            }
          }
        });
      }
    });

    // 2. Broadcast events
    channel.onBroadcast(event: 'TELEMETRY_UPDATE', callback: (payload) {
      final data = (payload['payload'] is Map) ? Map<String, dynamic>.from(payload['payload'] as Map) : payload;
      if (mounted) {
        setState(() {
          if (data['battery_level'] != null) {
            batteryLevel = (data['battery_level'] as num).toInt();
            activeDevice?['battery_level'] = batteryLevel;
          }
          if (data['is_charging'] != null) {
            isCharging = data['is_charging'] == true;
            activeDevice?['is_charging'] = isCharging;
          }
          final appName = data['current_app'] ?? data['current_app_name'];
          if (appName != null) {
            currentAppName = appName.toString();
            activeDevice?['current_app_name'] = currentAppName;
          }
          if (data['agent_version'] != null) {
            activeDevice?['agent_version'] = data['agent_version'];
          }
          final idx = familyDevices.indexWhere((d) => d['id'] == deviceId);
          if (idx != -1) {
            if (batteryLevel != null) familyDevices[idx]['battery_level'] = batteryLevel;
            familyDevices[idx]['is_charging'] = isCharging;
            if (currentAppName != null) familyDevices[idx]['current_app_name'] = currentAppName;
            if (data['agent_version'] != null) familyDevices[idx]['agent_version'] = data['agent_version'];
          }
        });
      }
    });

    channel.onBroadcast(event: 'PANIC_LOCKDOWN', callback: (payload) {
      final data = (payload['payload'] is Map) ? Map<String, dynamic>.from(payload['payload'] as Map) : payload;
      if (data['is_locked'] != null) {
        final isLocked = data['is_locked'] == true;
        if (mounted) {
          setState(() => isEmergencyLocked = isLocked);
        }
        final deviceName = activeDevice?['custom_name'] ?? activeDevice?['device_name'] ?? 'Máy Con';
        SystemNotificationService().showLockdownNotification(
          deviceName: deviceName,
          isLocked: isLocked,
        );
      }
    });

    channel.onBroadcast(event: 'TIME_REQUEST', callback: (payload) {
      _handleTimeRequest(payload);
    });

    channel.onBroadcast(event: 'ACK_MESSAGE', callback: (payload) {
      _handleAckMessage(payload);
    });

    // 3. Postgres Changes (Dự phòng đảm bảo tin cậy 100%)
    // 3.1. Xác nhận lời nhắc từ máy con trên bảng device_messages
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'device_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'device_id',
        value: deviceId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord['is_acknowledged'] == true) {
          _handleAckMessage(newRecord);
        }
      },
    );

    // 3.2. Yêu cầu xin thêm giờ từ máy con trên bảng time_requests
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'time_requests',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'device_id',
        value: deviceId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord['status'] == 'pending') {
          _handleTimeRequest(newRecord);
        }
      },
    );

    // 3.3. Cập nhật trạng thái máy con trên bảng devices
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'devices',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: deviceId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (mounted) {
          setState(() {
            if (newRecord['battery_level'] != null) {
              batteryLevel = (newRecord['battery_level'] as num).toInt();
              activeDevice?['battery_level'] = batteryLevel;
            }
            if (newRecord['is_charging'] != null) {
              isCharging = newRecord['is_charging'] == true;
              activeDevice?['is_charging'] = isCharging;
            }
            final appName = newRecord['current_app_name'] ?? newRecord['current_app'];
            if (appName != null) {
              currentAppName = appName.toString();
              activeDevice?['current_app_name'] = currentAppName;
            }
            if (newRecord['agent_version'] != null) {
              activeDevice?['agent_version'] = newRecord['agent_version'];
            }
            final idx = familyDevices.indexWhere((d) => d['id'] == deviceId);
            if (idx != -1) {
              familyDevices[idx] = Map<String, dynamic>.from(familyDevices[idx])..addAll(newRecord);
            }
          });
        }
      },
    );

    channel.subscribe();
    _deviceRealtimeChannel = channel;
  }

  DateTime? _lastAckNotificationTime;
  String? _lastAckMessageId;

  void _handleAckMessage(Map<String, dynamic> rawPayload) {
    final payload = (rawPayload['payload'] is Map)
        ? Map<String, dynamic>.from(rawPayload['payload'] as Map)
        : rawPayload;
    final msgId = (payload['message_id'] ?? payload['id'])?.toString();
    final now = DateTime.now();
    if (_lastAckMessageId == msgId && _lastAckNotificationTime != null &&
        now.difference(_lastAckNotificationTime!).inSeconds < 3) {
      return;
    }
    _lastAckMessageId = msgId;
    _lastAckNotificationTime = now;

    final deviceName = activeDevice?['custom_name'] ?? activeDevice?['device_name'] ?? 'Bé';
    SystemNotificationService().showAckNotification(
      deviceName: deviceName,
      message: 'Dạ con nghe rồi!',
    );
    if (mounted) {
      HapticFeedback.heavyImpact();
      AppleNotification.show(
        context,
        title: 'Bé Đã Phản Hồi! 👍',
        message: '$deviceName: "Dạ con nghe rồi!"',
        icon: Icons.check_circle_rounded,
        iconColor: AppleTheme.appleGreen,
      );
      ActivityHistoryService.logActivity(
        type: ActivityType.message,
        title: 'Bé Đã Xác Nhận Lời Nhắc',
        subtitle: '$deviceName đã nhận và bấm "Dạ con nghe rồi!"',
      );
      widget.onActionLogged();
    }
  }

  DateTime? _lastTimeRequestNotificationTime;
  void _handleTimeRequest(Map<String, dynamic> rawPayload) {
    final payload = (rawPayload['payload'] is Map)
        ? Map<String, dynamic>.from(rawPayload['payload'] as Map)
        : rawPayload;
    final now = DateTime.now();
    if (_lastTimeRequestNotificationTime != null &&
        now.difference(_lastTimeRequestNotificationTime!).inSeconds < 3) {
      return;
    }
    _lastTimeRequestNotificationTime = now;

    final reqMinutes = (payload['requested_minutes'] as num?)?.toInt() ?? 15;
    final reason = payload['reason'] as String? ?? 'Con xin thêm giờ chơi';
    final deviceName = activeDevice?['custom_name'] ?? activeDevice?['device_name'] ?? 'Bé';
    SystemNotificationService().showTimeRequestNotification(
      deviceName: deviceName,
      requestedMinutes: reqMinutes,
      reason: reason,
    );
    if (mounted) {
      _showTimeRequestDialog(payload);
    }
  }

  Future<void> _showPairingDialog() async {
    final success = await QrPairingSheet.show(
      context,
      supabaseService: _supabaseService,
      onPaired: (deviceName) {
        widget.onActionLogged();
        _loadDeviceData();
      },
    );
    if (success == true && mounted) {
      _loadDeviceData();
    }
  }

  Future<void> _toggleLockdown(bool targetLock) async {
    if (activeDevice == null) return;
    HapticFeedback.heavyImpact();

    final deviceId = activeDevice!['id'] as String;
    final deviceName = activeDevice!['custom_name'] ?? activeDevice!['device_name'] ?? 'Thiết bị con';

    setState(() => isEmergencyLocked = targetLock);

    try {
      await _supabaseService.triggerPanicLockdown(deviceId, targetLock);
      await ActivityHistoryService.logActivity(
        type: targetLock ? ActivityType.lock : ActivityType.unlock,
        title: targetLock ? 'Khóa Khẩn Cấp' : 'Mở Khóa Thiết Bị',
        subtitle: targetLock ? 'Đã gửi lệnh khóa màn hình tức thì tới $deviceName' : 'Đã gỡ khóa cho $deviceName',
      );
      widget.onActionLogged();

      if (mounted) {
        AppleNotification.show(
          context,
          title: targetLock ? 'Khóa Khẩn Cấp' : 'Mở Khóa Thiết Bị',
          message: targetLock
              ? 'Đã kích hoạt khóa màn hình tức thì tới $deviceName'
              : 'Đã gỡ khóa và khôi phục hoạt động cho $deviceName',
          icon: targetLock ? Icons.lock_rounded : Icons.lock_open_rounded,
          iconColor: targetLock ? AppleTheme.appleRed : AppleTheme.appleGreen,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => isEmergencyLocked = !targetLock);
        AppleNotification.show(
          context,
          title: 'Lỗi Gửi Lệnh',
          message: e.toString().replaceFirst('Exception: ', ''),
          icon: Icons.error_outline_rounded,
          iconColor: AppleTheme.appleRed,
        );
      }
    }
  }

  Future<void> _adjustScreenTime(int deltaMinutes, String reason) async {
    if (activeDevice == null) return;
    HapticFeedback.mediumImpact();

    final deviceId = activeDevice!['id'] as String;
    final deviceName = activeDevice!['custom_name'] ?? activeDevice!['device_name'] ?? 'Thiết bị con';

    setState(() {
      extraTimeMinutes = (extraTimeMinutes + deltaMinutes).clamp(0, 9999);
      if (deltaMinutes > 0) isEmergencyLocked = false;
    });

    try {
      await _supabaseService.adjustScreenTime(deviceId, deltaMinutes, reason: reason);
      final isBonus = deltaMinutes > 0;
      await ActivityHistoryService.logActivity(
        type: ActivityType.extraTime,
        title: isBonus ? 'Thưởng Giờ Chơi' : 'Phạt Trừ Giờ Chơi',
        subtitle: '${isBonus ? "+$deltaMinutes" : "$deltaMinutes"} phút cho $deviceName ($reason)',
      );
      widget.onActionLogged();

      if (mounted) {
        AppleNotification.show(
          context,
          title: isBonus ? 'Thưởng Giờ Chơi' : 'Trừ Giờ Chơi',
          message: '${isBonus ? "+$deltaMinutes" : "$deltaMinutes"} phút cho $deviceName.',
          icon: isBonus ? Icons.more_time_rounded : Icons.timer_off_rounded,
          iconColor: isBonus ? AppleTheme.appleBlue : AppleTheme.appleAmber,
        );
      }
    } catch (e) {
      if (mounted) {
        AppleNotification.show(
          context,
          title: 'Lỗi Cập Nhật Giờ',
          message: e.toString().replaceFirst('Exception: ', ''),
          icon: Icons.error_outline_rounded,
          iconColor: AppleTheme.appleRed,
        );
      }
    }
  }

  /// Đổi tên thiết bị con (P2-ADMIN-01)
  Future<void> _showRenameDialog() async {
    if (activeDevice == null) return;
    final deviceId = activeDevice!['id'] as String;
    final currentName = activeDevice!['custom_name'] ?? activeDevice!['device_name'] ?? 'Thiết bị con';
    final controller = TextEditingController(text: currentName);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: context.borderColor, width: 0.75),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppleTheme.applePurple.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.edit_rounded, color: AppleTheme.applePurple, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Đổi Tên Thiết Bị', style: AppleTypography.titleLarge),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Đặt tên gợi nhớ để phân biệt các máy trong gia đình (ví dụ: Điện thoại Bin, iPad Bon):',
              style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              style: AppleTypography.bodyLarge.copyWith(color: context.textPrimaryColor),
              decoration: InputDecoration(
                hintText: 'Nhập tên mới...',
                hintStyle: AppleTypography.bodyMedium.copyWith(color: AppleTheme.textSecondary),
                filled: true,
                fillColor: context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Hủy', style: AppleTypography.bodyMedium.copyWith(color: AppleTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppleTheme.applePurple,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: Text('Lưu Tên', style: AppleTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && mounted) {
      try {
        await _supabaseService.renameDevice(deviceId, newName);
        setState(() {
          activeDevice!['custom_name'] = newName;
          activeDevice!['device_name'] = newName;
          for (var d in familyDevices) {
            if (d['id'] == deviceId) {
              d['custom_name'] = newName;
              d['device_name'] = newName;
            }
          }
        });
        await ActivityHistoryService.logActivity(
          type: ActivityType.rename,
          title: 'Đổi Tên Thiết Bị',
          subtitle: 'Đã đổi tên máy thành "$newName"',
        );
        widget.onActionLogged();
        if (mounted) {
          AppleNotification.show(
            context,
            title: 'Đã Đổi Tên Thiết Bị',
            message: 'Thiết bị đã được đổi thành "$newName"',
            icon: Icons.check_circle_rounded,
            iconColor: AppleTheme.applePurple,
          );
        }
      } catch (e) {
        if (mounted) {
          AppleNotification.show(
            context,
            title: 'Lỗi Đổi Tên',
            message: e.toString().replaceFirst('Exception: ', ''),
            icon: Icons.error_outline_rounded,
            iconColor: AppleTheme.appleRed,
          );
        }
      }
    }
  }

  /// Hủy quyền quản lý thiết bị (P2-ADMIN-03)
  Future<void> _showUnpairDialog() async {
    if (activeDevice == null) return;
    final deviceId = activeDevice!['id'] as String;
    final deviceName = activeDevice!['custom_name'] ?? activeDevice!['device_name'] ?? 'Thiết bị con';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: context.borderColor, width: 0.75),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppleTheme.appleRed.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.link_off_rounded, color: AppleTheme.appleRed, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Hủy Quản Lý Thiết Bị?', style: AppleTypography.titleLarge),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn hủy quản lý "$deviceName"?\n\nMọi hạn mức và khóa khẩn cấp sẽ được gỡ bỏ ngay lập tức, thiết bị sẽ không còn liên kết với tài khoản phụ huynh này.',
          style: AppleTypography.bodyMedium.copyWith(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Giữ Lại', style: AppleTypography.bodyMedium.copyWith(color: AppleTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppleTheme.appleRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Hủy Quản Lý', style: AppleTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _supabaseService.revokeDeviceManagement(deviceId);
        await ActivityHistoryService.logActivity(
          type: ActivityType.unpair,
          title: 'Hủy Quản Lý Thiết Bị',
          subtitle: 'Đã hủy liên kết máy $deviceName khỏi gia đình',
        );
        widget.onActionLogged();
        if (mounted) {
          AppleNotification.show(
            context,
            title: 'Đã Hủy Quản Lý',
            message: 'Đã ngắt kết nối với $deviceName.',
            icon: Icons.link_off_rounded,
            iconColor: AppleTheme.appleRed,
          );
        }
        await _loadDeviceData();
      } catch (e) {
        if (mounted) {
          AppleNotification.show(
            context,
            title: 'Lỗi Hủy Quản Lý',
            message: e.toString().replaceFirst('Exception: ', ''),
            icon: Icons.error_outline_rounded,
            iconColor: AppleTheme.appleRed,
          );
        }
      }
    }
  }

  /// Cấu hình hạn mức Ngày / Tuần (P2-ADMIN-05)
  Future<void> _showPolicyConfigurationSheet() async {
    if (activeDevice == null) return;
    final deviceId = activeDevice!['id'] as String;
    final deviceName = activeDevice!['custom_name'] ?? activeDevice!['device_name'] ?? 'Thiết bị con';

    int selectedDailyMins = dailyLimitMinutes;
    String selectedRuleType = quotaMode;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isDark = context.isDark;
            return Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 28),
              decoration: BoxDecoration(
                color: isDark ? AppleTheme.darkSurface : AppleTheme.lightSurface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: context.borderColor, width: 0.75),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppleTheme.textSecondary.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppleTheme.appleAmber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.tune_rounded, color: AppleTheme.appleAmber, size: 20),
                          ),
                          const SizedBox(width: 10),
                          const Text('Cấu Hình Hạn Mức', style: AppleTypography.titleLarge),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppleTheme.textSecondary),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Thiết lập quy tắc giới hạn thời gian sử dụng cho $deviceName:',
                    style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 18),

                  // 1. Selector Ngày / Tuần
                  Text('CHẾ ĐỘ GIỚI HẠN', style: AppleTypography.labelSmall.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppleTheme.darkSurfaceVariant : AppleTheme.lightSurfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setSheetState(() => selectedRuleType = 'daily'),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                color: selectedRuleType == 'daily' ? AppleTheme.appleAmber : Colors.transparent,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Theo Ngày (Mặc định)',
                                style: AppleTypography.bodyMedium.copyWith(
                                  fontSize: 13,
                                  fontWeight: selectedRuleType == 'daily' ? FontWeight.w700 : FontWeight.w500,
                                  color: selectedRuleType == 'daily' ? Colors.white : AppleTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setSheetState(() => selectedRuleType = 'weekly'),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                color: selectedRuleType == 'weekly' ? AppleTheme.appleAmber : Colors.transparent,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Theo Tuần',
                                style: AppleTypography.bodyMedium.copyWith(
                                  fontSize: 13,
                                  fontWeight: selectedRuleType == 'weekly' ? FontWeight.w700 : FontWeight.w500,
                                  color: selectedRuleType == 'weekly' ? Colors.white : AppleTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 2. Daily limit slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        selectedRuleType == 'daily' ? 'Hạn mức mỗi ngày:' : 'Hạn mức ngày trung bình:',
                        style: AppleTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text(
                        '${selectedDailyMins ~/ 60}h ${selectedDailyMins % 60}m ($selectedDailyMins phút)',
                        style: AppleTypography.titleLarge.copyWith(
                          fontSize: 18,
                          color: AppleTheme.appleAmber,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Slider(
                    value: selectedDailyMins.toDouble(),
                    min: 30,
                    max: 480,
                    divisions: 30,
                    activeColor: AppleTheme.appleAmber,
                    onChanged: (val) {
                      setSheetState(() => selectedDailyMins = (val / 15).round() * 15);
                    },
                  ),

                  const SizedBox(height: 12),

                  // 3. Reset 00:00 note
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppleTheme.appleAmber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppleTheme.appleAmber.withValues(alpha: 0.25), width: 0.5),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.nightlight_round, color: AppleTheme.appleAmber, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Qua 00:00:00 nửa đêm, máy con tự động chạy bộ kích hoạt Reset để khôi phục hạn mức về ${selectedDailyMins ~/ 60}h ${selectedDailyMins % 60}m và mở khóa ứng dụng (kể cả khi offline mất mạng).',
                            style: AppleTypography.bodyMedium.copyWith(fontSize: 12.5, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 4. Save button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppleTheme.appleAmber,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          await _supabaseService.updateDevicePolicy(
                            deviceId,
                            ruleType: selectedRuleType,
                            dailyLimitMins: selectedDailyMins,
                          );
                          setState(() {
                            dailyLimitMinutes = selectedDailyMins;
                            quotaMode = selectedRuleType;
                            activeDevice!['daily_screen_time_limit_mins'] = selectedDailyMins;
                          });
                          await ActivityHistoryService.logActivity(
                            type: ActivityType.policy,
                            title: 'Cập Nhật Quy Tắc Giờ',
                            subtitle: 'Hạn mức mới: ${selectedDailyMins ~/ 60}h ${selectedDailyMins % 60}m ($selectedRuleType)',
                          );
                          widget.onActionLogged();
                          if (mounted) {
                            AppleNotification.show(
                              this.context,
                              title: 'Đã Cập Nhật Quy Tắc',
                              message: 'Hạn mức ${selectedDailyMins ~/ 60}h ${selectedDailyMins % 60}m đã được gửi tới $deviceName.',
                              icon: Icons.check_circle_rounded,
                              iconColor: AppleTheme.appleAmber,
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            AppleNotification.show(
                              this.context,
                              title: 'Lỗi Cập Nhật',
                              message: e.toString().replaceFirst('Exception: ', ''),
                              icon: Icons.error_outline_rounded,
                              iconColor: AppleTheme.appleRed,
                            );
                          }
                        }
                      },
                      child: Text(
                        'Áp Dụng Quy Tắc Mới',
                        style: AppleTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Gửi lời nhắc / Thông báo tức thì (P2-ADMIN-06)
  Future<void> _showRemoteMessageSheet() async {
    if (activeDevice == null) return;
    final deviceId = activeDevice!['id'] as String;
    final deviceName = activeDevice!['custom_name'] ?? activeDevice!['device_name'] ?? 'Thiết bị con';

    final controller = TextEditingController();
    String? selectedPreset;

    final presets = [
      {'key': 'dinner', 'label': '🍚 Đến giờ ăn cơm rồi con ơi!'},
      {'key': 'study', 'label': '📚 Mau tắt máy đi học bài nào!'},
      {'key': 'bedtime', 'label': '🛏️ Đến giờ đi ngủ rồi nhé con!'},
      {'key': 'warn_5m', 'label': '⚠️ Còn 5 phút nữa là hết giờ chơi!'},
      {'key': 'cleanup', 'label': '🧹 Dọn dẹp phòng đồ chơi nhé con!'},
      {'key': 'sport', 'label': '⚽ Ra ngoài vận động một chút nào!'},
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isDark = context.isDark;
            return Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 28),
              decoration: BoxDecoration(
                color: isDark ? AppleTheme.darkSurface : AppleTheme.lightSurface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: context.borderColor, width: 0.75),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppleTheme.textSecondary.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppleTheme.appleBlue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.mark_chat_unread_rounded, color: AppleTheme.appleBlue, size: 20),
                          ),
                          const SizedBox(width: 10),
                          const Text('Gửi Lời Nhắc Tức Thì', style: AppleTypography.titleLarge),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppleTheme.textSecondary),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Thông báo sẽ hiển thị trực tiếp lên màn hình của $deviceName kèm rung chuông:',
                    style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 14),

                  // Presets chips
                  Text('MẪU CÂU NHẮC NHỞ NHANH', style: AppleTypography.labelSmall.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presets.map((p) {
                      final isSelected = selectedPreset == p['key'];
                      return ChoiceChip(
                        label: Text(p['label']!, style: AppleTypography.bodyMedium.copyWith(fontSize: 12.5)),
                        selected: isSelected,
                        selectedColor: AppleTheme.appleBlue.withValues(alpha: 0.2),
                        backgroundColor: isDark ? AppleTheme.darkSurfaceVariant : AppleTheme.lightSurfaceVariant,
                        labelStyle: TextStyle(
                          color: isSelected ? AppleTheme.appleBlue : context.textPrimaryColor,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        side: BorderSide(
                          color: isSelected ? AppleTheme.appleBlue : context.borderColor,
                          width: 0.5,
                        ),
                        onSelected: (val) {
                          setSheetState(() {
                            selectedPreset = val ? p['key'] : null;
                            if (val) {
                              controller.text = p['label']!;
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // Custom text field
                  Text('NỘI DUNG LỜI NHẮC', style: AppleTypography.labelSmall.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    maxLines: 2,
                    maxLength: 150,
                    style: AppleTypography.bodyLarge.copyWith(color: context.textPrimaryColor, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Nhập nội dung lời nhắc muốn gửi tới con...',
                      hintStyle: AppleTypography.bodyMedium.copyWith(color: AppleTheme.textSecondary),
                      filled: true,
                      fillColor: isDark ? AppleTheme.darkSurfaceVariant : AppleTheme.lightSurfaceVariant,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Send button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppleTheme.appleBlue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      label: Text(
                        'Gửi Lời Nhắc Tới Con',
                        style: AppleTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 15),
                      ),
                      onPressed: () async {
                        final text = controller.text.trim();
                        if (text.isEmpty) return;
                        Navigator.pop(ctx);
                        try {
                          await _supabaseService.sendRemoteMessage(
                            deviceId,
                            title: 'Lời nhắc từ Ba Mẹ',
                            body: text,
                            templateKey: selectedPreset,
                          );
                          await ActivityHistoryService.logActivity(
                            type: ActivityType.message,
                            title: 'Gửi Lời Nhắc Tức Thì',
                            subtitle: 'Đã gửi tới $deviceName: "$text"',
                          );
                          widget.onActionLogged();
                          if (mounted) {
                            AppleNotification.show(
                              this.context,
                              title: 'Đã Gửi Lời Nhắc',
                              message: 'Lời nhắc đã được phát tới $deviceName.',
                              icon: Icons.check_circle_rounded,
                              iconColor: AppleTheme.appleBlue,
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            AppleNotification.show(
                              this.context,
                              title: 'Lỗi Gửi Lời Nhắc',
                              message: e.toString().replaceFirst('Exception: ', ''),
                              icon: Icons.error_outline_rounded,
                              iconColor: AppleTheme.appleRed,
                            );
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Nhận và xử lý yêu cầu xin thêm giờ của bé (P2-CHILD-02)
  void _showTimeRequestDialog(Map<String, dynamic> rawPayload) {
    HapticFeedback.heavyImpact();
    final payload = (rawPayload['payload'] is Map)
        ? Map<String, dynamic>.from(rawPayload['payload'] as Map)
        : rawPayload;
    final reqMinutes = (payload['requested_minutes'] as num?)?.toInt() ?? 15;
    final reason = payload['reason'] as String? ?? 'Con xin thêm giờ chơi';
    final deviceId = (payload['device_id'] as String?) ?? activeDevice?['id'];
    final deviceName = activeDevice?['custom_name'] ?? activeDevice?['device_name'] ?? 'Bé';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppleTheme.appleGreen, width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppleTheme.appleGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.access_time_filled_rounded, color: AppleTheme.appleGreen, size: 22),
            ),
            const SizedBox(width: 10),
            const Text('Bé Xin Thêm Giờ!', style: AppleTypography.titleLarge),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$deviceName đang xin thêm $reqMinutes phút sử dụng máy.',
              style: AppleTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.isDark ? AppleTheme.darkSurfaceVariant : AppleTheme.lightSurfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: AppleTheme.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '"$reason"',
                      style: AppleTypography.bodyMedium.copyWith(
                        fontStyle: FontStyle.italic,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (deviceId != null) {
                await _supabaseService.resolveTimeRequest(deviceId, approve: false);
                await ActivityHistoryService.logActivity(
                  type: ActivityType.timeRequest,
                  title: 'Từ Chối Xin Giờ',
                  subtitle: 'Đã từ chối yêu cầu +$reqMinutes phút của $deviceName',
                );
                widget.onActionLogged();
              }
            },
            child: Text('Từ Chối', style: AppleTypography.bodyMedium.copyWith(color: AppleTheme.appleRed, fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppleTheme.appleGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              if (deviceId != null) {
                await _supabaseService.resolveTimeRequest(deviceId, approve: true, grantedMinutes: reqMinutes);
                setState(() => extraTimeMinutes += reqMinutes);
                await ActivityHistoryService.logActivity(
                  type: ActivityType.timeRequest,
                  title: 'Duyệt Xin Thêm Giờ',
                  subtitle: 'Đã đồng ý thưởng thêm +$reqMinutes phút cho $deviceName',
                );
                widget.onActionLogged();
                if (mounted) {
                  AppleNotification.show(
                    context,
                    title: 'Đã Duyệt Thêm Giờ',
                    message: 'Đã cộng thêm +$reqMinutes phút cho $deviceName.',
                    icon: Icons.check_circle_rounded,
                    iconColor: AppleTheme.appleGreen,
                  );
                }
              }
            },
            child: Text('Đồng Ý (+$reqMinutes m)', style: AppleTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: SafeArea(
        bottom: false,
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: AppleTheme.appleRed))
            : RefreshIndicator(
                color: AppleTheme.appleRed,
                backgroundColor: context.surfaceColor,
                onRefresh: _loadDeviceData,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    const SizedBox(height: 12),

                    // 1. Header chuẩn Apple Music
                    _buildHeader(),

                    const SizedBox(height: 14),

                    // 2. Multi-device Carousel Bar (P2-ADMIN-01)
                    _buildDeviceSelectorBar(),

                    const SizedBox(height: 14),

                    // 3. Signature 3-Card Quick Stats Grid
                    _buildQuickStatsGrid(),

                    const SizedBox(height: 20),

                    if (errorMessage != null) ...[
                      _buildErrorBanner(errorMessage!),
                      const SizedBox(height: 16),
                    ],

                    // 4. Section 1: Thẻ Thiết Bị Con Đang Quản Lý & Telemetry
                    _buildSectionHeader('THIẾT BỊ CON ĐANG CHỌN'),
                    _buildDeviceGroupCard(),

                    const SizedBox(height: 22),

                    // 5. Section 2: Hạn Mức Sử Dụng Hôm Nay
                    _buildSectionHeader('HẠN MỨC SỬ DỤNG HÔM NAY'),
                    _buildQuotaGroupCard(),

                    const SizedBox(height: 22),

                    // 6. Section 3: Điều Khiển Tức Thì
                    _buildSectionHeader('ĐIỀU KHIỂN THỜI GIAN THỰC'),
                    _buildControlGroupCard(),

                    // Khoảng đệm để không bị Bottom Bar nổi che khuất
                    const SizedBox(height: 110),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Giám Sát',
              style: AppleTypography.displayLarge,
            ),
            Row(
              children: [
                _buildCircleButton(Icons.refresh_rounded, _loadDeviceData),
                const SizedBox(width: 8),
                _buildCircleButton(Icons.qr_code_scanner_rounded, _showPairingDialog, isAccent: true),
              ],
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Quản lý đa thiết bị thời gian thực và bảo vệ con',
          style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
        ),
      ],
    );
  }

  /// Thanh chọn nhanh đa thiết bị con (P2-ADMIN-01)
  Widget _buildDeviceSelectorBar() {
    if (familyDevices.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DANH SÁCH MÁY CON (${familyDevices.length})',
                style: AppleTypography.labelSmall.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppleTheme.textSecondary,
                  letterSpacing: 0.35,
                ),
              ),
              GestureDetector(
                onTap: _showPairingDialog,
                child: Text(
                  '+ Ghép Nối Máy',
                  style: AppleTypography.labelSmall.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppleTheme.appleRed,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: familyDevices.length + 1,
            separatorBuilder: (_, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == familyDevices.length) {
                // Nút thêm máy
                return InkWell(
                  onTap: _showPairingDialog,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 76,
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: context.borderColor, width: 0.75),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_rounded, color: AppleTheme.appleRed, size: 24),
                        const SizedBox(height: 2),
                        Text(
                          'Thêm máy',
                          style: AppleTypography.labelSmall.copyWith(fontSize: 11, color: AppleTheme.appleRed),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final dev = familyDevices[index];
              final isSelected = activeDevice?['id'] == dev['id'];
              final name = dev['custom_name'] ?? dev['device_name'] ?? 'Máy ${index + 1}';
              final devBattery = (dev['battery_level'] as num?)?.toInt();
              final devCharging = dev['is_charging'] == true;

              return InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _selectDevice(dev);
                },
                borderRadius: BorderRadius.circular(18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppleTheme.appleRed.withValues(alpha: 0.12) : context.surfaceColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelected ? AppleTheme.appleRed : context.borderColor,
                      width: isSelected ? 1.5 : 0.75,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppleTheme.appleRed.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppleTheme.appleRed.withValues(alpha: 0.2)
                              : (context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.phone_android_rounded,
                          color: isSelected ? AppleTheme.appleRed : AppleTheme.textSecondary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Text(
                                name,
                                style: AppleTypography.bodyLarge.copyWith(
                                  fontSize: 14,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                  color: isSelected ? AppleTheme.appleRed : context.textPrimaryColor,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: (isSelected ? isOnline : dev['status'] != 'offline')
                                      ? AppleTheme.appleGreen
                                      : AppleTheme.textSecondary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (devBattery != null) ...[
                                Text(
                                  devCharging ? '⚡$devBattery%' : '🔋$devBattery%',
                                  style: AppleTypography.labelSmall.copyWith(fontSize: 11, color: AppleTheme.textSecondary),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                isSelected && isEmergencyLocked ? 'Đang khóa' : (isSelected ? 'Đang chọn' : 'Chạm để xem'),
                                style: AppleTypography.labelSmall.copyWith(
                                  fontSize: 11,
                                  color: isSelected && isEmergencyLocked ? AppleTheme.appleRed : AppleTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Hàng 3 thẻ thống kê nhanh (Quick Stats Pills)
  Widget _buildQuickStatsGrid() {
    final totalAllowedMins = dailyLimitMinutes + extraTimeMinutes;

    return Row(
      children: [
        // Pill 1: Thiết bị & Kết nối
        Expanded(
          child: _buildStatPill(
            icon: Icons.phone_android_rounded,
            iconColor: AppleTheme.appleRed,
            value: '${familyDevices.length} Máy',
            label: isOnline ? 'Trực tuyến' : 'Ngoại tuyến',
            onClick: _loadDeviceData,
          ),
        ),
        const SizedBox(width: 10),
        // Pill 2: Hạn mức hôm nay
        Expanded(
          child: _buildStatPill(
            icon: Icons.timer_outlined,
            iconColor: AppleTheme.appleAmber,
            value: '${totalAllowedMins ~/ 60}h ${totalAllowedMins % 60}m',
            label: quotaMode == 'weekly' ? 'Hạn mức tuần' : 'Hạn mức ngày',
            onClick: _showPolicyConfigurationSheet,
          ),
        ),
        const SizedBox(width: 10),
        // Pill 3: Trạng thái khóa
        Expanded(
          child: _buildStatPill(
            icon: Icons.shield_rounded,
            iconColor: isEmergencyLocked ? AppleTheme.appleRed : AppleTheme.appleGreen,
            value: isEmergencyLocked ? 'ĐANG KHÓA' : 'An Toàn',
            label: 'Trạng thái',
            onClick: () {},
          ),
        ),
      ],
    );
  }

  Widget _buildStatPill({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required VoidCallback onClick,
  }) {
    return InkWell(
      onTap: onClick,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.borderColor, width: 0.75),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: context.isDark ? 0.25 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppleTypography.titleLarge.copyWith(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: context.textPrimaryColor,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              style: AppleTypography.labelSmall.copyWith(
                fontSize: 11,
                color: AppleTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: AppleTypography.labelSmall.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppleTheme.textSecondary,
          letterSpacing: 0.35,
        ),
      ),
    );
  }

  Widget _buildCircleButton(IconData icon, VoidCallback onTap, {bool isAccent = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isAccent
              ? AppleTheme.appleRed.withValues(alpha: 0.15)
              : (context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant),
          shape: BoxShape.circle,
          border: Border.all(
            color: isAccent ? AppleTheme.appleRed.withValues(alpha: 0.3) : context.borderColor,
            width: 0.5,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isAccent ? AppleTheme.appleRed : AppleTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2C0B0E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.shade800, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppleTypography.bodyMedium.copyWith(color: Colors.white, fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  /// Thẻ Thiết Bị Con & Live Telemetry (P2-ADMIN-01 & P2-ADMIN-02)
  Widget _buildDeviceGroupCard() {
    final hasDevice = activeDevice != null;
    final deviceName = hasDevice
        ? (activeDevice!['custom_name'] ?? activeDevice!['device_name'] ?? 'Thiết bị con')
        : 'Chưa ghép nối thiết bị';
    final model = hasDevice ? (activeDevice!['model'] ?? 'Android') : 'Bấm nút [+] để ghép nối mã OTP';
    final osVersion = hasDevice ? (activeDevice!['os_version'] ?? '') : '';
    final agentVersion = hasDevice ? (activeDevice!['agent_version'] ?? '') : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderColor, width: 0.75),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isEmergencyLocked
                      ? AppleTheme.appleRed.withValues(alpha: 0.15)
                      : (isOnline
                          ? AppleTheme.appleGreen.withValues(alpha: 0.15)
                          : (context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isEmergencyLocked ? Icons.lock_rounded : Icons.phone_android_rounded,
                  color: isEmergencyLocked
                      ? AppleTheme.appleRed
                      : (isOnline ? AppleTheme.appleGreen : AppleTheme.textSecondary),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            deviceName,
                            style: AppleTypography.bodyLarge.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isOnline ? AppleTheme.appleGreen : AppleTheme.textSecondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        if (hasDevice) ...[
                          const SizedBox(width: 4),
                          // Nút đổi tên ✏️ (P2-ADMIN-01)
                          InkWell(
                            onTap: _showRenameDialog,
                            borderRadius: BorderRadius.circular(12),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.edit_outlined, size: 16, color: AppleTheme.applePurple),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasDevice
                          ? (agentVersion.isNotEmpty ? '$model • $osVersion • v$agentVersion' : '$model • $osVersion')
                          : model,
                      style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (!hasDevice)
                FilledButton.tonal(
                  onPressed: _showPairingDialog,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppleTheme.appleRed.withValues(alpha: 0.15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  child: Text(
                    'Ghép Nối',
                    style: AppleTypography.bodyMedium.copyWith(color: AppleTheme.appleRed, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
            ],
          ),

          if (hasDevice) ...[
            Divider(color: context.hairlineDividerColor, height: 24, indent: 58),

            // Live Telemetry Row (P2-ADMIN-02)
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.apps_rounded, size: 16, color: AppleTheme.appleBlue),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          currentAppName != null && currentAppName!.isNotEmpty
                              ? currentAppName!
                              : (isOnline ? 'Đang ở màn hình chính' : 'Ngoại tuyến'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppleTypography.labelSmall.copyWith(
                            fontSize: 12,
                            color: currentAppName != null ? context.textPrimaryColor : AppleTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      isCharging ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
                      size: 16,
                      color: batteryLevel != null && batteryLevel! < 20 ? AppleTheme.appleRed : AppleTheme.appleGreen,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      batteryLevel != null ? (isCharging ? '⚡$batteryLevel%' : '$batteryLevel%') : '--%',
                      style: AppleTypography.labelSmall.copyWith(
                        fontSize: 12,
                        color: batteryLevel != null && batteryLevel! < 20 ? AppleTheme.appleRed : AppleTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                // Nút Hủy Quản Lý (P2-ADMIN-03)
                InkWell(
                  onTap: _showUnpairDialog,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppleTheme.appleRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.link_off_rounded, size: 14, color: AppleTheme.appleRed),
                        const SizedBox(width: 4),
                        Text(
                          'Hủy máy',
                          style: AppleTypography.labelSmall.copyWith(fontSize: 11, color: AppleTheme.appleRed, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Thẻ Hạn Mức Quota (P2-ADMIN-05)
  Widget _buildQuotaGroupCard() {
    final totalAllowedMins = dailyLimitMinutes + extraTimeMinutes;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderColor, width: 0.75),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${totalAllowedMins ~/ 60}h ${totalAllowedMins % 60}m Cho Phép',
                style: AppleTypography.headlineLarge.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.35,
                ),
              ),
              Row(
                children: [
                  if (extraTimeMinutes > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppleTheme.appleBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppleTheme.appleBlue.withValues(alpha: 0.3), width: 0.5),
                      ),
                      child: Text(
                        '+$extraTimeMinutes phút',
                        style: AppleTypography.labelSmall.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppleTheme.appleBlue,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _showPolicyConfigurationSheet,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppleTheme.appleAmber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.tune_rounded, size: 18, color: AppleTheme.appleAmber),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: isEmergencyLocked ? 1.0 : 0.35,
              minHeight: 7,
              backgroundColor: context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                isEmergencyLocked ? AppleTheme.appleRed : AppleTheme.appleAmber,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  isEmergencyLocked
                      ? '🚨 Thiết bị đang ở trạng thái Khóa Khẩn Cấp.'
                      : '🛡️ Thiết bị đang trong khung giờ an toàn (Reset 00:00).',
                  style: AppleTypography.bodyMedium.copyWith(
                    fontSize: 13,
                    color: isEmergencyLocked ? AppleTheme.appleRed : AppleTheme.textSecondary,
                    fontWeight: isEmergencyLocked ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _showPolicyConfigurationSheet,
                child: Text(
                  'Cấu hình >',
                  style: AppleTypography.labelSmall.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppleTheme.appleAmber,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Thẻ Điều Khiển Tức Thì (P2-ADMIN-06 & P2-CHILD-01)
  Widget _buildControlGroupCard() {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.borderColor, width: 0.75),
      ),
      child: Column(
        children: [
          // Mục 1: Khóa Khẩn Cấp với iOS Style Toggle Switch
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                _buildSmallIconBox(Icons.lock_rounded, AppleTheme.appleRed),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Khóa khẩn cấp',
                        style: AppleTypography.bodyLarge.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tắt màn hình & chặn mọi app ngay',
                        style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                CupertinoSwitch(
                  value: isEmergencyLocked,
                  activeTrackColor: AppleTheme.appleRed,
                  onChanged: (val) => _toggleLockdown(val),
                ),
              ],
            ),
          ),

          Divider(color: context.hairlineDividerColor, height: 1, indent: 62),

          // Mục 2: Thưởng & Phạt giờ động (+/-)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildSmallIconBox(Icons.more_time_rounded, AppleTheme.appleBlue),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Thưởng / Phạt thời gian',
                          style: AppleTypography.bodyLarge.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Cộng thêm hoặc phạt trừ giờ chơi của con',
                          style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _buildTimeChip('+15m', 15, isBonus: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTimeChip('+30m', 30, isBonus: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTimeChip('+1h', 60, isBonus: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTimeChip('-15m', -15, isBonus: false)),
                  ],
                ),
              ],
            ),
          ),

          Divider(color: context.hairlineDividerColor, height: 1, indent: 62),

          // Mục 3: Gửi lời nhắc tức thì (P2-ADMIN-06)
          InkWell(
            onTap: _showRemoteMessageSheet,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  _buildSmallIconBox(Icons.mark_chat_unread_rounded, AppleTheme.applePurple),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gửi lời nhắc tức thì',
                          style: AppleTypography.bodyLarge.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ăn cơm, học bài, đi ngủ hoặc nhắc nhở tùy ý',
                          style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: AppleTheme.textSecondary, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallIconBox(IconData icon, Color color) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }

  Widget _buildTimeChip(String label, int minutes, {required bool isBonus}) {
    return InkWell(
      onTap: () => _adjustScreenTime(minutes, isBonus ? 'Thưởng giờ' : 'Phạt trừ giờ'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isBonus
              ? (context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant)
              : AppleTheme.appleRed.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isBonus ? context.borderColor : AppleTheme.appleRed.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppleTypography.bodyLarge.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isBonus ? context.textPrimaryColor : AppleTheme.appleRed,
          ),
        ),
      ),
    );
  }
}
// TAB 2: LỊCH SỬ TƯƠNG TÁC (TIMELINE AUDIT LOG)
// ==============================================================================

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  List<ActivityRecord> _activities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() => _isLoading = true);
    final list = await ActivityHistoryService.getActivities();
    if (mounted) {
      setState(() {
        _activities = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearHistory() async {
    await ActivityHistoryService.clearHistory();
    refresh();
    if (mounted) {
      AppleNotification.show(
        context,
        title: 'Đã Xóa Lịch Sử',
        message: 'Toàn bộ nhật ký hoạt động đã được làm sạch.',
        icon: Icons.delete_sweep_rounded,
        iconColor: AppleTheme.appleAmber,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Large Title & Subtitle
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'Lịch Sử',
                        style: AppleTypography.displayLarge,
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: AppleTheme.textSecondary, size: 22),
                            tooltip: 'Xóa lịch sử',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: context.surfaceColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(22),
                                    side: BorderSide(color: context.borderColor, width: 0.75),
                                  ),
                                  title: const Text('Xóa lịch sử?', style: AppleTypography.titleLarge),
                                  content: const Text('Toàn bộ nhật ký gửi lệnh sẽ được làm sạch.', style: AppleTypography.bodyMedium),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: Text('Hủy', style: AppleTypography.bodyMedium.copyWith(color: AppleTheme.textSecondary)),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: AppleTheme.appleRed),
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        _clearHistory();
                                      },
                                      child: Text('Xóa', style: AppleTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, color: AppleTheme.textSecondary, size: 22),
                            onPressed: refresh,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Dòng thời gian tương tác và điều khiển thiết bị',
                    style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ),

            // Thẻ tóm lược Liquid Glass (Tương tự thẻ Ký Ức trong Apple Music)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: context.borderColor, width: 0.75),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppleTheme.appleRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, color: AppleTheme.appleRed, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tổng số tương tác',
                            style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_activities.length} sự kiện',
                            style: AppleTypography.headlineLarge.copyWith(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppleTheme.appleRed,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppleTheme.appleRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Thời gian thực',
                        style: AppleTypography.labelSmall.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: AppleTheme.appleRed),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 8),
              child: Text(
                'DÒNG THỜI GIAN HOẠT ĐỘNG',
                style: AppleTypography.labelSmall.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppleTheme.textSecondary,
                  letterSpacing: 0.35,
                ),
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppleTheme.appleRed))
                  : _activities.isEmpty
                      ? const Center(
                          child: Text('Chưa có lịch sử hoạt động', style: AppleTypography.bodyMedium),
                        )
                      : Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: context.surfaceColor,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: context.borderColor, width: 0.75),
                          ),
                          child: ListView.separated(
                            padding: const EdgeInsets.only(bottom: 90),
                            itemCount: _activities.length,
                            separatorBuilder: (context, index) => Divider(
                              color: context.hairlineDividerColor,
                              height: 1,
                              indent: 62,
                            ),
                            itemBuilder: (context, index) {
                              final item = _activities[index];
                              return _buildTimelineItem(item);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem(ActivityRecord item) {
    IconData icon;
    Color iconColor;

    switch (item.type) {
      case ActivityType.lock:
        icon = Icons.lock_rounded;
        iconColor = AppleTheme.appleRed;
        break;
      case ActivityType.unlock:
        icon = Icons.lock_open_rounded;
        iconColor = AppleTheme.appleGreen;
        break;
      case ActivityType.extraTime:
        icon = Icons.add_circle_outline_rounded;
        iconColor = AppleTheme.appleBlue;
        break;
      case ActivityType.pairing:
        icon = Icons.link_rounded;
        iconColor = AppleTheme.appleAmber;
        break;
      case ActivityType.rename:
        icon = Icons.edit_rounded;
        iconColor = AppleTheme.applePurple;
        break;
      case ActivityType.unpair:
        icon = Icons.link_off_rounded;
        iconColor = AppleTheme.appleRed;
        break;
      case ActivityType.message:
        icon = Icons.mark_chat_unread_rounded;
        iconColor = AppleTheme.appleBlue;
        break;
      case ActivityType.policy:
        icon = Icons.tune_rounded;
        iconColor = AppleTheme.appleAmber;
        break;
      case ActivityType.timeRequest:
        icon = Icons.access_time_filled_rounded;
        iconColor = AppleTheme.appleGreen;
        break;
      default:
        icon = Icons.check_circle_outline;
        iconColor = AppleTheme.textSecondary;
    }

    final timeStr = _formatTimestamp(item.timestamp);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppleTypography.bodyLarge.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeStr,
                      style: AppleTypography.labelSmall.copyWith(
                        fontSize: 12,
                        color: AppleTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.subtitle,
                  style: AppleTypography.bodyMedium.copyWith(
                    fontSize: 13,
                    color: AppleTheme.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m trước';
    if (diff.inHours < 24) return '${diff.inHours}h trước';
    return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ==============================================================================
// TAB 3: CÀI ĐẶT & CẬP NHẬT GITHUB (APPLE SETTINGS STYLE)
// ==============================================================================

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final ParentAppUpdater _updater = ParentAppUpdater();

  Future<void> _showCreateInviteDialog() async {
    final supabaseService = MdmSupabaseService();
    try {
      final invite = await supabaseService.createFamilyInvite();
      final code = (invite['invite_code'] as String?) ?? 'FAM-0000';
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: context.borderColor, width: 0.75),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppleTheme.applePurple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.share_rounded, color: AppleTheme.applePurple, size: 22),
              ),
              const SizedBox(width: 10),
              const Text('Mã Mời Co-Admin', style: AppleTypography.titleLarge),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Gửi mã này cho người thân để cùng quản lý các thiết bị con trong gia đình:',
                style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: context.isDark ? AppleTheme.darkSurfaceVariant : AppleTheme.lightSurfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppleTheme.applePurple.withValues(alpha: 0.3), width: 1),
                ),
                child: Column(
                  children: [
                    Text(
                      code,
                      style: AppleTypography.displayLarge.copyWith(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                        color: AppleTheme.applePurple,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Hiệu lực trong 24 giờ',
                      style: AppleTypography.labelSmall.copyWith(fontSize: 11, color: AppleTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Đóng', style: AppleTypography.bodyMedium.copyWith(color: AppleTheme.textSecondary)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppleTheme.applePurple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.white),
              label: Text('Sao Chép Mã', style: AppleTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: Colors.white)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                Navigator.pop(ctx);
                AppleNotification.show(
                  context,
                  title: 'Đã Sao Chép',
                  message: 'Mã mời $code đã được lưu vào bộ nhớ tạm.',
                  icon: Icons.copy_rounded,
                  iconColor: AppleTheme.applePurple,
                );
              },
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        AppleNotification.show(
          context,
          title: 'Lỗi Tạo Mã',
          message: e.toString().replaceFirst('Exception: ', ''),
          icon: Icons.error_outline_rounded,
          iconColor: AppleTheme.appleRed,
        );
      }
    }
  }

  Future<void> _showJoinFamilyDialog() async {
    final controller = TextEditingController();
    final supabaseService = MdmSupabaseService();

    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: context.borderColor, width: 0.75),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppleTheme.appleBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.group_add_rounded, color: AppleTheme.appleBlue, size: 22),
            ),
            const SizedBox(width: 10),
            const Text('Tham Gia Gia Đình', style: AppleTypography.titleLarge),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nhập mã mời 6 ký tự nhận được từ phụ huynh trưởng gia đình:',
              style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              style: AppleTypography.titleLarge.copyWith(
                letterSpacing: 2,
                color: context.textPrimaryColor,
              ),
              decoration: InputDecoration(
                hintText: 'Ví dụ: FAM-8924',
                hintStyle: AppleTypography.bodyMedium.copyWith(color: AppleTheme.textSecondary),
                filled: true,
                fillColor: context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Hủy', style: AppleTypography.bodyMedium.copyWith(color: AppleTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppleTheme.appleBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: Text('Tham Gia', style: AppleTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ],
      ),
    );

    if (code != null && code.isNotEmpty && mounted) {
      try {
        await supabaseService.joinFamilyByCode(code);
        if (mounted) {
          AppleNotification.show(
            context,
            title: 'Tham Gia Thành Công',
            message: 'Bạn đã là Co-Admin trong gia đình!',
            icon: Icons.check_circle_rounded,
            iconColor: AppleTheme.appleGreen,
          );
        }
      } catch (e) {
        if (mounted) {
          AppleNotification.show(
            context,
            title: 'Lỗi Tham Gia',
            message: e.toString().replaceFirst('Exception: ', ''),
            icon: Icons.error_outline_rounded,
            iconColor: AppleTheme.appleRed,
          );
        }
      }
    }
  }

  String currentVersion = '1.3.4';
  bool isCheckingUpdate = false;
  double? downloadProgress;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final ver = await _updater.getCurrentAppVersion();
    if (mounted) setState(() => currentVersion = ver);
  }

  Future<void> _checkUpdate() async {
    setState(() => isCheckingUpdate = true);
    final releaseInfo = await _updater.checkForUpdate(currentVersion);

    if (!mounted) return;
    setState(() => isCheckingUpdate = false);

    if (releaseInfo == null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: context.borderColor, width: 0.75),
          ),
          title: const Text('Ứng Dụng Đã Mới Nhất', style: AppleTypography.titleLarge),
          content: Text('VFam Admin đang ở phiên bản mới nhất ($currentVersion). Không có bản cập nhật nào.', style: AppleTypography.bodyMedium),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('OK', style: AppleTypography.bodyMedium.copyWith(color: AppleTheme.appleRed, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    } else {
      _showUpdateDialog(releaseInfo);
    }
  }

  void _showUpdateDialog(GitHubReleaseInfo release) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: context.surfaceColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: context.borderColor, width: 0.75),
            ),
            title: Row(
              children: [
                const Icon(Icons.system_update_rounded, color: AppleTheme.appleRed),
                const SizedBox(width: 10),
                Text('Bản Cập Nhật ${release.tagName}', style: AppleTypography.titleLarge),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Phát hành: ${release.publishedAt.split('T').first}',
                  style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 12),
                Text('Nội dung cập nhật:', style: AppleTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      release.releaseNotes.isNotEmpty ? release.releaseNotes : 'Bản cập nhật tối ưu hóa giao diện và trải nghiệm.',
                      style: AppleTypography.bodyMedium.copyWith(fontSize: 13, height: 1.3),
                    ),
                  ),
                ),
                if (downloadProgress != null) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: downloadProgress,
                      minHeight: 6,
                      backgroundColor: context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppleTheme.appleRed),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Đang tải: ${(downloadProgress! * 100).toStringAsFixed(1)}%',
                      style: AppleTypography.labelSmall.copyWith(color: AppleTheme.appleRed, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (downloadProgress == null) ...[
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Để Sau', style: AppleTypography.bodyMedium.copyWith(color: AppleTheme.textSecondary, fontSize: 15)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppleTheme.appleRed,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    setDialogState(() => downloadProgress = 0.0);
                    try {
                      final apkFile = await _updater.downloadApk(
                        release.apkDownloadUrl,
                        onProgress: (prog, rec, tot) {
                          setDialogState(() => downloadProgress = prog);
                        },
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _updater.installApk(apkFile);
                    } catch (e) {
                      setDialogState(() => downloadProgress = null);
                      if (context.mounted) {
                        AppleNotification.show(
                          context,
                          title: 'Lỗi Tải Bản Cập Nhật',
                          message: e.toString().replaceFirst('Exception: ', ''),
                          icon: Icons.error_outline_rounded,
                          iconColor: AppleTheme.appleRed,
                        );
                      }
                    }
                  },
                  child: Text('Cập Nhật Ngay', style: AppleTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.white)),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.backgroundColor,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            const SizedBox(height: 12),

            // Large Title & Subtitle
            const Text(
              'Cài Đặt',
              style: AppleTypography.displayLarge,
            ),
            const SizedBox(height: 2),
            Text(
              'Hệ thống, giao diện và hạ tầng Supabase',
              style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
            ),

            const SizedBox(height: 24),

            // SECTION 0: GIAO DIỆN & CHỦ ĐỀ (THEME) - Chuẩn Apple Music
            _buildSectionTitle('GIAO DIỆN & CHỦ ĐỀ'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: context.borderColor, width: 0.75),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppleTheme.appleBlue, // iOS System Blue
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.palette_rounded, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chế độ giao diện',
                              style: AppleTypography.bodyLarge.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              themeManager.themeMode == ThemeMode.system
                                  ? 'Theo hệ thống'
                                  : (themeManager.themeMode == ThemeMode.light
                                      ? 'Giao diện Sáng (Light)'
                                      : 'Giao diện Tối (AMOLED Dark)'),
                              style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Apple-style 3-Segment Control
                  _ThemeSegmentedPicker(
                    selectedMode: themeManager.themeMode,
                    onSelectMode: (mode) {
                      themeManager.setThemeMode(mode);
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // SECTION: GIA ĐÌNH & CO-ADMIN (P2-ADMIN-04)
            _buildSectionTitle('QUẢN TRỊ VIÊN & CHIA SẺ GIA ĐÌNH'),
            Container(
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: context.borderColor, width: 0.75),
              ),
              child: Column(
                children: [
                  _buildSettingsRow(
                    icon: Icons.person_add_alt_1_rounded,
                    iconColor: AppleTheme.applePurple,
                    title: 'Mời phụ huynh khác (Co-Admin)',
                    subtitle: 'Chia sẻ quyền quản lý máy con qua mã mời',
                    onTap: _showCreateInviteDialog,
                    trailingWidget: const Icon(Icons.arrow_forward_ios_rounded, color: AppleTheme.textSecondary, size: 14),
                  ),
                  Divider(color: context.hairlineDividerColor, height: 1, indent: 62),
                  _buildSettingsRow(
                    icon: Icons.group_add_rounded,
                    iconColor: AppleTheme.appleBlue,
                    title: 'Tham gia gia đình khác',
                    subtitle: 'Nhập mã mời từ phụ huynh khác',
                    onTap: _showJoinFamilyDialog,
                    trailingWidget: const Icon(Icons.arrow_forward_ios_rounded, color: AppleTheme.textSecondary, size: 14),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // SECTION 1: CẬP NHẬT ỨNG DỤNG
            _buildSectionTitle('BẢN CẬP NHẬT PHẦN MỀM'),
            Container(
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: context.borderColor, width: 0.75),
              ),
              child: _buildSettingsRow(
                icon: Icons.system_update_rounded,
                iconColor: AppleTheme.appleAmber,
                title: 'Cập nhật ứng dụng',
                subtitle: 'Phiên bản hiện tại: v$currentVersion',
                onTap: isCheckingUpdate ? null : _checkUpdate,
                trailingWidget: isCheckingUpdate
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppleTheme.appleRed))
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppleTheme.appleRed.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'v$currentVersion',
                              style: AppleTypography.labelSmall.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppleTheme.appleRed,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward_ios_rounded, color: AppleTheme.appleRed, size: 12),
                          ],
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 24),

            // SECTION 2: BẢO MẬT & HẠ TẦNG CLOUD
            _buildSectionTitle('BẢO MẬT & HẠ TẦNG'),
            Container(
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: context.borderColor, width: 0.75),
              ),
              child: Column(
                children: [
                  _buildSettingsRow(
                    icon: Icons.cloud_done_rounded,
                    iconColor: AppleTheme.appleGreen,
                    title: 'Hạ tầng kết nối',
                    subtitle: 'Supabase Realtime WebSocket',
                    trailingWidget: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppleTheme.appleGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Online',
                          style: AppleTypography.labelSmall.copyWith(fontSize: 13, color: AppleTheme.appleGreen, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: context.hairlineDividerColor, height: 1, indent: 62),
                  _buildSettingsRow(
                    icon: Icons.fingerprint_rounded,
                    iconColor: AppleTheme.applePurple,
                    title: 'Phiên phụ huynh',
                    subtitle: 'Đăng nhập ẩn danh tự động (Zero-Login)',
                    trailingWidget: const Icon(Icons.check_circle_rounded, color: AppleTheme.applePurple, size: 20),
                  ),
                  Divider(color: context.hairlineDividerColor, height: 1, indent: 62),
                  _buildSettingsRow(
                    icon: Icons.security_rounded,
                    iconColor: AppleTheme.appleAmber,
                    title: 'Chính sách bảo vệ',
                    subtitle: 'Thực thi Device Owner & Device Admin',
                    trailingWidget: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppleTheme.appleAmber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Tối cao',
                        style: AppleTypography.labelSmall.copyWith(fontSize: 12, color: AppleTheme.appleAmber, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Padding bottom để không bị che bởi floating bar
            const SizedBox(height: 110),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: AppleTypography.labelSmall.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppleTheme.textSecondary,
          letterSpacing: 0.35,
        ),
      ),
    );
  }

  Widget _buildSettingsRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailingWidget,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppleTypography.bodyLarge.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppleTypography.bodyMedium.copyWith(
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            ?trailingWidget,
          ],
        ),
      ),
    );
  }
}

/// Bộ chọn Theme 3 phân đoạn chuẩn Apple Music (Hệ thống / Sáng / Tối)
class _ThemeSegmentedPicker extends StatelessWidget {
  final ThemeMode selectedMode;
  final ValueChanged<ThemeMode> onSelectMode;

  const _ThemeSegmentedPicker({
    required this.selectedMode,
    required this.onSelectMode,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      (ThemeMode.system, 'Hệ thống', Icons.brightness_auto_rounded),
      (ThemeMode.light, 'Sáng', Icons.light_mode_rounded),
      (ThemeMode.dark, 'Tối', Icons.dark_mode_rounded),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final containerBg = isDark ? AppleTheme.darkSurfaceVariant : AppleTheme.lightSurfaceVariant;
    final unselectedText = AppleTheme.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: options.map((option) {
          final mode = option.$1;
          final label = option.$2;
          final icon = option.$3;
          final isSelected = selectedMode == mode;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                onSelectMode(mode);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppleTheme.appleRed : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppleTheme.appleRed.withValues(alpha: 0.35),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: isSelected ? Colors.white : unselectedText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: AppleTypography.bodyMedium.copyWith(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? Colors.white : unselectedText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
