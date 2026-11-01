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
  // Nền card/bề mặt phụ (tương đương iOS .secondarySystemBackground)
  static const Color darkSurface = Color(0xFF1C1C1E);
  // Nền elevated / item hover (tương đương iOS .tertiarySystemBackground)
  static const Color darkSurfaceElevated = Color(0xFF2C2C2E);
  // Đường kẻ viền siêu mảnh (Hairline Divider)
  static const Color hairlineDivider = Color(0xFF38383A);

  // Bảng màu Accent Apple
  static const Color appleRed = Color(0xFFFA2D55); // Apple Music Red
  static const Color appleBlue = Color(0xFF007AFF); // iOS System Blue
  static const Color appleGreen = Color(0xFF34C759); // iOS System Green
  static const Color appleAmber = Color(0xFFFF9500); // iOS System Orange
  static const Color applePurple = Color(0xFFAF52DE); // iOS System Purple

  // Màu văn bản phân cấp
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93); // iOS System Gray (Gray93)
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
        // Sử dụng 100% font hệ thống của chính máy Android (Samsung One UI Sans, Honor Sans, Roboto...)
        fontFamily: 'sans-serif',
        fontFamilyFallback: const [
          'sans-serif',
          'sans-serif-medium',
          'Roboto',
        ],
        typography: Typography.material2021(platform: TargetPlatform.android),
        colorScheme: const ColorScheme.dark(
          primary: AppleTheme.appleRed,
          secondary: AppleTheme.appleBlue,
          surface: AppleTheme.darkSurface,
        ),
        cardTheme: CardThemeData(
          color: AppleTheme.darkSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppleTheme.hairlineDivider, width: 0.5),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppleTheme.darkBackground,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppleTheme.textPrimary,
          ),
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
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppleTheme.darkSurface,
          border: Border(
            top: BorderSide(color: AppleTheme.hairlineDivider, width: 0.5),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.shield_rounded, Icons.shield_outlined, 'Giám Sát'),
                _buildNavItem(1, Icons.history_rounded, Icons.history_outlined, 'Lịch Sử'),
                _buildNavItem(2, Icons.tune_rounded, Icons.tune_outlined, 'Cài Đặt'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isSelected = _currentIndex == index;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _currentIndex = index);
        if (index == 1) _historyKey.currentState?.refresh();
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : inactiveIcon,
              color: isSelected ? AppleTheme.appleRed : AppleTheme.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'sans-serif',
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppleTheme.appleRed : AppleTheme.textSecondary,
              ),
            ),
          ],
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
        backgroundColor: AppleTheme.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppleTheme.hairlineDivider, width: 0.5),
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
                fontFamily: 'sans-serif',
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
                    SnackBar(backgroundColor: Colors.red.shade900, content: Text('Lỗi: $e')),
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
        title: targetLock ? 'Khóa Khẩn Cấp Thiết Bị' : 'Mở Khóa Thiết Bị',
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
          SnackBar(backgroundColor: Colors.red.shade900, content: Text('Lỗi gửi lệnh: $e')),
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
          SnackBar(backgroundColor: Colors.red.shade900, content: Text('Lỗi cộng giờ: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppleTheme.darkBackground,
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: AppleTheme.appleRed))
            : RefreshIndicator(
                color: AppleTheme.appleRed,
                backgroundColor: AppleTheme.darkSurface,
                onRefresh: _loadDeviceData,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    const SizedBox(height: 12),

                    // Header chuẩn Apple Large Title
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Giám Sát',
                          style: TextStyle(
                            fontFamily: 'sans-serif',
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

                    const SizedBox(height: 20),

                    if (errorMessage != null) ...[
                      _buildErrorBanner(errorMessage!),
                      const SizedBox(height: 16),
                    ],

                    // Section 1: Thẻ Thiết Bị Con
                    _buildSectionHeader('THIẾT BỊ CON ĐANG KẾT NỐI'),
                    _buildDeviceGroupCard(),

                    const SizedBox(height: 22),

                    // Section 2: Thời Gian & Hạn Mức
                    _buildSectionHeader('HẠN MỨC SỬ DỤNG HÔM NAY'),
                    _buildQuotaGroupCard(),

                    const SizedBox(height: 22),

                    // Section 3: Điều Khiển Thiết Bị (Khóa khẩn cấp & Thưởng giờ)
                    _buildSectionHeader('ĐIỀU KHIỂN THỜI GIAN THỰC'),
                    _buildControlGroupCard(),

                    const SizedBox(height: 32),
                  ],
                ),
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
          fontFamily: 'sans-serif',
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade800, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontFamily: 'sans-serif', color: Colors.white, fontSize: 13, height: 1.3),
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
        color: AppleTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppleTheme.hairlineDivider, width: 0.5),
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
              borderRadius: BorderRadius.circular(10),
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
                          fontFamily: 'sans-serif',
                          fontSize: 17,
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
                    fontFamily: 'sans-serif',
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
        color: AppleTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppleTheme.hairlineDivider, width: 0.5),
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
                  fontFamily: 'sans-serif',
                  fontSize: 28,
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
                  ),
                  child: Text(
                    '+$extraTimeMinutes phút',
                    style: const TextStyle(
                      fontFamily: 'sans-serif',
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
              minHeight: 6,
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
              fontFamily: 'sans-serif',
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
        color: AppleTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppleTheme.hairlineDivider, width: 0.5),
      ),
      child: Column(
        children: [
          // Mục 1: Khóa Khẩn Cấp với iOS Style Toggle Switch
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _buildSmallIconBox(Icons.lock_rounded, AppleTheme.appleRed),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Khóa khẩn cấp thiết bị con',
                        style: TextStyle(fontFamily: 'sans-serif', fontSize: 16, fontWeight: FontWeight.w600, color: AppleTheme.textPrimary),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Tắt màn hình và chặn mở ứng dụng ngay lập tức',
                        style: TextStyle(fontFamily: 'sans-serif', fontSize: 13, color: AppleTheme.textSecondary),
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
                          'Cấp thêm thời gian',
                          style: TextStyle(fontFamily: 'sans-serif', fontSize: 16, fontWeight: FontWeight.w600, color: AppleTheme.textPrimary),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Thưởng thêm giờ sử dụng cho con',
                          style: TextStyle(fontFamily: 'sans-serif', fontSize: 13, color: AppleTheme.textSecondary),
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
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }

  Widget _buildTimeChip(String label, int minutes) {
    return InkWell(
      onTap: () => _grantExtraTime(minutes),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppleTheme.darkSurfaceElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'sans-serif',
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Lịch Sử',
                    style: TextStyle(
                      fontFamily: 'sans-serif',
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
                              backgroundColor: AppleTheme.darkSurface,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppleTheme.appleRed))
                  : _activities.isEmpty
                      ? const Center(
                          child: Text('Chưa có lịch sử hoạt động', style: TextStyle(fontFamily: 'sans-serif', color: AppleTheme.textSecondary)),
                        )
                      : Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: AppleTheme.darkSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppleTheme.hairlineDivider, width: 0.5),
                          ),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
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
            const SizedBox(height: 16),
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
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor,
              borderRadius: BorderRadius.circular(8),
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
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontFamily: 'sans-serif',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppleTheme.textPrimary,
                      ),
                    ),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        fontFamily: 'sans-serif',
                        fontSize: 12,
                        color: AppleTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  style: const TextStyle(
                    fontFamily: 'sans-serif',
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

  String currentVersion = '1.2.0';
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
          backgroundColor: AppleTheme.darkSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
            backgroundColor: AppleTheme.darkSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppleTheme.hairlineDivider, width: 0.5),
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
                  style: const TextStyle(fontFamily: 'sans-serif', color: AppleTheme.textSecondary, fontSize: 13),
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
                      release.releaseNotes.isNotEmpty ? release.releaseNotes : 'Bản cập nhật tối ưu hóa hiệu năng và sửa lỗi.',
                      style: const TextStyle(fontFamily: 'sans-serif', color: AppleTheme.textSecondary, fontSize: 13, height: 1.3),
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
                      style: const TextStyle(fontFamily: 'sans-serif', color: AppleTheme.appleRed, fontSize: 12, fontWeight: FontWeight.w600),
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
                          SnackBar(backgroundColor: Colors.red.shade900, content: Text('Lỗi tải: $e')),
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
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            const SizedBox(height: 12),

            // Large Title
            const Text(
              'Cài Đặt',
              style: TextStyle(
                fontFamily: 'sans-serif',
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: AppleTheme.textPrimary,
              ),
            ),

            const SizedBox(height: 24),

            // SECTION 1: CẬP NHẬT ỨNG DỤNG
            _buildSectionTitle('CẬP NHẬT ỨNG DỤNG'),
            Container(
              decoration: BoxDecoration(
                color: AppleTheme.darkSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppleTheme.hairlineDivider, width: 0.5),
              ),
              child: Column(
                children: [
                  _buildSettingsRow(
                    icon: Icons.info_outline_rounded,
                    iconColor: AppleTheme.appleBlue,
                    title: 'Phiên bản ứng dụng',
                    trailingText: 'v$currentVersion',
                  ),
                  const Divider(color: AppleTheme.hairlineDivider, height: 1, indent: 62),
                  _buildSettingsRow(
                    icon: Icons.system_update_rounded,
                    iconColor: AppleTheme.appleRed,
                    title: 'Kiểm tra bản cập nhật mới',
                    onTap: isCheckingUpdate ? null : _checkUpdate,
                    trailingWidget: isCheckingUpdate
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppleTheme.appleRed))
                        : const Icon(Icons.arrow_forward_ios_rounded, color: AppleTheme.textSecondary, size: 14),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // SECTION 2: BẢO MẬT & HẠ TẦNG CLOUD
            _buildSectionTitle('BẢO MẬT & HẠ TẦNG'),
            Container(
              decoration: BoxDecoration(
                color: AppleTheme.darkSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppleTheme.hairlineDivider, width: 0.5),
              ),
              child: Column(
                children: [
                  _buildSettingsRow(
                    icon: Icons.cloud_done_rounded,
                    iconColor: AppleTheme.appleGreen,
                    title: 'Hạ tầng kết nối',
                    trailingText: 'Supabase Realtime',
                  ),
                  const Divider(color: AppleTheme.hairlineDivider, height: 1, indent: 62),
                  _buildSettingsRow(
                    icon: Icons.fingerprint_rounded,
                    iconColor: AppleTheme.applePurple,
                    title: 'Phiên phụ huynh',
                    trailingText: 'Anonymous Auth (Zero-Login)',
                  ),
                  const Divider(color: AppleTheme.hairlineDivider, height: 1, indent: 62),
                  _buildSettingsRow(
                    icon: Icons.security_rounded,
                    iconColor: AppleTheme.appleAmber,
                    title: 'Chính sách bảo vệ',
                    trailingText: 'Device Admin & DO Enforce',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
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
          fontFamily: 'sans-serif',
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
    String? trailingText,
    Widget? trailingWidget,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'sans-serif',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppleTheme.textPrimary,
                ),
              ),
            ),
            if (trailingText != null)
              Text(
                trailingText,
                style: const TextStyle(
                  fontFamily: 'sans-serif',
                  fontSize: 14,
                  color: AppleTheme.textSecondary,
                ),
              ),
            ?trailingWidget,
          ],
        ),
      ),
    );
  }
}
