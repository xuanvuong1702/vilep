import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state.dart';
import '../../widgets.dart';

const _tabs = <(String, String)>[
  ('need', 'Cần cứu'),
  ('almost', 'Sắp xong'),
  ('newest', 'Mới nhất'),
  ('friends', 'Bạn bè'),
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
    final firstName = (auth.user?.nickname ?? '').split(' ').first;
    final featured = feed.items.where((e) => e.percent >= 45).take(6).toList();

    return Scaffold(
      backgroundColor: V.surface,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: V.green,
          backgroundColor: V.surface,
          onRefresh: () => ref.read(feedProvider.notifier).load(reset: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: V.surface.withValues(alpha: 0.96),
                surfaceTintColor: Colors.transparent,
                titleSpacing: 20,
                title: const _Wordmark(),
                actions: [
                  _IconAction(icon: Icons.search_rounded, onTap: () => context.push('/search')),
                  _IconAction(
                    icon: Icons.notifications_none_rounded,
                    badge: unread,
                    onTap: () => context.go('/notifications'),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: GestureDetector(
                      onTap: () => context.go('/me'),
                      child: auth.isLoggedIn
                          ? AvatarBubble(name: auth.user!.nickname, avatarKey: auth.user!.avatarKey, size: 34, ring: true)
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
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.isLoggedIn ? 'Chào $firstName 👋' : 'Ví lép, bạn bè lo!',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: V.muted),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Hôm nay, cứu ai đó.',
                        style: TextStyle(fontSize: 32, height: 1.06, fontWeight: FontWeight.w800, letterSpacing: -1.2),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${feed.items.length} khoản nợ vui đang chờ — tiền giữ hộ, chuyển thẳng cho chủ nợ.',
                        style: const TextStyle(fontSize: 13, color: V.muted, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _SegmentedTabs(
                    active: feed.tab,
                    onChanged: (tab) => ref.read(feedProvider.notifier).setTab(tab),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                    itemCount: _categories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
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
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(const [SkeletonCard(), SkeletonCard(), SkeletonCard()]),
                  ),
                )
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
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                    child: _CreateBanner(onTap: () => context.push('/create')),
                  ),
                ),
                if (featured.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: SectionHeader(
                        title: 'Sắp chạm đích',
                        subtitle: 'Góp thêm chút là xong',
                        action: 'Xem tất cả',
                        onAction: () => ref.read(feedProvider.notifier).setTab('almost'),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 208,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        physics: const BouncingScrollPhysics(),
                        itemCount: featured.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final item = featured[index];
                          return CaseCard(item: item, horizontal: true, onTap: () => context.push('/case/${item.id}'));
                        },
                      ),
                    ),
                  ),
                ],
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
                    child: SectionHeader(
                      title: feed.tab == 'almost' ? 'Sắp xong' : 'Tất cả khoản nợ',
                      subtitle: '${feed.items.length} case đang mở',
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
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
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
                    child: Center(
                      child: feed.loadingMore
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: V.green))
                          : Text('Ví lép, bạn bè lo! 💚',
                              style: TextStyle(color: V.muted.withValues(alpha: 0.85), fontSize: 11.5, letterSpacing: 0.2)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          'ví lép',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -1.4, height: 1),
        ),
        Container(
          margin: const EdgeInsets.only(left: 3, bottom: 3),
          width: 6,
          height: 6,
          decoration: const BoxDecoration(color: V.green, shape: BoxShape.circle),
        ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  const _IconAction({required this.icon, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: 22),
          if (badge > 0)
            Positioned(
              right: -3,
              top: -2,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: V.danger, shape: BoxShape.circle, border: Border.all(color: V.surface, width: 1.5)),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  final String active;
  final ValueChanged<String> onChanged;

  const _SegmentedTabs({required this.active, required this.onChanged});

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
          for (final (key, label) in _tabs)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(key),
                child: AnimatedContainer(
                  duration: V.fast,
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active == key ? V.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(V.rPill),
                    boxShadow: active == key ? V.cardShadow : null,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active == key ? FontWeight.w800 : FontWeight.w600,
                      color: active == key ? V.ink : V.muted,
                      letterSpacing: -0.1,
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
        duration: V.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? V.ink : V.surface,
          borderRadius: BorderRadius.circular(V.rPill),
          border: Border.all(color: active ? V.ink : V.line),
        ),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : V.ink2,
          ),
        ),
      ),
    );
  }
}

class _CreateBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(color: V.ink, borderRadius: BorderRadius.circular(V.r20)),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
              child: const WalletMascot(progress: 0.12, size: 38),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ví bạn đang lép?',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5, letterSpacing: -0.2)),
                  SizedBox(height: 2),
                  Text('Kể khoản nợ vui trong 2 phút',
                      style: TextStyle(color: Color(0xFFB7C0BA), fontSize: 11.5, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(color: V.green, shape: BoxShape.circle),
              child: const Icon(Icons.arrow_forward_rounded, color: V.greenInk, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
