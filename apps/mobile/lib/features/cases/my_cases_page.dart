import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../state.dart';
import '../../widgets.dart';

class MyCasesPage extends ConsumerStatefulWidget {
  const MyCasesPage({super.key});

  @override
  ConsumerState<MyCasesPage> createState() => _MyCasesPageState();
}

class _MyCasesPageState extends ConsumerState<MyCasesPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myCasesProvider);
    final contribs = ref.watch(myContributionsProvider);

    return Scaffold(
      backgroundColor: V.surface,
      appBar: AppBar(
        title: const Text('Case của tôi'),
        actions: [
          IconButton(onPressed: () => ref.invalidate(myCasesProvider), icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Row(
            children: [
              _tabButton(0, 'Tôi đăng'),
              _tabButton(1, 'Tôi đã cứu'),
            ],
          ),
        ),
      ),
      body: _tab == 0
          ? async.when(
              loading: () => const LoadingView(),
              error: (e, _) => EmptyState(emoji: '📡', title: 'Không tải được', body: e is ApiException ? e.message : '$e'),
              data: (cases) {
                if (cases.isEmpty) {
                  return EmptyState(
                    emoji: '👛',
                    title: 'Chưa có case nào',
                    body: 'Ví đang lép? Tạo case đầu tiên, cả nhà sẽ cứu bạn.',
                    actionLabel: 'Tạo case',
                    onAction: () => context.push('/create'),
                  );
                }
                return RefreshIndicator(
                  color: V.green,
                  onRefresh: () async => ref.invalidate(myCasesProvider),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      ...cases.map((item) => _MyCaseTile(item: item)),
                    ],
                  ),
                );
              },
            )
          : contribs.when(
              loading: () => const LoadingView(),
              error: (e, _) => EmptyState(emoji: '📡', title: 'Không tải được', body: e is ApiException ? e.message : '$e'),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    emoji: '💚',
                    title: 'Bạn chưa cứu ai',
                    body: 'Góp một ly trà sữa cũng là cứu người. Xem các case đang cần giải cứu nhé.',
                    actionLabel: 'Khám phá',
                    onAction: () => context.go('/discover'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _ContributionTile(item: item);
                  },
                );
              },
            ),
    );
  }

  Widget _tabButton(int index, String label) {
    final active = _tab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = index),
        child: SizedBox(
          height: 46,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    color: active ? V.ink : V.muted,
                  )),
              const SizedBox(height: 7),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 2.5,
                width: active ? 44 : 0,
                decoration: BoxDecoration(color: V.ink, borderRadius: BorderRadius.circular(99)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyCaseTile extends ConsumerWidget {
  final CaseSummary item;

  const _MyCaseTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = item.state;
    final active = state == 'funding' || state == 'pending_creditor' || state == 'draft';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: V.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: V.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(12)),
                  child: Text('${item.coverEmoji}', style: const TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => context.push('/case/${item.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, height: 1.25)),
                        const SizedBox(height: 3),
                        Text('${item.percent}% · ${money(item.raisedAmount)} / ${money(item.targetAmount)}',
                            style: const TextStyle(fontSize: 12, color: V.muted)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: active ? V.greenSoft : V.canvas,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    stateLabel(state),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: active ? V.greenDark : V.muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            WalletProgress(percent: item.percent, height: 7),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () async {
                      final url = '${const String.fromEnvironment('API_BASE', defaultValue: 'http://127.0.0.1:5080')}/share/${item.code}';
                      await Clipboard.setData(ClipboardData(text: url));
                      if (!context.mounted) return;
                      showSnack(context, 'Đã copy link chia sẻ case');
                    },
                    icon: const Icon(Icons.ios_share_rounded, size: 16),
                    label: const Text('Chia sẻ', style: TextStyle(fontSize: 12.5)),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => context.push('/case/${item.id}'),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Xem', style: TextStyle(fontSize: 12.5)),
                  ),
                ),
                if (active)
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _cancel(context, ref),
                      icon: const Icon(Icons.close_rounded, size: 16, color: V.danger),
                      label: const Text('Huỷ', style: TextStyle(fontSize: 12.5, color: V.danger)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Huỷ case này?'),
        content: const Text('Nếu case đã có người góp, toàn bộ tiền sẽ được hoàn lại cho người góp.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Không')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Huỷ case')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(apiProvider).post('/api/v1/my/cases/${item.id}/cancel');
      ref.invalidate(myCasesProvider);
      ref.invalidate(feedProvider);
      if (!context.mounted) return;
      showSnack(context, 'Đã huỷ case');
    } on ApiException catch (e) {
      if (!context.mounted) return;
      showSnack(context, e.message, error: true);
    }
  }
}

class _ContributionTile extends StatelessWidget {
  final Map<String, dynamic> item;

  const _ContributionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final state = '${item['state']}';
    final title = '${item['caseTitle'] ?? 'Case'}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: V.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: V.line)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: V.greenSoft, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.favorite_rounded, color: V.greenDark, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text('${money((item['amount'] as num?)?.toInt() ?? 0)} · ${stateLabel(state)}',
                    style: const TextStyle(fontSize: 11.5, color: V.muted)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => context.push('/case/${item['caseId']}'),
            icon: const Icon(Icons.chevron_right_rounded, color: V.muted),
          ),
        ],
      ),
    );
  }
}
