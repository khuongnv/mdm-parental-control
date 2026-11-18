# 📋 Nhật Ký Thực Thi: Thống nhất cơ chế lấy Version thực tế khi Build, đánh dấu Latest Release trên GitHub và phát hành đồng bộ v1.5.4 All

- **Ngày thực hiện**: 2026-11-18 21:16:25 - 22:11:24
- **Agent phụ trách**: `lead-architect`, `device-owner-specialist`, `parent-ui-specialist`, `qa-security-perf-specialist`
- **Yêu cầu gốc**: Các app: child, admin-android, admin-ios đều đang hiển thị sai version, dẫn đến click vào update đều ra bản mới mặc dù đã cài bản mới nhất. Cần thống nhất và làm đúng cách để lấy đúng giá trị version khi build app và đánh dấu release latest trên GitHub. Hoàn thiện thì deploy-app all.
- **Trạng thái**: ✅ Hoàn thành

---

## 1. Phân Tích Nguyên Nhân Gốc Rễ & Kế Hoạch (Analysis & Planning)

### 1.1. Nguyên nhân các ứng dụng hiển thị sai version và báo cập nhật liên tục:
1. **Admin iOS (`admin-node/ios`)**:
   - Dự án iOS sử dụng `UISceneDelegate` ([SceneDelegate.swift](file:///d:/Project/github.com/mdm-parental-control/admin-node/ios/Runner/SceneDelegate.swift) trong `Info.plist`). Với kiến trúc `UIScene`, `window?.rootViewController` trong `AppDelegate.application(_:didFinishLaunchingWithOptions:)` luôn là `nil` tại thời điểm khởi chạy!
   - Do đó, `FlutterMethodChannel("vn.hanoi.khuongnv.vfam.admin/updater")` **không bao giờ được đăng ký** trên iOS.
   - Khi Flutter gọi `_channel.invokeMethod('getAppVersion')`, iOS ném lỗi `MissingPluginException` và rơi vào giá trị fallback cứng `ParentAppUpdater.appVersion = '1.5.2'` trong `github_release_updater.dart`. Vì `1.5.2 < 1.5.3` (trên GitHub), app luôn hiển thị `v1.5.2` và luôn báo có bản cập nhật mới `1.5.3`!
   - Ngoài ra, trong `deploy_ios.ps1`, lệnh `flutter build ios` bị hardcode `--build-number="11"` trong khi `pubspec.yaml` là `+12`.
2. **Admin Android (`admin-node/android`)**:
   - `SettingsTab` khởi tạo `String currentVersion = ParentAppUpdater.appVersion` (bị hardcode `'1.5.2'`). Nếu người dùng mở app hoặc bấm kiểm tra trước khi channel trả về hoặc khi build không truyền `--dart-define=APP_VERSION`, giá trị mặc định vẫn là `1.5.2`.
   - Trong `deploy.ps1`, lệnh `flutter build apk --release` không truyền tường minh `--build-name=$Version --build-number=$adminBuildNumber --dart-define=APP_VERSION=$Version`, và `version: $Version+12` bị hardcode số `+12` không tăng `versionCode`.
3. **Child DO Android (`target-node`)**:
   - Trong `deploy.ps1`, chỉ thay thế `versionName` mà **không tăng `versionCode`**, và `MainActivity.kt` / `GitHubReleaseUpdater.kt` đọc `BuildConfig.VERSION_NAME` tĩnh thay vì truy vấn trực tiếp `PackageManager.getPackageInfo(packageName, 0).versionName` của gói APK thực tế đang cài đặt trên hệ điều hành.
4. **GitHub Releases (`--latest`)**:
   - Trong `deploy.ps1` và `deploy_ios.ps1`, lệnh `gh release create` chưa gắn cờ `--latest` và khi chạy `-Target all` chưa tự động tạo bản phát hành tổng hợp `v$Version` với cờ `--latest`.

---

## 2. Chi Tiết Các Bước Thực Hiện (Execution Steps)
- **Bước 1**: Nâng cấp `admin-node/ios/Runner/AppDelegate.swift` đăng ký `FlutterMethodChannel` trực tiếp trong `didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge)` thông qua `engineBridge.applicationRegistrar.messenger()`, đọc trực tiếp `CFBundleShortVersionString` & `CFBundleVersion` từ `Bundle.main.infoDictionary`.
- **Bước 2**: Nâng cấp `admin-node/lib/services/github_release_updater.dart`, `admin-node/lib/main.dart`, và `admin-node/android/app/src/main/kotlin/vn/hanoi/khuongnv/vfam/admin/MainActivity.kt` để đồng bộ `APP_VERSION` từ `--dart-define=APP_VERSION` và truy vấn lại `getCurrentAppVersion()` ngay trước khi chạy `checkForUpdate()`.
- **Bước 3**: Nâng cấp `target-node` (`MainActivity.kt`, `GitHubReleaseUpdater.kt`, `build.gradle.kts`) để lấy `versionName` và `longVersionCode` thực tế từ `PackageManager` (`1.5.4`, Build `15`).
- **Bước 4**: Chuẩn hóa `.agents/skills/deploy-app/scripts/deploy.ps1` và `deploy_ios.ps1`:
  - Tự động tăng `versionCode` / `build-number` khi bump version.
  - Truyền tường minh `--build-name=$Version --build-number=$adminBuildNumber --dart-define=APP_VERSION=$Version` cho cả Android và iOS.
  - Thêm `-n` cho `ssh` tránh treo stdin trên Windows OpenSSH.
  - Gắn cờ `--latest` cho mọi lệnh `gh release create` và tự động tạo Unified Release `v1.5.4` (`--latest`).

---

## 3. Danh Sách Tệp Thay Đổi (Impacted Files)
- `[Modified]`: [`admin-node/ios/Runner/AppDelegate.swift`](file:///d:/Project/github.com/mdm-parental-control/admin-node/ios/Runner/AppDelegate.swift) - Đăng ký MethodChannel chuẩn UIScene qua `engineBridge.applicationRegistrar.messenger()`.
- `[Modified]`: [`admin-node/lib/services/github_release_updater.dart`](file:///d:/Project/github.com/mdm-parental-control/admin-node/lib/services/github_release_updater.dart) - Đọc `String.fromEnvironment('APP_VERSION', defaultValue: '1.5.4')`.
- `[Modified]`: [`admin-node/lib/main.dart`](file:///d:/Project/github.com/mdm-parental-control/admin-node/lib/main.dart) - Tự động làm mới `currentVersion` từ native trước khi kiểm tra bản cập nhật.
- `[Modified]`: [`admin-node/android/app/src/main/kotlin/vn/hanoi/khuongnv/vfam/admin/MainActivity.kt`](file:///d:/Project/github.com/mdm-parental-control/admin-node/android/app/src/main/kotlin/vn/hanoi/khuongnv/vfam/admin/MainActivity.kt) - Bổ sung `getAppBuildNumber` và đồng bộ fallback `1.5.4`.
- `[Modified]`: [`admin-node/pubspec.yaml`](file:///d:/Project/github.com/mdm-parental-control/admin-node/pubspec.yaml) - Nâng version lên `1.5.4+13`.
- `[Modified]`: [`admin-node/test/updater_test.dart`](file:///d:/Project/github.com/mdm-parental-control/admin-node/test/updater_test.dart) - Cập nhật unit test kiểm tra `ParentAppUpdater.appVersion`.
- `[Modified]`: [`target-node/app/build.gradle.kts`](file:///d:/Project/github.com/mdm-parental-control/target-node/app/build.gradle.kts) - Nâng version lên `1.5.4` (`versionCode = 15`).
- `[Modified]`: [`target-node/app/src/main/java/com/mdm/parentalcontrol/child/ui/MainActivity.kt`](file:///d:/Project/github.com/mdm-parental-control/target-node/app/src/main/java/com/mdm/parentalcontrol/child/ui/MainActivity.kt) - Lấy `versionName` và `longVersionCode` trực tiếp từ `PackageManager`.
- `[Modified]`: [`target-node/app/src/main/java/com/mdm/parentalcontrol/child/updater/GitHubReleaseUpdater.kt`](file:///d:/Project/github.com/mdm-parental-control/target-node/app/src/main/java/com/mdm/parentalcontrol/child/updater/GitHubReleaseUpdater.kt) - Bổ sung `getInstalledVersionName()` đọc từ `PackageManager`.
- `[Modified]`: [`.agents/skills/deploy-app/scripts/deploy.ps1`](file:///d:/Project/github.com/mdm-parental-control/.agents/skills/deploy-app/scripts/deploy.ps1) - Đồng bộ build-name/build-number/dart-define, tự động tăng versionCode và phát hành `--latest` + Unified Release.
- `[Modified]`: [`.agents/skills/deploy-app/scripts/deploy_ios.ps1`](file:///d:/Project/github.com/mdm-parental-control/.agents/skills/deploy-app/scripts/deploy_ios.ps1) - Đồng bộ build-number động, thêm `-n` cho `ssh` và gắn cờ `--latest`.

---

## 4. Kết Quả Triển Khai & Kiểm Thử (Verification & Release Summary)

| Ứng Dụng | Nền Tảng | Release Tag | Tệp Đính Kèm | Kích Thước | Trạng Thái |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Child DO Agent** | Android | `child-android-v1.5.4` | `vfam-child-android-1.5.4.apk` | 21.95 MB | ✅ Đã phát hành & gửi QR Telegram (`#2776`) |
| **Parent Admin** | Android | `admin-android-v1.5.4` | `vfam-admin-android-1.5.4.apk` | 68.87 MB | ✅ Đã phát hành & gửi QR Telegram (`#2780`) |
| **Parent Admin** | iOS Enterprise | `admin-ios-v1.5.4` | `vfam-admin-ios-1.5.4.ipa`<br>`manifest.plist` | 10.85 MB | ✅ Đã ký số VNPT (`9638a3f5...`) & gửi QR Telegram (`#2789`) |
| **Unified Release** | All | `v1.5.4` (`--latest`) | Trọn bộ 4 assets trên | — | ✅ Đã gán cờ `--latest` trên GitHub Releases |

---

## 5. Kết Luận & Liên Kết Cài Đặt Trực Tiếp
- **VFam Child DO (Android v1.5.4 - Build 15)**: `https://github.com/khuongnv/mdm-parental-control/releases/download/v1.5.4/vfam-child-android-1.5.4.apk`
- **VFam Parent Admin (Android v1.5.4 - Build 13)**: `https://github.com/khuongnv/mdm-parental-control/releases/download/v1.5.4/vfam-admin-android-1.5.4.apk`
- **VFam Parent Admin (iOS Enterprise v1.5.4 - Build 13 OTA)**: `itms-services://?action=download-manifest&url=https://github.com/khuongnv/mdm-parental-control/releases/download/admin-ios-v1.5.4/manifest.plist`
