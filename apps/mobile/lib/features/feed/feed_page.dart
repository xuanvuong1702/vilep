import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state.dart';
import '../../widgets.dart';

const _tabs = <(String, String)>[
  ('need', 'Đang cần giải cứu'),
  ('almost', 'Sắp xong'),
  ('newest', 'Mới nhất'),
  ('friends', 'Của bạn bè'),
];

const _categories = <(String, String)>[
  ('all', 'Tất cả'),
  ('tra-sua', '🧋 Trà sữa'),
  ('nhau', '🍻 Nợ nhậu'),
  ('ca-cuoc', '⚽ Thua cược'),
  ('an-uong', '🍜 Mượn tiền ăn'),
  ('qua-sinh-nhat', '🎁 Quà sinh nhật'),
  ('muon-tien', '🤝 Mượn tiền'),
];

class FeedPage extends ConsumerWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedProvider);
    final auth = ref.watch(authProvider);
    final unread = ref.watch(notificationsProvider).value?.unread ?? 0;

    return Scaffold(
      backgroundColor: V.surface,
      body: RefreshIndicator(
        color: V.green,
        onRefresh: () => ref.read(feedProvider.notifier).load(reset: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: V.surface,
              surfaceTintColor: Colors.transparent,
              titleSpacing: 20,
              title: Row(
                children: [
                  const Text('Ví Lép',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.9)),
                  const SizedBox(width: 6),
                  const Text('👛', style: TextStyle(fontSize: 18)),
                ],
              ),
              actions: [
                IconButton(
                  onPressed: () => context.push('/search'),
                  icon: const Icon(Icons.search_rounded),
                ),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      onPressed: () => context.go('/notifications'),
                      icon: const Icon(Icons.notifications_none_rounded),
                    ),
                    if (unread > 0)
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: V.danger, shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 16, left: 4),
                  child: GestureDetector(
                    onTap: () => context.go('/me'),
                    child: auth.isLoggedIn
                        ? AvatarBubble(
                            name: auth.user!.nickname,
                            avatarKey: auth.user!.avatarKey,
                            size: 34,
                          )
                        : Container(
                            width: 34,
                            height: 34,
                            decoration: const BoxDecoration(color: V.canvas, shape: BoxShape.circle),
                            child: const Icon(Icons.person_outline_rounded, size: 19, color: V.muted),
                          ),
                  ),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Row(
                  children: [
                    Text('Ví lép, bạn bè lo!',
                        style: TextStyle(fontSize: 13, color: V.muted.withValues(alpha: 0.9), fontWeight: FontWeight.w500)),
                    const Spacer(),
                    if (feed.items.isNotEmpty)
                      Text('${feed.items.length} case đang mở',
                          style: const TextStyle(fontSize: 12, color: V.muted)),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: _Tabs(feed.tab, (tab) => ref.read(feedProvider.notifier).setTab(tab))),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final (key, label) = _categories[index];
                    return _CategoryPill(
                      label: label,
                      active: feed.category == key,
                      onTap: () => ref.read(feedProvider.notifier).setCategory(key),
                    );
                  },
                ),
              ),
            ),
            if (feed.loading && feed.items.isEmpty)
              const SliverFillRemaining(hasScrollBody: false, child: LoadingView(label: 'Đang gom case...'))
            else if (feed.error != null && feed.items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  emoji: '📡',
                  title: 'Không tải được feed',
                  body: feed.error!,
                  actionLabel: 'Thử lại',
                  onAction: () => ref.read(feedProvider.notifier).load(reset: true),
                ),
              )
            else if (feed.items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  emoji: '👛',
                  title: feed.tab == 'friends' ? 'Chưa có case của bạn bè' : 'Chưa có case nào',
                  body: feed.tab == 'friends'
                      ? 'Khi bạn góp cho ai đó, case của những người cùng nhóm sẽ hiện ở đây.'
                      : 'Ví lép quá? Kể khoản nợ đầu tiên của bạn, cả nhà sẽ cứu.',
                  actionLabel: 'Tạo case đầu tiên',
                  onAction: () => context.push('/create'),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: SizedBox(
                    height: 54,
                    child: Material(
                      color: const Color(0xFF101010),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => context.push('/create'),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 18),
                          child: Row(
                            children: [
                              WalletMascot(progress: 0.1, size: 40),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text('Ví bạn đang lép? Kể ngay trong 2 phút',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
                              ),
                              Icon(Icons.arrow_forward_rounded, color: V.green, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (feed.tab == 'need' && feed.items.length > 2)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(title: 'Sắp chạm đích'),
                        SizedBox(
                          height: 240,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(right: 20),
                            itemCount: feed.items.take(6).where((e) => e.percent >= 50).length,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final almost = feed.items.where((e) => e.percent >= 50).toList()[index];
                              return CaseCard(
                                item: almost,
                                horizontal: true,
                                onTap: () => context.push('/case/${almost.id}'),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                sliver: SliverList.builder(
                  itemCount: feed.items.length,
                  itemBuilder: (context, index) {
                    final item = feed.items[index];
                    return CaseCard(item: item, onTap: () => context.push('/case/${item.id}'));
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  child: Center(
                    child: feed.loadingMore
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: V.green))
                        : Text('Ví lép, bạn bè lo! 💚', style: TextStyle(color: V.muted.withValues(alpha: 0.8), fontSize: 12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  final String active;
  final ValueChanged<String> onChanged;

  const _Tabs(this.active, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 20),
        itemBuilder: (context, index) {
          final (key, label) = _tabs[index];
          final selected = key == active;
          return GestureDetector(
            onTap: () => onChanged(key),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? V.ink : V.muted,
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 2.5,
                  width: selected ? 34 : 0,
                  decoration: BoxDecoration(color: V.ink, borderRadius: BorderRadius.circular(99)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _CategoryPill({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? V.green : V.canvas,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? V.green : V.line),
        ),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: active ? const Color(0xFF04170E) : V.inkSoft,
          ),
        ),
      ),
    );
  }
}