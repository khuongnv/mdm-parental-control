import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/mdm_supabase_service.dart';
import 'services/activity_history_service.dart';
import 'services/github_release_updater.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await MdmSupabaseService.initialize();
  } catch (e) {
    debugPrint('Supabase init error: $e');
  }
  runApp(const MdmParentApp());
}

/// Hệ màu và kiểu dáng chuẩn Apple Music UI/UX Design System
class AppleTheme {
  // Nền đen sâu chuẩn AMOLED
  static const Color darkBackground = Color(0xFF000000);
  // Nền Liquid Glass Card bán trong suốt cao cấp
  static const Color glassSurface = Color(0xEE1E1E22);
  // Nền surface phụ / item hover
  static const Color darkSurfaceElevated = Color(0xFF2C2C2E);
  // Đường viền sáng bạc Liquid Glass (Luminous silver rim)
  static const Color glassBorder = Color(0x33FFFFFF);
  // Đường kẻ viền siêu mảnh (Hairline Divider)
  static const Color hairlineDivider = Color(0xFF38383A);

  // Bảng màu Accent Apple Music
  static const Color appleRed = Color(0xFFFA2D55); // Apple Music Red
  static const Color appleBlue = Color(0xFF007AFF); // iOS System Blue
  static const Color appleGreen = Color(0xFF34C759); // iOS System Green
  static const Color appleAmber = Color(0xFFFF9500); // iOS System Orange
  static const Color applePurple = Color(0xFFAF52DE); // iOS System Purple

  // Màu văn bản phân cấp
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93); // Gray93
}

/// Hệ Typography khớp 100% với Type.kt của dự án Android Music Player
class AppleTypography {
  static const String fontFamily = 'sans-serif';
  static const List<String> fontFamilyFallback = ['sans-serif', 'sans-serif-medium', 'Roboto'];

