# Kiến trúc & quyết định thiết kế

## 1. Vì sao chọn cấu trúc này

Spec yêu cầu modular monolith (.NET 8) + Flutter + PostgreSQL + Redis + MinIO. Bản MVP giữ đúng **ranh giới nghiệp vụ** nhưng cắt hạ tầng chưa cần:

| Thành phần spec | MVP | Lý do |
|---|---|---|
| PostgreSQL | SQLite (dev) / PostgreSQL (docker, env) | Chạy được ngay trên máy dev không cần Docker; cùng một model EF Core |
| Redis (cache, rate limit, khoá) | Rate limiter trong process + transaction DB | 1 instance, chưa cần phân tán |
| MinIO | Chưa có upload ảnh ở P1 | Thẻ chia sẻ sinh SVG, không cần lưu trữ |
| Hangfire | `BackgroundService` + `/admin/jobs/run` | Chỉ 5 job, không cần dashboard |
| SignalR | Polling + refresh | Feed p95 đủ nhanh với 10k case |
| Web admin (Refine) | REST `/api/v1/admin/*` | Có thể gắn Refine/Appsmith sau mà không đổi backend |

Điểm **không** cắt: sổ cái bút toán kép, idempotency, máy trạng thái, audit log, payout maker-checker, invariant — vì đây là phần rủi ro cao nhất của sản phẩm.

## 2. Phân lớp

```
Features/*Endpoints.cs   → HTTP, xác thực, map DTO
Services/*.cs            → nghiệp vụ tiền & trạng thái
Domain/Model.cs          → entity + CaseStateMachine
Data/VilepDbContext.cs   → mapping snake_case, converter SQLite
```

Quy tắc: endpoint **không** sửa `case.State`, **không** tự ghi ledger. Chỉ `CaseWorkflow.Transition` và `LedgerService.Post`.

## 3. Máy trạng thái

Một bảng chuyển tiếp duy nhất trong `CaseStateMachine` (spec 3.5). `CaseWorkflow.Transition`:

1. kiểm tra `CanTransition(mode, from, to)`,
2. tăng `version` (concurrency token),
3. ghi `audit_logs` với `before/after` + lý do + actor.

Nhờ vậy mọi lịch sử trạng thái truy vết được qua `/admin/cases/{id}/audit`, và mọi case đều đi qua cùng một cửa.

## 4. Luồng chế độ A

```
draft ──invite──▶ pending_creditor ──creditor confirm──▶ funding
funding ──đủ tiền──▶ funded ──▶ payout_pending ──▶ paid ──creditor nhận──▶ closed
funding ──hết hạn──▶ expired ──▶ refunding ──▶ refunded
pending_creditor ──72h không phản hồi──▶ cancelled
```

- Payout tạo **một lần** cho mỗi case; dưới ngưỡng `AutoApprovePayoutLimit` thì tự duyệt (maker = system), trên ngưỡng cần admin duyệt (checker).
- Chủ nợ xác nhận "đã nhận" là điều kiện đóng case và sinh giấy chứng nhận.

## 5. Đồng thời & tính đúng

- Ghi đóng góp nằm trong transaction DB; case có `Version` làm concurrency token nên hai request đồng thời chỉ một thắng, request còn lại nhận 409 và UI cho thử lại.
- Webhook lặp được chặn bởi `payment_transactions.status` + `idempotency_key` UNIQUE của ledger.
- Phần vượt mục tiêu (nếu có do race) được **cắt** và tạo refund phần dư, không bao giờ để `raised > target` ở chế độ A.
- Payout unique theo case (state khác failed/cancelled) + khoá idempotency khi chuyển tiền.

## 6. Bảo mật

- JWT access ngắn hạn + refresh xoay vòng (lưu hash), thu hồi khi logout/khoá.
- Số tài khoản ngân hàng mã hoá AES-256-GCM (`Encryption:Key`), chỉ trả về 4 số cuối.
- CCCD chỉ lưu SHA-256 để so khớp + danh sách đen.
- Webhook xác thực HMAC-SHA256 trên **raw body** (không parse lại JSON trước khi verify).
- Đóng góp/OTP/rút tiền có rate limit theo IP/user.
- Ảnh chụp, link chủ nợ dùng token ngẫu nhiên; URL công khai chỉ trả dữ liệu đã che.

## 7. Giới hạn đã biết (MVP)

- Chưa có EF migrations (dùng `EnsureCreated`); đổi schema phải xoá DB dev.
- Chưa có worker outbox: lời gọi gateway payout/refund chạy trong request hoặc job; production nên tách outbox + retry có kiểm soát.
- Chế độ B mới có nền (schema hold/available, endpoint nâng cấp B→A), chưa có UI ví/rút/bằng chứng.
- Yếu tố viral (meme caption AI, Kèo Trả Ơn, bảng xếp hạng) chưa làm — đúng P2.
- Trang OG dùng SVG; Zalo/Facebook thực tế cần PNG — thêm bước render PNG (ImageSharp/Playwright) trước khi launch.

## 8. Bản đồ màn hình → file

| Màn hình spec | File |
|---|---|
| Onboarding 3 màn + mascot | `features/onboarding/onboarding_page.dart` |
| Đăng nhập OTP | `features/auth/login_page.dart` |
| Feed 4 tab + lọc + tìm kiếm | `features/feed/feed_page.dart`, `search_page.dart` |
| Chi tiết case + tường người cứu + thanh toán | `features/case/case_detail_page.dart` |
| Tạo case wizard + mời chủ nợ | `features/create/create_case_page.dart` |
| Case của tôi / lịch sử cứu nợ | `features/cases/my_cases_page.dart` |
| Chủ nợ xác nhận | `features/creditor/creditor_page.dart` |
| Giấy chứng nhận + confetti | `features/certificate/certificate_page.dart` |
| Hồ sơ, eKYC, tài khoản nhận tiền | `features/profile/*` |
| Thông báo | `features/notifications/notifications_page.dart` |
