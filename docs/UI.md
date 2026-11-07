# Thiết kế giao diện Ví Lép — phân tích & tối ưu

Mục tiêu: giao diện **chuyên nghiệp, đáng tin** cho một sản phẩm động tới tiền, nhưng vẫn giữ chất
Kickstarter: chữ lớn, tiến độ xanh, nút pill, nội dung kể chuyện.

Ảnh sau khi tối ưu nằm trong [`shots/`](../shots). So sánh nhanh: bản cũ dùng tab gạch chân dày,
chip bị cắt chữ, card trắng phẳng, hero bị app bar che mất bo góc, chưa có skeleton.

---

## 1. Vấn đề của bản đầu tiên

| Vấn đề | Hệ quả | Cách xử lý |
|---|---|---|
| Tab gạch chân đen dày, chip danh mục bị cắt chữ | Nhìn "thô", thiếu tinh tế | Chuyển sang **segmented control** nền canvas, pill trắng nổi + bóng nhẹ; chip dùng `maxLines: 1, softWrap: false` |
| Card trắng viền xám, chữ và số cùng cỡ | Không có phân cấp thị giác, khó quét nhanh | Hệ **type scale** rõ: tiêu đề 17/800, số tiền 14.5/800, phần trăm trong pill xanh, meta 11.5/xám |
| Ảnh bìa chỉ là khối màu + emoji | Thiếu chiều sâu, emoji như "dán" lên nền | Gradient 2 lớp + vòng sáng radial + emoji neo góc dưới phải, chip danh mục nền trắng mờ |
| Hero case detail cao 300, bo góc bị app bar cắt | Mất hiệu ứng "tấm thiệp" (signature của Kickstarter) | Hạ còn 284, thêm **"đuôi" gradient 26px** nằm trong sliver nội dung rồi mới tới khung trắng bo 28 → bo góc luôn hiển thị |
| Nút/ô nhập bo 12–14 rời rạc | Thiếu nhất quán | Chuẩn hoá radius 12/16/20/24/pill, input 16, card 20, sheet 28 |
| Không có trạng thái tải | Màn hình trắng khi mạng chậm | **Skeleton shimmer** cho feed và "Case của tôi" |
| Bottom nav icon trần | Khó biết đang ở đâu | Pill nền xanh nhạt sau icon active, nhãn đậm, badge thông báo có viền trắng |
| Wizard tạo case dạng list dài | Mệt khi chọn mẫu | **Grid 2 cột** thẻ gradient + thanh tiến độ 1/3 ở app bar |
| Sheet thanh toán thiếu "đủ phần còn thiếu" | Người dùng phải tự tính | Thêm preset **"Đủ phần còn thiếu"** và tổng tiền cập nhật trực tiếp |

---

## 2. Hệ thống thiết kế (design tokens)

Định nghĩa trong `lib/core/theme.dart`:

**Màu**

| Token | Giá trị | Dùng cho |
|---|---|---|
| `V.green` | `#05CE78` | tiến độ, CTA, nhấn mạnh |
| `V.greenDark` | `#059A5C` | chữ trên nền xanh nhạt (đạt WCAG AA) |
| `V.greenSoft` | `#E9FBF2` | chip/trạng thái "đã xác nhận" |
| `V.ink` | `#0B0B0C` | tiêu đề, nền banner |
| `V.ink2` | `#3F3F46` | nội dung |
| `V.muted` / `V.faint` | `#71717A` / `#A1A1AA` | meta, placeholder |
| `V.canvas` | `#F7F7F4` | nền phụ, input, segmented |
| `V.line` | `#ECECE8` | hairline 1px thay cho đổ bóng nặng |

Chỉ **một** màu nhấn. Không dùng đỏ cho tiền, chỉ dùng cho huỷ/lỗi.

**Chữ** — Be Vietnam Pro (bundle offline, hỗ trợ tiếng Việt đầy đủ), tracking âm cho tiêu đề lớn:
46→11px, weight 800 cho display/headline, 600–700 cho nội dung, line-height 1.5–1.7 cho đoạn kể.

**Nhịp & bo góc** — thang 4pt (4/8/12/16/20/24/32/40), radius 12/16/20/24/pill.
Card dùng `border 1px` + bóng 2 lớp rất nhẹ (`0 1px 2px` + `0 8px 16px` alpha 4%) thay vì đổ bóng đậm.

**Chuyển động** — 110ms cho nhấn (scale 0.985), 160ms cho tab/chip, 280ms cho chuyển màn,
750ms cho thanh tiến độ (easeOutCubic), Hero cho ảnh bìa card → chi tiết. Không animation vô nghĩa.

---

## 3. Từng màn hình

