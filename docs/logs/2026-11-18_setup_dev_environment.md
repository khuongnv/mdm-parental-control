# 📋 Nhật Ký Thực Thi: Pull Source & Thiết Lập Môi Trường Phát Triển (Windows)

- **Ngày thực hiện**: 2026-11-18 19:45:00
- **Agent phụ trách**: `lead-architect`
- **Yêu cầu gốc**: Pull source từ `https://github.com/khuongnv/mdm-parental-control.git` và cài đặt đầy đủ các công cụ cần thiết phục vụ phát triển dự án sau khi cài đặt lại Windows.
- **Trạng thái**: ✅ Hoàn thành

---

## 1. Phân Tích & Kế Hoạch (Analysis & Planning)
- **Bối cảnh kỹ thuật**: Máy trạm vừa cài đặt lại Windows, chưa có Git, Flutter SDK, Android SDK `cmdline-tools`, `gh` CLI hay biến môi trường (`JAVA_HOME`, `ANDROID_HOME`, `PATH`).
- **Các module phục vụ**:
  - `target-node` (Child DO Agent - Kotlin Native Android SDK 34, Gradle 8.10.2, JDK 17/21).
  - `admin-node` (Parent App - Flutter 3.x & Android toolchain).
  - `.agents/skills/deploy-app` (Pipeline đóng gói, ký số debug/release và phát hành GitHub Releases qua `gh` CLI).

## 2. Chi Tiết Các Bước Thực Hiện (Execution Steps)
- **Bước 1 - Cài đặt Git & Pull Source**:
  - Cài đặt `Git.MinGit` (v2.56.1) qua `winget` và thêm vào User `PATH`.
  - Clone toàn bộ mã nguồn dự án từ `https://github.com/khuongnv/mdm-parental-control.git` về `d:\Project\github.com\mdm-parental-control`.
- **Bước 2 - Cấu hình JDK & Android SDK Toolchain**:
  - Khai báo `JAVA_HOME = C:\Program Files\Android\Android Studio\jbr` (OpenJDK 21.0.8).
  - Khai báo `ANDROID_HOME` và `ANDROID_SDK_ROOT = C:\Users\khuongnv\AppData\Local\Android\Sdk`.
  - Tải và cài đặt `cmdline-tools;latest`, chấp nhận toàn bộ Android SDK Licenses (`sdkmanager --licenses`), cài đặt `platforms;android-34` và `build-tools;34.0.0`.
  - Khởi tạo `~/.android/debug.keystore` phục vụ cấu hình ký APK của `target-node`.
  - Tạo tệp `target-node/local.properties` và `admin-node/android/local.properties` (Git-ignored).
- **Bước 3 - Cài đặt Flutter SDK & GitHub CLI (`gh`)**:
  - Clone Flutter SDK (channel `stable`, v3.50.0 / Dart 3.14.0) vào `D:\Tools\flutter` và cấu hình `jdk-dir`, `android-sdk`.
  - Cài đặt GitHub CLI (`gh` v2.105.0) vào `D:\Tools\gh` và thêm vào User `PATH`.
  - Chạy `flutter doctor` xác nhận `[√] Flutter` và `[√] Android toolchain` đạt chuẩn.

## 3. Danh Sách Tệp Thay Đổi (Impacted Files)
- `[Created]`: `target-node/local.properties` - Khai báo `sdk.dir` cục bộ (Git-ignored).
- `[Created]`: `admin-node/android/local.properties` - Khai báo `sdk.dir` và `flutter.sdk` cục bộ (Git-ignored).
- `[Created]`: `docs/logs/2026-11-18_setup_dev_environment.md` - Nhật ký thực thi thiết lập môi trường.
- `[Modified]`: `docs/logs/README.md` - Cập nhật chỉ mục nhật ký thực thi.

## 4. Kiểm Thử & Đánh Giá Bảo Mật (Verification & Security Audit)
- Kiểm tra `git --version`, `java -version`, `adb version`, `gh --version`, `flutter doctor` đều hoạt động bình thường.
- Không lưu thông tin nhạy cảm vào Git; các tệp `local.properties` nằm trong danh sách `.gitignore`.

## 5. Kết Luận & Hướng Dẫn Tiếp Theo (Conclusion & Next Steps)
- Toàn bộ mã nguồn dự án và bộ công cụ phát triển trên Windows đã sẵn sàng.
- Lưu ý: Nếu cần chạy plugin Flutter có sử dụng symlink trên Windows, hãy bật **Developer Mode** trong Windows Settings (`start ms-settings:developers`), và sao chép `.env.example` thành `.env` khi cần chạy kịch bản deploy.
