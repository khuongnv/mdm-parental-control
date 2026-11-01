# EPIC 03: Cơ chế Thực thi Giới hạn & Chặn ứng dụng (Rule Enforcement & App Suspension)

## 1. Mục tiêu
Thực thi các lệnh khóa/mở ứng dụng tầng hệ điều hành một cách triệt để, không dùng overlay che tạm thời, đảm bảo người dùng không thể can thiệp.

## 2. Danh sách User Stories / Tasks chi tiết
- **US3.1: Cơ chế Suspend ứng dụng cấp HĐH (`setPackagesSuspended`):**
  - Tích hợp API `DevicePolicyManager.setPackagesSuspended(admin, packageNames, true)`.
  - Đổi màu icon ứng dụng bị khóa thành xám trên Launcher.
  - Tùy chỉnh thông điệp hệ thống hiển thị khi bấm vào app bị khóa.
- **US3.2: Cơ chế Ẩn ứng dụng (`setApplicationHidden`):**
  - Ẩn hoàn toàn icon ứng dụng khỏi App Drawer đối với các app thuộc Blacklist vĩnh viễn.
- **US3.3: Quản lý Quota & Lịch biểu Cục bộ (Local Rule Engine):**
  - Hết hạn mức thời gian ngày (ví dụ 45 phút TikTok): Tự động trigger suspend mà không cần chờ Backend ra lệnh.
  - Chế độ Giờ đi ngủ (Bedtime Mode): Tự động khóa toàn bộ nhóm ứng dụng giải trí theo khung giờ định sẵn (ví dụ 21h00 - 06h00).
- **US3.4: Danh sách ngoại lệ (White-list) & Khẩn cấp:**
  - Luôn đảm bảo các ứng dụng thiết yếu (Gọi điện, Tin nhắn khẩn cấp, Bản đồ, Ứng dụng trường học) không bị khóa.

## 3. Tiêu chí chấp nhận (Acceptance Criteria)
- Khi hết giờ hoặc bị khóa, ứng dụng lập tức dừng và không thể mở lại bằng bất kỳ thao tác nào từ launcher hay notification.
- Tự động mở khóa đúng 00:00 hoặc theo đúng cấu hình khung giờ cho phép.
