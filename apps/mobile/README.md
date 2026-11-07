# Ví Lép — app Flutter

App di động (iOS/Android) + bản web demo cho Ví Lép. Xem hướng dẫn đầy đủ ở [README gốc](../../README.md).

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:5080
```

## Cấu trúc

```
lib/
  main.dart                  bootstrap + SharedPreferences + ProviderScope
  app.dart                   router (go_router) + MaterialApp + theme
  state.dart                 Riverpod providers/controllers (auth, feed, case, notifications)
  widgets.dart               mascot Ví Lép (CustomPainter), progress ví, case card, chips, confetti
  core/                      api client (dio), models, format tiền/ngày, theme token
  features/
    onboarding/             3 màn giới thiệu + mascot phồng dần
    auth/                   đăng nhập OTP (dev code hiện sẵn)
    feed/                   feed 4 tab + lọc danh mục + tìm kiếm
    case/                   chi tiết case + sheet đóng góp (tip, ẩn danh, QR sandbox)
    create/                 wizard tạo case + mời chủ nợ + link chia sẻ
    cases/                  case của tôi / lịch sử cứu nợ
    creditor/               trang chủ nợ xác nhận khoản nợ (mở bằng link)
    certificate/            giấy chứng nhận "Ví đã phồng trở lại" + confetti
    profile/                hồ sơ, eKYC, tài khoản nhận tiền
    notifications/          hộp thư
    shell/                  bottom navigation
```

## Cờ build cho demo

| Cờ | Tác dụng |
|---|---|
| `API_BASE` | URL API (mặc định `http://127.0.0.1:5080`; Android emulator dùng `http://10.0.2.2:5080`) |
| `DEMO_PHONE` | Tự đăng nhập bằng OTP dev với SĐT này |
| `SKIP_ONBOARDING` | Bỏ qua 3 màn onboarding |

Build store: **không** truyền `DEMO_PHONE`, và đặt `Vilep__ExposeOtpInResponse=false` ở API.

## Test

```bash
flutter test
flutter analyze
```
