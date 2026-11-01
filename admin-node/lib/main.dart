import 'dart:async';
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

/// Hệ màu chuẩn Apple Music UI/UX Design System
class AppleTheme {
  static const Color darkBackground = Color(0xFF000000); // Deep AMOLED Black
  static const Color darkSurface = Color(0xFF1C1C1E); // Secondary System Background
  static const Color darkSurfaceElevated = Color(0xFF2C2C2E); // Tertiary System Background
  static const Color hairlineDivider = Color(0xFF38383A); // Hairline Divider
  static const Color appleRed = Color(0xFFFA2D55); // Primary Accent (Apple Music Red)
  static const Color appleBlue = Color(0xFF007AFF); // iOS System Blue
  static const Color appleGreen = Color(0xFF34C759); // iOS System Green
  static const Color appleAmber = Color(0xFFFF9500); // iOS System Orange/Amber
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93); // iOS System Gray
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
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            color: AppleTheme.textPrimary,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppleTheme.darkSurface,
          selectedItemColor: AppleTheme.appleRed,
          unselectedItemColor: AppleTheme.textSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
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
          border: Border(
            top: BorderSide(color: AppleTheme.hairlineDivider, width: 0.5),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          backgroundColor: AppleTheme.darkSurface.withOpacity(0.95),
          indicatorColor: AppleTheme.appleRed.withOpacity(0.18),
          elevation: 0,
          onDestinationSelected: (index) {
            HapticFeedback.lightImpact();
            setState(() => _currentIndex = index);
            if (index == 1) {
              _historyKey.currentState?.refresh();
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.shield_outlined, color: AppleTheme.textSecondary),
              selectedIcon: Icon(Icons.shield, color: AppleTheme.appleRed),
              label: 'Giám Sát',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_toggle_off, color: AppleTheme.textSecondary),
              selectedIcon: Icon(Icons.history, color: AppleTheme.appleRed),
              label: 'Lịch Sử',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined, color: AppleTheme.textSecondary),
              selectedIcon: Icon(Icons.tune, color: AppleTheme.appleRed),
              label: 'Cài Đặt',
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// TAB 1: DASHBOARD (GIÁM SÁT THỜI GIAN THỰC)
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

        // Đăng ký Presence thời gian thực
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
        title: const Text('Ghép Nối Thiết Bị Con', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nhập mã OTP 6 chữ số đang hiển thị trên màn hình ứng dụng VFam Child của con:',
              style: TextStyle(color: AppleTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 10, color: AppleTheme.textPrimary),
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
            child: const Text('Hủy', style: TextStyle(color: AppleTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppleTheme.appleRed),
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
                  title: 'Ghép Nối Thiết Bị Mới',
                  subtitle: result['device_name'] != null ? 'Đã ghép nối thiết bị: ${result['device_name']}' : 'Ghép nối thành công',
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
                    SnackBar(backgroundColor: Colors.red.shade900, content: Text('Lỗi ghép nối: $e')),
                  );
                }
              }
            },
            child: const Text('Xác Nhận', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLockdown() async {
    if (activeDevice == null) return;
    HapticFeedback.heavyImpact();

    final deviceId = activeDevice!['id'] as String;
    final deviceName = activeDevice!['device_name'] ?? 'Thiết bị con';
    final targetLock = !isEmergencyLocked;

    setState(() => isEmergencyLocked = targetLock);

    try {
      await _supabaseService.triggerPanicLockdown(deviceId, targetLock);
      await ActivityHistoryService.logActivity(
        type: targetLock ? ActivityType.lock : ActivityType.unlock,
        title: targetLock ? 'Khóa Khẩn Cấp Thiết Bị' : 'Mở Khóa Thiết Bị',
        subtitle: targetLock ? 'Đã kích hoạt khóa ngay lập tức trên $deviceName' : 'Đã gỡ bỏ khóa và cho phép sử dụng lại trên $deviceName',
      );
      widget.onActionLogged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: targetLock ? AppleTheme.appleRed : AppleTheme.appleGreen,
            content: Text(targetLock ? '🚨 Đã gửi lệnh KHÓA KHẨN CẤP tới $deviceName' : '✅ Đã gửi lệnh MỞ KHÓA cho $deviceName'),
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
        title: 'Thưởng Thêm Giờ Sử Dụng',
        subtitle: 'Đã cộng thêm +$minutes phút cho $deviceName',
      );
      widget.onActionLogged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppleTheme.appleBlue,
            content: Text('🎁 Đã thưởng thêm +$minutes phút cho $deviceName'),
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
      appBar: AppBar(
        title: const Text('VFam Giám Sát'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppleTheme.textSecondary),
            tooltip: 'Làm mới',
            onPressed: _loadDeviceData,
          ),
          IconButton(
            icon: const Icon(Icons.add_link, color: AppleTheme.appleRed),
            tooltip: 'Ghép nối OTP',
            onPressed: _showPairingDialog,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: AppleTheme.appleRed))
          : RefreshIndicator(
              color: AppleTheme.appleRed,
              backgroundColor: AppleTheme.darkSurface,
              onRefresh: _loadDeviceData,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  if (errorMessage != null) ...[
                    _buildErrorBanner(errorMessage!),
                    const SizedBox(height: 16),
                  ],

                  // Card Trạng Thái Thiết Bị Con
                  _buildDeviceCard(),
                  const SizedBox(height: 20),

                  // Thẻ Quota Thời Gian Sử Dụng
                  _buildQuotaCard(),
                  const SizedBox(height: 20),

                  // Bảng Điều Khiển Tức Thì (Lock & Extra Time)
                  _buildQuickActionSection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2C0B0E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade800, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.redAccent, size: 22),
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

  Widget _buildDeviceCard() {
    final hasDevice = activeDevice != null;
    final deviceName = hasDevice ? (activeDevice!['device_name'] ?? 'Thiết bị con') : 'Chưa ghép nối thiết bị';
    final model = hasDevice ? (activeDevice!['model'] ?? 'Android') : 'Bấm nút ghép nối ở góc trên';
    final osVersion = hasDevice ? (activeDevice!['os_version'] ?? '') : '';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppleTheme.darkSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppleTheme.hairlineDivider, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: isEmergencyLocked
                  ? AppleTheme.appleRed.withOpacity(0.15)
                  : (isOnline ? AppleTheme.appleGreen.withOpacity(0.15) : AppleTheme.darkSurfaceElevated),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isEmergencyLocked ? Icons.lock_rounded : Icons.phone_android_rounded,
              color: isEmergencyLocked ? AppleTheme.appleRed : (isOnline ? AppleTheme.appleGreen : AppleTheme.textSecondary),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        deviceName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppleTheme.textPrimary),
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
                const SizedBox(height: 4),
                Text(
                  hasDevice ? '$model • $osVersion' : 'Chưa có máy con liên kết',
                  style: const TextStyle(fontSize: 13, color: AppleTheme.textSecondary),
                ),
              ],
            ),
          ),
          if (!hasDevice)
            FilledButton.tonal(
              onPressed: _showPairingDialog,
              style: FilledButton.styleFrom(backgroundColor: AppleTheme.appleRed.withOpacity(0.15)),
              child: const Text('Ghép Nối', style: TextStyle(color: AppleTheme.appleRed, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  Widget _buildQuotaCard() {
    final dailyLimitMins = 120;
    final totalAvailableMins = dailyLimitMins + extraTimeMinutes;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppleTheme.darkSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppleTheme.hairlineDivider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Hạn Mức Thời Gian Hôm Nay', style: TextStyle(fontSize: 14, color: AppleTheme.textSecondary)),
              if (extraTimeMinutes > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppleTheme.appleBlue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '+$extraTimeMinutes phút thưởng',
                    style: const TextStyle(color: AppleTheme.appleBlue, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${totalAvailableMins ~/ 60}h ${totalAvailableMins % 60}m Cho Phép',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppleTheme.textPrimary),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: isEmergencyLocked ? 1.0 : 0.35,
              minHeight: 8,
              backgroundColor: AppleTheme.darkSurfaceElevated,
              valueColor: AlwaysStoppedAnimation<Color>(
                isEmergencyLocked ? AppleTheme.appleRed : AppleTheme.appleAmber,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isEmergencyLocked
                ? '🚨 Thiết bị đang ở trạng thái Khóa Khẩn Cấp tầng hệ điều hành.'
                : '🛡️ Thiết bị đang trong khung giờ an toàn và được bảo vệ.',
            style: TextStyle(
              fontSize: 13,
              color: isEmergencyLocked ? AppleTheme.appleRed : AppleTheme.textSecondary,
              fontWeight: isEmergencyLocked ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text('ĐIỀU KHIỂN NHANH', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppleTheme.textSecondary, letterSpacing: 0.8)),
        ),

        // Nút Khóa Khẩn Cấp Toàn Phần (Hero Lockdown Button)
        GestureDetector(
          onTap: _toggleLockdown,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isEmergencyLocked
                    ? [const Color(0xFF10B981), const Color(0xFF059669)] // Xanh mở khóa
                    : [const Color(0xFFFA2D55), const Color(0xFFD90429)], // Đỏ khóa
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: (isEmergencyLocked ? AppleTheme.appleGreen : AppleTheme.appleRed).withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isEmergencyLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Text(
                  isEmergencyLocked ? 'MỞ KHÓA THIẾT BỊ NGAY' : 'KHÓA KHẨN CẤP THIẾT BỊ',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Hàng nút thưởng thêm thời gian (+15m, +30m, +1h)
        Row(
          children: [
            Expanded(child: _buildTimeRewardButton('+15 Phút', 15)),
            const SizedBox(width: 10),
            Expanded(child: _buildTimeRewardButton('+30 Phút', 30)),
            const SizedBox(width: 10),
            Expanded(child: _buildTimeRewardButton('+1 Giờ', 60)),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeRewardButton(String label, int minutes) {
    return InkWell(
      onTap: () => _grantExtraTime(minutes),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppleTheme.darkSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppleTheme.hairlineDivider, width: 0.5),
        ),
        child: Column(
          children: [
            const Icon(Icons.more_time_rounded, color: AppleTheme.appleBlue, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppleTheme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// TAB 2: HISTORY (LỊCH SỬ TƯƠNG TÁC & AUDIT LOGS)
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
      appBar: AppBar(
        title: const Text('Lịch Sử Tương Tác'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppleTheme.textSecondary),
            tooltip: 'Xóa lịch sử',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppleTheme.darkSurface,
                  title: const Text('Xóa lịch sử?'),
                  content: const Text('Toàn bộ nhật ký gửi lệnh sẽ được làm sạch.', style: TextStyle(color: AppleTheme.textSecondary)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
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
            icon: const Icon(Icons.refresh, color: AppleTheme.textSecondary),
            onPressed: refresh,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppleTheme.appleRed))
          : _activities.isEmpty
              ? const Center(
                  child: Text('Chưa có nhật ký hoạt động nào', style: TextStyle(color: AppleTheme.textSecondary)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _activities.length,
                  separatorBuilder: (context, index) => const Divider(
                    color: AppleTheme.hairlineDivider,
                    height: 1,
                    indent: 58,
                  ),
                  itemBuilder: (context, index) {
                    final item = _activities[index];
                    return _buildTimelineItem(item);
                  },
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
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
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppleTheme.textPrimary),
                    ),
                    Text(
                      timeStr,
                      style: const TextStyle(fontSize: 12, color: AppleTheme.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  style: const TextStyle(fontSize: 13, color: AppleTheme.textSecondary, height: 1.3),
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
// TAB 3: SETTINGS & AUTO-UPDATE GITHUB
// ==============================================================================

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final ParentAppUpdater _updater = ParentAppUpdater();

  String currentVersion = '1.1.0';
  bool isCheckingUpdate = false;
  double? downloadProgress;
  String? updateMessage;

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
    setState(() {
      isCheckingUpdate = true;
      updateMessage = null;
    });

    final releaseInfo = await _updater.checkForUpdate(currentVersion);

    if (!mounted) return;

    setState(() => isCheckingUpdate = false);

    if (releaseInfo == null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppleTheme.darkSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Đã Là Bản Mới Nhất'),
          content: Text('Ứng dụng VFam Admin đang ở phiên bản mới nhất ($currentVersion). Không có bản cập nhật nào.'),
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
                  style: const TextStyle(color: AppleTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Text('Nội dung cập nhật:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppleTheme.darkSurfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      release.releaseNotes.isNotEmpty ? release.releaseNotes : 'Tối ưu hóa hiệu năng và vá lỗi hệ thống.',
                      style: const TextStyle(color: AppleTheme.textSecondary, fontSize: 13, height: 1.3),
                    ),
                  ),
                ),
                if (downloadProgress != null) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: downloadProgress,
                    backgroundColor: AppleTheme.darkSurfaceElevated,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppleTheme.appleRed),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Đang tải: ${(downloadProgress! * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(color: AppleTheme.appleRed, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (downloadProgress == null) ...[
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Để Sau', style: TextStyle(color: AppleTheme.textSecondary)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppleTheme.appleRed),
                  onPressed: () async {
                    setDialogState(() => downloadProgress = 0.0);
                    try {
                      final apkFile = await _updater.downloadApk(
                        release.apkDownloadUrl,
                        onProgress: (prog, rec, tot) {
                          setDialogState(() => downloadProgress = prog);
                        },
                      );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      await _updater.installApk(apkFile);
                    } catch (e) {
                      setDialogState(() => downloadProgress = null);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(backgroundColor: Colors.red.shade900, content: Text('Lỗi tải cập nhật: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Cập Nhật Ngay', style: TextStyle(fontWeight: FontWeight.bold)),
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
      appBar: AppBar(title: const Text('Cài Đặt & Hệ Thống')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Thẻ Thông Tin Ứng Dụng
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppleTheme.darkSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppleTheme.hairlineDivider, width: 0.5),
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppleTheme.appleRed.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.admin_panel_settings, color: AppleTheme.appleRed, size: 36),
                ),
                const SizedBox(height: 12),
                const Text(
                  'VFam Parental Admin',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppleTheme.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Phiên bản $currentVersion (Build 2)',
                  style: const TextStyle(fontSize: 13, color: AppleTheme.textSecondary),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppleTheme.darkSurfaceElevated,
                      foregroundColor: AppleTheme.appleRed,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: isCheckingUpdate ? null : _checkUpdate,
                    icon: isCheckingUpdate
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppleTheme.appleRed))
                        : const Icon(Icons.cloud_sync_rounded),
                    label: Text(
                      isCheckingUpdate ? 'Đang Kiểm Tra GitHub...' : 'Kiểm Tra Bản Cập Nhật Mới',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Thông tin kết nối Supabase Cloud
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('HẠ TẦNG CLOUD & BẢO MẬT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppleTheme.textSecondary, letterSpacing: 0.8)),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppleTheme.darkSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppleTheme.hairlineDivider, width: 0.5),
            ),
            child: Column(
              children: [
                _buildInfoTile('Hạ Tầng Backend', 'Supabase BaaS Realtime', Icons.cloud_done_rounded, AppleTheme.appleBlue),
                const Divider(color: AppleTheme.hairlineDivider, height: 1, indent: 56),
                _buildInfoTile('Định Danh Phụ Huynh', 'Anonymous Auth (Zero-Login)', Icons.fingerprint_rounded, AppleTheme.appleGreen),
                const Divider(color: AppleTheme.hairlineDivider, height: 1, indent: 56),
                _buildInfoTile('Kênh Điều Khiển', 'WebSocket Phoenix & FCM', Icons.bolt_rounded, AppleTheme.appleAmber),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String title, String subtitle, IconData icon, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppleTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: AppleTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
