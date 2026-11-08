import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state.dart';
import '../../widgets.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: V.surface,
      appBar: AppBar(
        title: const Text('Thông báo'),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await ref.read(apiProvider).post('/api/v1/me/notifications/read-all');
                ref.invalidate(notificationsProvider);
              } on ApiException catch (e) {
                if (!context.mounted) return;
                showSnack(context, e.message, error: true);
              }
            },
            child: const Text('Đọc tất cả', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PageFrame(
        child: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => EmptyState(emoji: '📡', title: 'Không tải được', body: e is ApiException ? e.message : '$e'),
        data: (state) {
          if (state.items.isEmpty) {
            return const EmptyState(
              emoji: '🔔',
              title: 'Chưa có thông báo',
              body: 'Khi có người góp, case đủ tiền hoặc chủ nợ xác nhận, bạn sẽ thấy ở đây.',
            );
          }
          return RefreshIndicator(
            color: V.green,
            onRefresh: () async => ref.invalidate(notificationsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              itemCount: state.items.length,
              separatorBuilder: (_, __) => const Divider(height: 24),
              itemBuilder: (context, index) {
                final item = state.items[index];
                return InkWell(
                  onTap: () async {
                    if (item.unread) {
                      try {
                        await ref.read(apiProvider).post('/api/v1/me/notifications/${item.id}/read');
                        ref.invalidate(notificationsProvider);
                      } catch (_) {}
                    }
                  },
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: item.unread ? V.greenSoft : V.canvas, shape: BoxShape.circle),
                        child: Icon(_iconFor(item.type), size: 18, color: item.unread ? V.greenDark : V.muted),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(item.title,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: item.unread ? FontWeight.w800 : FontWeight.w600,
                                      )),
                                ),
                                if (item.unread)
                                  Container(width: 7, height: 7, decoration: const BoxDecoration(color: V.green, shape: BoxShape.circle)),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(item.body, style: const TextStyle(fontSize: 12.5, height: 1.45, color: V.muted)),
                            const SizedBox(height: 4),
                            Text(timeAgo(item.createdAt), style: const TextStyle(fontSize: 10.5, color: V.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
      ),
    );
  }

  IconData _iconFor(String type) => switch (type) {
        'contribution_new' => Icons.favorite_rounded,
        'case_funded' => Icons.celebration_rounded,
        'payout_paid' => Icons.account_balance_wallet_rounded,
        'case_closed' => Icons.workspace_premium_rounded,
        'creditor_confirmed' => Icons.verified_rounded,
        'refund_done' => Icons.replay_rounded,
        'case_expired' => Icons.timer_off_rounded,
        'case_suspended' => Icons.pause_circle_outline_rounded,
        'report_received' => Icons.flag_rounded,
        _ => Icons.notifications_rounded,
      };
}

class NotificationsSettingsPage extends StatelessWidget {
  const NotificationsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt thông báo')),
      body: ListView(
        children: [
          SwitchListTile.adaptive(value: true, onChanged: (_) {}, title: const Text('Có người góp tiền')),
          SwitchListTile.adaptive(value: true, onChanged: (_) {}, title: const Text('Case đủ tiền')),
          SwitchListTile.adaptive(value: true, onChanged: (_) {}, title: const Text('Chủ nợ xác nhận')),
          SwitchListTile.adaptive(value: true, onChanged: (_) {}, title: const Text('Nhắc nộp bằng chứng')),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Bản MVP lưu lựa chọn cục bộ; API cài đặt từng loại sẽ có ở P2.',
                style: TextStyle(fontSize: 12, color: V.muted)),
          ),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }
}
