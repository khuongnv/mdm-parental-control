# ☁️ EPICS CHI TIẾT: BACKEND (CENTRAL ORCHESTRATOR & REAL-TIME PIPELINE)

- **Thành phần**: `backend` (Central Server / Cloud Services)
- **Nền tảng công nghệ**: **ASP.NET Core (.NET 8 / .NET 9)** Web API & SignalR
- **Kiến trúc**: Clean Architecture + CQRS (MediatR) hướng sự kiện (Event-Driven)
- **Mục tiêu**: Máy chủ trung tâm quản lý danh tính, phân giải quan hệ Bố-Con, duy trì đường truyền điều khiển 2 chiều thời gian thực (< 3s), tiếp nhận khối lượng lớn usage telemetry và tổng hợp dữ liệu báo cáo.

---

## B-EPIC 01: Quản Lý Định Danh, Xác Thực & Ghép Nối Thiết Bị (Identity & Pairing Engine)
*Phân rã từ: EPIC 04 & EPIC 05 toàn dự án*

### 1.1. Xác thực Phụ huynh & Phân quyền (Parent Auth & RBAC)
- **Mục tiêu**: Quản lý tài khoản phụ huynh an toàn, hỗ trợ gia đình nhiều người giám sát.
- **User Stories & Nhiệm vụ**:
  - Đăng ký / Đăng nhập: Email & Password (băm bằng Argon2id hoặc bcrypt), hỗ trợ OAuth2 (Google Sign-In, Apple Sign-In).
  - Cấp phát JWT Access Token (ngắn hạn 15m) và Refresh Token quay vòng (rotation) lưu trong Redis/Database.
  - Phân quyền gia đình (Family RBAC): Phụ huynh chính (Owner) và Phụ huynh đồng quản lý (Co-parent).

### 1.2. Luồng Ghép nối Thiết bị bằng QR/OTP 1 Lần (Secure 1-Step Pairing Service)
- **Mục tiêu**: Bắt tay liên kết giữa máy Con (`target-node`) và máy Bố (`admin-node`) trong vòng 5 phút an toàn tuyệt đối.
- **User Stories & Nhiệm vụ**:
  - API `POST /api/v1/pairing/request-code`: Thiết bị con yêu cầu mã ghép nối -> Backend sinh mã token mã hóa ngẫu nhiên và mã OTP 6 số (TTL 5 phút, lưu trong Redis).
  - API `POST /api/v1/pairing/claim`: Phụ huynh quét QR hoặc nhập OTP -> Backend kiểm tra tính hợp lệ, liên kết `parent_id` với `child_device_id`.
  - Cấp phát chứng chỉ thiết bị (Device JWT / mTLS token) cho máy con để kết nối an toàn lâu dài.

### 1.3. Quản lý Hồ sơ Thiết bị Con (Child Device Registry)
- **Mục tiêu**: Quản lý thông số phần cứng và trạng thái của các máy con thuộc gia đình.
- **User Stories & Nhiệm vụ**:
  - CRUD thông tin: Tên bé, avatar, model máy, phiên bản Android, IMEI/Android ID băm, phiên bản Agent.
  - Quản lý trạng thái: Đang hoạt động, Tạm dừng, hoặc Thu hồi quyền (Revoked).

---

## B-EPIC 02: Quản Trị & Đồng Bộ Chính Sách (Rule & Policy Management Engine)
*Phân rã từ: EPIC 03 & EPIC 04 toàn dự án*

### 2.1. Lược đồ Quản lý Chính sách Linh hoạt (Policy Data Schema)
- **Mục tiêu**: Lưu trữ đa dạng các loại hạn mức và lịch biểu.
- **User Stories & Nhiệm vụ**:
  - Hạn mức tổng thời gian màn hình (Daily Screen Time Quota: Phút/ngày).
  - Hạn mức riêng từng ứng dụng (Per-App Limit) và hạn mức theo nhóm (Social Media, Games, Study).
  - Khung giờ Giờ đi ngủ (Bedtime Window) tách biệt: Ngày thường (Thứ 2 - Thứ 6) vs Cuối tuần (Thứ 7 - CN).
  - Danh sách đen chặn vĩnh viễn (Blacklist) và Danh sách trắng an toàn (Whitelist).

### 2.2. Kiểm tra Phiên bản Chính sách & Đồng bộ Vi mô (Policy Versioning & ETag Sync)
- **Mục tiêu**: Đồng bộ nhanh chóng, không truyền tải dữ liệu thừa khi chính sách không đổi.
- **User Stories & Nhiệm vụ**:
  - Mỗi khi phụ huynh chỉnh sửa rule, Backend cập nhật số phiên bản `policy_version` và sinh chuỗi ETag hash.
  - API `GET /api/v1/devices/{id}/policies` hỗ trợ header `If-None-Match`: Trả về `304 Not Modified` nếu không có thay đổi.
  - Tự động phát socket event thông báo Agent tải chính sách mới khi có cập nhật.

### 2.3. Danh mục & Phân loại Ứng dụng Toàn cầu (Global App Taxonomy Service)
- **Mục tiêu**: Cung cấp metadata (tên hiển thị, icon, danh mục chuẩn) cho hàng trăm ngàn package name Android.
- **User Stories & Nhiệm vụ**:
  - Lưu trữ cơ sở dữ liệu taxonomy ánh xạ package name (vd: `com.ss.android.ugc.trill` -> `TikTok`, danh mục: `Mạng xã hội`).
  - API truy vấn metadata ứng dụng cho cả Target Agent và Parent App.

---

## B-EPIC 03: Đường Truyền Thời Gian Thực Siêu Tốc & Dự Phòng FCM (Real-Time Pipeline)
*Phân rã từ: EPIC 04 toàn dự án*

