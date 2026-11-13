---
name: deploy-app
description: "Quy trình và kịch bản tự động hóa build, ký số Enterprise, gắn git tag và phát hành (deploy/release) các ứng dụng di động (Child DO Android, Parent Admin Android & iOS Enterprise) lên GitHub Releases kèm giám sát Telegram HUB-LOG / HniBOT."
user-invocable: true
---

# 🚀 Kỹ Năng: Deploy Đa Nền Tảng (Android & iOS Enterprise) & Giám Sát Telegram

Kỹ năng này hướng dẫn và cung cấp công cụ tự động hóa toàn diện 100% để **Swarm Agent** và kỹ sư phát hành phiên bản mới độc lập cho các ứng dụng trong hệ thống MDM Parental Control:
1. `target-node`: Ứng dụng máy con nắm quyền **Android Device Owner (DO)**. Tự động tải về và nâng cấp ngầm (**Silent Install**) qua GitHub Releases.
2. `admin-node` (Android): Ứng dụng di động **Parent Admin (Flutter Android APK)**. Thông báo trong app và tải APK cài đè.
3. `admin-node` (iOS): Ứng dụng di động **Parent Admin (Flutter iOS Enterprise IPA)**. Tự động build từ xa qua Mac M1 Pro (`100.111.29.5`), ký chứng chỉ In-House Enterprise VNPT, xuất file `.ipa` + Apple OTA Manifest (`manifest.plist`), cài đặt trực tiếp qua giao thức `itms-services://`.
4. **Giám sát thời gian thực qua Telegram**: Tự động thông báo từng bước thực hiện và tổng kết kết quả lên kênh **HUB-LOG** qua bot **HniBOT**.

---

## 🏷️ 1. Quy Chuẩn Phân Biệt Ứng Dụng Trên GitHub Releases

Để các client mobile tự động nhận diện và cập nhật đúng phiên bản mà không bị xung đột giữa Android vs iOS, giữa Admin vs Child:

| Ứng dụng | Nền tảng | Git Tag Định Danh | Tệp Đính Kèm (Release Assets) | Cơ Chế Nâng Cấp Client |
| :--- | :--- | :--- | :--- | :--- |
| **Child Agent** (`target-node`) | Android | `child-android-vX.Y.Z` | `vfam-child-android-X.Y.Z.apk` | DO Silent Install qua `PackageInstaller` |
| **Parent Admin** (`admin-node`) | Android | `admin-android-vX.Y.Z` | `vfam-admin-android-X.Y.Z.apk` | In-App Intent mở trình cài đặt APK |
| **Parent Admin** (`admin-node`) | iOS | `admin-ios-vX.Y.Z` | `vfam-admin-ios-X.Y.Z.ipa`<br>`manifest.plist` | Apple OTA: `itms-services://?action=download-manifest&url=...` |

> [!IMPORTANT]
> - Client Android (`GitHubReleaseUpdater.kt` & `github_release_updater.dart`) và Client iOS tự động lọc theo tiền tố `child-android-v`, `admin-android-v`, hoặc `admin-ios-v` từ danh sách releases của GitHub API, loại bỏ triệt để rủi ro nhận nhầm bản build của nền tảng khác.

---

## 📲 2. Kiến Trúc Build & Ký Số iOS Enterprise Từ Xa (Remote Mac M1 Pro)

Đối với `admin-node` iOS:
- **Máy Build**: Mac M1 Pro (`100.111.29.5`, SSH port 22, user `khuongnv`, pass `1230`).
- **Chứng chỉ Enterprise**: `VNPT_Enterprise_iOS Distribution_18082029.p12` (Team ID: `JPMH34L85K`).
- **Provisioning Profile**: `docs/dev/Prov_HNI_comdhtthniquanlytaptrung.mobileprovision` (UUID: `f5a84849-5dda-4021-adcb-877132002773`, Name: `Prov_HNI_com.dhtthni.quanlytaptrung`).
- **Bundle ID**: `com.dhtthni.quanlytaptrung` (đã khai báo đồng bộ trong `docs/dev/GoogleService-Info.plist` và `Runner.xcodeproj`).
- **Quy tắc ký số**: Manual Signing trong `Release.xcconfig` và `ExportOptions-enterprise.plist`, đồng thời khóa toàn bộ Pods với `CODE_SIGNING_ALLOWED = "NO"`.

---

## 🛰️ 3. Kênh Giám Sát Telegram Telemetry (HUB-LOG & HniBOT)

- **Bot**: `HniBOT` (`8005142785:AAHSrJ2Yp4l0Gj6Yk7iu8hwSwThZIiVKrCU`)
- **Kênh tiếp nhận**: `HUB-LOG` (`-1003609918702`)
- **Các mốc thông báo tự động**:
  - `Bước 1`: Khởi động phát hành (Tên app, Nền tảng, Phiên bản, Git Tag)
  - `Bước 2`: Kiểm tra Keychain & Nạp Chứng chỉ Enterprise / Profile trên Mac M1 Pro
  - `Bước 3`: Đồng bộ Source Code & Cài đặt Pods (`flutter pub get`, `pod install`)
  - `Bước 4`: Biên dịch Release IPA (`xcodebuild archive` & `xcodebuild -exportArchive`)
  - `Bước 5`: Đóng gói Apple OTA Manifest (`manifest.plist`) & Đẩy lên GitHub Releases
  - `Bước 6`: **TỔNG KẾT PHÁT HÀNH THÀNH CÔNG** (Link OTA trực tiếp cho iPhone, Link GitHub Release, mã băm SHA256)

