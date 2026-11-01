import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/mdm_supabase_service.dart';
import 'services/activity_history_service.dart';
import 'services/github_release_updater.dart';
import 'widgets/apple_notification.dart';
import 'utils/system_font_manager.dart';
import 'utils/theme_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Nạp font chữ hệ thống Android gốc (Samsung One UI, Pixel, v.v.)
  await SystemFontManager.init();
  // Nạp cấu hình theme (Hệ thống / Sáng / Tối AMOLED)
  await themeManager.init();
  try {
    await MdmSupabaseService.initialize();
  } catch (e) {
    debugPrint('Supabase init error: $e');
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

  Map<String, dynamic>? activeDevice;
  bool isEmergencyLocked = false;
  bool isOnline = true;
  int extraTimeMinutes = 0;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDeviceData();
  }

  Future<void> _loadDeviceData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final devices = await _supabaseService.getFamilyDevices();
      if (devices.isNotEmpty && mounted) {
        final dev = devices.first;
        setState(() {
          activeDevice = dev;
          isEmergencyLocked = dev['is_locked'] == true;
          extraTimeMinutes = (dev['extra_time_minutes'] as num?)?.toInt() ?? 0;
          isLoading = false;
        });

        final deviceId = dev['id'] as String;
        _supabaseService.subscribeDevicePresence(
          deviceId,
          onStatusChanged: (online, meta) {
            if (mounted) setState(() => isOnline = online);
          },
        );
      } else if (mounted) {
        setState(() {
          activeDevice = null;
          isLoading = false;
        });
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

  void _showPairingDialog() {
    final otpController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: context.borderColor, width: 0.75),
        ),
        title: Text(
          'Ghép Nối Thiết Bị Con',
          style: AppleTypography.titleLarge.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nhập mã OTP 6 chữ số đang hiển thị trên ứng dụng VFam Child của con:',
              style: AppleTypography.bodyMedium.copyWith(fontSize: 14, height: 1.35),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppleTypography.fontFamily,
                fontFamilyFallback: AppleTypography.fontFamilyFallback,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 8,
                color: context.textPrimaryColor,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                hintText: '••••••',
                hintStyle: const TextStyle(color: AppleTheme.textSecondary, letterSpacing: 8),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Hủy',
              style: AppleTypography.bodyMedium.copyWith(fontSize: 15, color: AppleTheme.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppleTheme.appleRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final otp = otpController.text.trim();
              if (otp.length != 6) {
                AppleNotification.show(
                  context,
                  title: 'Mã OTP Chưa Đủ',
                  message: 'Vui lòng nhập đủ 6 chữ số OTP từ thiết bị con',
                  icon: Icons.pin_outlined,
                  iconColor: AppleTheme.appleAmber,
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                final result = await _supabaseService.claimDevice(otp);
                final devName = result['device_name'] ?? 'Thiết bị con';
                await ActivityHistoryService.logActivity(
                  type: ActivityType.pairing,
                  title: 'Ghép Nối Thành Công',
                  subtitle: 'Đã liên kết thiết bị: $devName',
                );
                widget.onActionLogged();
                if (mounted) {
                  AppleNotification.show(
                    context,
                    title: 'Ghép Nối Thành Công',
                    message: 'Đã liên kết hoàn tất với $devName',
                    icon: Icons.check_circle_rounded,
                    iconColor: AppleTheme.appleGreen,
                  );
                  _loadDeviceData();
                }
              } catch (e) {
                if (mounted) {
                  AppleNotification.show(
                    context,
                    title: 'Ghép Nối Thất Bại',
                    message: e.toString().replaceFirst('Exception: ', ''),
                    icon: Icons.error_outline_rounded,
                    iconColor: AppleTheme.appleRed,
                  );
                }
              }
            },
            child: Text('Xác Nhận', style: AppleTypography.bodyMedium.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLockdown(bool targetLock) async {
    if (activeDevice == null) return;
    HapticFeedback.heavyImpact();

    final deviceId = activeDevice!['id'] as String;
    final deviceName = activeDevice!['device_name'] ?? 'Thiết bị con';

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

  Future<void> _grantExtraTime(int minutes) async {
    if (activeDevice == null) return;
    HapticFeedback.mediumImpact();

    final deviceId = activeDevice!['id'] as String;
    final deviceName = activeDevice!['device_name'] ?? 'Thiết bị con';

    setState(() {
      extraTimeMinutes += minutes;
      isEmergencyLocked = false;
    });

    try {
      await _supabaseService.grantExtraTime(deviceId, minutes);
      await ActivityHistoryService.logActivity(
        type: ActivityType.extraTime,
        title: 'Thưởng Giờ Sử Dụng',
        subtitle: 'Đã cộng thêm +$minutes phút cho $deviceName',
      );
      widget.onActionLogged();

      if (mounted) {
        AppleNotification.show(
          context,
          title: 'Thưởng Giờ Sử Dụng',
          message: 'Đã cộng thêm +$minutes phút sử dụng cho $deviceName',
          icon: Icons.more_time_rounded,
          iconColor: AppleTheme.appleBlue,
        );
      }
    } catch (e) {
      if (mounted) {
        AppleNotification.show(
          context,
          title: 'Lỗi Cộng Giờ',
          message: e.toString().replaceFirst('Exception: ', ''),
          icon: Icons.error_outline_rounded,
          iconColor: AppleTheme.appleRed,
        );
      }
    }
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

                    // 1. Header chuẩn Apple Music Large Title & Subtitle
                    _buildHeader(),

                    const SizedBox(height: 14),

                    // 2. Signature 3-Card Quick Stats Grid (Apple Music Style)
                    _buildQuickStatsGrid(),

                    const SizedBox(height: 20),

                    if (errorMessage != null) ...[
                      _buildErrorBanner(errorMessage!),
                      const SizedBox(height: 16),
                    ],

                    // 3. Section 1: Thẻ Thiết Bị Con Đang Kết Nối
                    _buildSectionHeader('THIẾT BỊ CON ĐANG KẾT NỐI'),
                    _buildDeviceGroupCard(),

                    const SizedBox(height: 22),

                    // 4. Section 2: Hạn Mức Sử Dụng Hôm Nay
                    _buildSectionHeader('HẠN MỨC SỬ DỤNG HÔM NAY'),
                    _buildQuotaGroupCard(),

                    const SizedBox(height: 22),

                    // 5. Section 3: Điều Khiển Tức Thì
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
                _buildCircleButton(Icons.add_link_rounded, _showPairingDialog, isAccent: true),
              ],
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Quản lý thời gian thực và bảo vệ thiết bị con',
          style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
        ),
      ],
    );
  }

  /// Hàng 3 thẻ thống kê nhanh (Signature Quick Stats Pills từ Apple Music)
  Widget _buildQuickStatsGrid() {
    final hasDevice = activeDevice != null;
    final totalAllowedMins = 120 + extraTimeMinutes;

    return Row(
      children: [
        // Pill 1: Thiết bị & Kết nối
        Expanded(
          child: _buildStatPill(
            icon: Icons.phone_android_rounded,
            iconColor: AppleTheme.appleRed,
            value: hasDevice ? '1 Máy' : '0 Máy',
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
            label: 'Hạn mức',
            onClick: () {},
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
          color: isAccent ? AppleTheme.appleRed.withValues(alpha: 0.15) : (context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant),
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

  Widget _buildDeviceGroupCard() {
    final hasDevice = activeDevice != null;
    final deviceName = hasDevice ? (activeDevice!['device_name'] ?? 'Thiết bị con') : 'Chưa ghép nối thiết bị';
    final model = hasDevice ? (activeDevice!['model'] ?? 'Android') : 'Bấm nút [+] để ghép nối mã OTP';
    final osVersion = hasDevice ? (activeDevice!['os_version'] ?? '') : '';

    return Container(
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
              color: isEmergencyLocked
                  ? AppleTheme.appleRed.withValues(alpha: 0.15)
                  : (isOnline ? AppleTheme.appleGreen.withValues(alpha: 0.15) : (context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isEmergencyLocked ? Icons.lock_rounded : Icons.phone_android_rounded,
              color: isEmergencyLocked ? AppleTheme.appleRed : (isOnline ? AppleTheme.appleGreen : AppleTheme.textSecondary),
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
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOnline ? AppleTheme.appleGreen : AppleTheme.textSecondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  hasDevice ? '$model • $osVersion' : model,
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
    );
  }

  Widget _buildQuotaGroupCard() {
    final dailyLimitMins = 120;
    final totalAllowedMins = dailyLimitMins + extraTimeMinutes;

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
          Text(
            isEmergencyLocked
                ? '🚨 Thiết bị đang ở trạng thái Khóa Khẩn Cấp tầng hệ điều hành.'
                : '🛡️ Thiết bị đang trong khung giờ an toàn và được quản lý bảo vệ.',
            style: AppleTypography.bodyMedium.copyWith(
              fontSize: 13,
              color: isEmergencyLocked ? AppleTheme.appleRed : AppleTheme.textSecondary,
              fontWeight: isEmergencyLocked ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

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

          // Mục 2: Thưởng thêm giờ nhanh
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
                          'Thưởng thêm thời gian',
                          style: AppleTypography.bodyLarge.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Cộng thêm giờ sử dụng cho con',
                          style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _buildTimeChip('+15 Phút', 15)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildTimeChip('+30 Phút', 30)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildTimeChip('+1 Giờ', 60)),
                  ],
                ),
              ],
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

  Widget _buildTimeChip(String label, int minutes) {
    return InkWell(
      onTap: () => _grantExtraTime(minutes),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderColor, width: 0.5),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppleTypography.bodyLarge.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.textPrimaryColor,
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
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

  String currentVersion = '1.2.4';
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
