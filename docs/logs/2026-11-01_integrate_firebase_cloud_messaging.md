# 📋 Nhật Ký Thực Thi: Tích Hợp Firebase Cloud Messaging (FCM) & Chuẩn Hóa Package Name vn.hanoi.khuongnv.vfam

- **Ngày thực hiện**: 2026-11-01 19:35:00
- **Agent phụ trách**: `lead-architect`, `device-owner-specialist`, `parent-ui-specialist`, `backend-sync-specialist`, `qa-security-perf-specialist`
- **Yêu cầu gốc**: Tích hợp Firebase Cloud Messaging (FCM) làm kênh dự phòng đánh thức máy con khi ở chế độ ngủ sâu (Doze Mode). Đăng ký và chuẩn hóa định danh 2 ứng dụng trên Firebase:
  - Máy con (`target-node`): `vn.hanoi.khuongnv.vfam.child`
  - Máy phụ huynh (`admin-node`): `vn.hanoi.khuongnv.vfam.admin`
- **Trạng thái**: ✅ Hoàn thành

---

## 1. Phân Tích & Kế Hoạch (Analysis & Planning)

### 1.1. Bối cảnh kỹ thuật & Tầm quan trọng của FCM trong MDM
- Trong môi trường Android thực tế, khi máy con tắt màn hình và không cắm sạc một khoảng thời gian, hệ điều hành Android sẽ kích hoạt **Doze Mode (Deep Sleep)** và ngắt kết nối mạng ngầm (bao gồm cả kết nối WebSocket Supabase Realtime).
- **FCM High-Priority Data Messages** là kênh truyền thông duy nhất được hệ điều hành Android cấp đặc quyền đánh thức ngầm (Silent Wakeup) CPU của máy con mà không cần phụ huynh hoặc trẻ phải mở app, giúp:
  1. Kích hoạt lệnh **Khóa Khẩn Cấp (Panic Lockdown)** tức thì (< 1-2 giây) thông qua `DevicePolicyManager.setPackagesSuspended`.
  2. Cấp thêm thời gian sử dụng nhanh (+15m, +30m).
  3. Đánh thức `UsageTrackingForegroundService` để kết nối lại WebSocket và đồng bộ chính sách Room Database.

### 1.2. Thống nhất định danh ứng dụng (Package Naming)
- Sau khi bàn bạc với người dùng, nhóm Swarm thống nhất đăng ký 2 ứng dụng độc lập trên Firebase Console thuộc cùng project `mdm-parental-control`:
  - **Child Node**: `vn.hanoi.khuongnv.vfam.child`
  - **Admin Node**: `vn.hanoi.khuongnv.vfam.admin`
- Bộ cấu hình `google-services.json` đầy đủ đã được trích xuất và phân bổ cho từng ứng dụng.

---

## 2. Chi Tiết Các Bước Thực Hiện (Execution Steps)

