# EPIC 05: Ứng dụng Phụ huynh (Parent Management Dashboard & Controller)

## 1. Mục tiêu
Cung cấp giao diện trực quan, thân thiện cho phụ huynh theo dõi tình hình sử dụng thiết bị của con và ra các quyết định điều chỉnh tức thì.

## 2. Danh sách User Stories / Tasks chi tiết
- **US5.1: Luồng Quét ghép nối Thiết bị mới (Onboarding & Pairing Flow):**
  - Quét mã QR từ màn hình App Con để hoàn tất pairing thiết bị trong 1 bước.
- **US5.2: Dashboard Thống kê Trực quan (Real-time Analytics Dashboard):**
  - Biểu đồ thời lượng On-screen hôm nay, so sánh với ngày trước.
  - Phân bổ thời lượng theo nhóm ứng dụng (Học tập vs Giải trí vs Mạng xã hội).
  - Trạng thái hiện tại: Đang mở app nào, máy đang khóa hay mở.
- **US5.3: Bộ điều khiển Giới hạn & Lịch biểu (Rule Configuration UI):**
  - Đặt hạn mức thời gian cho từng ứng dụng cụ thể (slider / input).
  - Thiết lập khung giờ Bedtime và Focus Mode (học bài).
- **US5.4: Bộ công cụ Điều khiển Khẩn cấp (Instant Actions):**
  - Nút chuyển trạng thái "Khóa toàn bộ thiết bị ngay lập tức" (Lockdown).
  - Nút cấp thêm thời gian nhanh: +15 phút, +30 phút, +1 giờ.

## 3. Tiêu chí chấp nhận (Acceptance Criteria)
- Dashboard cập nhật trạng thái mới nhất của con gần với thời gian thực.
- Thao tác khóa/mở tức thì phản hồi mượt mà và có thông báo xác nhận thành công.
