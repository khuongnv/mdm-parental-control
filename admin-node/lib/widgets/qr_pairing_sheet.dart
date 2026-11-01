import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/mdm_supabase_service.dart';
import '../services/activity_history_service.dart';
import '../widgets/apple_notification.dart';
import '../main.dart';

/// Bảng điều khiển Ghép nối Thiết bị Con (QR Scanner + OTP Manual) chuẩn Apple Music
class QrPairingSheet extends StatefulWidget {
  final MdmSupabaseService supabaseService;
  final void Function(String deviceName)? onPaired;

  const QrPairingSheet({
    super.key,
    required this.supabaseService,
    this.onPaired,
  });

  /// Hiển thị Modal Sheet ghép nối chuẩn Apple
  static Future<bool?> show(
    BuildContext context, {
    required MdmSupabaseService supabaseService,
    void Function(String deviceName)? onPaired,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => QrPairingSheet(
        supabaseService: supabaseService,
        onPaired: onPaired,
      ),
    );
  }

  @override
  State<QrPairingSheet> createState() => _QrPairingSheetState();
}

class _QrPairingSheetState extends State<QrPairingSheet>
    with SingleTickerProviderStateMixin {
  int _selectedTabIndex = 0; // 0: Quét QR, 1: Nhập OTP
  late MobileScannerController _scannerController;
  final TextEditingController _otpTextController = TextEditingController();

  late AnimationController _laserAnimController;
  late Animation<double> _laserPositionAnimation;

  bool _isProcessing = false;
  bool _isTorchOn = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
      facing: CameraFacing.back,
    );

    _laserAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _laserPositionAnimation = Tween<double>(begin: 0.08, end: 0.92).animate(
      CurvedAnimation(
        parent: _laserAnimController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _laserAnimController.dispose();
    _scannerController.dispose();
    _otpTextController.dispose();
    super.dispose();
  }

  /// Trích xuất mã OTP 6 chữ số từ nhiều định dạng mã quét (URI, raw, JSON, query)
  static String? extractOtp(String raw) {
    final trimmed = raw.trim();

    // 1. Mã thuần 6 chữ số
    if (RegExp(r'^\d{6}$').hasMatch(trimmed)) {
      return trimmed;
    }

    // 2. Định dạng URI chuẩn VFam: vfam://pair?otp=123456&device=...
    try {
      final uri = Uri.parse(trimmed);
      final otp = uri.queryParameters['otp'];
      if (otp != null && RegExp(r'^\d{6}$').hasMatch(otp.trim())) {
        return otp.trim();
      }
    } catch (_) {}

    // 3. Định dạng JSON: {"otp": "123456", ...}
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map && decoded['otp'] != null) {
        final otp = decoded['otp'].toString().trim();
        if (RegExp(r'^\d{6}$').hasMatch(otp)) {
          return otp;
        }
      }
    } catch (_) {}

    // 4. Tìm kiếm chuỗi phụ otp=XXXXXX
    final match = RegExp(r'otp=(\d{6})', caseSensitive: false).firstMatch(trimmed);
    if (match != null) {
      return match.group(1);
    }

    return null;
  }

  /// Xử lý sự kiện nhận diện mã QR từ Camera
  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_isProcessing) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        final otp = extractOtp(rawValue);
        if (otp != null) {
          _submitClaim(otp);
          break;
        } else {
          // Mã QR không đúng cấu trúc VFam
          _showInvalidQrWarning();
          break;
        }
      }
    }
  }

  void _showInvalidQrWarning() {
    if (_isProcessing) return;
    HapticFeedback.selectionClick();
    setState(() {
      _statusMessage = '⚠️ Mã QR không hợp lệ. Vui lòng quét mã từ app VFam Child.';
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_isProcessing) {
        setState(() {
          _statusMessage = null;
        });
      }
    });
  }

  /// Gửi yêu cầu ghép nối thiết bị con lên Supabase
  Future<void> _submitClaim(String otp) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Đang liên kết thiết bị với mã: $otp...';
    });

    try {
      HapticFeedback.mediumImpact();
      final result = await widget.supabaseService.claimDevice(otp);
      final devName = result['device_name'] ?? 'Thiết bị con';

      await ActivityHistoryService.logActivity(
        type: ActivityType.pairing,
        title: 'Ghép Nối Thành Công',
        subtitle: 'Đã liên kết thiết bị: $devName',
      );

      if (mounted) {
        AppleNotification.show(
          context,
          title: 'Ghép Nối Thành Công',
          message: 'Đã liên kết hoàn tất với $devName',
          icon: Icons.check_circle_rounded,
          iconColor: AppleTheme.appleGreen,
        );
        widget.onPaired?.call(devName);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        AppleNotification.show(
          context,
          title: 'Ghép Nối Thất Bại',
          message: e.toString().replaceFirst('Exception: ', ''),
          icon: Icons.error_outline_rounded,
          iconColor: AppleTheme.appleRed,
        );
        setState(() {
          _isProcessing = false;
          _statusMessage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isDark = context.isDark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: context.borderColor, width: 0.75),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.2),
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // Thanh kéo Drag Handle chuẩn Apple
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Tiêu đề & Nút đóng
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ghép Nối Thiết Bị Con',
                          style: AppleTypography.titleLarge.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Liên kết máy con vào hệ thống giám sát gia đình',
                          style: AppleTypography.bodyMedium.copyWith(
                            fontSize: 13,
                            color: AppleTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: context.surfaceVariantColor,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: context.textPrimaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Segmented Control Apple Style
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: context.surfaceVariantColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTabButton(
                          index: 0,
                          icon: Icons.qr_code_scanner_rounded,
                          label: 'Quét Mã QR',
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _buildTabButton(
                          index: 1,
                          icon: Icons.pin_rounded,
                          label: 'Nhập Mã OTP',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Nội dung hiển thị theo Tab
              AnimatedCrossFade(
                firstChild: _buildQrScannerView(context),
                secondChild: _buildManualOtpView(context),
                crossFadeState: _selectedTabIndex == 0
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                duration: const Duration(milliseconds: 240),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// Nút bấm chuyển Tab kiểu iOS Segmented Pill
  Widget _buildTabButton({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _selectedTabIndex == index;
    final isDark = context.isDark;

    return GestureDetector(
      onTap: () {
        if (_selectedTabIndex != index) {
          HapticFeedback.selectionClick();
          setState(() {
            _selectedTabIndex = index;
            _statusMessage = null;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF3A3A3C) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                    blurRadius: 6,
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
              color: isSelected ? AppleTheme.appleGreen : AppleTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppleTypography.bodyMedium.copyWith(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? context.textPrimaryColor : AppleTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Màn hình Quét QR Code với Camera Viewfinder
  Widget _buildQrScannerView(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Khung Viewfinder Camera
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              width: double.infinity,
              height: 290,
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Camera Scanner Stream
                  MobileScanner(
                    controller: _scannerController,
                    onDetect: _onBarcodeDetected,
                    errorBuilder: (ctx, error) {
                      return Container(
                        padding: const EdgeInsets.all(24),
                        color: const Color(0xFF1C1C1E),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.videocam_off_rounded,
                              size: 46,
                              color: AppleTheme.appleAmber,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Không thể mở Camera',
                              style: AppleTypography.titleLarge.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Vui lòng cấp quyền Camera trong Cài đặt hoặc chuyển sang tab Nhập Mã OTP.',
                              textAlign: TextAlign.center,
                              style: AppleTypography.bodyMedium.copyWith(
                                fontSize: 13,
                                color: AppleTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedTabIndex = 1;
                                });
                              },
                              icon: const Icon(Icons.pin_rounded, size: 16),
                              label: const Text('Chuyển Sang Nhập OTP'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppleTheme.appleGreen,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // Khung ngắm Reticle Apple Style
                  Center(
                    child: SizedBox(
                      width: 210,
                      height: 210,
                      child: Stack(
                        children: [
                          CustomPaint(
                            size: const Size(210, 210),
                            painter: _ScannerTargetPainter(
                              color: AppleTheme.appleGreen,
                            ),
                          ),
                          // Tia quét Laser chuyển động
                          if (!_isProcessing)
                            AnimatedBuilder(
                              animation: _laserPositionAnimation,
                              builder: (ctx, child) {
                                return Positioned(
                                  top: 210 * _laserPositionAnimation.value,
                                  left: 12,
                                  right: 12,
                                  child: Container(
                                    height: 2.5,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          AppleTheme.appleGreen.withValues(alpha: 0.1),
                                          AppleTheme.appleGreen,
                                          AppleTheme.appleGreen.withValues(alpha: 0.1),
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppleTheme.appleGreen.withValues(alpha: 0.6),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Đang xử lý ghép nối (Overlay HUD)
                  if (_isProcessing)
                    Container(
                      color: Colors.black.withValues(alpha: 0.72),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CupertinoActivityIndicator(
                            radius: 16,
                            color: AppleTheme.appleGreen,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _statusMessage ?? 'Đang xác thực ghép nối...',
                            textAlign: TextAlign.center,
                            style: AppleTypography.bodyMedium.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Thanh công cụ trên khung camera (Flash & Flip Camera)
                  Positioned(
                    bottom: 12,
                    left: 12,
                    right: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Nút bật/tắt Đèn Flash (Torch)
                        _buildCameraControlButton(
                          icon: _isTorchOn
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                          isActive: _isTorchOn,
                          onPressed: () async {
                            try {
                              await _scannerController.toggleTorch();
                              setState(() {
                                _isTorchOn = !_isTorchOn;
                              });
                            } catch (_) {}
                          },
                        ),
                        // Nút xoay Camera trước/sau
                        _buildCameraControlButton(
                          icon: Icons.flip_camera_ios_rounded,
                          isActive: false,
                          onPressed: () async {
                            try {
                              await _scannerController.switchCamera();
                            } catch (_) {}
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Lời dẫn hướng dẫn
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.center_focus_strong_rounded,
                size: 16,
                color: AppleTheme.appleGreen,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Hướng camera về mã QR trên ứng dụng VFam Child',
                  textAlign: TextAlign.center,
                  style: AppleTypography.bodyMedium.copyWith(
                    fontSize: 13,
                    color: AppleTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),

          if (_statusMessage != null && !_isProcessing) ...[
            const SizedBox(height: 8),
            Text(
              _statusMessage!,
              textAlign: TextAlign.center,
              style: AppleTypography.bodyMedium.copyWith(
                fontSize: 12,
                color: AppleTheme.appleAmber,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Nút tròn bán trong suốt phủ trên Camera
  Widget _buildCameraControlButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isActive
              ? AppleTheme.appleGreen
              : Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 0.75,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isActive ? Colors.black : Colors.white,
        ),
      ),
    );
  }

  /// Giao diện Nhập Mã OTP Thủ Công
  Widget _buildManualOtpView(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Nhập mã số OTP 6 chữ số đang hiển thị trên ứng dụng VFam Child của con:',
            textAlign: TextAlign.center,
            style: AppleTypography.bodyMedium.copyWith(
              fontSize: 14,
              height: 1.35,
              color: AppleTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 20),

          // Ô nhập OTP cách điệu
          TextField(
            controller: _otpTextController,
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
              fillColor: context.surfaceVariantColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: context.borderColor, width: 0.75),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: context.borderColor, width: 0.75),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppleTheme.appleGreen, width: 1.5),
              ),
              hintText: '••••••',
              hintStyle: const TextStyle(
                color: AppleTheme.textSecondary,
                letterSpacing: 8,
              ),
              counterText: '',
            ),
          ),

          const SizedBox(height: 20),

          // Nút xác nhận ghép nối
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppleTheme.appleGreen,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            onPressed: _isProcessing
                ? null
                : () {
                    final otp = _otpTextController.text.trim();
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
                    _submitClaim(otp);
                  },
            child: _isProcessing
                ? const CupertinoActivityIndicator(radius: 12, color: Colors.black)
                : Text(
                    'Xác Nhận Ghép Nối',
                    style: AppleTypography.bodyMedium.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Painter vẽ 4 góc Reticle ngắm chuẩn Apple Scanner
class _ScannerTargetPainter extends CustomPainter {
  final Color color;

  static const double _cornerLength = 26.0;
  static const double _strokeWidth = 3.5;
  static const double _cornerRadius = 14.0;

  _ScannerTargetPainter({
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    const r = _cornerRadius;
    const l = _cornerLength;

    // Góc trên bên trái
    final pathTL = Path()
      ..moveTo(0, l)
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..lineTo(l, 0);
    canvas.drawPath(pathTL, paint);

    // Góc trên bên phải
    final pathTR = Path()
      ..moveTo(w - l, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..lineTo(w, l);
    canvas.drawPath(pathTR, paint);

    // Góc dưới bên trái
    final pathBL = Path()
      ..moveTo(0, h - l)
      ..lineTo(0, h - r)
      ..arcToPoint(Offset(r, h), radius: Radius.circular(r))
      ..lineTo(l, h);
    canvas.drawPath(pathBL, paint);

    // Góc dưới bên phải
    final pathBR = Path()
      ..moveTo(w - l, h)
      ..lineTo(w - r, h)
      ..arcToPoint(Offset(w, h - r), radius: Radius.circular(r))
      ..lineTo(w, h - l);
    canvas.drawPath(pathBR, paint);
  }

  @override
  bool shouldRepaint(covariant _ScannerTargetPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