---

## 🛠️ 4. Hướng Dẫn Sử Dụng Lệnh Triển Khai (`deploy.ps1`)

Kịch bản điều phối trung tâm: `.agents/skills/deploy-app/scripts/deploy.ps1`

### Cú pháp cơ bản:
```powershell
powershell -ExecutionPolicy Bypass -File .agents/skills/deploy-app/scripts/deploy.ps1 `
  -Target <child|admin|all> `
  -Platform <android|ios|all> `
  -Version <X.Y.Z> `
  -Notes "<Nội dung ghi chú cập nhật>"
```

### Các ví dụ cụ thể:

#### 1. Phát hành riêng iOS cho Parent Admin (`admin-node`):
```powershell
powershell -ExecutionPolicy Bypass -File .agents/skills/deploy-app/scripts/deploy.ps1 `
  -Target admin `
  -Platform ios `
  -Version "1.0.0" `
  -Notes "Phát hành phiên bản iOS Enterprise đầu tiên cho ứng dụng phụ huynh VFam Parent."
```
> Tự động SSH sang Mac M1 Pro, build IPA, ký chữ ký số VNPT Enterprise, xuất OTA Manifest, đẩy lên GitHub Release `admin-ios-v1.0.0` và bắn thông báo real-time lên Telegram HUB-LOG.

#### 2. Phát hành riêng Android cho Parent Admin (`admin-node`):
```powershell
powershell -ExecutionPolicy Bypass -File .agents/skills/deploy-app/scripts/deploy.ps1 `
  -Target admin `
  -Platform android `
  -Version "1.0.1" `
  -Notes "Nâng cấp giao diện biểu đồ Screen Time và tích hợp Supabase Realtime."
```
> Build APK cục bộ, tạo tag `admin-android-v1.0.1`, phát hành GitHub Release và gửi thông báo Telegram.

#### 3. Phát hành bản cập nhật cho máy con (`target-node` - Child DO Agent):
```powershell
powershell -ExecutionPolicy Bypass -File .agents/skills/deploy-app/scripts/deploy.ps1 `
  -Target child `
  -Platform android `
  -Version "1.0.2" `
  -Notes "Cải tiến Anti-Tampering, tối ưu Room DB và silent update qua Device Owner."
```
> Tạo tag `child-android-v1.0.2`, phát hành APK `vfam-child-android-1.0.2.apk`.

#### 4. Phát hành trọn gói cả Android & iOS:
```powershell
powershell -ExecutionPolicy Bypass -File .agents/skills/deploy-app/scripts/deploy.ps1 `
  -Target all `
  -Platform all `
  -Version "1.1.0" `
  -Notes "Đồng bộ phiên bản lớn 1.1.0 cho toàn bộ hệ thống MDM Parental Control."
```

---

## 🔒 5. Danh Mục Tệp Triển Khai & Cấu Hình

- `.agents/skills/deploy-app/scripts/deploy.ps1`: Kịch bản điều phối tổng thể đa nền tảng (hỗ trợ tạo QR Code cài đặt tự động).
- `.agents/skills/deploy-app/scripts/deploy_ios.ps1`: Kịch bản tự động hóa build iOS từ xa qua Mac M1 Pro và xuất mã QR Apple OTA.
- `.agents/skills/deploy-app/scripts/send-telegram.ps1`: Tiện ích gửi log tiến trình và gửi kèm mã QR Code cài đặt (sendPhoto) tới Telegram HUB-LOG / HniBOT.
- `.agents/skills/deploy-app/templates/manifest.plist.template`: Mẫu Apple OTA Manifest cho iOS Enterprise.
- `admin-node/ios/ExportOptions-enterprise.plist`: File cấu hình Enterprise manual signing cho xcodebuild.
- `admin-node/ios/Flutter/Release.xcconfig`: Cấu hình Signing & Bundle ID `com.dhtthni.quanlytaptrung`.
- `docs/dev/`: Chứa file `.p12`, `.mobileprovision` và `GoogleService-Info.plist`.

---

## 📱 6. Cơ Chế Quét QR Code Cài Đặt Qua Telegram

Mỗi khi hoàn thành phát hành bản build (Android hoặc iOS):
1. **iOS Enterprise**: Hệ thống tự động tạo mã QR chứa link OTA `itms-services://?action=download-manifest&url=...` trỏ đến `manifest.plist`.
2. **Android APK**: Hệ thống tự động tạo mã QR chứa link tải trực tiếp APK từ GitHub Releases.
3. Kịch bản `send-telegram.ps1` sử dụng Telegram API `sendPhoto` để gửi trực tiếp hình ảnh QR Code phân giải cao kèm theo toàn bộ thông tin phiên bản (Version, SHA256, dung lượng, ghi chú) vào kênh **HUB-LOG**. Người dùng chỉ cần mở Camera trên iPhone/iPad hoặc điện thoại Android quét hình ảnh trực tiếp trên màn hình Telegram để cài đặt ngay lập tức.
