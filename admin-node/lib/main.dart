import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const MdmParentApp());
}

class MdmParentApp extends StatelessWidget {
  const MdmParentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MDM Parent Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD0BCFF),
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
  bool isEmergencyLocked = false;
  int usedMinutes = 85;
  final int totalQuotaMinutes = 120;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (usedMinutes / totalQuotaMinutes).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MDM Giám Sát Con'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Ghép nối thiết bị mới',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mở trình quét QR ghép nối...')),
              );
            },
          ),
        ],
      ),
      body: ListView(
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
                    backgroundColor: isEmergencyLocked ? Colors.red.shade100 : Colors.green.shade100,
                    child: Icon(
                      isEmergencyLocked ? Icons.lock : Icons.phone_android,
                      color: isEmergencyLocked ? Colors.red : Colors.green,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Galaxy Tab A9 (Bé Nam)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isEmergencyLocked ? Colors.red : Colors.green,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isEmergencyLocked ? 'Bị khóa khẩn cấp' : 'Trực tuyến • Đang mở: Duolingo',
                              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ],
                    ),
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
                        onPressed: () {
                          setState(() {
                            usedMinutes = (usedMinutes - 15).clamp(0, totalQuotaMinutes);
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã thưởng thêm 15 phút!')),
                          );
                        },
                      ),
                      FilledButton.tonalIcon(
                        icon: Icon(isEmergencyLocked ? Icons.lock_open : Icons.lock),
                        label: Text(isEmergencyLocked ? 'Mở Khóa' : 'Khóa Ngay'),
                        style: FilledButton.styleFrom(
                          backgroundColor: isEmergencyLocked ? Colors.green.shade100 : Colors.red.shade100,
                          foregroundColor: isEmergencyLocked ? Colors.green.shade800 : Colors.red.shade800,
                        ),
                        onPressed: () {
                          setState(() {
                            isEmergencyLocked = !isEmergencyLocked;
                          });
                        },
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
