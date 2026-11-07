# Sổ cái & đối soát

## 1. Tài khoản

| Tài khoản | Ý nghĩa |
|---|---|
| `gateway_clearing` | Tiền đã vào cổng thanh toán nhưng chưa phân bổ |
| `case_escrow` | Tiền đang giữ hộ cho case chế độ A |
| `case_hold` | (chế độ B) tiền đang trong thời gian giữ |
| `case_available` | (chế độ B) tiền đã sẵn sàng rút |
| `creditor_payout_clearing` | Tiền đã chuyển khỏi escrow sang chủ nợ |
| `refund_clearing` | Tiền hoàn về người góp |
| `platform_tip` | Tip tự nguyện của người góp |
| `processing_fee` | Phí xử lý thanh toán (nếu có) |

## 2. Bút toán

Mỗi dòng `ledger_entries` là `debit → credit`, `amount > 0`, `idempotency_key` UNIQUE, bảng chỉ INSERT.

| Dòng tiền | Bút toán |
|---|---|
| Đóng góp thành công (A) | `gateway_clearing → case_escrow` |
| Tip | `gateway_clearing → platform_tip` |
| Phí xử lý | `gateway_clearing → processing_fee` |
| Payout chủ nợ | `case_escrow → creditor_payout_clearing` |
| Hoàn tiền (A) | `case_escrow → refund_clearing` |
| Hoàn phần vượt mục tiêu | `gateway_clearing → refund_clearing` |
| Đóng góp (B) | `gateway_clearing → case_hold` |
| Hết thời gian giữ (B) | `case_hold → case_available` |
| Rút tiền (B) | `case_available → withdrawal_clearing` |
| Nâng cấp B→A | `case_hold → case_escrow` |

Số dư một tài khoản = tổng credit − tổng debit (đã lọc theo case khi cần).

## 3. Invariant

Với mỗi case không ở `draft/cancelled`:

```
escrow + hold + available = Σ contribution(đã nhận, gồm cả đã hoàn) − Σ payout(paid) − Σ refund(done)
```

Kiểm tra ở:
- `GET /api/v1/admin/invariants` (trả về danh sách lệch),
- job `CheckInvariantsAsync` mỗi giờ (log error nếu lệch),
- test `Funding_case_creates_single_payout_and_zero_escrow`, `Expired_case_refunds_every_contribution`.

Ngoài ra với chế độ A: `raised_amount ≤ target_amount ≤ debt_amount`.

## 4. Chống trùng lặp

| Tình huống | Cơ chế |
|---|---|
| Cùng `Idempotency-Key` gửi 2 lần | UNIQUE `contributions.idempotency_key`, trả lại contribution cũ |
| Webhook gửi 3 lần | `payment_transactions.status = succeeded` → trả `duplicate: true`, không credit |
| Hai người góp cùng lúc vượt mục tiêu | transaction + `cases.version` (concurrency token) + cắt phần vượt và tạo refund |
| Payout chạy 2 lần | UNIQUE theo case cho payout chưa failed/cancelled + `payout:{id}:transfer` idempotent |
| Refund chạy lặp | `refunds` theo contribution + key `refund:{id}:transfer` |

## 5. Kiểm tra nhanh bằng tay

```bash
# Case có đủ tiền đã payout chưa?
curl -s localhost:5080/api/v1/admin/cases/{id}/ledger -H "Authorization: Bearer $ADMIN" | jq

# Toàn hệ thống có lệch không?
curl -s localhost:5080/api/v1/admin/invariants -H "Authorization: Bearer $ADMIN" | jq
```

## 6. Khi có sự cố

1. Khoanh vùng case qua `audit_logs` (`/admin/cases/{id}/audit`).
2. Xem `ledger_entries` của case, đối chiếu `contributions`, `payouts`, `refunds`.
3. Không sửa/xoá ledger. Nếu sai, ghi bút toán đảo bằng một script có idempotency key riêng, kèm audit.
4. Chạy `/admin/jobs/run` để retry payout/refund và kiểm tra invariant lại.