  static const TextStyle displayLarge = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.37,
    height: 41 / 34,
    color: AppleTheme.textPrimary,
  );

  static const TextStyle headlineLarge = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.35,
    height: 28 / 22,
    color: AppleTheme.textPrimary,
  );

  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.38,
    height: 25 / 20,
    color: AppleTheme.textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.41,
    height: 22 / 17,
    color: AppleTheme.textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.24,
    height: 20 / 15,
    color: AppleTheme.textSecondary,
  );

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
    return MaterialApp(
      title: 'VFam Admin',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppleTheme.darkBackground,
        fontFamily: AppleTypography.fontFamily,
        fontFamilyFallback: AppleTypography.fontFamilyFallback,
        typography: Typography.material2021(platform: TargetPlatform.android),
        textTheme: const TextTheme(
          displayLarge: AppleTypography.displayLarge,
          headlineLarge: AppleTypography.headlineLarge,
          titleLarge: AppleTypography.titleLarge,
          bodyLarge: AppleTypography.bodyLarge,
          bodyMedium: AppleTypography.bodyMedium,
          labelSmall: AppleTypography.labelSmall,
        ),
        colorScheme: const ColorScheme.dark(
          primary: AppleTheme.appleRed,
          secondary: AppleTheme.appleBlue,
          surface: AppleTheme.glassSurface,
        ),
        cardTheme: CardThemeData(
          color: AppleTheme.glassSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: AppleTheme.glassBorder, width: 0.75),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppleTheme.darkBackground,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: AppleTypography.titleLarge,
        ),
        useMaterial3: true,
      ),
      home: const MainNavigationScreen(),
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
      backgroundColor: AppleTheme.darkBackground,
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
    return SafeArea(
      top: false,
      bottom: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppleTheme.glassSurface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppleTheme.glassBorder, width: 0.75),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
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
          errorMessage = e.toString();
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
        backgroundColor: AppleTheme.glassSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppleTheme.glassBorder, width: 0.75),
        ),
        title: const Text('Ghép Nối Thiết Bị Con', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nhập mã OTP 6 chữ số đang hiển thị trên ứng dụng VFam Child của con:',
              style: TextStyle(color: AppleTheme.textSecondary, fontSize: 14, height: 1.3),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 8,
                color: AppleTheme.textPrimary,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppleTheme.darkSurfaceElevated,
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
            child: const Text('Hủy', style: TextStyle(color: AppleTheme.textSecondary, fontSize: 15)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppleTheme.appleRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final otp = otpController.text.trim();
              if (otp.length != 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vui lòng nhập đủ 6 chữ số OTP')),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                final result = await _supabaseService.claimDevice(otp);
                await ActivityHistoryService.logActivity(
                  type: ActivityType.pairing,
                  title: 'Ghép Nối Thiết Bị Thành Công',
                  subtitle: result['device_name'] != null ? 'Đã liên kết thiết bị: ${result['device_name']}' : 'Ghép nối thành công',
                );
                widget.onActionLogged();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppleTheme.appleGreen,
                      content: Text(result['message'] ?? 'Ghép nối thiết bị thành công!'),
                    ),
                  );
                  _loadDeviceData();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: const Color(0xFF2C0B0E), content: Text('Lỗi: $e')),
                  );
                }
              }
            },
            child: const Text('Xác Nhận', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: targetLock ? AppleTheme.appleRed : AppleTheme.appleGreen,
            content: Text(targetLock ? '🚨 Đã gửi lệnh KHÓA KHẨN CẤP tới $deviceName' : '✅ Đã MỞ KHÓA cho $deviceName'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => isEmergencyLocked = !targetLock);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: const Color(0xFF2C0B0E), content: Text('Lỗi gửi lệnh: $e')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppleTheme.appleBlue,
            content: Text('🎁 Đã thưởng +$minutes phút cho $deviceName'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: const Color(0xFF2C0B0E), content: Text('Lỗi cộng giờ: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppleTheme.darkBackground,
      body: SafeArea(
        bottom: false,
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: AppleTheme.appleRed))
            : RefreshIndicator(
                color: AppleTheme.appleRed,
                backgroundColor: AppleTheme.glassSurface,
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
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: AppleTheme.textPrimary,
              ),
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
        const Text(
          'Quản lý thời gian thực và bảo vệ thiết bị con',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppleTheme.textSecondary,
          ),
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
          color: AppleTheme.glassSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppleTheme.glassBorder, width: 0.75),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
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
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppleTheme.textPrimary,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
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
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppleTheme.textSecondary,
          letterSpacing: 0.4,
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
          color: isAccent ? AppleTheme.appleRed.withValues(alpha: 0.15) : AppleTheme.darkSurfaceElevated,
          shape: BoxShape.circle,
          border: Border.all(
            color: isAccent ? AppleTheme.appleRed.withValues(alpha: 0.3) : AppleTheme.glassBorder,
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
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
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
        color: AppleTheme.glassSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppleTheme.glassBorder, width: 0.75),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isEmergencyLocked
                  ? AppleTheme.appleRed.withValues(alpha: 0.15)
                  : (isOnline ? AppleTheme.appleGreen.withValues(alpha: 0.15) : AppleTheme.darkSurfaceElevated),
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
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppleTheme.textPrimary,
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
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppleTheme.textSecondary,
                  ),
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
              child: const Text('Ghép Nối', style: TextStyle(color: AppleTheme.appleRed, fontWeight: FontWeight.w600)),
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
        color: AppleTheme.glassSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppleTheme.glassBorder, width: 0.75),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${totalAllowedMins ~/ 60}h ${totalAllowedMins % 60}m Cho Phép',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: AppleTheme.textPrimary,
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
                    style: const TextStyle(
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
              backgroundColor: AppleTheme.darkSurfaceElevated,
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
            style: TextStyle(
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
        color: AppleTheme.glassSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppleTheme.glassBorder, width: 0.75),
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Khóa khẩn cấp',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppleTheme.textPrimary),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Tắt màn hình & chặn mọi app ngay',
                        style: TextStyle(fontSize: 13, color: AppleTheme.textSecondary),
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

          const Divider(color: AppleTheme.hairlineDivider, height: 1, indent: 62),

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
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Thưởng thêm thời gian',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppleTheme.textPrimary),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Cộng thêm giờ sử dụng cho con',
                          style: TextStyle(fontSize: 13, color: AppleTheme.textSecondary),
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
          color: AppleTheme.darkSurfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppleTheme.glassBorder, width: 0.5),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppleTheme.textPrimary,
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppleTheme.darkBackground,
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
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: AppleTheme.textPrimary,
                        ),
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
                                  backgroundColor: AppleTheme.glassSurface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(22),
                                    side: const BorderSide(color: AppleTheme.glassBorder, width: 0.75),
                                  ),
                                  title: const Text('Xóa lịch sử?'),
                                  content: const Text('Toàn bộ nhật ký gửi lệnh sẽ được làm sạch.', style: TextStyle(color: AppleTheme.textSecondary)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy', style: TextStyle(color: AppleTheme.textSecondary))),
                                    FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: AppleTheme.appleRed),
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        _clearHistory();
                                      },
                                      child: const Text('Xóa'),
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
                  const Text(
                    'Dòng thời gian tương tác và điều khiển thiết bị',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppleTheme.textSecondary,
                    ),
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
                  color: AppleTheme.glassSurface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppleTheme.glassBorder, width: 0.75),
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
                          const Text(
                            'Tổng số tương tác',
                            style: TextStyle(fontSize: 13, color: AppleTheme.textSecondary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_activities.length} sự kiện',
                            style: const TextStyle(
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
                      child: const Text(
                        'Thời gian thực',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppleTheme.appleRed),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 8),
              child: const Text(
                'DÒNG THỜI GIAN HOẠT ĐỘNG',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppleTheme.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppleTheme.appleRed))
                  : _activities.isEmpty
                      ? const Center(
                          child: Text('Chưa có lịch sử hoạt động', style: TextStyle(color: AppleTheme.textSecondary)),
                        )
                      : Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: AppleTheme.glassSurface,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: AppleTheme.glassBorder, width: 0.75),
                          ),
                          child: ListView.separated(
                            padding: const EdgeInsets.only(bottom: 90),
                            itemCount: _activities.length,
                            separatorBuilder: (context, index) => const Divider(
                              color: AppleTheme.hairlineDivider,
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
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppleTheme.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppleTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.subtitle,
                  style: const TextStyle(
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

  String currentVersion = '1.2.1';
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
          backgroundColor: AppleTheme.glassSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: AppleTheme.glassBorder, width: 0.75),
          ),
          title: const Text('Ứng Dụng Đã Mới Nhất'),
          content: Text('VFam Admin đang ở phiên bản mới nhất ($currentVersion). Không có bản cập nhật nào.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: AppleTheme.appleRed))),
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
            backgroundColor: AppleTheme.glassSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: AppleTheme.glassBorder, width: 0.75),
            ),
            title: Row(
              children: [
                const Icon(Icons.system_update_rounded, color: AppleTheme.appleRed),
                const SizedBox(width: 10),
                Text('Bản Cập Nhật ${release.tagName}'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Phát hành: ${release.publishedAt.split('T').first}',
                  style: const TextStyle(color: AppleTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Text('Nội dung cập nhật:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppleTheme.darkSurfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      release.releaseNotes.isNotEmpty ? release.releaseNotes : 'Bản cập nhật tối ưu hóa giao diện và trải nghiệm.',
                      style: const TextStyle(color: AppleTheme.textSecondary, fontSize: 13, height: 1.3),
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
                      backgroundColor: AppleTheme.darkSurfaceElevated,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppleTheme.appleRed),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Đang tải: ${(downloadProgress! * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(color: AppleTheme.appleRed, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (downloadProgress == null) ...[
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Để Sau', style: TextStyle(color: AppleTheme.textSecondary, fontSize: 15)),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(backgroundColor: const Color(0xFF2C0B0E), content: Text('Lỗi tải: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Cập Nhật Ngay', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
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
      backgroundColor: AppleTheme.darkBackground,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            const SizedBox(height: 12),

            // Large Title & Subtitle
            const Text(
              'Cài Đặt',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: AppleTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Hệ thống, phiên bản và hạ tầng Supabase',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppleTheme.textSecondary,
              ),
            ),

            const SizedBox(height: 24),

            // SECTION 1: CẬP NHẬT ỨNG DỤNG
            _buildSectionTitle('BẢN CẬP NHẬT PHẦN MỀM'),
            Container(
              decoration: BoxDecoration(
                color: AppleTheme.glassSurface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppleTheme.glassBorder, width: 0.75),
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
                              style: const TextStyle(
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
                color: AppleTheme.glassSurface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppleTheme.glassBorder, width: 0.75),
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
                        const Text(
                          'Online',
                          style: TextStyle(fontSize: 13, color: AppleTheme.appleGreen, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: AppleTheme.hairlineDivider, height: 1, indent: 62),
                  _buildSettingsRow(
                    icon: Icons.fingerprint_rounded,
                    iconColor: AppleTheme.applePurple,
                    title: 'Phiên phụ huynh',
                    subtitle: 'Đăng nhập ẩn danh tự động (Zero-Login)',
                    trailingWidget: const Icon(Icons.check_circle_rounded, color: AppleTheme.applePurple, size: 20),
                  ),
                  const Divider(color: AppleTheme.hairlineDivider, height: 1, indent: 62),
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
                      child: const Text(
                        'Tối cao',
                        style: TextStyle(fontSize: 12, color: AppleTheme.appleAmber, fontWeight: FontWeight.w600),
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
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppleTheme.textSecondary,
          letterSpacing: 0.4,
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppleTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppleTheme.textSecondary,
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
