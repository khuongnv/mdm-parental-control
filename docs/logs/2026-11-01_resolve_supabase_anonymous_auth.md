# 📋 Nhật Ký Thực Thi: Hướng Dẫn Kích Hoạt Anonymous Sign-ins Cho Supabase BaaS

- **Ngày thực hiện**: 2026-11-01 20:52:00
- **Agent phụ trách**: `lead-architect` & `backend-sync-specialist`
- **Yêu cầu gốc**: Khắc phục lỗi `AuthApiException(message: Anonymous sign-ins are disabled, statusCode: 422, code: anonymous_provider_disabled)` khi mở và ghép nối trên app VFam Admin.
- **Trạng thái**: ✅ Hoàn thành

---

## 1. Phân Tích & Kế Hoạch (Analysis & Planning)
- **Hiện tượng**:
  - Ứng dụng VFam Admin (`vfam-admin-1.1.0.apk`) đã khởi chạy thành công trên máy phụ huynh, không còn crash.
  - Tuy nhiên khi tải dữ liệu ban đầu hoặc khi bấm Ghép Nối Thiết Bị (`_showPairingDialog` $\rightarrow$ `claimDevice`), app hiện thông báo lỗi:
    `Lỗi: AuthApiException(message: Anonymous sign-ins are disabled, statusCode: 422, code: anonymous_provider_disabled)`.
- **Nguyên nhân kỹ thuật**:
  - Hệ thống kiến trúc MDM thiết kế luồng xác thực **Zero-login Anonymous Onboarding** cho phụ huynh thông qua `client.auth.signInAnonymously()` của Supabase SDK nhằm giúp phụ huynh không phải đăng ký tài khoản rườm rà.
  - Trên dự án Supabase Cloud `ueamgqbxgyzxruzzjofm`, tính năng **Anonymous sign-ins** mặc định ở trạng thái **Disabled (Tắt)** trong phần cấu hình Authentication Providers.
  - Do đó, mọi yêu cầu tạo phiên ẩn danh đều bị Supabase Auth Gateway từ chối với HTTP 422.

---

## 2. Giải Pháp Khắc Phục (Resolution Steps)
- **Thao tác trên Supabase Dashboard**:
  1. Truy cập trực tiếp: `https://supabase.com/dashboard/project/ueamgqbxgyzxruzzjofm/auth/providers`
  2. Kéo xuống phần provider **Anonymous**.
  3. Bật công tắc gạt **Enable Anonymous sign-ins** (chuyển sang màu xanh).
  4. Bấm **Save** ở cuối trang.
- **Cải tiến mã nguồn ứng dụng (`admin-node`)**:
  - Trong `admin-node/lib/services/mdm_supabase_service.dart`, đã bắt riêng mã lỗi `AuthApiException` (`anonymous_provider_disabled` hoặc status 422) để hiển thị thông báo hướng dẫn tiếng Việt rõ ràng, thân thiện.

---

## 3. Danh Sách Tệp Thay Đổi (Impacted Files)
- `[Modified]`: `admin-node/lib/services/mdm_supabase_service.dart` - Bắt lỗi AuthApiException và cung cấp thông điệp hướng dẫn rõ ràng.
- `[Created]`: `docs/logs/2026-11-01_resolve_supabase_anonymous_auth.md` - Tệp nhật ký này.
- `[Modified]`: `docs/logs/README.md` - Đăng ký nhật ký truy vết.

---

## 4. Kiểm Thử & Xác Minh (Verification)
- Kiểm tra REST API: `POST /auth/v1/signup` với payload trống xác nhận phản hồi HTTP 422 `{"code":422,"error_code":"anonymous_provider_disabled"}` từ Supabase.
- Kiểm tra các phiên ghép nối từ máy con (`HONOR ROD2-W09`): Máy con đã gọi RPC `create_device_pairing` thành công tạo mã OTP trong bảng `pairing_sessions`. Sau khi bật Anonymous sign-ins, máy phụ huynh sẽ claim được ngay lập tức.
