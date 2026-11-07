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
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFF2FFF8), V.surface], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: V.line),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    AvatarBubble(name: user.nickname, avatarKey: user.avatarKey, size: 60),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.nickname, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                          const SizedBox(height: 2),
                          Text(_maskPhone(user.phone), style: const TextStyle(fontSize: 12.5, color: V.muted)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _badge(kycLabel, user.kycTier >= 1 ? V.greenSoft : V.canvas,
                                  user.kycTier >= 1 ? V.greenDark : V.muted),
                              const SizedBox(width: 6),
                              _badge('${user.trustScore} điểm tin cậy', V.canvas, V.muted),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _editProfile(context, ref, user.nickname, user.bio),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                  ],
                ),
                if (user.bio.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(user.bio, style: const TextStyle(fontSize: 13, height: 1.5, color: V.inkSoft)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          stats.when(
            loading: () => const SizedBox(height: 84, child: LoadingView(label: '')),
            error: (_, __) => const SizedBox.shrink(),
            data: (data) => Row(
              children: [
                _stat('${data['casesCreated'] ?? 0}', 'case đã tạo'),
                _stat('${data['rescues'] ?? 0}', 'lần cứu nợ'),
                _stat(moneyShort((data['rescuedAmount'] as num?)?.toInt() ?? 0), 'tiền đã cứu'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _menuGroup(context, ref, [
            _MenuItem(
              icon: Icons.verified_user_outlined,
              title: user.kycTier >= 1 ? 'Xác minh danh tính (eKYC)' : 'Xác minh để nhận tiền',
              subtitle: user.kycTier >= 1 ? kycLabel : 'Cần eKYC bậc 1 để mở case chế độ A',
              onTap: () => context.push('/kyc'),
            ),
            _MenuItem(
              icon: Icons.account_balance_outlined,
              title: 'Tài khoản nhận tiền',
              subtitle: 'Thêm tài khoản để nhận hoàn tiền / rút tiền',
              onTap: () => context.push('/banks'),
            ),
            _MenuItem(
              icon: Icons.notifications_none_rounded,
              title: 'Thông báo',
              subtitle: 'Cài đặt và hộp thư',
              onTap: () => context.go('/notifications'),
            ),
          ]),
          const SizedBox(height: 12),
          _menuGroup(context, ref, [
            _MenuItem(
              icon: Icons.shield_outlined,
              title: 'An toàn & quyền riêng tư',
              subtitle: 'PIN, sinh trắc học, chặn người dùng',
              onTap: () => showSnack(context, 'Bản MVP chưa mở phần này — sẽ có ở P1.5'),
            ),
            _MenuItem(
              icon: Icons.description_outlined,
              title: 'Điều khoản & chính sách',
              subtitle: 'Điều khoản sử dụng, hoàn tiền, quyền riêng tư',
              onTap: () => showSnack(context, 'Xem điều khoản tại vilep.vn/terms (bản demo)'),
            ),
            _MenuItem(
              icon: Icons.delete_outline_rounded,
              title: 'Xoá tài khoản',
              subtitle: 'Xoá dữ liệu theo yêu cầu',
              danger: true,
              onTap: () => _deleteAccount(context, ref),
            ),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(authProvider.notifier).signOut();
              if (!context.mounted) return;
              context.go('/discover');
            },
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Đăng xuất'),
          ),
          const SizedBox(height: 18),
          const Center(
            child: Text('Ví Lép · MVP 0.4 · Ví lép, bạn bè lo!',
                style: TextStyle(fontSize: 11, color: V.muted)),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: V.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: V.line)),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10.5, color: V.muted)),
          ],
        ),
      ),
    );
  }

  Widget _menuGroup(BuildContext context, WidgetRef ref, List<_MenuItem> items) {
    return Container(
      decoration: BoxDecoration(color: V.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: V.line)),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(indent: 56, endIndent: 16),
            InkWell(
              onTap: items[i].onTap,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(items[i].icon, size: 20, color: items[i].danger ? V.danger : V.inkSoft),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(items[i].title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: items[i].danger ? V.danger : V.ink,
                              )),
                          if (items[i].subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(items[i].subtitle!, style: const TextStyle(fontSize: 11.5, color: V.muted)),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 18, color: V.muted),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
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
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, bottom: 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sửa hồ sơ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
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
                child: const Text('Lưu'),
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

class _MenuItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;

  _MenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });
}
