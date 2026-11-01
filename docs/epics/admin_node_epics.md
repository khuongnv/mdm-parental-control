# 📱 EPICS CHI TIẾT: ADMIN-NODE (PARENT MANAGEMENT APP)

- **Thành phần**: `admin-node` (Ứng dụng Di động dành cho Phụ huynh)
- **Mục tiêu**: Cung cấp giao diện trực quan, tin cậy, thông báo trạng thái con theo thời gian thực và cho phép can thiệp tức thì bằng các nút bấm khẩn cấp phản hồi dưới 3 giây.

---

## P-EPIC 01: Xác Thực & Luồng Ghép Nối Thiết Bị 1 Bước (Auth & 1-Step Pairing)
*Phân rã từ: EPIC 04 & EPIC 05 toàn dự án*

### 1.1. Luồng Xác Thực Tài Khoản Phụ Huynh (Parent Auth Flow)
- **Mục tiêu**: Đăng nhập nhanh, an toàn, hỗ trợ khóa sinh trắc học trên máy phụ huynh.
- **User Stories & Nhiệm vụ**:
  - Đăng ký / Đăng nhập qua Email + Mật khẩu hoặc Đăng nhập nhanh bằng Google / Apple.
  - Hỗ trợ Mở khóa vân tay / Face ID (Biometric Authentication) để mở app nhanh mà không cần gõ lại mật khẩu.

### 1.2. Trình Quét Camera Ghép Nối 1 Bước (1-Step QR Scanner Flow)
- **Mục tiêu**: Ghép nối với máy con cực kỳ tiện lợi chỉ bằng 1 thao tác quét camera.
- **User Stories & Nhiệm vụ**:
  - Tích hợp trình quét mã QR camera tốc độ cao.
  - Quét mã QR hiển thị trên màn hình máy con (`target-node`), tự động giải mã token và gửi API Claim lên Backend.
  - Tùy chọn nhập mã OTP 6 số thủ công nếu camera gặp sự cố.
  - Hoàn tất ghép nối và chuyển hướng ngay vào Dashboard máy con.

### 1.3. Quản lý Hồ sơ Nhiều Con & Thiết Bị (Multi-Child Profile Switcher)
- **Mục tiêu**: Phụ huynh có thể quản lý nhiều con và mỗi con có thể có nhiều thiết bị (Điện thoại, Máy tính bảng).
- **User Stories & Nhiệm vụ**:
  - Thanh chuyển đổi danh thiếp bé (Child Selector Pill/Bar) ở đầu màn hình.
  - Thêm, sửa tên, đổi ảnh đại diện và tùy biến màu sắc nhận diện cho từng bé.

---

## P-EPIC 02: Dashboard Giám Sát Thời Gian Thực (Real-Time Analytics Dashboard)
*Phân rã từ: EPIC 05 toàn dự án*

### 2.1. Thẻ Chỉ Báo Trạng Thái Trực Tuyến (Live Device Status Card)
- **Mục tiêu**: Cho phụ huynh biết ngay con đang làm gì trên máy trong nháy mắt (3-second clarity).
- **User Stories & Nhiệm vụ**:
  - Badge trạng thái kết nối: `🟢 Trực tuyến`, `🔴 Bị Khóa (Lockdown)`, `🟡 Giờ Đi Ngủ (Bedtime)` hoặc `⚪ Ngoại tuyến (Offline)`.
  - Hiển thị tên ứng dụng đang chạy ở Foreground (ví dụ: `Đang mở: Duolingo`).
  - Hiển thị mức pin hiện tại của máy con và biểu tượng trạng thái mạng (Wi-Fi/4G).

### 2.2. Widget Thời Gian Màn Hình Cốt Lõi (Hero Screen Time Gauge)
- **Mục tiêu**: Trực quan hóa tiến độ sử dụng trong ngày so với định mức cho phép.
- **User Stories & Nhiệm vụ**:
  - Vòng tròn tiến độ (Circular Progress Gauge) thể hiện thời gian đã sử dụng (ví dụ: `2h 15m`) trên tổng thời gian cho phép (ví dụ: `3h 00m`).
  - Đổi màu cảnh báo động: Xanh lá cây (< 80%) -> Cam hổ phách (80% - 99%) -> Đỏ hồng (Đạt 100% hoặc vượt quota).

### 2.3. Biểu Đồ Phân Bổ Danh Mục & Lịch Sử Sử Dụng (Visual Charts & Trends)
- **Mục tiêu**: Minh bạch hóa thời gian con dành cho học tập hay giải trí.
- **User Stories & Nhiệm vụ**:
  - Biểu đồ tròn (Donut Chart) hoặc thanh phân đoạn chia tỉ lệ: Học tập vs Mạng xã hội vs Trò chơi giải trí.
  - Biểu đồ cột (Bar Chart) 24 giờ trong ngày: Cho thấy con dùng máy nhiều nhất vào khung giờ nào.
  - So sánh xu hướng: Tăng/giảm bao nhiêu phần trăm so với ngày hôm qua hoặc tuần trước.

---

