import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state.dart';
import '../../widgets.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  static const _pages = [
    _Slide(
      progress: 0.08,
      eyebrow: 'CHÀO BẠN',
      title: 'Ví lép,\nbạn bè lo!',
      body: 'Kể khoản nợ vui của bạn — nợ trà sữa, nợ nhậu, thua kèo bóng. '
          'Bạn bè góp chút tiền để cứu ví bạn. Không ai bị phán xét, chỉ bị trêu nhẹ thôi.',
    ),
    _Slide(
      progress: 0.55,
      eyebrow: 'XÁC NHẬN HAI CHIỀU',
      title: 'Chủ nợ bấm link,\nxác nhận là xong',
      body: 'Chủ nợ không cần cài app. Họ mở link, xác nhận bạn đúng là con nợ và khai tài khoản nhận. '
          'Case chỉ mở gây quỹ khi có xác nhận — tiền không đi lung tung.',
    ),
    _Slide(
      progress: 1.0,
      eyebrow: 'TIỀN VỀ ĐÚNG CHỖ',
      title: 'Đủ tiền,\ntiền về thẳng chủ nợ',
      body: 'Tiền được giữ hộ và chuyển một lần cho chủ nợ khi đủ mục tiêu. '
          'Hết hạn mà chưa đủ, mọi người được hoàn đủ. Minh bạch từng đồng.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(prefsProvider).setBool('seen_onboarding', true);
    if (!mounted) return;
    context.go(ref.read(authProvider).isLoggedIn ? '/discover' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_index];
    return Scaffold(
      backgroundColor: V.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(
                children: [
                  const Text('VÍ LÉP',
                      style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2.4, fontSize: 13, color: V.greenDark)),
                  const Spacer(),
                  TextButton(onPressed: _finish, child: const Text('Bỏ qua')),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) {
                  final slide = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2FFF8),
                            borderRadius: BorderRadius.circular(36),
                          ),
                          child: WalletMascot(progress: slide.progress, size: 190),
                        ),
                        const SizedBox(height: 36),
                        Text(slide.eyebrow,
                            style: const TextStyle(fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w800, color: V.greenDark)),
                        const SizedBox(height: 10),
                        Text(slide.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 32, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -1)),
                        const SizedBox(height: 14),
                        Text(slide.body,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14.5, height: 1.55, color: V.muted)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (i) {
                      final active = i == _index;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        height: 7,
                        width: active ? 24 : 7,
                        decoration: BoxDecoration(
                          color: active ? V.green : V.line,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        if (_index == _pages.length - 1) {
                          _finish();
                        } else {
                          _controller.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
                        }
                      },
                      child: Text(_index == _pages.length - 1 ? 'Bắt đầu cứu ví' : 'Tiếp tục'),
                    ),
                  ),
                  TextButton(
                    onPressed: _finish,
                    child: Text('Đã có tài khoản? Đăng nhập',
                        style: TextStyle(color: page.progress > 0.9 ? V.ink : V.muted, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final double progress;
  final String eyebrow;
  final String title;
  final String body;

  const _Slide({required this.progress, required this.eyebrow, required this.title, required this.body});
}
