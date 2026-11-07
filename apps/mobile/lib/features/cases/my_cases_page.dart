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
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: _Segmented(
              labels: const ['Tôi đăng', 'Tôi đã cứu'],
              index: _tab,
              onChanged: (index) => setState(() => _tab = index),
            ),
          ),
        ),
      ),
      body: _tab == 0
          ? async.when(
              loading: () => const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(children: [SkeletonCard(), SkeletonCard()]),
              ),
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
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    children: [
                      for (final item in cases) _MyCaseTile(item: item),
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
                  physics: const BouncingScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _ContributionTile(item: items[index]),
                );
              },
            ),
    );
  }
}

class _Segmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  const _Segmented({required this.labels, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: V.canvas,
        borderRadius: BorderRadius.circular(V.rPill),
        border: Border.all(color: V.line),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: V.fast,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: index == i ? V.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(V.rPill),
                    boxShadow: index == i ? V.cardShadow : null,
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: index == i ? FontWeight.w800 : FontWeight.w600,
                      color: index == i ? V.ink : V.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
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
    final tone = switch (state) {
      'funding' => (V.greenSoft, V.greenDark),
      'pending_creditor' || 'draft' => (V.amberSoft, const Color(0xFF9A6400)),
      'paid' || 'closed' => (V.greenSoft, V.greenDark),
      _ => (V.canvas, V.muted),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: V.surface,
          borderRadius: BorderRadius.circular(V.r20),
          border: Border.all(color: V.line),
          boxShadow: V.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: coverGradient(item.coverColor),
                    borderRadius: BorderRadius.circular(V.r12),
                  ),
                  child: Text(item.coverEmoji, style: const TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.push('/case/${item.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14.5, height: 1.24, letterSpacing: -0.3)),
                        const SizedBox(height: 3),
                        Text('${money(item.raisedAmount)} / ${money(item.targetAmount)}',
                            style: const TextStyle(fontSize: 11.5, color: V.muted)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(color: tone.$1, borderRadius: BorderRadius.circular(8)),
                  child: Text(stateLabel(state),
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: tone.$2)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: WalletProgress(percent: item.percent, height: 6)),
                const SizedBox(width: 10),
                Text('${item.percent}%',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: V.greenDark)),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _Action(
                    icon: Icons.ios_share_rounded,
                    label: 'Chia sẻ',
                    onTap: () async {
                      final url =
                          '${const String.fromEnvironment('API_BASE', defaultValue: 'http://127.0.0.1:5080')}/share/${item.code}';
                      await Clipboard.setData(ClipboardData(text: url));
                      if (!context.mounted) return;
                      showSnack(context, 'Đã copy link chia sẻ case');
                    },
                  ),
                ),
                Expanded(
                  child: _Action(
                    icon: Icons.open_in_new_rounded,
                    label: 'Xem',
                    onTap: () => context.push('/case/${item.id}'),
                  ),
                ),
                if (active)
                  Expanded(
                    child: _Action(
                      icon: Icons.close_rounded,
                      label: 'Huỷ',
                      danger: true,
                      onTap: () => _cancel(context, ref),
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
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: V.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Huỷ case'),
          ),
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

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _Action({required this.icon, required this.label, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V.r12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: danger ? V.danger : V.ink2),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: danger ? V.danger : V.ink2)),
          ],
        ),
      ),
    );
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
      decoration: BoxDecoration(
        color: V.surface,
        borderRadius: BorderRadius.circular(V.r16),
        border: Border.all(color: V.line),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: V.greenSoft, borderRadius: BorderRadius.circular(V.r12)),
            child: const Icon(Icons.favorite_rounded, color: V.greenDark, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text('${money((item['amount'] as num?)?.toInt() ?? 0)} · ${stateLabel(state)}',
                    style: const TextStyle(fontSize: 11, color: V.muted)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => context.push('/case/${item['caseId']}'),
            icon: const Icon(Icons.chevron_right_rounded, color: V.faint),
          ),
        ],
      ),
    );
  }
}
