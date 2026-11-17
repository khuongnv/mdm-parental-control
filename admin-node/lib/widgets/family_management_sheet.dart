import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../services/mdm_supabase_service.dart';
import 'apple_notification.dart';

/// Modal Quản Lý Gia Đình Chuẩn Apple Style
/// Cho phép tạo gia đình, đổi tên, thêm phụ huynh (Co-Admin), thêm thiết bị con và chuyển đổi gia đình
class FamilyManagementSheet extends StatefulWidget {
  final String activeFamilyId;
  final Function(String newFamilyId)? onFamilySwitched;
  final VoidCallback? onFamilyUpdated;
  final VoidCallback? onOpenPairingScanner;

  const FamilyManagementSheet({
    super.key,
    required this.activeFamilyId,
    this.onFamilySwitched,
    this.onFamilyUpdated,
    this.onOpenPairingScanner,
  });

  static Future<void> show({
    required BuildContext context,
    required String activeFamilyId,
    Function(String newFamilyId)? onFamilySwitched,
    VoidCallback? onFamilyUpdated,
    VoidCallback? onOpenPairingScanner,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FamilyManagementSheet(
        activeFamilyId: activeFamilyId,
        onFamilySwitched: onFamilySwitched,
        onFamilyUpdated: onFamilyUpdated,
        onOpenPairingScanner: onOpenPairingScanner,
      ),
    );
  }

  @override
  State<FamilyManagementSheet> createState() => _FamilyManagementSheetState();
}

class _FamilyManagementSheetState extends State<FamilyManagementSheet> {
  final MdmSupabaseService _supabaseService = MdmSupabaseService();

  bool _isLoading = true;
  String _currentFamilyId = '';
  List<Map<String, dynamic>> _myFamilies = [];
  Map<String, dynamic>? _familyDetails;

