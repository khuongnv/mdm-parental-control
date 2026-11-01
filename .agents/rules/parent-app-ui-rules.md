# 👨‍👩‍👧 Quy Chuẩn Thiết Kế Giao Diện Ứng Dụng Phụ Huynh (Parent App UI/UX Rules)

Tài liệu này là quy tắc kỹ thuật và trải nghiệm người dùng (UI/UX) bắt buộc áp dụng khi phát triển **Ứng dụng Phụ huynh (Parent Management App)** trong dự án **MDM Parental Control**.
Mục tiêu cốt lõi: **Giao diện hiện đại, trực quan, minh bạch dữ liệu theo thời gian thực và cung cấp thao tác can thiệp khẩn cấp tức thì (< 3 giây phản hồi)**.

---

## 🎨 1. Triết Lý Thiết Kế Trọng Tâm (Design Philosophy)

1. **Minh Bạch & Dễ Hiểu (Instant Clarity)**:
   - Phụ huynh không cần phải am hiểu kỹ thuật. Màn hình chính (Dashboard) phải trả lời ngay được 3 câu hỏi chỉ trong 3 giây:
     - *Hôm nay con đã dùng máy bao lâu rồi?*
     - *Hiện tại con đang mở ứng dụng gì, máy đang Khóa hay Mở?*
     - *Ứng dụng nào đang chiếm nhiều thời gian nhất?*
2. **Can Thiệp Tức Thời (Immediate Peace of Mind)**:
   - Các nút hành động khẩn cấp (Emergency Lockdown, Mở thêm giờ) phải nằm ở vị trí thuận tiện nhất ngón tay cái (Thumb Zone), có phản hồi rung/haptic và hiệu ứng thị giác xác nhận ngay lập tức (Optimistic UI).
3. **Thẩm Mỹ Tinh Tế & Đáng Tin Cậy (Modern & Trustworthy)**:
   - Áp dụng triết lý Jetpack Compose Material 3 hiện đại: bo góc mềm mại (`16.dp` - `24.dp`), độ tương phản cao, bảng màu biểu thị trạng thái chuẩn xác.

---

## 🌈 2. Bảng Màu & Chỉ Báo Trạng Thái (Status & Color Palette)

| Mục Đích | Màu Sắc | Mã Hex | Ứng Dụng Trong Giao Diện |
| :--- | :--- | :--- | :--- |
| **Bình Thường / An Toàn** | Emerald Green | `#10B981` | Máy đang mở, còn nhiều quota, thiết bị đang online ổn định |
| **Cảnh Báo Quota** | Amber Orange | `#F59E0B` | Đã dùng trên 80% quota trong ngày, sắp đến giờ Bedtime |
| **Đang Bị Khóa / Hết Giờ** | Rose Red | `#EF4444` | Đang ở chế độ Lockdown, app đã bị suspend, hết quota |
| **Chế Độ Đi Ngủ (Bedtime)** | Indigo Violet | `#6366F1` | Khung giờ Bedtime đang có hiệu lực |
| **Mất Kết Nối (Offline)** | Neutral Gray | `#9CA3AF` | Máy con đang ngắt kết nối Internet (dữ liệu lưu trữ cục bộ) |

---

## 📐 3. Quy Chuẩn Các Màn Hình Trọng Tâm (Key Screen Guidelines)

### 3.1. Dashboard Thống Kê Thời Gian Thực (Real-Time Dashboard)
- **Status Banner**:
  - Huy hiệu (Badge) thể hiện tình trạng kết nối: `🟢 Trực tuyến - Đang dùng: Duolingo` hoặc `🔴 Thiết bị đang khóa (Lockdown)`.
- **Hero Screen Time Widget**:
  - Vòng cung tiến độ (Circular Progress) hiển thị tổng thời gian on-screen hôm nay so với hạn mức cho phép (ví dụ: `2h 15m / 3h 00m`).
  - Thanh phân bổ màu danh mục ứng dụng: Xanh (Học tập), Vàng (Mạng xã hội), Đỏ/Tím (Trò chơi giải trí).
- **Quick Action Bar**:
  - Nút **"Khóa Ngay" (Panic Lock)** màu đỏ nổi bật.
  - Các nút pill nhanh: `+15 phút`, `+30 phút`, `+1 giờ`.

### 3.2. Cấu Hình Giới Hạn Ứng Dụng (Rule & Limit Configuration)
- Danh sách ứng dụng cài trên máy con có tìm kiếm và bộ lọc theo Category.
- Mỗi ứng dụng hiển thị:
  - Icon ứng dụng, tên gói, thời lượng đã dùng hôm nay.
  - Thanh gạt Bật/Tắt chặn vĩnh viễn (Blacklist / Hide).
  - Thanh trượt Slider chỉnh quota thời gian mỗi ngày (từ 0 phút đến 8 tiếng, bước nhảy 15 phút).
  - Lịch biểu riêng biệt: Ngày trong tuần (Thứ 2 - Thứ 6) vs Cuối tuần (Thứ 7 - CN).

### 3.3. Luồng Ghép Nối Thiết Bị 1 Bước (1-Step Pairing Flow)
- Phụ huynh mở màn hình "Thêm Thiết Bị Con".
- Ứng dụng kích hoạt Camera quét mã QR hiển thị trên màn hình Target Agent.
- Sau khi quét thành công: Tự động bắt tay trao đổi mã khóa (Handshake Token), lưu trữ định danh thiết bị và chuyển hướng thẳng vào Dashboard mà không cần nhập liệu thủ công rườm rà.

---

## ⚡ 4. Nguyên Tắc Trải Nghiệm Thời Gian Thực (Optimistic UI & Feedback)

1. **Cập Nhật Lạc Quan (Optimistic Update)**:
   - Khi phụ huynh nhấn nút "Khóa Ngay", giao diện Parent App chuyển trạng thái sang "Đang Khóa" ngay lập tức, đồng thời gửi socket command xuống server.
   - Nếu trong 5 giây không nhận được ACK từ server/máy con, hiển thị cảnh báo nhẹ: *"Lệnh đã gửi, đang chờ thiết bị nhận diện mạng..."*.
2. **Tự Động Kết Nối Lại (Auto Reconnect)**:
   - Duy trì WebSocket / MQTT connection ngầm với cơ chế exponential backoff reconnect khi phụ huynh chuyển đổi mạng 4G/Wi-Fi.