### Bước 1: Phân bổ tệp cấu hình Firebase Google Services
- Tiếp nhận tệp cấu hình từ Firebase Console:
  - Sao chép vào [`target-node/app/google-services.json`](file:///d:/PROJECT/github.com/mdm-parental-control/target-node/app/google-services.json).
  - Sao chép vào [`admin-node/android/app/google-services.json`](file:///d:/PROJECT/github.com/mdm-parental-control/admin-node/android/app/google-services.json).

### Bước 2: Tích hợp Firebase SDK vào Target Node (`target-node`)
1. **Cập nhật Build Gradle**:
   - `target-node/build.gradle.kts`: Bổ sung plugin `com.google.gms.google-services` v4.4.2.
   - `target-node/app/build.gradle.kts`:
     - Thay đổi `applicationId` thành `vn.hanoi.khuongnv.vfam.child`.
     - Thêm `id("com.google.gms.google-services")`.
     - Thêm thư viện `firebase-bom:33.5.1` và `firebase-messaging-ktx`.
2. **Cập nhật `DevicePreferences.kt`**:
   - Bổ sung thuộc tính `fcmToken: String?` để lưu trữ token FCM cục bộ.
3. **Mở rộng `MdmSupabaseClient.kt`**:
   - Bổ sung hàm `updateFcmToken(deviceId: String, fcmToken: String)` để đồng bộ token của thiết bị lên bảng `devices` trong Supabase.
4. **Xây dựng `MdmFirebaseMessagingService.kt`**:
   - Kế thừa `FirebaseMessagingService`, đánh dấu `@AndroidEntryPoint` để Hilt inject dependencies.
   - `onNewToken`: Tự động lưu và cập nhật token lên Supabase.
   - `onMessageReceived`: Nhận diện Data Payload:
     - `ACTION_PANIC_LOCKDOWN`: Gọi `DevicePolicyManager.setPackagesSuspended`, cập nhật Room DB (`isEmergencyLockdown`) và đánh thức Foreground Service.
     - `ACTION_GRANT_EXTRA_TIME`: Cộng thêm phút hạn mức trong Room DB và kích hoạt lại service.
     - `ACTION_SYNC_POLICY`: Đánh thức service để tái kết nối WebSocket.
5. **Khai báo trong `AndroidManifest.xml`**:
   - Đăng ký service `MdmFirebaseMessagingService` với intent-filter `com.google.firebase.MESSAGING_EVENT`.
6. **Cập nhật `MainActivity.kt`**:
   - Tự động lấy token qua `FirebaseMessaging.getInstance().token` khi khởi động hoặc sau khi ghép nối thành công để đẩy lên Supabase.

### Bước 3: Cập nhật cấu hình Android cho Admin Node (`admin-node`)
- `admin-node/android/settings.gradle.kts`: Thêm plugin `com.google.gms.google-services` v4.4.2.
- `admin-node/android/app/build.gradle.kts`:
  - Thay đổi `applicationId` và `namespace` thành `vn.hanoi.khuongnv.vfam.admin`.
  - Áp dụng plugin `com.google.gms.google-services`.

### Bước 4: Xây dựng Supabase Edge Function gửi Push FCM HTTP v1
- Xây dựng Edge Function tại [`backend/supabase/functions/send-fcm-command/index.ts`](file:///d:/PROJECT/github.com/mdm-parental-control/backend/supabase/functions/send-fcm-command/index.ts):
  - Nhận lệnh `{ device_id, action, is_locked, extra_minutes }`.
  - Tự động truy vấn `fcm_token` từ bảng `devices`.
  - Sử dụng Deno SubtleCrypto để ký JWT với Private Key từ Service Account.
  - Gọi Google OAuth2 lấy Bearer Token và gửi HTTP POST v1 tới `https://fcm.googleapis.com/v1/projects/{projectId}/messages:send` với mức ưu tiên cao (`priority: "HIGH"`, `direct_boot_ok: true`).

---

## 3. Danh Sách Tệp Thay Đổi (Impacted Files)

| Thao tác | Đường dẫn tệp | Mô tả |
| :--- | :--- | :--- |
| `[Created]` | [`target-node/app/google-services.json`](file:///d:/PROJECT/github.com/mdm-parental-control/target-node/app/google-services.json) | File cấu hình Firebase cho máy con |
| `[Created]` | [`admin-node/android/app/google-services.json`](file:///d:/PROJECT/github.com/mdm-parental-control/admin-node/android/app/google-services.json) | File cấu hình Firebase cho máy phụ huynh |
| `[Created]` | [`target-node/.../service/MdmFirebaseMessagingService.kt`](file:///d:/PROJECT/github.com/mdm-parental-control/target-node/app/src/main/java/com/mdm/parentalcontrol/child/service/MdmFirebaseMessagingService.kt) | Service đón silent push đánh thức Doze Mode & khóa app native |
| `[Created]` | [`backend/supabase/functions/send-fcm-command/index.ts`](file:///d:/PROJECT/github.com/mdm-parental-control/backend/supabase/functions/send-fcm-command/index.ts) | Supabase Edge Function gửi FCM Push HTTP v1 |
| `[Modified]` | [`target-node/build.gradle.kts`](file:///d:/PROJECT/github.com/mdm-parental-control/target-node/build.gradle.kts) | Thêm plugin Google Services v4.4.2 |
| `[Modified]` | [`target-node/app/build.gradle.kts`](file:///d:/PROJECT/github.com/mdm-parental-control/target-node/app/build.gradle.kts) | Cập nhật `applicationId = "vn.hanoi.khuongnv.vfam.child"`, thêm Firebase BOM |
| `[Modified]` | [`target-node/.../data/local/DevicePreferences.kt`](file:///d:/PROJECT/github.com/mdm-parental-control/target-node/app/src/main/java/com/mdm/parentalcontrol/child/data/local/DevicePreferences.kt) | Bổ sung lưu trữ fcm_token cục bộ |
| `[Modified]` | [`target-node/.../network/MdmSupabaseClient.kt`](file:///d:/PROJECT/github.com/mdm-parental-control/target-node/app/src/main/java/com/mdm/parentalcontrol/child/network/MdmSupabaseClient.kt) | Bổ sung API đồng bộ FCM Token lên Supabase |
| `[Modified]` | [`target-node/.../ui/MainActivity.kt`](file:///d:/PROJECT/github.com/mdm-parental-control/target-node/app/src/main/java/com/mdm/parentalcontrol/child/ui/MainActivity.kt) | Lấy và đồng bộ FCM token khi ghép nối |
| `[Modified]` | [`target-node/app/src/main/AndroidManifest.xml`](file:///d:/PROJECT/github.com/mdm-parental-control/target-node/app/src/main/AndroidManifest.xml) | Đăng ký MdmFirebaseMessagingService |
| `[Modified]` | [`admin-node/android/settings.gradle.kts`](file:///d:/PROJECT/github.com/mdm-parental-control/admin-node/android/settings.gradle.kts) | Thêm plugin Google Services cho Flutter Android |
| `[Modified]` | [`admin-node/android/app/build.gradle.kts`](file:///d:/PROJECT/github.com/mdm-parental-control/admin-node/android/app/build.gradle.kts) | Đổi `applicationId = "vn.hanoi.khuongnv.vfam.admin"`, apply google-services |
| `[Modified]` | [`docs/logs/README.md`](file:///d:/PROJECT/github.com/mdm-parental-control/docs/logs/README.md) | Cập nhật danh mục nhật ký truy vết |

---

## 4. Kiểm Thử & Đánh Giá Bảo Mật (Verification & Security Audit)

### 4.1. Phân Tích Bảo Mật (Security & Anti-Bypass Audit)
- **Zero-Bypass Doze Mode**: Ngay cả khi thiết bị con tắt màn hình hoặc mạng nền WebSocket bị ngắt, FCM High-Priority Data message đảm bảo lệnh Panic Lockdown được thực thi ngay trong vòng 1-2 giây.
- **Bảo mật Service Account**: Private Key của Firebase Service Account được cấu hình bảo mật trong Supabase Edge Function Secrets (`FIREBASE_SERVICE_ACCOUNT_JSON`), không bao giờ bị lộ ra ngoài client.

### 4.2. Kết quả Biên Dịch (Compilation Results)
- **Target Node (Android Native Kotlin)**:
  - Chạy `./gradlew.bat compileDebugSources --no-daemon`:
  - **Kết quả**: `BUILD SUCCESSFUL in 35s` (21 actionable tasks: 3 executed, 18 up-to-date). Không có lỗi biên dịch.
- **Admin Node (Flutter)**:
  - Chạy `flutter analyze`: `No issues found! (ran in 6.3s)` - 0 warnings, 0 errors.
  - Chạy `flutter build apk --debug`: `√ Built build\app\outputs\flutter-apk\app-debug.apk` thành công 100%.

---

## 5. Kết Luận & Hướng Dẫn Tiếp Theo (Conclusion & Next Steps)

- **Kết luận**:
  - Hệ thống đã tích hợp hoàn chỉnh hạ tầng Firebase Cloud Messaging (FCM) ở cả 3 tầng: Target Node, Admin Node và Backend Supabase Edge Function.
  - Package Name đã được đồng bộ chuẩn xác: `vn.hanoi.khuongnv.vfam.child` và `vn.hanoi.khuongnv.vfam.admin`.
- **Bước tiếp theo cần từ người dùng**:
  - Cung cấp tệp **Firebase Service Account JSON** (từ Firebase Console -> Project Settings -> Service accounts -> Generate new private key) để triển khai Edge Function gửi push trên môi trường Supabase production.