  @override
  void initState() {
    super.initState();
    _currentFamilyId = widget.activeFamilyId;
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final families = await _supabaseService.getMyFamilies();
      if (!mounted) return;

      String selectedId = _currentFamilyId;
      if (selectedId.isEmpty && families.isNotEmpty) {
        selectedId = families.first['id'] as String;
      } else if (families.isNotEmpty && !families.any((f) => f['id'] == selectedId)) {
        selectedId = families.first['id'] as String;
      }

      _myFamilies = families;
      _currentFamilyId = selectedId;

      if (selectedId.isNotEmpty) {
        final details = await _supabaseService.getFamilyDetails(selectedId);
        if (mounted) {
          setState(() {
            _familyDetails = details;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppleNotification.show(
          context,
          title: 'Lỗi Tải Dữ Liệu Gia Đình',
          message: e.toString().replaceFirst('Exception: ', ''),
          icon: Icons.error_outline_rounded,
          iconColor: AppleTheme.appleRed,
        );
      }
    }
  }

  /// Đổi gia đình đang hoạt động
  void _switchFamily(String familyId) async {
    if (familyId == _currentFamilyId) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentFamilyId = familyId;
      _isLoading = true;
    });
    try {
      final details = await _supabaseService.getFamilyDetails(familyId);
      if (mounted) {
        setState(() {
          _familyDetails = details;
          _isLoading = false;
        });
      }
      widget.onFamilySwitched?.call(familyId);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Dialog: Tạo Gia Đình Mới
  Future<void> _showCreateFamilyDialog() async {
    final famNameController = TextEditingController(text: 'Gia Đình Tôi');
    final myNameController = TextEditingController(text: 'Chủ gia đình');

    final result = await showDialog<bool>(
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
              child: const Icon(Icons.add_home_work_rounded, color: AppleTheme.appleBlue, size: 22),
            ),
            const SizedBox(width: 10),
            const Text('Tạo Gia Đình Mới', style: AppleTypography.titleLarge),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thiết lập không gian quản lý riêng cho các thành viên và thiết bị của gia đình bạn:',
              style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text('Tên Gia Đình', style: AppleTypography.labelSmall.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: famNameController,
              autofocus: true,
              style: AppleTypography.bodyLarge.copyWith(color: context.textPrimaryColor),
              decoration: InputDecoration(
                hintText: 'Ví dụ: Gia Đình Nguyễn, Nhà Bác Ba',
                filled: true,
                fillColor: context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 14),
            Text('Tên Của Bạn (Hiển thị với người thân)', style: AppleTypography.labelSmall.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: myNameController,
              style: AppleTypography.bodyLarge.copyWith(color: context.textPrimaryColor),
              decoration: InputDecoration(
                hintText: 'Ví dụ: Bố, Mẹ, Ông, Bà',
                filled: true,
                fillColor: context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Hủy', style: AppleTypography.bodyMedium.copyWith(color: AppleTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppleTheme.appleBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              if (famNameController.text.trim().isNotEmpty) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text('Tạo Ngay', style: AppleTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        final res = await _supabaseService.createNewFamily(
          familyName: famNameController.text.trim(),
          displayName: myNameController.text.trim(),
        );
        final newId = res['family_id']?.toString() ?? '';
        await _loadAllData();
        if (newId.isNotEmpty) {
          _switchFamily(newId);
        }
        widget.onFamilyUpdated?.call();
        if (mounted) {
          AppleNotification.show(
            context,
            title: 'Tạo Thành Công',
            message: 'Đã tạo "${famNameController.text.trim()}" làm gia đình mới!',
            icon: Icons.check_circle_rounded,
            iconColor: AppleTheme.appleGreen,
          );
        }
      } catch (e) {
        if (mounted) {
          AppleNotification.show(
            context,
            title: 'Lỗi Tạo Gia Đình',
            message: e.toString().replaceFirst('Exception: ', ''),
            icon: Icons.error_outline_rounded,
            iconColor: AppleTheme.appleRed,
          );
        }
      }
    }
  }

  /// Dialog: Đổi tên gia đình
  Future<void> _showRenameFamilyDialog() async {
    final currentName = (_familyDetails?['family_name'] as String?) ?? 'Gia Đình';
    final controller = TextEditingController(text: currentName);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: context.borderColor, width: 0.75),
        ),
        title: const Text('Đổi Tên Gia Đình', style: AppleTypography.titleLarge),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppleTypography.bodyLarge.copyWith(color: context.textPrimaryColor),
          decoration: InputDecoration(
            hintText: 'Nhập tên gia đình mới',
            filled: true,
            fillColor: context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Hủy', style: AppleTypography.bodyMedium.copyWith(color: AppleTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppleTheme.appleBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Lưu', style: AppleTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok == true && controller.text.trim().isNotEmpty && mounted) {
      try {
        await _supabaseService.updateFamilyName(_currentFamilyId, controller.text.trim());
        await _loadAllData();
        widget.onFamilyUpdated?.call();
        if (mounted) {
          AppleNotification.show(
            context,
            title: 'Đã Cập Nhật',
            message: 'Đổi tên gia đình thành "${controller.text.trim()}"',
            icon: Icons.check_circle_rounded,
            iconColor: AppleTheme.appleGreen,
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

  /// Dialog: Tạo mã mời phụ huynh (Co-Admin)
  Future<void> _showInviteParentDialog() async {
    try {
      final invite = await _supabaseService.createFamilyInvite(familyId: _currentFamilyId);
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
                child: const Icon(Icons.person_add_alt_1_rounded, color: AppleTheme.applePurple, size: 22),
              ),
              const SizedBox(width: 10),
              const Text('Mời Phụ Huynh Mới', style: AppleTypography.titleLarge),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Gửi mã mời này cho người thân (Bố, Mẹ, Ông, Bà) để cùng đồng hành quản lý các thiết bị con:',
                style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                decoration: BoxDecoration(
                  color: context.isDark ? AppleTheme.darkSurfaceVariant : AppleTheme.lightSurfaceVariant,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppleTheme.applePurple.withValues(alpha: 0.35), width: 1.2),
                ),
                child: Column(
                  children: [
                    Text(
                      code,
                      style: AppleTypography.displayLarge.copyWith(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                        color: AppleTheme.applePurple,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Hiệu lực 24 giờ • Phân quyền Co-Admin',
                      style: AppleTypography.labelSmall.copyWith(fontSize: 11, color: AppleTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Người thân chỉ cần mở VFam Admin -> Cài đặt -> Quản lý gia đình -> bấm "Tham Gia Gia Đình" và nhập mã trên.',
                textAlign: TextAlign.center,
                style: AppleTypography.labelSmall.copyWith(fontSize: 11.5, color: AppleTheme.textSecondary),
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
          title: 'Lỗi Tạo Mã Mời',
          message: e.toString().replaceFirst('Exception: ', ''),
          icon: Icons.error_outline_rounded,
          iconColor: AppleTheme.appleRed,
        );
      }
    }
  }

  /// Dialog: Tham gia gia đình bằng mã mời
  Future<void> _showJoinFamilyDialog() async {
    final codeController = TextEditingController();
    final nameController = TextEditingController(text: 'Phụ huynh');

    final result = await showDialog<bool>(
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
                color: AppleTheme.appleGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.group_add_rounded, color: AppleTheme.appleGreen, size: 22),
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
              'Nhập mã mời nhận từ người thân để cùng quản lý:',
              style: AppleTypography.bodyMedium.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 14),
            Text('Mã Mời (FAM-XXXX)', style: AppleTypography.labelSmall.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: codeController,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              style: AppleTypography.titleLarge.copyWith(letterSpacing: 2, color: context.textPrimaryColor),
              decoration: InputDecoration(
                hintText: 'Ví dụ: FAM-8924',
                filled: true,
                fillColor: context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 14),
            Text('Tên Của Bạn Trong Gia Đình Này', style: AppleTypography.labelSmall.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: nameController,
              style: AppleTypography.bodyLarge.copyWith(color: context.textPrimaryColor),
              decoration: InputDecoration(
                hintText: 'Ví dụ: Mẹ, Bố, Bác',
                filled: true,
                fillColor: context.isDark ? AppleTheme.darkSurfaceElevated : AppleTheme.lightSurfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Hủy', style: AppleTypography.bodyMedium.copyWith(color: AppleTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppleTheme.appleGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              if (codeController.text.trim().isNotEmpty) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text('Tham Gia', style: AppleTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        final res = await _supabaseService.joinFamilyByCode(
          codeController.text.trim(),
          displayName: nameController.text.trim(),
        );
        final joinedFamId = res['family_id']?.toString() ?? '';
        await _loadAllData();
        if (joinedFamId.isNotEmpty) {
          _switchFamily(joinedFamId);
        }
        widget.onFamilyUpdated?.call();
        if (mounted) {
          AppleNotification.show(
            context,
            title: 'Tham Gia Thành Công',
            message: 'Bạn đã trở thành Co-Admin của gia đình!',
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

  /// Xóa thành viên phụ huynh
  Future<void> _removeMember(String userId, String displayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: context.borderColor, width: 0.75),
        ),
        title: const Text('Xác Nhận Xóa Phụ Huynh', style: AppleTypography.titleLarge),
        content: Text('Bạn có chắc muốn xóa "$displayName" khỏi gia đình này? Họ sẽ không còn quyền theo dõi hay điều khiển các thiết bị con.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppleTheme.appleRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await _supabaseService.removeFamilyMember(_currentFamilyId, userId);
        await _loadAllData();
        widget.onFamilyUpdated?.call();
        if (mounted) {
          AppleNotification.show(
            context,
            title: 'Đã Xóa Thành Viên',
            message: 'Đã xóa "$displayName" khỏi gia đình.',
            icon: Icons.check_circle_rounded,
            iconColor: AppleTheme.appleAmber,
          );
        }
      } catch (e) {
        if (mounted) {
          AppleNotification.show(
            context,
            title: 'Lỗi Xóa Thành Viên',
            message: e.toString().replaceFirst('Exception: ', ''),
            icon: Icons.error_outline_rounded,
            iconColor: AppleTheme.appleRed,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: context.borderColor, width: 0.75),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4.5,
            decoration: BoxDecoration(
              color: AppleTheme.textSecondary.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppleTheme.applePurple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.family_restroom_rounded, color: AppleTheme.applePurple, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quản Lý Gia Đình',
                        style: AppleTypography.headlineLarge.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Phụ huynh đồng quản trị & thiết bị con',
                        style: AppleTypography.labelSmall.copyWith(fontSize: 12, color: AppleTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: context.isDark ? AppleTheme.darkSurfaceVariant : AppleTheme.lightSurfaceVariant,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: context.hairlineDividerColor, height: 1),

          // Body
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppleTheme.applePurple))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
                    children: [
                      // 1. Selector chọn gia đình (nếu có nhiều hơn 1)
                      if (_myFamilies.length > 1) ...[
                        _buildSectionHeader('CHỌN GIA ĐÌNH HOẠT ĐỘNG'),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: context.isDark ? AppleTheme.darkSurfaceVariant : AppleTheme.lightSurfaceVariant,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: context.borderColor, width: 0.5),
                          ),
                          child: Row(
                            children: _myFamilies.map((fam) {
                              final isSelected = fam['id'] == _currentFamilyId;
                              return Expanded(
                                child: GestureDetector(
                                  onTap: () => _switchFamily(fam['id']),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? (context.isDark ? AppleTheme.darkSurfaceElevated : Colors.white)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: isSelected
                                          ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 2))]
                                          : null,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      fam['name'] ?? 'Gia đình',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppleTypography.bodyMedium.copyWith(
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                        color: isSelected ? context.textPrimaryColor : AppleTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // 2. Thẻ thông tin gia đình hiện tại
                      _buildCurrentFamilyCard(),
                      const SizedBox(height: 24),

                      // 3. Danh sách Phụ Huynh & Co-Admin
                      _buildParentsSection(),
                      const SizedBox(height: 24),

                      // 4. Danh sách Thiết bị con & Thành viên nhí
                      _buildChildrenDevicesSection(),
                      const SizedBox(height: 24),

                      // 5. Nút Thao Tác Bổ Sung (Tạo mới & Tham gia)
                      _buildFooterActions(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: AppleTypography.labelSmall.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppleTheme.textSecondary,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  /// Card tóm tắt gia đình hiện tại
  Widget _buildCurrentFamilyCard() {
    final famName = (_familyDetails?['family_name'] as String?) ?? 'Gia Đình Tôi';
    final isOwner = _familyDetails?['is_owner'] == true;
    final parents = (_familyDetails?['parents'] as List?) ?? [];
    final devices = (_familyDetails?['devices'] as List?) ?? [];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: context.isDark
              ? [const Color(0xFF2C2036), const Color(0xFF1E1A29)]
              : [const Color(0xFFF3E8FF), const Color(0xFFEFE9FE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppleTheme.applePurple.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        famName,
                        style: AppleTypography.titleLarge.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: isOwner
                            ? AppleTheme.appleRed.withValues(alpha: 0.15)
                            : AppleTheme.applePurple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isOwner ? 'Chủ Gia Đình' : 'Co-Admin',
                        style: AppleTypography.labelSmall.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isOwner ? AppleTheme.appleRed : AppleTheme.applePurple,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _showRenameFamilyDialog,
                tooltip: 'Đổi tên gia đình',
                icon: const Icon(Icons.edit_rounded, size: 18, color: AppleTheme.applePurple),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(6),
                  backgroundColor: context.surfaceColor.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatChip(
                icon: Icons.supervisor_account_rounded,
                label: '${parents.length} Phụ huynh',
                color: AppleTheme.applePurple,
              ),
              const SizedBox(width: 10),
              _buildStatChip(
                icon: Icons.devices_rounded,
                label: '${devices.length} Thiết bị con',
                color: AppleTheme.appleBlue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.surfaceColor.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppleTypography.bodyMedium.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.textPrimaryColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Section: Danh sách Phụ Huynh
  Widget _buildParentsSection() {
    final parents = (_familyDetails?['parents'] as List?) ?? [];
    final isOwner = _familyDetails?['is_owner'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'PHỤ HUYNH & CO-ADMIN (${parents.length})',
          trailing: InkWell(
            onTap: _showInviteParentDialog,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.add_rounded, size: 15, color: AppleTheme.applePurple),
                  const SizedBox(width: 2),
                  Text(
                    'Mời Thêm',
                    style: AppleTypography.bodyMedium.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppleTheme.applePurple,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.borderColor, width: 0.75),
          ),
          child: parents.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text('Chưa có thông tin thành viên', style: AppleTypography.bodyMedium.copyWith(color: AppleTheme.textSecondary)),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: parents.length,
                  separatorBuilder: (context, index) => Divider(color: context.hairlineDividerColor, height: 1, indent: 60),
                  itemBuilder: (ctx, index) {
                    final p = parents[index] as Map<String, dynamic>;
                    final name = p['display_name'] ?? 'Phụ huynh';
                    final role = p['role'] ?? 'parent';
                    final isCurr = p['is_current_user'] == true;
                    final isMemberOwner = role == 'owner';
                    final userId = p['user_id']?.toString() ?? '';

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: isMemberOwner
                                ? AppleTheme.appleRed.withValues(alpha: 0.15)
                                : AppleTheme.applePurple.withValues(alpha: 0.15),
                            child: Icon(
                              isMemberOwner ? Icons.workspace_premium_rounded : Icons.person_rounded,
                              color: isMemberOwner ? AppleTheme.appleRed : AppleTheme.applePurple,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        name,
                                        style: AppleTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600, fontSize: 14.5),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isCurr) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '(Bạn)',
                                        style: AppleTypography.labelSmall.copyWith(
                                          color: AppleTheme.appleBlue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isMemberOwner ? 'Chủ gia đình • Toàn quyền' : 'Đồng quản trị (Co-Admin)',
                                  style: AppleTypography.labelSmall.copyWith(fontSize: 11, color: AppleTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          if (isOwner && !isMemberOwner && !isCurr)
                            IconButton(
                              onPressed: () => _removeMember(userId, name),
                              tooltip: 'Xóa khỏi gia đình',
                              icon: const Icon(Icons.person_remove_rounded, size: 18, color: AppleTheme.appleRed),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Section: Danh sách Thiết Bị Con
  Widget _buildChildrenDevicesSection() {
    final devices = (_familyDetails?['devices'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'THIẾT BỊ CON & THÀNH VIÊN NHÍ (${devices.length})',
          trailing: InkWell(
            onTap: () {
              Navigator.pop(context);
              widget.onOpenPairingScanner?.call();
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner_rounded, size: 15, color: AppleTheme.appleBlue),
                  const SizedBox(width: 4),
                  Text(
                    '+ Thêm Thiết Bị',
                    style: AppleTypography.bodyMedium.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppleTheme.appleBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.borderColor, width: 0.75),
          ),
          child: devices.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                  child: Column(
                    children: [
                      Icon(Icons.phonelink_setup_rounded, size: 40, color: AppleTheme.textSecondary.withValues(alpha: 0.5)),
                      const SizedBox(height: 10),
                      Text(
                        'Chưa ghép nối thiết bị con nào',
                        style: AppleTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Mở app VFam Child trên máy con để quét mã QR ghép nối vào gia đình này.',
                        textAlign: TextAlign.center,
                        style: AppleTypography.labelSmall.copyWith(fontSize: 12, color: AppleTheme.textSecondary),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppleTheme.appleBlue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onOpenPairingScanner?.call();
                        },
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 16, color: Colors.white),
                        label: const Text('Ghép Nối Thiết Bị Con', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: devices.length,
                  separatorBuilder: (context, index) => Divider(color: context.hairlineDividerColor, height: 1, indent: 60),
                  itemBuilder: (ctx, index) {
                    final d = devices[index] as Map<String, dynamic>;
                    final devName = d['custom_name'] ?? d['device_name'] ?? 'Thiết bị con';
                    final model = d['model'] ?? 'Android Device';
                    final isLocked = d['is_locked'] == true;
                    final battery = (d['battery_level'] as num?)?.toInt();
                    final isCharging = d['is_charging'] == true;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: isLocked
                                  ? AppleTheme.appleAmber.withValues(alpha: 0.15)
                                  : AppleTheme.appleGreen.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isLocked ? Icons.lock_rounded : Icons.phone_android_rounded,
                              color: isLocked ? AppleTheme.appleAmber : AppleTheme.appleGreen,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  devName,
                                  style: AppleTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600, fontSize: 14.5),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  model,
                                  style: AppleTypography.labelSmall.copyWith(fontSize: 11, color: AppleTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          if (battery != null) ...[
                            Icon(
                              isCharging ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
                              size: 15,
                              color: isCharging ? AppleTheme.appleGreen : AppleTheme.textSecondary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '$battery%',
                              style: AppleTypography.labelSmall.copyWith(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: isCharging ? AppleTheme.appleGreen : AppleTheme.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Nút hành động bổ sung (Tạo gia đình mới & Tham gia gia đình khác)
  Widget _buildFooterActions() {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor, width: 0.75),
      ),
      child: Column(
        children: [
          _buildActionRow(
            icon: Icons.add_home_work_rounded,
            color: AppleTheme.appleBlue,
            title: 'Tạo thêm gia đình mới',
            subtitle: 'Tạo không gian riêng cho gia đình khác',
            onTap: _showCreateFamilyDialog,
          ),
          Divider(color: context.hairlineDividerColor, height: 1, indent: 56),
          _buildActionRow(
            icon: Icons.group_add_rounded,
            color: AppleTheme.appleGreen,
            title: 'Tham gia gia đình khác',
            subtitle: 'Nhập mã mời FAM-XXXX nhận từ người thân',
            onTap: _showJoinFamilyDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppleTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(subtitle, style: AppleTypography.labelSmall.copyWith(fontSize: 11, color: AppleTheme.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppleTheme.textSecondary, size: 13),
          ],
        ),
      ),
    );
  }
}
