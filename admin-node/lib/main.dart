import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'services/mdm_supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await MdmSupabaseService.initialize();
  } catch (e) {
    debugPrint('Supabase init error: $e');
  }
  runApp(const MdmParentApp());
}

class MdmParentApp extends StatelessWidget {
  const MdmParentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VFam Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A), // Royal Cobalt Navy
          secondary: const Color(0xFFF59E0B), // Amber Gold
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6), // Royal Blue Light
          secondary: const Color(0xFFFBBF24), // Gold Light
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final MdmSupabaseService _supabaseService = MdmSupabaseService();
  String? activeDeviceId;
  String activeDeviceName = 'Thiết bị con';
  bool isEmergencyLocked = false;
  bool isOnline = true;
  int usedMinutes = 85;
  int totalQuotaMinutes = 120;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final devices = await _supabaseService.getFamilyDevices();
      if (devices.isNotEmpty && mounted) {
        final dev = devices.first;
        setState(() {
          activeDeviceId = dev['id'];
          activeDeviceName = dev['device_name'] ?? 'Thiết bị con';
          isEmergencyLocked = dev['is_locked'] == true;
          isLoading = false;
        });

        // Đăng ký Realtime Presence
        if (activeDeviceId != null) {
          _supabaseService.subscribeDevicePresence(
            activeDeviceId!,
            onStatusChanged: (online, meta) {
              if (mounted) {
                setState(() {
                  isOnline = online;
                });
              }
            },
          );
        }
      } else if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading initial devices: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showPairingDialog() {
    final otpController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ghép Nối Thiết Bị Con'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nhập mã OTP 6 chữ số hiển thị trên màn hình ứng dụng con:'),
            const SizedBox(height: 16),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '123456',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              final otp = otpController.text.trim();
              if (otp.length != 6) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Vui lòng nhập đủ 6 chữ số')),
                  );
                }
                return;
              }
              Navigator.pop(ctx);
              try {
                final result = await _supabaseService.claimDevice(otp);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result['message'] ?? 'Ghép nối thành công!')),
                  );
                  _loadInitialData();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Lỗi: $e')),
                  );
                }
              }
            },
            child: const Text('Xác Nhận'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLockdown() async {
    final targetState = !isEmergencyLocked;
    setState(() => isEmergencyLocked = targetState);

    if (activeDeviceId != null) {
      try {
        await _supabaseService.triggerPanicLockdown(activeDeviceId!, targetState);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(targetState ? 'Đã gửi lệnh KHÓA KHẨN CẤP tới thiết bị con' : 'Đã gửi lệnh MỞ KHÓA thiết bị con'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => isEmergencyLocked = !targetState);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi gửi lệnh khóa: $e')),
          );
        }
      }
    }
  }

  Future<void> _grantExtraTime(int minutes) async {
    setState(() {
      usedMinutes = (usedMinutes - minutes).clamp(0, totalQuotaMinutes);
    });

    if (activeDeviceId != null) {
      try {
        await _supabaseService.grantExtraTime(activeDeviceId!, minutes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã thưởng thêm $minutes phút cho thiết bị con')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi cộng thêm thời gian: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (usedMinutes / totalQuotaMinutes).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MDM Giám Sát Con (Supabase)'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: 'Ghép nối mã OTP',
            onPressed: _showPairingDialog,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // Device Status Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: isEmergencyLocked ? Colors.red.shade100 : (isOnline ? Colors.green.shade100 : Colors.grey.shade200),
                          child: Icon(
                            isEmergencyLocked ? Icons.lock : Icons.phone_android,
                            color: isEmergencyLocked ? Colors.red : (isOnline ? Colors.green : Colors.grey),
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(activeDeviceName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isEmergencyLocked ? Colors.red : (isOnline ? Colors.green : Colors.grey),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isEmergencyLocked
                                        ? 'Bị khóa khẩn cấp'
                                        : (isOnline ? 'Trực tuyến (Supabase Realtime)' : 'Ngoại tuyến (Offline)'),
                                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Tải lại',
                          onPressed: _loadInitialData,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Screen Time Progress Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Text('Thời gian sử dụng hôm nay', style: theme.textTheme.titleSmall?.copyWith(color: Colors.grey.shade600)),
                        const SizedBox(height: 12),
                        Text('${usedMinutes ~/ 60}h ${usedMinutes % 60}m / ${totalQuotaMinutes ~/ 60}h ${totalQuotaMinutes % 60}m',
                            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: percent,
                          minHeight: 12,
                          borderRadius: BorderRadius.circular(8),
                          color: percent > 0.9 ? Colors.red : (percent > 0.7 ? Colors.orange : Colors.green),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.more_time),
                              label: const Text('+15 Phút'),
                              onPressed: () => _grantExtraTime(15),
                            ),
                            FilledButton.tonalIcon(
                              icon: Icon(isEmergencyLocked ? Icons.lock_open : Icons.lock),
                              label: Text(isEmergencyLocked ? 'Mở Khóa' : 'Khóa Ngay'),
                              style: FilledButton.styleFrom(
                                backgroundColor: isEmergencyLocked ? Colors.green.shade100 : Colors.red.shade100,
                                foregroundColor: isEmergencyLocked ? Colors.green.shade800 : Colors.red.shade800,
                              ),
                              onPressed: _toggleLockdown,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // App Usage Breakdown Chart
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Phân Bổ Thể Loại Ứng Dụng', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 160,
                          child: PieChart(
                            PieChartData(
                              sectionsSpace: 4,
                              centerSpaceRadius: 40,
                              sections: [
                                PieChartSectionData(color: Colors.blue, value: 50, title: 'Học tập 50m', radius: 45, titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                                PieChartSectionData(color: Colors.orange, value: 20, title: 'Giải trí 20m', radius: 45, titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                                PieChartSectionData(color: Colors.purple, value: 15, title: 'Mạng XH 15m', radius: 45, titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
