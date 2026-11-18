# 📋 Nhật Ký Thực Thi: Thống nhất cơ chế lấy Version thực tế khi Build, đánh dấu Latest Release trên GitHub và phát hành đồng bộ v1.5.4 All

- **Ngày thực hiện**: 2026-11-18 21:16:25
- **Agent phụ trách**: `lead-architect`, `device-owner-specialist`, `parent-ui-specialist`, `qa-security-perf-specialist`
- **Yêu cầu gốc**: Các app: child, admin-android, admin-ios đều đang hiển thị sai version, dẫn đến click vào update đều ra bản mới mặc dù đã cài bản mới nhất. Cần thống nhất và làm đúng cách để lấy đúng giá trị version khi build app và đánh dấu release latest trên GitHub. Hoàn thiện thì deploy-app all.
- **Trạng thái**: 🔄 Đang tiến hành

---

## 1. Phân Tích Nguyên Nhân Gốc Rễ & Kế Hoạch (Analysis & Planning)

### 1.1. Nguyên nhân các ứng dụng hiển thị sai version và báo cập nhật liên tục:
1. **Admin iOS (`admin-node/ios`)**:
   - Dự án iOS sử dụng `UISceneDelegate` (`SceneDelegate.swift` trong `Info.plist`). Với kiến trúc `UIScene`, `window?.rootViewController` trong `AppDelegate.application(_:didFinishLaunchingWithOptions:)` luôn là `nil` tại thời điểm khởi chạy!
   - Do đó, `FlutterMethodChannel("vn.hanoi.khuongnv.vfam.admin/updater")` **không bao giờ được đăng ký** trên iOS.
   - Khi Flutter gọi `_channel.invokeMethod('getAppVersion')`, iOS ném lỗi `MissingPluginException` và rơi vào giá trị fallback cứng `ParentAppUpdater.appVersion = '1.5.2'` trong `github_release_updater.dart`. Vì `1.5.2 < 1.5.3` (trên GitHub), app luôn hiển thị `v1.5.2` và luôn báo có bản cập nhật mới `1.5.3`!
   - Ngoài ra, trong `deploy_ios.ps1`, lệnh `flutter build ios` bị hardcode `--build-number="11"` trong khi `pubspec.yaml` là `+12`.
2. **Admin Android (`admin-node/android`)**:
   - `SettingsTab` khởi tạo `String currentVersion = ParentAppUpdater.appVersion` (bị hardcode `'1.5.2'`). Nếu người dùng mở app hoặc bấm kiểm tra trước khi channel trả về hoặc khi build không truyền `--dart-define=APP_VERSION`, giá trị mặc định vẫn là `1.5.2`.
   - Trong `deploy.ps1`, lệnh `flutter build apk --release` không truyền tường minh `--build-name=$Version --build-number=$adminBuildNumber --dart-define=APP_VERSION=$Version`, và `version: $Version+12` bị hardcode số `+12` không tăng `versionCode` khiến Android PackageInstaller hoặc Gradle cache có thể giữ metadata cũ.
3. **Child DO Android (`target-node`)**:
   - Trong `deploy.ps1`, chỉ thay thế `versionName` mà **không tăng `versionCode`** (luôn giữ `14`), và `MainActivity.kt` / `GitHubReleaseUpdater.kt` đọc `BuildConfig.VERSION_NAME` tĩnh thay vì truy vấn trực tiếp `PackageManager.getPackageInfo(packageName, 0).versionName` của gói APK thực tế đang cài đặt trên hệ điều hành.
4. **GitHub Releases (`--latest`)**:
   - Trong `deploy.ps1` và `deploy_ios.ps1`, lệnh `gh release create` chưa gắn cờ `--latest` và khi chạy `-Target all` chưa tự động tạo bản phát hành tổng hợp `v$Version` với cờ `--latest`.

### 1.2. Giải pháp khắc phục toàn diện:
- **iOS Native (`AppDelegate.swift`)**: Chuyển đăng ký `FlutterMethodChannel` vào `didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge)` thông qua `engineBridge.applicationRegistrar.messenger()`. Đảm bảo 100% MethodChannel hoạt động trên UIScene lifecycle và đọc trực tiếp `CFBundleShortVersionString` & `CFBundleVersion` từ `Bundle.main.infoDictionary`.
- **Android Native & Child DO (`MainActivity.kt`, `GitHubReleaseUpdater.kt`)**: Đọc trực tiếp `packageManager.getPackageInfo(packageName, 0).versionName` và `longVersionCode` tại runtime, đồng thời làm mới `currentVersion` ngay trước mỗi lần gọi `_checkUpdate()`.
- **Build & Deploy Pipeline (`deploy.ps1`, `deploy_ios.ps1`)**:
  - Tự động đồng bộ và tăng `versionCode` / `build-number` khi bump version.
  - Truyền tường minh `--build-name=$Version --build-number=$adminBuildNumber --dart-define=APP_VERSION=$Version` cho cả Android APK và iOS IPA.
  - Thêm cờ `--latest` vào tất cả lệnh `gh release create` và tự động tạo Unified Release `v$Version --latest` chứa trọn bộ 4 artifacts khi chạy `-Target all`.

---

## 2. Chi Tiết Các Bước Thực Hiện (Execution Steps)
- **Bước 1**: Nâng cấp `admin-node/ios/Runner/AppDelegate.swift` đăng ký channel qua `engineBridge.applicationRegistrar.messenger()`.
- **Bước 2**: Nâng cấp `admin-node/lib/services/github_release_updater.dart`, `admin-node/lib/main.dart`, và `admin-node/android/app/src/main/kotlin/vn/hanoi/khuongnv/vfam/admin/MainActivity.kt` để đồng bộ `APP_VERSION` từ `--dart-define` và `PackageManager`.
- **Bước 3**: Nâng cấp `target-node` (`MainActivity.kt`, `GitHubReleaseUpdater.kt`, `build.gradle.kts`) để lấy `versionName` và `longVersionCode` thực tế từ `PackageManager`.
- **Bước 4**: Chuẩn hóa `.agents/skills/deploy-app/scripts/deploy.ps1` và `deploy_ios.ps1` hỗ trợ `--latest`, truyền `--build-name`, `--build-number`, `--dart-define=APP_VERSION`, và phát hành đồng bộ `v1.5.4`.
