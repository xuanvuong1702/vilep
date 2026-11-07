# Ví Lép — MVP

> Ví lép, bạn bè lo!

Bản MVP chạy được của **Ví Lép** theo `vi_lep_requirements_v0.4.md`: app Flutter (iOS/Android/Web) + API ASP.NET Core + PostgreSQL (hoặc SQLite cho dev), với trọng tâm là **phần tiền** ở chế độ A (giữ hộ → trả thẳng chủ nợ), cùng nền tảng cho chế độ B.

| | |
|---|---|
| App | Flutter 3.47 / Dart 3.13, Riverpod, go_router, dio |
| API | ASP.NET Core (.NET 10), EF Core, JWT, minimal API, OpenAPI |
| Dữ liệu | SQLite (dev mặc định), PostgreSQL (production/docker) |
| Thanh toán | Mock gateway ký HMAC + webhook thật; adapter PayOS (cần key) |
| Tests | 22 test backend (luồng tiền + máy trạng thái) + test widget Flutter |

---

## 1. Chạy trong 5 phút

```bash
# 1) API (http://127.0.0.1:5080)
cd apps/api
dotnet run --project Vilep.Api

# 2) App (web, mở http://127.0.0.1:8080)
cd apps/mobile
flutter pub get
flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:5080
```

Lần chạy đầu, API tự tạo DB SQLite (`Vilep.Api/bin/.../App_Data/vilep.db`) và **seed dữ liệu demo**: 6 người dùng, 9 case đủ trạng thái (đang gọi vốn, sắp xong, đã trả nợ, đã hoàn tiền, chờ chủ nợ xác nhận).

### Tài khoản demo (OTP hiện ngay trong app/response ở chế độ dev)

| SĐT | Vai trò |
|---|---|
| `0900000001` | Minh Anh — con nợ (case của mình) |
| `0900000002` | Lan Nhi — người cứu nợ |
| `0900000003` | Admin Ví Lép |

Chủ nợ demo chưa xác nhận: mở `/api/v1/creditor/invite/demo-caphe` hoặc trong app mở `/#/creditor/demo-caphe`.

### Bật PostgreSQL

```bash
docker compose up -d postgres
export Database__Provider=postgres
export Database__ConnectionString="Host=localhost;Port=5432;Database=vilep;Username=vilep;Password=vilep"
dotnet run --project apps/api/Vilep.Api
```

> Schema hiện được tạo bằng `EnsureCreated` + trigger chặn sửa/xoá `ledger_entries`. Trước khi lên production nên chuyển sang EF migrations có versioning.

---

## 2. Phạm vi đã làm (P1 – Nợ vui, chế độ A)

| Nhóm | Đã có |
|---|---|
| Tài khoản | OTP + JWT (access/refresh xoay vòng), hồ sơ, eKYC bậc 1–2 (mock auto-verify), tài khoản ngân hàng mã hoá AES-GCM, xoá tài khoản, chặn 18+ |
| Case | Wizard 3 bước + mẫu nợ vui, nháp → mời chủ nợ → chủ nợ xác nhận → funding, huỷ case (hoàn tiền nếu đã có góp), nâng cấp B→A, audit log mọi chuyển trạng thái |
| Chủ nợ | Link token public (không cần cài app), xác nhận khoản nợ + khai tài khoản nhận, xác nhận đã nhận tiền |
| Đóng góp | Idempotency-Key, chống tự góp, chặn vượt phần còn thiếu, tip tách riêng, webhook HMAC-SHA256, ghi nhận lặp không nhân đôi tiền, "Người chốt hạ" |
| Tiền | Sổ cái bút toán kép bất biến (trigger), escrow theo case, payout một lần, maker-checker theo ngưỡng, hoàn tiền khi hết hạn/huỷ, invariant kiểm tra hằng ngày |
| Feed | 4 tab (cần cứu / sắp xong / mới nhất / của bạn bè), lọc danh mục, tìm kiếm, phân trang cursor |
| Chia sẻ | Trang OG `/share/{code}`, thẻ meme SVG `/api/v1/cases/{id}/share-card.svg`, deep link `vilep://case/{code}` |
| Khác | Thông báo trong app, báo cáo vi phạm, admin API (queue, khoá case, duyệt payout, cấu hình, invariant, audit), job nền mỗi giờ |

**Chưa làm (đúng lộ trình P2/P3):** chế độ B đầy đủ (ví case, rút theo bậc, bằng chứng trả nợ, bảo đảm hoàn tiền), Kèo Trả Ơn, bảng xếp hạng, nhóm, AI caption, web admin UI, eKYC/payment thật.

---

## 3. Kiến trúc

