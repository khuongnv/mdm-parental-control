# 📋 Nhật Ký Thực Thi: Phân rã chi tiết Epics cho 3 project con (target-node, backend, admin-node) và thiết lập tiêu chí lựa chọn công nghệ

- **Ngày thực hiện**: 2026-11-01 08:29:32
- **Agent phụ trách**: `lead-architect`
- **Yêu cầu gốc**: Phân tích epics tổng thể của dự án để viết epics chi tiết cho 3 project con tương ứng với 3 thư mục `target-node`, `backend`, `admin-node`, đồng thời đưa ra các yêu cầu/tiêu chí kỹ thuật để lựa chọn công nghệ.
- **Trạng thái**: ✅ Hoàn thành

---

## 1. Phân Tích & Kế Hoạch (Analysis & Planning)
- **Bối cảnh & Mục tiêu kỹ thuật**:
  - Dự án được cấu trúc thành 3 thành phần độc lập trong không gian mã nguồn:
    1. `target-node`: Ứng dụng Agent giám sát chạy trên điện thoại con với quyền Android Device Owner (DO).
    2. `backend`: Máy chủ trung tâm điều phối, xác thực, quản lý rule, duy trì socket thời gian thực và tổng hợp dữ liệu telemetry.
    3. `admin-node`: Ứng dụng di động quản trị dành cho Phụ huynh, hiển thị dashboard thời gian thực và các nút can thiệp khẩn cấp tức thời.
  - Cần phân rã toàn diện 5 Epics tổng thể của dự án (`EPIC_01` đến `EPIC_05`) thành các Epics chuyên biệt cho từng node.
  - Thiết lập bộ tiêu chí kỹ thuật chuẩn xác để lựa chọn công nghệ (Tech Stack) cho cả 3 node, phân tích ưu nhược điểm và khuyến nghị giải pháp tối ưu.

---

## 2. Chi Tiết Các Bước Thực Hiện (Execution Steps)

- **Bước 1**: Phân rã Epics tổng thể thành 5 Epics chi tiết cho `target-node` (`T-EPIC 01` đến `T-EPIC 05`) tập trung vào Android Device Owner, Anti-tampering zero-bypass, UsageStats millisecond tracking, native suspension (`setPackagesSuspended`), offline-first Room buffer và WebSocket/FCM client. Lưu tại `docs/epics/target_node_epics.md`.
- **Bước 2**: Phân rã Epics tổng thể thành 5 Epics chi tiết cho `backend` (`B-EPIC 01` đến `B-EPIC 05`) tập trung vào Auth & 1-step pairing QR/OTP, Policy ETag versioning, Ultra-low latency WebSocket/MQTT broker (< 3s) với Redis Pub/Sub, FCM High-Priority gateway, high-throughput batch ingestion và time-series aggregation. Lưu tại `docs/epics/backend_epics.md`.
- **Bước 3**: Phân rã Epics tổng thể thành 5 Epics chi tiết cho `admin-node` (`P-EPIC 01` đến `P-EPIC 05`) tập trung vào Auth & 1-step Camera QR scanner, Live device status & 3-second clarity dashboard, App-by-app quota sliders, Panic lockdown switch và Smart alerts. Lưu tại `docs/epics/admin_node_epics.md`.
- **Bước 4**: Khởi tạo tài liệu `README.md` trong từng thư mục con (`target-node/README.md`, `backend/README.md`, `admin-node/README.md`) nhằm định nghĩa rõ ràng phạm vi, vai trò và quy chuẩn bắt buộc của từng node.
- **Bước 5**: Xây dựng báo cáo phân tích yêu cầu công nghệ (Tech Stack Selection Requirements) với các tiêu chí khắt khe về độ trễ, an ninh hệ điều hành, mức tiêu thụ pin và khả năng mở rộng.
- **Bước 6**: Cập nhật tệp nhật ký thực thi này và cập nhật trạng thái trong `docs/logs/README.md`.

---

## 3. Danh Sách Tệp Thay Đổi (Impacted Files)

- `[Created]` `docs/epics/target_node_epics.md` - Đặc tả 5 Epics chi tiết cho `target-node` (Child Agent).
- `[Created]` `docs/epics/backend_epics.md` - Đặc tả 5 Epics chi tiết cho `backend` (Central Orchestrator).
- `[Created]` `docs/epics/admin_node_epics.md` - Đặc tả 5 Epics chi tiết cho `admin-node` (Parent App).
- `[Created]` `target-node/README.md` - Giới thiệu tổng quan, phạm vi và quy chuẩn kỹ thuật cho Target Node.
- `[Created]` `backend/README.md` - Giới thiệu tổng quan, phạm vi và quy chuẩn kỹ thuật cho Backend Node.
- `[Created]` `admin-node/README.md` - Giới thiệu tổng quan, phạm vi và quy chuẩn kỹ thuật cho Admin Node.
- `[Modified]` `docs/logs/README.md` - Cập nhật trạng thái tác vụ trong chỉ mục.
- `[Created]` `docs/logs/2026-11-01_decompose_epics_and_tech_stack_requirements.md` - Nhật ký chi tiết tác vụ này.

---

## 4. Kiểm Thử & Đánh Giá Bảo Mật (Verification & Security Audit)

- Tất cả các Epics chi tiết đã được rà soát để đảm bảo:
  - 100% không dùng Overlay Window (`SYSTEM_ALERT_WINDOW`) trên máy con.
  - Đảm bảo tính sẵn sàng ngoại tuyến (Offline-First) trên máy con: Quota trừ cục bộ, suspend tự động.
  - Đảm bảo kênh khẩn cấp đạt chuẩn phản hồi < 3 giây giữa Parent App -> Backend -> Child Agent.
  - Đảm bảo các tiêu chuẩn bảo mật dữ liệu trẻ em (COPPA / GDPR-K).

---

## 5. Kết Luận & Hướng Dẫn Tiếp Theo (Conclusion & Next Steps)

- Đã hoàn tất việc phân rã Epics và chuẩn bị tài liệu kỹ thuật hoàn chỉnh cho cả 3 project con.
- Đã sẵn sàng trình bày các yêu cầu lựa chọn công nghệ cho người dùng phê duyệt để chuẩn bị scaffold mã nguồn thực tế cho từng node.
