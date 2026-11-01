# 📋 Nhật Ký Thực Thi: Tạo Skill deploy-app Cho Phép Cập Nhật Phiên Bản Độc Lập Từng App

- **Ngày thực hiện**: 2026-11-01 12:54:37
- **Agent phụ trách**: `lead-architect` (phối hợp với `qa-security-perf-specialist`)
- **Yêu cầu gốc**: Tạo skill deploy-app phù hợp để update version cho từng app qua GitHub Release.
- **Trạng thái**: ✅ Hoàn thành

---

## 1. Phân Tích & Kế Hoạch (Analysis & Planning)
- **Mục tiêu**:
  - Cung cấp kỹ năng chuẩn (`.agents/skills/deploy-app/`) để Swarm Agent có thể tự động hóa toàn bộ luồng phát hành phiên bản mới cho từng ứng dụng di động:
    - `-Target target`: Build và phát hành `target-node` (Child DO Agent) kèm tag `target-vX.Y.Z`.
    - `-Target admin`: Build và phát hành `admin-node` (Parent App) kèm tag `admin-vX.Y.Z`.
    - `-Target all`: Build và phát hành cả 2 ứng dụng đồng thời.
  - Tận dụng GitHub CLI (`gh release create`) đã được xác thực an toàn trên môi trường máy chủ.

---

## 2. Chi Tiết Các Bước Thực Hiện (Execution Steps)

- **Bước 1**:
  - Tạo script điều phối [`.agents/skills/deploy-app/scripts/deploy.ps1`](file:///d:/VNPT/Source/github.com/mdm-parental-control/.agents/skills/deploy-app/scripts/deploy.ps1):
    - Hỗ trợ tham số `-Target`, `-Version`, `-Notes`.
    - Tự động gọi `./gradlew app:assembleDebug` đối với `target-node` hoặc `flutter build apk` đối với `admin-node`.
    - Đổi tên tệp APK thành `mdm-child-agent-<version>.apk` hoặc `mdm-parent-admin-<version>.apk`.
    - Tự động commit các thay đổi phiên bản chưa stage, tạo git tag có tiền tố (`target-vX.Y.Z` hoặc `admin-vX.Y.Z`), đẩy tag lên origin và gọi `gh release create` đính kèm file APK.
    - Dọn dẹp tệp APK tạm sau khi publish.

- **Bước 2**:
  - Biên soạn tài liệu hướng dẫn kỹ năng [`.agents/skills/deploy-app/SKILL.md`](file:///d:/VNPT/Source/github.com/mdm-parental-control/.agents/skills/deploy-app/SKILL.md) với đầy đủ metadata, sơ đồ quy trình Mermaid và các ví dụ thực thi chi tiết.

---

## 3. Danh Sách Tệp Thay Đổi (Impacted Files)
- `[Created]`: `.agents/skills/deploy-app/scripts/deploy.ps1` - Kịch bản tự động build, tag và release lên GitHub
- `[Created]`: `.agents/skills/deploy-app/SKILL.md` - Cẩm nang kỹ năng deploy-app
- `[Created]`: `docs/logs/2026-11-01_create_deploy_app_skill.md` - Nhật ký thực thi
- `[Modified]`: `docs/logs/README.md` - Cập nhật danh mục nhật ký

---

## 4. Kiểm Thử & Đánh Giá An Toàn (`qa-security-perf-specialist`)
- Kiểm tra tính sẵn sàng của GitHub CLI: `gh auth status` xác nhận đăng nhập tài khoản `khuongnv` với đầy đủ quyền `repo`.
- Kịch bản `deploy.ps1` có cơ chế kiểm tra lỗi cú pháp, tự động rollback và dọn dẹp các artifact trung gian nếu quá trình build hoặc upload thất bại.

---

## 5. Kết Luận
Skill `deploy-app` đã sẵn sàng đưa vào vận hành thực tế cho dự án.
