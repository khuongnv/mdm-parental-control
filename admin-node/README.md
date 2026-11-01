# 📱 Admin Node: Parent Management App

Ứng dụng di động quản trị dành cho Phụ huynh trong hệ thống **MDM Parental Control**. Cung cấp giao diện trực quan, tin cậy, theo dõi trạng thái thiết bị của con theo thời gian thực và cho phép can thiệp tức thì.

---

## 🎯 1. Vai Trò & Trách Nhiệm Chính
- **Luồng Ghép Nối Tiện Lợi (1-Step QR Pairing)**: Quét mã QR trên màn hình điện thoại con bằng camera để hoàn tất kết nối trong vài giây.
- **Dashboard Thống Kê Trực Quan (Real-Time Analytics)**: Trả lời 3 câu hỏi chỉ trong 3 giây: Tổng thời lượng On-Screen hôm nay, Con đang mở ứng dụng nào, và Phân bổ thời gian giữa Học tập vs Game vs Mạng xã hội.
- **Bộ Điều Khiển Giới Hạn & Lịch Biểu**: Thanh trượt chỉnh quota cho từng app, lịch biểu phân tách Ngày thường vs Cuối tuần, cài đặt Giờ đi ngủ (Bedtime Mode) và Giờ học tập (Focus Mode).
- **Bộ Công Cụ Điều Khiển Khẩn Cấp (Instant Actions)**: Nút Khóa khẩn cấp toàn máy (Panic Lockdown), các nút cấp thêm giờ nhanh (`+15 phút`, `+30 phút`) với phản hồi thời gian thực dưới 3 giây (Optimistic UI & Haptics).
- **Hệ Thống Thông Báo & Duyệt Yêu Cầu**: Cảnh báo khi con chạm mốc 80%/100% quota, cảnh báo khi con cố tình can thiệp cài đặt, hộp thư duyệt yêu cầu xin thêm giờ của con.

---

## 📋 2. Danh Sách Epics Chi Tiết
Xem tài liệu đặc tả đầy đủ tại: [`docs/epics/admin_node_epics.md`](../docs/epics/admin_node_epics.md)
- **P-EPIC 01**: Xác Thực & Luồng Ghép Nối Thiết Bị 1 Bước (Auth & 1-Step Pairing).
- **P-EPIC 02**: Dashboard Giám Sát Thời Gian Thực (Real-Time Analytics Dashboard).
- **P-EPIC 03**: Bộ Điều Khiển Giới Hạn & Lịch Biểu Linh Hoạt (Rule Configuration UI).
- **P-EPIC 04**: Bộ Công Cụ Điều Khiển Khẩn Cấp Tức Thì (Instant Actions Controller).
- **P-EPIC 05**: Hệ Thống Cảnh Báo & Xử Lý Yêu Cầu Từ Con (Alerts & Request Manager).

---

## 🛠️ 3. Quy Chuẩn Giao Diện Bắt Buộc
- **Quy chuẩn thiết kế Parent App**: Tuân thủ nghiêm ngặt [Parent App UI/UX Rules](../.agents/rules/parent-app-ui-rules.md).
