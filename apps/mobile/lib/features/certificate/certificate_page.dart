import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state.dart';
import '../../widgets.dart';

class CertificatePage extends ConsumerWidget {
  final String caseId;

  const CertificatePage({super.key, required this.caseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(caseDetailProvider(caseId));

    return Scaffold(
      backgroundColor: V.surface,
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.close_rounded)),
        actions: [
          IconButton(
            onPressed: () async {
              final code = async.value?.certificateCode;
              if (code != null) {
                await Clipboard.setData(ClipboardData(text: code));
                if (!context.mounted) return;
                showSnack(context, 'Đã copy mã chứng nhận');
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => EmptyState(emoji: '📡', title: 'Không tải được', body: e is ApiException ? e.message : '$e'),
        data: (detail) {
          final s = detail.summary;
          return ConfettiBurst(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                const Center(
                  child: Text('VÍ LÉP',
                      style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 12, color: V.greenDark)),
                ),
                const SizedBox(height: 18),
                const Center(child: WalletMascot(progress: 1, size: 170)),
                const SizedBox(height: 14),
                const Text('Ví đã phồng trở lại!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -1)),
                const SizedBox(height: 8),
                Text('${s.debtor?.nickname ?? 'Bạn'} đã được cả nhà cứu khỏi khoản "${s.title}".',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13.5, height: 1.55, color: V.muted)),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: V.green, width: 1.4),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF6FFFA), Color(0xFFE9FBF2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(money(s.raisedAmount),
                          style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1.4)),
                      const Text('đã được cứu', style: TextStyle(fontSize: 12.5, color: V.muted)),
                      const SizedBox(height: 16),
                      const Divider(color: Color(0xFFCDEBDC)),
                      const SizedBox(height: 12),
                      _row('Người đăng', s.debtor?.nickname ?? 'Ẩn danh'),
                      _row('Ngày hoàn tất', dayMonth(detail.paidAt ?? DateTime.now())),
                      _row('Số chứng nhận', detail.certificateCode ?? 'VL-${s.code.toUpperCase()}'),
                      _row('Người cứu', '${detail.contributors.length} người'),
                      _row('Chế độ', s.isModeA ? 'A · trả thẳng chủ nợ' : 'B · bằng chứng trả nợ'),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '"Ví lép, bạn bè lo!" — cảm ơn bạn đã là người cứu nợ tử tế. '
                  'Đừng để ví lép lại nhé, hẹn gặp ở lần cứu tiếp theo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: V.muted, height: 1.55),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: '$kApiBase/share/${s.code}'));
                    if (!context.mounted) return;
                    showSnack(context, 'Đã copy link chứng nhận');
                  },
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('Chia sẻ chứng nhận'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => context.go('/discover'),
                  child: const Text('Về trang chủ'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: V.muted)),
          const Spacer(),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
