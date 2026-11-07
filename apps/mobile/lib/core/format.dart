import 'package:intl/intl.dart';

final NumberFormat _money = NumberFormat.decimalPattern('vi');
final DateFormat _shortDate = DateFormat('dd/MM/yyyy');

String money(num value) => '${_money.format(value)}đ';

String moneyShort(num value) {
  if (value >= 1000000) {
    final millions = value / 1000000;
    return '${_trim(millions.toStringAsFixed(millions >= 10 ? 0 : 1))}tr';
  }
  if (value >= 1000) {
    final thousands = value / 1000;
    return '${_trim(thousands.toStringAsFixed(thousands >= 100 ? 0 : 1))}k';
  }
  return '${value.toInt()}đ';
}

String _trim(String number) => number.endsWith('.0') ? number.substring(0, number.length - 2) : number;

String shortDate(DateTime? date) => date == null ? '' : _shortDate.format(date.toLocal());

String dayMonth(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  return '${local.day}/${local.month}/${local.year}';
}

String relativeDeadline(int daysLeft) {
  if (daysLeft <= 0) return 'Đã hết hạn';
  if (daysLeft == 1) return 'Còn 1 ngày';
  return 'Còn $daysLeft ngày';
}

String timeAgo(DateTime? date) {
  if (date == null) return '';
  final diff = DateTime.now().difference(date.toLocal());
  if (diff.inMinutes < 1) return 'vừa xong';
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
  if (diff.inHours < 24) return '${diff.inHours} giờ trước';
  if (diff.inDays < 30) return '${diff.inDays} ngày trước';
  return dayMonth(date);
}

String stateLabel(String state) => switch (state) {
      'draft' => 'Bản nháp',
      'pending_creditor' => 'Chờ chủ nợ xác nhận',
      'funding' => 'Đang gây quỹ',
      'funded' => 'Đã đủ tiền',
      'payout_pending' => 'Chờ chuyển tiền',
      'payout_failed' => 'Chuyển tiền lỗi',
      'paid' => 'Đã chuyển cho chủ nợ',
      'closed' => 'Hoàn tất',
      'expired' => 'Hết hạn',
      'refunding' => 'Đang hoàn tiền',
      'refunded' => 'Đã hoàn tiền',
      'cancelled' => 'Đã huỷ',
      'suspended' => 'Tạm khoá',
      'disputed' => 'Tranh chấp',
      'ended' => 'Đã kết thúc',
      _ => state,
    };

String categoryLabel(String key) => switch (key) {
      'tra-sua' => 'Trà sữa',
      'nhau' => 'Nợ nhậu',
      'ca-cuoc' => 'Thua cược',
      'an-uong' => 'Mượn tiền ăn',
      'qua-sinh-nhat' => 'Quà sinh nhật',
      'muon-tien' => 'Mượn tiền',
      _ => 'Khác',
    };

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts.first.substring(0, 1).toUpperCase();
  if (parts.length == 1) return first;
  return first + parts.last.substring(0, 1).toUpperCase();
}
