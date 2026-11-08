# Build cho iPhone (iOS)

## TL;DR

- **Không thể** build iOS trên Windows. Apple bắt buộc **macOS + Xcode** cho mọi bước compile/ký.
- Repo **đã sẵn sàng cho iOS**: thư mục `ios/` đã được tạo, bundle id `vn.vilep.app`, tên app "Ví Lép", ATS mở cho API LAN khi dev.
- Có 3 cách ra bản cài iPhone: **Mac + Xcode**, **CI macOS (GitHub Actions/Codemagic)**, hoặc **TestFlight qua Apple Developer**.
- Chưa có Mac? Dùng tạm **bản web/PWA** trên iPhone (Safari → Chia sẻ → Thêm vào màn hình chính) — dùng được ngay hôm nay.

---

## 1. Trên Mac (cách chuẩn)

```bash
# Yêu cầu: macOS 14+, Xcode 16+, CocoaPods
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
brew install cocoapods

cd apps/mobile
flutter pub get
cd ios && pod install && cd ..

# Chạy thử trên iPhone cắm cáp (cần chọn Team trong Xcode)
open ios/Runner.xcworkspace
# Xcode → Runner target → Signing & Capabilities → Team = Apple ID của bạn
flutter run -d <device-id>

# Build bản lưu trữ
flutter build ipa --release --dart-define=API_BASE=https://api.vilep.vn \
  --export-options-plist=ios/ExportOptions.plist
```

Kết quả: `build/ios/ipa/*.ipa`. Mở bằng **Transporter** hoặc Xcode Organizer để đẩy lên TestFlight/App Store.

### Tài khoản Apple cần gì?

| Mục đích | Yêu cầu | Ghi chú |
|---|---|---|
| Chạy thử trên iPhone của bạn | Apple ID miễn phí | Chứng chỉ hết hạn sau 7 ngày, tối đa 3 app |
| TestFlight / phát hành | **Apple Developer Program** ($99/năm) | Cần App Store Connect, privacy policy, review |
| Phân phối nội bộ (doanh nghiệp) | Apple Developer Enterprise | Chỉ tổ chức đủ điều kiện |

### Cấu hình đã có sẵn trong repo

- `ios/Runner.xcodeproj` — bundle id `vn.vilep.app` (3 target), deployment target mặc định của Flutter 3.47.
- `ios/Runner/Info.plist` — `CFBundleDisplayName = Ví Lép`.
- `NSAppTransportSecurity → NSAllowsArbitraryLoads = true` **chỉ để dev gọi API HTTP trong LAN**; trước khi phát hành phải **xoá key này** (API production dùng HTTPS).
- Chưa có `ExportOptions.plist` và signing team — bạn tự thêm (không nên commit team ID cá nhân).

---

## 2. Không có Mac: CI macOS

Repo có sẵn workflow [`.github/workflows/ios.yml`](../.github/workflows/ios.yml):

1. Push repo lên GitHub → tab **Actions** → **iOS build** → **Run workflow**.
2. Runner `macos-15` sẽ `flutter build ios --release --no-codesign` và upload `Runner.app` (chưa ký).
3. Bản chưa ký chỉ chứng minh **compile OK**, không cài trực tiếp lên iPhone.

Muốn ra **IPA cài được** trên CI, thêm signing secrets:

| Secret | Nội dung |
|---|---|
| `IOS_CERT_P12` | file `.p12` (base64) của Apple Development/Distribution |
| `IOS_CERT_PASSWORD` | mật khẩu p12 |
| `IOS_PROVISIONING_PROFILE` | `.mobileprovision` (base64) |
| `IOS_TEAM_ID` | Team ID (Apple Developer) |

Sau đó thêm bước `flutter build ipa --export-options-plist ...` với `ExportOptions.plist` tương ứng. Codemagic/Bitrise có UI ký tự động nếu bạn không muốn viết tay.

---

## 3. Những gì sẽ phải xử lý trước khi lên App Store

1. **Đăng nhập Apple** (Sign in with Apple) — nếu có đăng nhập bên thứ ba, Apple yêu cầu thêm.
2. **Thanh toán trong app**: nếu bán tip/gói trong app, Apple có thể yêu cầu **In-App Purchase** (30%/15%); mô hình quyên góp cho người khác cần mô tả rõ và đúng chính sách.
3. **UGC**: đã có báo cáo case, chặn người dùng, xoá tài khoản — đủ bộ tối thiểu; cần thêm **lọc nội dung** và **liên hệ hỗ trợ** trong app.
4. **Privacy**: khai báo `PrivacyInfo.xcprivacy` cho các plugin (shared_preferences, url_launcher) và mục đích thu thập dữ liệu (CCCD, ảnh biên lai) trong App Privacy.
5. **Xoá tài khoản** trong app (đã có) — Apple bắt buộc.
6. **HTTPS** toàn bộ; bỏ `NSAllowsArbitraryLoads`.
7. **18+**: dùng age rating phù hợp và chặn thanh toán với tài khoản chưa xác nhận tuổi (đã có logic).

---

## 4. Kiểm tra nhanh trên Windows

```powershell
flutter build ios    # -> không có subcommand ios trên Windows (chỉ apk/appbundle/web/windows)
```

Đây là giới hạn của Flutter tool: các target iOS/macOS chỉ đăng ký trên macOS. Vì vậy pipeline iOS phải chạy trên máy Mac hoặc CI macOS.
