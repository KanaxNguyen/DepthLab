# DepthLab

Công cụ đo thực nghiệm (không phải sản phẩm): LiDAR (camera sau) và TrueDepth (camera trước) nhìn xa tối đa bao nhiêu mét, còn đáng tin tới đâu, để đánh giá việc gắn iPhone gần gương chiếu hậu nhìn xuống ghế sau (khoảng 1,5 đến 2 m).

SwiftUI, iOS 17+, bundle id `vn.cabinsentinel.depthlab`. Không dùng mạng, không tài khoản. Kết quả chỉ là số liệu thực nghiệm trên một máy, không phải thông số của Apple.

## Chạy

```bash
brew install xcodegen          # một lần
xcodegen generate              # tạo DepthLab.xcodeproj từ project.yml
open DepthLab.xcodeproj
```

Trong Xcode: chọn iPhone thật, Signing & Capabilities dùng Automatic signing (tài khoản Apple miễn phí được). `project.yml` đang đặt `DEVELOPMENT_TEAM: P5M34J84PB`; đổi sang team của bạn nếu cần. Lần đầu mở app cần cấp quyền camera.

Lệnh build / test:

```bash
xcodebuild -project DepthLab.xcodeproj -scheme DepthLab -destination 'generic/platform=iOS' -allowProvisioningUpdates build
xcodebuild -project DepthLab.xcodeproj -scheme DepthLab -destination 'generic/platform=iOS Simulator' build
xcodebuild -project DepthLab.xcodeproj -scheme DepthLab -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

Simulator không có LiDAR/TrueDepth: app báo "Không hỗ trợ" thay vì crash.

## Quy ước "độ xa tin cậy" (của app, không phải của Apple)

Độ sâu chia thành các dải 0,25 m (0 đến 6 m). Độ xa tin cậy là mép xa của dải xa nhất có ít nhất N % điểm hợp lệ trong dải đó là "tin cậy cao" (N mặc định 30 %, chỉnh trong Cài đặt). Dải có dưới 0,5 % tổng số điểm bị bỏ qua để tránh nhiễu.

- LiDAR: độ tin cậy từng điểm lấy từ `confidenceMap` của ARKit (cao = `.high`).
- TrueDepth: cảm biến không có độ tin cậy từng điểm. App coi điểm hợp lệ là "cao" nếu `depthDataQuality == .high`, "trung bình" nếu `.low`. Mặc định tắt lọc/nội suy của hệ thống để thấy dữ liệu thô.

## Cách đo từng mốc

1. Cố định iPhone trên giá đỡ, chọn chế độ ở tab Đo.
2. Đặt búp bê cỡ trẻ nhỏ (hoặc ghế trống, balo, vải tối, áp phích phẳng) đúng mốc 0,5 / 1 / 1,5 / 2 / 3 / 4 / 5 m, đo thước từ cảm biến tới vật.
3. Chờ số đo ổn định vài giây, bấm **Ghi mẫu**, nhập khoảng cách thật, loại vật, ánh sáng.
4. Lặp lại cho 4 điều kiện ánh sáng (tối / trong nhà / bóng râm / nắng gắt), tick ô tương ứng ở tab Quy trình.
5. **Chụp mẫu** để lưu depth.png, depth_heatmap.png, confidence.png, points.ply, meta.json (rgb.jpg chỉ khi bạn bật công tắc; chỉ dùng búp bê/vật thay thế).
6. Tab Mẫu: biểu đồ sai số và **Chia sẻ CSV**. Tab Thêm > Thông số đo được: tự điền từ dữ liệu đã ghi.

Không thử với trẻ thật hay thú thật.

Tệp chụp nằm ở `Documents/Captures/<thời điểm>-<chế độ>/` (xem được qua app Tệp vì đã bật chia sẻ tệp). Ảnh và PLY ở hướng cảm biến (ngang), không xoay dọc. depth.png: 16-bit xám, đơn vị mm, 0 = không có dữ liệu. confidence.png: 0 không có, 85 thấp, 170 trung bình, 255 cao.

## Bảng kết quả (để trống, tự điền)

Sai số = |đo − thật|.

| Cảm biến | Mốc (m) | Ánh sáng | Đo (m) | Sai số (m) | % hợp lệ | % tin cậy cao | Độ xa tin cậy (m) |
|---|---|---|---|---|---|---|---|
| LiDAR | 0,5 | | | | | | |
| LiDAR | 1 | | | | | | |
| LiDAR | 1,5 | | | | | | |
| LiDAR | 2 | | | | | | |
| LiDAR | 3 | | | | | | |
| LiDAR | 4 | | | | | | |
| LiDAR | 5 | | | | | | |
| TrueDepth | 0,5 | | | | | | |
| TrueDepth | 1 | | | | | | |
| TrueDepth | 1,5 | | | | | | |
| TrueDepth | 2 | | | | | | |
| TrueDepth | 3 | | | | | | |
| TrueDepth | 4 | | | | | | |
| TrueDepth | 5 | | | | | | |

| Thông số | LiDAR | TrueDepth |
|---|---|---|
| Máy | | |
| Độ phân giải depthMap | | |
| FPS thật | | |
| Khoảng cách nhỏ nhất quan sát được | | |
| Khoảng cách lớn nhất quan sát được | | |
| Độ xa tin cậy lớn nhất | | |
