import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state.dart';
import '../../widgets.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final stats = ref.watch(myStatsProvider);

    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hồ sơ')),
        body: EmptyState(
          emoji: '👤',
          title: 'Bạn chưa đăng nhập',
          body: 'Đăng nhập để theo dõi case, khoản đã cứu và nhận thông báo.',
          actionLabel: 'Đăng nhập',
          onAction: () => context.push('/login?next=${Uri.encodeComponent('/me')}'),
        ),
      );
    }

    final user = auth.user!;
    final kycLabel = switch (user.kycTier) {
      0 => 'Chưa eKYC',
      1 => 'eKYC bậc 1',
      _ => 'eKYC bậc 2',
    };

    return Scaffold(
      backgroundColor: V.canvas,
      appBar: AppBar(
        backgroundColor: V.canvas,
        title: const Text('Hồ sơ'),
        actions: [
          IconButton(onPressed: () => ref.read(authProvider.notifier).refreshMe(), icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: V.surface,
              borderRadius: BorderRadius.circular(V.r24),
              border: Border.all(color: V.line),
              boxShadow: V.cardShadow,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    AvatarBubble(name: user.nickname, avatarKey: user.avatarKey, size: 62, ring: true),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.nickname,
                              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                          const SizedBox(height: 2),
                          Text(_maskPhone(user.phone), style: const TextStyle(fontSize: 12, color: V.muted)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _badge(kycLabel, user.kycTier >= 1 ? V.greenSoft : V.canvas,
                                  user.kycTier >= 1 ? V.greenDark : V.muted),
                              const SizedBox(width: 6),
                              _badge('${user.trustScore} điểm', V.canvas, V.muted),
                            ],
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _editProfile(context, ref, user.nickname, user.bio),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: V.canvas, shape: BoxShape.circle, border: Border.all(color: V.line)),
                        child: const Icon(Icons.edit_outlined, size: 17, color: V.ink2),
                      ),
                    ),
                  ],
                ),
                if (user.bio.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(user.bio, style: const TextStyle(fontSize: 12.5, height: 1.55, color: V.muted)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          stats.when(
            loading: () => const SizedBox(height: 80, child: LoadingView()),
            error: (_, _) => const SizedBox.shrink(),
            data: (data) => Row(
              children: [
                StatTile(
                  icon: Icons.assignment_outlined,
                  value: '${data['casesCreated'] ?? 0}',
                  label: 'case đã tạo',
                ),
                const SizedBox(width: 8),
                StatTile(
                  icon: Icons.favorite_border_rounded,
                  value: '${data['rescues'] ?? 0}',
                  label: 'lần cứu nợ',
                ),
                const SizedBox(width: 8),
                StatTile(
                  icon: Icons.savings_outlined,
                  value: moneyShort((data['rescuedAmount'] as num?)?.toInt() ?? 0),
                  label: 'tiền đã cứu',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _GroupLabel('Tài khoản & xác minh'),
          _Group(items: [
            _MenuItem(
              icon: Icons.verified_user_outlined,
              title: user.kycTier >= 1 ? 'Xác minh danh tính' : 'Xác minh để nhận tiền',
              subtitle: user.kycTier >= 1 ? 'Đã xác minh CCCD + selfie' : 'Cần eKYC bậc 1 để mở case chế độ A',
              trailing: user.kycTier >= 1 ? null : 'Cần làm',
              trailingAccent: user.kycTier < 1,
              onTap: () => context.push('/kyc'),
            ),
            _MenuItem(
              icon: Icons.account_balance_outlined,
              title: 'Tài khoản nhận tiền',
              subtitle: 'Nhận hoàn tiền / rút tiền về tài khoản của bạn',
              onTap: () => context.push('/banks'),
            ),
          ]),
          const SizedBox(height: 20),
          const _GroupLabel('Cài đặt'),
          _Group(items: [
            _MenuItem(
              icon: Icons.notifications_none_rounded,
              title: 'Thông báo',
              subtitle: 'Hộp thư và cài đặt nhận tin',
              onTap: () => context.go('/notifications'),
            ),
            _MenuItem(
              icon: Icons.shield_outlined,
              title: 'An toàn & quyền riêng tư',
              subtitle: 'PIN, sinh trắc học, chặn người dùng',
              onTap: () => showSnack(context, 'Bản MVP chưa mở phần này — sẽ có ở P1.5'),
            ),
            _MenuItem(
              icon: Icons.description_outlined,
              title: 'Điều khoản & chính sách',
              subtitle: 'Sử dụng, hoàn tiền, quyền riêng tư',
              onTap: () => showSnack(context, 'Xem điều khoản tại vilep.vn/terms (bản demo)'),
            ),
          ]),
          const SizedBox(height: 20),
          const _GroupLabel('Khác'),
          _Group(items: [
            _MenuItem(
              icon: Icons.logout_rounded,
              title: 'Đăng xuất',
              subtitle: 'Thoát khỏi thiết bị này',
              onTap: () async {
                await ref.read(authProvider.notifier).signOut();
                if (!context.mounted) return;
                context.go('/discover');
              },
            ),
            _MenuItem(
              icon: Icons.delete_outline_rounded,
              title: 'Xoá tài khoản',
              subtitle: 'Xoá dữ liệu theo yêu cầu',
              danger: true,
              onTap: () => _deleteAccount(context, ref),
            ),
          ]),
          const SizedBox(height: 26),
          Center(
            child: Column(
              children: [
                const WalletMascot(progress: 0.55, size: 54),
                const SizedBox(height: 8),
                Text('Ví Lép · MVP 0.4',
                    style: TextStyle(fontSize: 11, color: V.muted.withValues(alpha: 0.9), fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Ví lép, bạn bè lo!',
                    style: TextStyle(fontSize: 11, color: V.faint.withValues(alpha: 0.9))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(V.rPill)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  String _maskPhone(String phone) {
    if (phone.length < 7) return phone;
    return '${phone.substring(0, 3)} **** ${phone.substring(phone.length - 3)}';
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref, String nickname, String bio) async {
    final nicknameController = TextEditingController(text: nickname);
    final bioController = TextEditingController(text: bio);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, bottom: 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(color: V.line, borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const Text('Sửa hồ sơ', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
            const SizedBox(height: 16),
            TextField(controller: nicknameController, decoration: const InputDecoration(labelText: 'Biệt danh')),
            const SizedBox(height: 12),
            TextField(
              controller: bioController,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Bio ngắn', counterText: ''),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  try {
                    await ref.read(authProvider.notifier).updateProfile(
                          nickname: nicknameController.text.trim(),
                          bio: bioController.text.trim(),
                        );
                    if (context.mounted) Navigator.pop(context, true);
                  } on ApiException catch (e) {
                    if (context.mounted) showSnack(context, e.message, error: true);
                  }
                },
                child: const Text('Lưu thay đổi'),
              ),
            ),
          ],
        ),
      ),
    );
    nicknameController.dispose();
    bioController.dispose();
    if (saved == true && context.mounted) showSnack(context, 'Đã cập nhật hồ sơ');
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá tài khoản?'),
        content: const Text('Toàn bộ dữ liệu cá nhân sẽ bị xoá, các case đang chạy phải đóng trước. '
            'Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Không')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: V.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá vĩnh viễn'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(apiProvider).delete('/api/v1/me');
      await ref.read(authProvider.notifier).signOut();
      if (!context.mounted) return;
      context.go('/discover');
      showSnack(context, 'Tài khoản đã được xoá');
    } on ApiException catch (e) {
      if (!context.mounted) return;
      showSnack(context, e.message, error: true);
    }
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;

  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text.toUpperCase(),
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: V.faint)),
    );
  }
}

class _Group extends StatelessWidget {
  final List<_MenuItem> items;

  const _Group({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: V.surface, borderRadius: BorderRadius.circular(V.r20), border: Border.all(color: V.line)),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(indent: 58, endIndent: 16),
            _Row(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final _MenuItem item;

  const _Row({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(V.r20),
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: item.danger ? V.dangerSoft : V.canvas,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, size: 18, color: item.danger ? V.danger : V.ink2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: item.danger ? V.danger : V.ink,
                        letterSpacing: -0.1,
                      )),
                  if (item.subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(item.subtitle!, style: const TextStyle(fontSize: 11, color: V.muted)),
                    ),
                ],
              ),
            ),
            if (item.trailing != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(item.trailing!,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: item.trailingAccent ? V.amber : V.greenDark,
                    )),
              ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: V.faint),
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final bool trailingAccent;
  final VoidCallback onTap;
  final bool danger;

  _MenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.trailingAccent = false,
    this.danger = false,
  });
}