```
apps/
  api/
    Vilep.Api/            ASP.NET Core minimal API
      Domain/             entities + máy trạng thái case (một cửa duy nhất)
      Data/               EF Core DbContext, snake_case, SQLite/PG
      Services/           Ledger, CaseWorkflow, Contribution, Payout, Refund, Config
      Features/           endpoints: Auth, Cases, Creditor, Payments, Admin, Share
      Jobs/               đối soát + hết hạn + retry payout
    Vilep.Tests/          xUnit v3 + WebApplicationFactory (SQLite tạm)
  mobile/                 Flutter app (Riverpod + go_router + dio)
scripts/
  smoke.ps1               E2E qua HTTP: 40 assert cho luồng tiền
  screenshots.mjs         chụp ảnh app qua CDP
docs/
  ARCHITECTURE.md         quyết định thiết kế + vì sao
  LEDGER.md               bút toán, invariant, cách kiểm tra
```

### Nguyên tắc phần tiền

- **Chỉ một hàm đổi trạng thái case**: `CaseWorkflow.Transition` + `CaseStateMachine`. Không UPDATE cột `state` ở nơi khác.
- **Ledger append-only**: mỗi bút toán có `idempotency_key` UNIQUE; trigger DB chặn UPDATE/DELETE.
- **Webhook là nguồn sự thật duy nhất** để ghi nhận tiền vào; retry 3 lần chỉ ghi 1 lần.
- **Không vượt mục tiêu**: kiểm tra phần còn thiếu trong transaction + cắt phần vượt và hoàn lại.
- **Payout một lần**: unique theo case + state, maker-checker trên ngưỡng.
- **Invariant**: `escrow + hold + available = tổng góp đã nhận − payout − hoàn`, chạy hằng ngày qua job và endpoint admin.

---

## 4. Kiểm thử

```bash
# backend: 22 test (ledger, webhook lặp, chặn vượt mục tiêu, payout 1 lần, hoàn tiền, invariant, state machine)
cd apps/api/Vilep.Tests && dotnet run

# E2E qua HTTP (cần API đang chạy)
pwsh ./scripts/smoke.ps1          # hoặc: powershell -ExecutionPolicy Bypass -File ./scripts/smoke.ps1

# flutter
cd apps/mobile && flutter test && flutter analyze
```

---

## 5. Cấu hình

`apps/api/Vilep.Api/appsettings.json` (hoặc biến môi trường `Section__Key`):

| Khoá | Ý nghĩa |
|---|---|
| `Database:Provider` | `sqlite` (dev) hoặc `postgres` |
| `Jwt:Key` | khoá ký JWT — **đổi khi deploy** |
| `Payments:Provider` | `mock` hoặc `payos` |
| `Payments:WebhookSecret` | khoá ký webhook mock |
| `Payments:ChecksumKey` | khoá PayOS (khi dùng payos) |
| `Payments:AutoApprovePayoutLimit` | ngưỡng payout tự động (mặc định 500.000đ) |
| `Vilep:FunModeAMin/Max`, `Vilep:HoldDays` | hạn mức & thời gian giữ |
| `Vilep:ExposeOtpInResponse` | trả OTP trong response (chỉ dev) |
| `Vilep:EnableDevPayments` | bật trang thanh toán giả lập |

### Nối PayOS thật

1. Đặt `Payments:Provider=payos`, `ClientId`, `ApiKey`, `ChecksumKey` (sandbox trước).
2. Webhook URL: `https://<domain>/api/v1/webhooks/payment/payos`, header `x-payos-signature`.
3. PayOS không hỗ trợ chuyển tiền cho bên thứ ba → payout rơi về trạng thái chờ admin nhập chứng từ (`POST /admin/payouts/{id}/mark-paid`), đúng với cây quyết định mục 1.6 của spec.

---

## 6. API chính

Mở `http://127.0.0.1:5080/swagger`. Quy ước: `{ ok, data, error:{code,message} }`, tiền là số nguyên VND, thao tác tiền yêu cầu header `Idempotency-Key`.

```
POST /api/v1/auth/otp/request|verify|refresh
GET  /api/v1/cases?tab=&category=&q=          GET /api/v1/cases/{id}
POST /api/v1/my/cases  ... /publish /cancel /invite-creditor /upgrade-to-creditor
GET  /api/v1/creditor/invite/{token}          POST /api/v1/creditor/invite/{token}/confirm
POST /api/v1/cases/{id}/contributions         POST /api/v1/webhooks/payment/{provider}
POST /api/v1/guarantee/... (P2)               GET  /api/v1/me/notifications
GET  /api/v1/admin/stats|invariants|payouts|reports|config|audit
```

---

## 7. Ghi chú triển khai

- `Dockerfile` cho API và `docker-compose.yml` (Postgres + API + Caddy tuỳ chọn) nằm ở gốc repo.
- Reverse proxy cần chuyển `X-Forwarded-*`; bật HTTPS/HSTS trước khi mở công khai.
- Ảnh chụp màn hình: `shots/`.
- Mọi hành vi đùa cợt chỉ áp dụng nhánh **Nợ vui**; nhánh Nợ hoàn cảnh (P3) sẽ dùng UI trung tính riêng.

## 8. Giấy phép

Mã nguồn demo cho mục đích đánh giá sản phẩm. Font **Be Vietnam Pro** (OFL-1.1) đi kèm trong `apps/mobile/assets/fonts`.
