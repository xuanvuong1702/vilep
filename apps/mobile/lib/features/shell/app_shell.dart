import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state.dart';

class AppShell extends ConsumerWidget {
  final String location;
  final Widget child;

  const AppShell({super.key, required this.location, required this.child});

  int get _index {
    if (location.startsWith('/my')) return 1;
    if (location.startsWith('/notifications')) return 2;
    if (location.startsWith('/me')) return 3;
    return 0;
  }

  void _go(BuildContext context, String path, int index) {
    if (_index == index && location == path) return;
    context.go(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationsProvider).value?.unread ?? 0;

    return Scaffold(
      backgroundColor: V.surface,
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: V.surface,
          border: Border(top: BorderSide(color: V.line)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.explore_outlined,
                  activeIcon: Icons.explore,
                  label: 'Khám phá',
                  active: _index == 0,
                  onTap: () => _go(context, '/discover', 0),
                ),
                _NavItem(
                  icon: Icons.account_balance_wallet_outlined,
                  activeIcon: Icons.account_balance_wallet,
                  label: 'Case của tôi',
                  active: _index == 1,
                  onTap: () => _go(context, '/my', 1),
                ),
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      onTap: () => context.push('/create'),
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: V.green,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: V.green.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: const Icon(Icons.add_rounded, color: Color(0xFF04170E), size: 28),
                      ),
                    ),
                  ),
                ),
                _NavItem(
                  icon: Icons.notifications_none_rounded,
                  activeIcon: Icons.notifications_rounded,
                  label: 'Thông báo',
                  active: _index == 2,
                  badge: unread,
                  onTap: () => _go(context, '/notifications', 2),
                ),
                _NavItem(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: 'Hồ sơ',
                  active: _index == 3,
                  onTap: () => _go(context, '/me', 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(active ? activeIcon : icon, size: 23, color: active ? V.ink : V.muted),
                if (badge > 0)
                  Positioned(
                    right: -6,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(minWidth: 15),
                      height: 15,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: V.danger, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? V.ink : V.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