## P-EPIC 03: Bộ Điều Khiển Giới Hạn & Lịch Biểu Linh Hoạt (Rule Configuration UI)
*Phân rã từ: EPIC 03 & EPIC 05 toàn dự án*

### 3.1. Cấu Hình Hạn Mức Từng Ứng Dụng (App-by-App Limit Sliders)
- **Mục tiêu**: Cho phép phụ huynh đặt thời gian chi tiết cho từng app.
- **User Stories & Nhiệm vụ**:
  - Danh sách toàn bộ ứng dụng cài đặt trên máy con kèm icon sắc nét và danh mục.
  - Thanh trượt (Slider) đặt thời gian theo bước nhảy 15 phút (từ 0 phút đến 8 tiếng).
  - Phân tách hạn mức: Ngày thường (Thứ 2 - Thứ 6) vs Cuối tuần (Thứ 7 - CN).

### 3.2. Cấu Hình Khung Giờ Đi Ngủ & Tập Trung (Bedtime & Focus Mode Picker)
- **Mục tiêu**: Khóa toàn diện máy hoặc nhóm app giải trí theo khung giờ cố định.
- **User Stories & Nhiệm vụ**:
  - Trình chọn giờ dạng đồng hồ tròn trực quan (ví dụ: Đi ngủ từ 21h30 đến 06h30 sáng hôm sau).
  - Chế độ Focus Mode: Đặt lịch giờ học bài (ví dụ: 19h00 - 21h00), tự động chặn mọi app ngoại trừ app học tập trong danh sách trắng.

### 3.3. Công Tắc Ẩn & Chặn Vĩnh Viễn (Stealth App Hiding Switch)
- **Mục tiêu**: Xóa sổ app khỏi tầm mắt trẻ chỉ bằng một nút gạt.
- **User Stories & Nhiệm vụ**:
  - Nút Switch "Ẩn khỏi App Drawer" (kích hoạt `setApplicationHidden` ở máy con).
  - Nút Switch "Chặn vĩnh viễn" (đưa vào Blacklist).

---

## P-EPIC 04: Bộ Công Cụ Điều Khiển Khẩn Cấp Tức Thì (Instant Actions Controller)
*Phân rã từ: EPIC 05 toàn dự án*

### 4.1. Nút Khóa Toàn Bộ Thiết Bị Khẩn Cấp (Panic Lockdown Switch)
- **Mục tiêu**: Phụ huynh có thể ngắt kết nối con ngay lập tức trong các tình huống khẩn cấp.
- **User Stories & Nhiệm vụ**:
  - Nút chuyển đổi lớn, màu đỏ cảnh báo đặt tại vùng thuận tay cái (Thumb Zone).
  - Có bước xác nhận nhanh (hoặc vuốt để khóa) để tránh bấm nhầm.
  - Gửi lệnh WebSocket trực tiếp tới máy con và hiển thị trạng thái chờ ACK trong vòng 3 giây.

### 4.2. Bộ Nút Cấp Thêm Giờ Nhanh (Quick Bonus Time Pills)
- **Mục tiêu**: Khuyến khích trẻ khi làm việc tốt mà không cần vào sâu trong menu cài đặt.
- **User Stories & Nhiệm vụ**:
  - Các nút bấm nhanh: `+15 phút`, `+30 phút`, `+1 giờ`.
  - Bấm nút lập tức gửi lệnh mở khóa tạm thời xuống máy con.

### 4.3. Trải Nghiệm Giao Diện Cập Nhật Lạc Quan (Optimistic UI Feedback)
- **Mục tiêu**: Đem lại cảm giác mượt mà, phản hồi tức thì cho người dùng.
- **User Stories & Nhiệm vụ**:
  - Giao diện đổi trạng thái ngay khi phụ huynh bấm nút, kèm rung nhẹ (Haptic Feedback).
  - Hiển thị dấu tích xanh nhỏ khi nhận được xác nhận (ACK) từ máy con.

---

## P-EPIC 05: Hệ Thống Cảnh Báo & Xử Lý Yêu Cầu Từ Con (Alerts & Request Manager)
*Phân rã từ: EPIC 04 & EPIC 05 toàn dự án*

### 5.1. Thông Báo Đẩy Thông Minh (Smart Push Notifications)
- **Mục tiêu**: Báo cho phụ huynh biết các sự kiện trọng yếu mà không gây phiền nhiễu.
- **User Stories & Nhiệm vụ**:
  - Nhận thông báo khi con dùng đạt 80% và 100% hạn mức ngày.
  - Nhận cảnh báo bảo mật khẩn cấp: Bé cố tình vào Cài đặt để gỡ ứng dụng hoặc khởi động lại máy vào Safe Mode.

### 5.2. Hộp Thư Duyệt Yêu Cầu Cấp Thêm Giờ (Time Request Inbox)
- **Mục tiêu**: Tương tác văn minh giữa phụ huynh và con trẻ.
- **User Stories & Nhiệm vụ**:
  - Khi bé bấm "Xin thêm 15 phút" trên máy con, Parent App nhận thông báo kèm 2 nút: `Đồng ý (+15m)` hoặc `Từ chối`.
  - Phụ huynh ra quyết định chỉ với một chạm từ Notification Bar hoặc từ màn hình App.
