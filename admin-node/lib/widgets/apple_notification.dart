import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/system_font_manager.dart';

/// Floating Dynamic Capsule / Liquid Glass Toast HUD chuẩn Apple Music
class AppleNotification {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
    Duration duration = const Duration(milliseconds: 2800),
  }) {
    // Rung phản hồi haptic
    HapticFeedback.mediumImpact();

    // Hủy notification cũ nếu đang hiển thị
    _dismissTimer?.cancel();
    _currentEntry?.remove();
    _currentEntry = null;

    final overlay = Overlay.of(context);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _AppleNotificationWidget(
        title: title,
        message: message,
        icon: icon,
        iconColor: iconColor,
        onDismiss: () {
          _dismissTimer?.cancel();
          if (_currentEntry == entry) {
            _currentEntry?.remove();
            _currentEntry = null;
          }
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _dismissTimer = Timer(duration, () {
      if (_currentEntry == entry) {
        _currentEntry?.remove();
        _currentEntry = null;
      }
    });
  }
}

class _AppleNotificationWidget extends StatefulWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onDismiss;

  const _AppleNotificationWidget({
    required this.title,
    required this.message,
    required this.icon,
    required this.iconColor,
    required this.onDismiss,
  });

  @override
  State<_AppleNotificationWidget> createState() => _AppleNotificationWidgetState();
}

class _AppleNotificationWidgetState extends State<_AppleNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xF21E1E22) : const Color(0xF2FFFFFF);
    final border = isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000);
    final titleColor = isDark ? Colors.white : Colors.black;
    final shadowColor = isDark ? Colors.black.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.12);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: GestureDetector(
                onTap: _handleDismiss,
                onVerticalDragUpdate: (details) {
                  if (details.primaryDelta != null && details.primaryDelta! < -5) {
                    _handleDismiss();
                  }
                },
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: border, width: 0.75),
                      boxShadow: [
                        BoxShadow(
                          color: shadowColor,
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: widget.iconColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(widget.icon, color: widget.iconColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: SystemFontManager.fontFamily,
                                  fontFamilyFallback: [
                                    SystemFontManager.fontFamily,
                                    'SamsungSans',
                                    'sec-roboto-light',
                                    'sans-serif',
                                    'Roboto',
                                  ],
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: titleColor,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                widget.message,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: SystemFontManager.fontFamily,
                                  fontFamilyFallback: [
                                    SystemFontManager.fontFamily,
                                    'SamsungSans',
                                    'sec-roboto-light',
                                    'sans-serif',
                                    'Roboto',
                                  ],
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w400,
                                  color: const Color(0xFF8E8E93),
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