### Feed
- Wordmark "ví lép." chữ thường đậm + chấm xanh — nhận diện, không cần logo ảnh.
- Headline editorial "Hôm nay, cứu ai đó." tạo cảm xúc thay vì chỉ liệt kê.
- Segmented 4 tab (Cần cứu / Sắp xong / Mới nhất / Bạn bè) + chip danh mục cuộn ngang.
- Banner tối "Ví bạn đang lép?" với CTA tròn xanh — điểm nhấn tương phản duy nhất trên nền sáng.
- Carousel "Sắp chạm đích" (card 246px) cho cảm giác gần đích; danh sách chính dùng card dọc đầy đủ metadata.

### Chi tiết case
- Hero 284px: gradient + emoji + scrim tối để chip trắng luôn đọc được.
- Khung trắng bo 28 trượt lên trên "đuôi" gradient → cảm giác tấm thiệp.
- Khối tiền: số lớn 31px + pill %, thanh tiến độ 10px, dòng "còn 30.000đ là chạm đích",
  3 metric (người cứu / an toàn escrow / mục tiêu) chia bằng hairline dọc.
- "Tiền sẽ về đâu" dùng nền xanh rất nhạt + icon khiên; dải tin cậy chủ nợ (tên đã che + 4 số TK).
- Tường người cứu: chồng avatar + câu "A và 3 người khác đã góp", từng dòng có số tiền canh phải.
- Bottom bar nổi: số còn thiếu + CTA pill, bóng đổ nhẹ để tách khỏi nội dung.

### Sheet đóng góp
- Preset nhanh 20k/35k/50k/100k/200k (lọc theo phần còn thiếu), "Khác", và **"Đủ phần còn thiếu"**.
- Tip tách rõ "tự nguyện · không bắt buộc", mặc định 0.
- Bảng tổng kết Tiền xoá nợ / Tip / Phí / Tổng, CTA hiển thị luôn số tiền.
- Bước QR sandbox + nhãn "cổng giả lập"; trạng thái thành công có confetti + mascot phồng.

### Tạo case
- 3 bước có thanh tiến độ 1/3 trên app bar.
- Bước 1: grid 2 cột thẻ gradient theo danh mục, bấm là điền sẵn tiêu đề/số tiền/lời kể.
- Bước 2: form + chip số tiền + chọn chế độ hiển thị (biệt danh/tên thật/ẩn danh).
- Bước 3: mời chủ nợ, tóm tắt case, cảnh báo 72h; xong hiện link mời + copy.

### Case của tôi / Hồ sơ
- Cùng một segmented control, tile có ảnh thu nhỏ gradient, phần trăm, trạng thái màu theo state.
- Hồ sơ: thẻ nhận diện, 3 stat có icon, nhóm menu theo "Tài khoản & xác minh / Cài đặt / Khác",
  badge eKYC chỉ hiện khi cần hành động (tránh lặp chữ).

### Giấy chứng nhận
- Nền trắng, khung gradient xanh nhạt viền 1.4px, số tiền 38px, bảng thông tin canh hai bên,
  confetti một lần, mascot cười ở mức 100%.

---

## 4. Khả năng truy cập & hiệu năng

- Tương phản: chữ xám trên trắng đạt ≥ 4.5:1 (`#71717A`), chữ xanh đậm trên nền xanh nhạt ≥ 4.5:1.
- Vùng chạm tối thiểu 44×44 (icon button 38 + padding, nav item cao 64).
- Không phụ thuộc màu: trạng thái luôn kèm icon/nhãn chữ.
- Hỗ trợ `textScaler` của hệ thống: layout dùng `Flexible/Expanded`, tránh chiều cao cố định ở chỗ có chữ.
- Không ảnh raster: emoji + gradient + CustomPainter → bundle web ~3.4MB JS, không tải ảnh mạng.
- Hero/skeleton/AnimatedContainer chỉ dùng transform & opacity, không layout lại liên tục.

---

## 5. Việc nên làm tiếp (P1.5)

1. **Dark mode**: token đã tách khỏi widget, chỉ cần bảng màu tối + `ThemeMode.system`.
2. **Ảnh bìa thật**: thay emoji bằng ảnh người dùng tải (MinIO + URL ký), giữ gradient làm placeholder.
3. **Motion nâng cao**: shared-axis khi mở case, bottom sheet kéo thả snap 2 mức.
4. **Empty/error states theo ngữ cảnh**: phân biệt lỗi mạng, lỗi quyền, hết hạn.
5. **i18n**: hiện chuỗi tiếng Việt nằm trong widget; tách ARB trước khi mở rộng.
6. **Đo lường**: PostHog cho tỷ lệ bấm CTA, độ sâu cuộn, tỷ lệ hoàn tất wizard.