### 3.1. Hub Kết Nối WebSocket / MQTT với Redis Pub/Sub Backplane
- **Mục tiêu**: Duy trì kết nối ổn định cho hàng chục ngàn thiết bị đồng thời, độ trễ truyền tin < 1 giây.
- **User Stories & Nhiệm vụ**:
  - Cổng kết nối WebSocket / MQTT phân luồng theo `device_id` và `family_id`.
  - Tích hợp Redis Pub/Sub adapter để có thể mở rộng cụm nhiều server (horizontal scaling) mà không lo phân mảnh socket.
  - Cơ chế Heartbeat & Ping-Pong theo dõi trạng thái sống/chết (Presence Detection) của máy con.

### 3.2. Cơ chế Định Tuyến Lệnh Khẩn Cấp & Theo Dõi ACK (Instant Command Router)
- **Mục tiêu**: Đảm bảo lệnh của phụ huynh được thực thi tức thời và có phản hồi tin cậy.
- **User Stories & Nhiệm vụ**:
  - Khi Phụ huynh bấm "Khóa Ngay" (Panic Lockdown): Đẩy gói tin `COMMAND_LOCK` trực tiếp qua socket máy con.
  - Khi Phụ huynh bấm "Cộng 15 phút": Đẩy gói tin `COMMAND_ADD_TIME` mang tham số `duration_minutes: 15`.
  - Cơ chế ACK (Acknowledgement): Máy con phản hồi mã đã thực thi thành công -> Backend bắn thông báo lại cho Parent App tắt trạng thái chờ (Optimistic UI -> Confirmed).

### 3.3. Cổng Đẩy Thông Báo FCM Ưu Tiên Cao (FCM High-Priority Gateway)
- **Mục tiêu**: Đánh thức máy con thi hành lệnh khẩn cấp khi đường truyền socket bị ngắt tạm thời.
- **User Stories & Nhiệm vụ**:
  - Khi socket máy con offline: Tự động chuyển hướng payload sang FCM Data Message với cờ `priority: "high"`.
  - Gửi thông báo đẩy đến Parent App khi bé sắp hết quota (80%) hoặc hết sạch quota (100%).

---

## B-EPIC 04: Ingestion Pipeline & Thống Kê Báo Cáo Dữ Liệu Lớn (Telemetry & Analytics)
*Phân rã từ: EPIC 04 toàn dự án*

### 4.1. Cổng Tiếp Nhận Batch Log Hiệu Năng Cao (Batch Ingestion API)
- **Mục tiêu**: Xử lý êm ái hàng triệu bản ghi usage log gửi lên định kỳ từ các máy con.
- **User Stories & Nhiệm vụ**:
  - API `POST /api/v1/telemetry/usage-batch`: Tiếp nhận mảng các session log (package name, start time, end time, total foreground duration).
  - Đẩy dữ liệu vào Message Queue (RabbitMQ / Kafka / Redis Streams) để xử lý bất đồng bộ, không làm nghẽn API server.

### 4.2. Worker Tổng hợp & Lập chỉ mục Thời gian (Time-Series Aggregation Worker)
- **Mục tiêu**: Chuẩn bị sẵn dữ liệu số liệu để Dashboard hiển thị ngay lập tức không cần tính toán nặng.
- **User Stories & Nhiệm vụ**:
  - Tổng hợp dữ liệu theo các khung thời gian: Theo từng giờ trong ngày, theo ngày, theo tuần và theo tháng.
  - Phân bổ phần trăm thời gian theo nhóm danh mục (Games, Social, Education).

### 4.3. API Báo Cáo Thống Kê Dashboard (Analytics API)
- **Mục tiêu**: Cung cấp dữ liệu trực quan cho giao diện Parent App.
- **User Stories & Nhiệm vụ**:
  - API `GET /api/v1/analytics/summary?deviceId={id}&date={today}`: Trả về tổng On-Screen time, so sánh với hôm qua, top 5 ứng dụng dùng nhiều nhất.
  - API `GET /api/v1/analytics/timeline?deviceId={id}`: Trả về biểu đồ cột phân bổ thời lượng sử dụng theo 24 giờ.

---

## B-EPIC 05: An Ninh Doanh Nghiệp, Kiểm Toán & Giới Hạn Tần Suất (Enterprise Security)
*Phân rã từ: Toàn bộ kiến trúc an ninh*

### 5.1. Mã hóa Dữ liệu Nhạy cảm (Data Encryption & Privacy)
- **Mục tiêu**: Tuân thủ tiêu chuẩn an toàn dữ liệu trẻ em (COPPA / GDPR-K).
- **User Stories & Nhiệm vụ**:
  - Mã hóa toàn bộ dữ liệu định danh và log hành vi nhạy cảm trên đường truyền (TLS 1.3) và khi lưu trữ (AES-256 at rest).
  - Cơ chế xóa sạch dữ liệu (Right to be Forgotten) khi phụ huynh hủy ghép nối hoặc xóa tài khoản.

### 5.2. Nhật ký Kiểm toán Thao tác Quản trị (Audit Logging)
- **Mục tiêu**: Truy vết mọi hành động can thiệp vào máy con.
- **User Stories & Nhiệm vụ**:
  - Ghi log bất biến mọi thao tác: Bật/tắt khóa khẩn cấp, thay đổi hạn mức, đổi giờ bedtime kèm timestamp và ID phụ huynh thực hiện.

### 5.3. Giới hạn Tần suất & Phòng vệ (Rate Limiting & Anti-DDoS)
- **Mục tiêu**: Ngăn chặn tấn công brute-force hoặc spam API.
- **User Stories & Nhiệm vụ**:
  - Áp dụng Rate Limiting theo IP và Device Token cho các API nhạy cảm (Pairing, Auth, Instant Commands).
