# 📱 Target Node: Child Device Owner Agent

Phần mềm giám sát và thực thi chính sách quản lý thiết bị cài đặt trực tiếp trên điện thoại của con (Target Android Device). Ứng dụng chạy với đặc quyền tối cao **Android Device Owner (DO)** nhằm loại bỏ hoàn toàn khả năng bị gỡ bỏ, ép dừng hoặc vượt rào.

---

## 🎯 1. Vai Trò & Trách Nhiệm Chính
- **Kích hoạt Device Owner**: Qua lệnh ADB shell (`dpm set-device-owner`) hoặc mã QR Provisioning khi máy mới Setup.
- **Bảo Vệ Chống Phá Hoại (Anti-Tampering)**: Chặn gỡ app, chặn Safe Mode, chặn Factory Reset, khóa đổi ngày giờ hệ thống, khóa tạo người dùng Guest, khóa ADB debugging sau kích hoạt.
- **Engine Giám Sát Thời Lượng (Usage Tracking)**: Đọc chính xác mili-giây qua `UsageStatsManager.queryEvents()`, adaptive polling theo màn hình (`SCREEN_ON` vs `SCREEN_OFF`), dịch vụ chạy ngầm 2 lớp (Foreground Service + WorkManager), tiêu thụ pin < 3-5%/ngày.
- **Thực Thi Khóa Cấp Hệ Điều Hành**: Dùng API `DevicePolicyManager.setPackagesSuspended` (làm xám icon, chặn native) và `setApplicationHidden` (ẩn vĩnh viễn khỏi App Drawer).
- **Hoạt Động Ngoại Tuyến (Offline First)**: Tự trừ quota và tự động khóa app bằng Room Database cục bộ kể cả khi mất kết nối mạng.
- **Điều Khiển Thời Gian Thực**: WebSocket client nhận lệnh khóa khẩn cấp (`Panic Lockdown`) và cấp thêm giờ (+15m) từ Backend trong < 3 giây; dự phòng bằng FCM High-Priority Data Push.

---

## 📋 2. Danh Sách Epics Chi Tiết
Xem tài liệu đặc tả đầy đủ tại: [`docs/epics/target_node_epics.md`](../docs/epics/target_node_epics.md)
- **T-EPIC 01**: Core Device Owner Setup & Chống Phá Hoại (Anti-Tampering).
- **T-EPIC 02**: Engine Thu Thập & Thống Kê Thời Lượng Sử Dụng Siêu Nhẹ.
- **T-EPIC 03**: Cơ Chế Thực Thi Giới Hạn Cấp Hệ Điều Hành (Policy Enforcement).
- **T-EPIC 04**: Kênh Truyền Thông Thời Gian Thực & Đồng Bộ Dữ Liệu.
- **T-EPIC 05**: Giao Diện Màn Hình Con & Ghép Nối (Child Pairing UI).

---

## 🛠️ 3. Quy Chuẩn Kỹ Thuật Bắt Buộc
- **Quy tắc bảo mật Device Owner**: Tuân thủ nghiêm ngặt [Device Owner Security Rules](../.agents/rules/device-owner-security-rules.md).
- **Quy tắc pin & chạy ngầm**: Tuân thủ nghiêm ngặt [Battery Background Rules](../.agents/rules/battery-background-rules.md).
