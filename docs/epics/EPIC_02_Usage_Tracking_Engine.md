# EPIC 02: Engine Thu thập & Thống kê Thời lượng Sử dụng (Usage Tracking Engine)

## 1. Mục tiêu
Thu thập chính xác thời lượng và hành vi sử dụng từng ứng dụng theo thời gian thực mà không gây tiêu hao pin quá mức.

## 2. Danh sách User Stories / Tasks chi tiết
- **US2.1: Lắng nghe và truy vấn Sự kiện sử dụng (Usage Events Collector):**
  - Sử dụng `UsageStatsManager.queryEvents()` để bắt các mốc `ACTIVITY_RESUMED` và `ACTIVITY_PAUSED`.
  - Tính toán chính xác thời gian active của ứng dụng Foreground (mili-giây).
- **US2.2: Cơ chế Background Polling & Session Watcher:**
  - Thiết kế Foreground Service chạy ngầm siêu nhẹ (low footprint) với Silent Notification.
  - Tích hợp `WorkManager` làm fail-safe định kỳ quét và lưu trạng thái vào Room Database cục bộ.
- **US2.3: Bộ đệm cục bộ (Local Aggregator & Buffer):**
  - Lưu trữ tổng thời gian sử dụng trong ngày vào SQLite/Room DB.
  - Hỗ trợ hoạt động Offline: Vẫn tính quota và thực thi rule ngay cả khi ngắt kết nối mạng.
- **US2.4: Phân loại ứng dụng (App Categorization):**
  - Trích xuất thông tin App Category từ Android System (Game, Social, Audio, Video, Productivity) hoặc mapping từ backend.

## 3. Tiêu chí chấp nhận (Acceptance Criteria)
- Độ lệch thời gian ghi nhận so với thực tế < 2 giây.
- Tiêu thụ pin < 3-5% tổng thời lượng pin mỗi ngày.
- Khi mất kết nối mạng hoặc tắt máy mở lại, số liệu usage không bị mất hoặc reset sai thời điểm.
