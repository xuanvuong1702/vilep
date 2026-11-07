# Ví Lép — app Flutter

App Flutter cho iOS / Android / web. **Cùng một codebase Dart** (`lib/`), chỉ khác target build.
Xem hướng dẫn đầy đủ ở [README gốc](../../README.md).

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:5080   # web
flutter run -d <device-id> --dart-define=API_BASE=http://10.0.2.2:5080  # Android emulator
```

## Build APK

Cần Android SDK + JDK 17/21 (Android Studio cài sẵn cả hai):

```bash
flutter build apk --release --dart-define=API_BASE=http://192.168.1.30:5080
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Hoặc dùng script gốc repo: `pwsh ../../scripts/build-apk.ps1 -ApiBase http://<ip>:5080`.

APK release hiện ký bằng debug key (đủ để cài thử). Khi phát hành thật, tạo keystore và cấu hình `signingConfigs.release` trong `android/app/build.gradle.kts`.

> Máy dev hiện tại có Android SDK 36 + JDK 21 nhưng DSH sandbox chặn tiến trình con của Gradle (aapt2/kotlin worker) nên build APK không hoàn tất trong phiên này — chạy lệnh trên ở terminal thường hoặc Android Studio là được.

## Cấu trúc

```
lib/
  main.dart                  bootstrap + SharedPreferences + ProviderScope
  app.dart                   router (go_router) + MaterialApp + theme
  state.dart                 Riverpod providers/controllers (auth, feed, case, notifications), server override
  widgets.dart               mascot Ví Lép (CustomPainter), progress ví, case card, chips, confetti
  core/                      api client (dio), models, format tiền/ngày, theme token
  features/
    onboarding/             3 màn giới thiệu + mascot phồng dần
    auth/                   đăng nhập OTP (dev code hiện sẵn) + đổi địa chỉ API
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

## Cờ build

| Cờ | Tác dụng |
|---|---|
| `API_BASE` | URL API mặc định (đổi được trong app ở màn đăng nhập) |
| `DEMO_PHONE` | Tự đăng nhập bằng OTP dev với SĐT này |
| `SKIP_ONBOARDING` | Bỏ qua 3 màn onboarding |

Build store: **không** truyền `DEMO_PHONE`, và đặt `Vilep__ExposeOtpInResponse=false` ở API.

## Test

```bash
flutter test
flutter analyze
```
