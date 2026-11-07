import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../state.dart';
import '../../widgets.dart';

class LoginPage extends ConsumerStatefulWidget {
  final String? next;

  const LoginPage({super.key, this.next});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _otpFocus = FocusNode();

  bool _otpSent = false;
  bool _busy = false;
  String? _devCode;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  String get _phone {
    final raw = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (raw.startsWith('84')) return '0${raw.substring(2)}';
    return raw;
  }

  Future<void> _requestOtp() async {
    if (_busy) return;
    final phone = _phone;
    if (phone.length < 9) {
      setState(() => _error = 'Nhập số điện thoại hợp lệ (VD: 0901234567)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = await ref.read(authProvider.notifier).requestOtp(phone);
      setState(() {
        _otpSent = true;
        _devCode = code;
        if (code != null) _otpController.text = code;
      });
      _otpFocus.requestFocus();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).verifyOtp(_phone, _otpController.text.trim());
      if (!mounted) return;
      final next = widget.next;
      context.go(next != null && next.isNotEmpty ? Uri.decodeComponent(next) : '/discover');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _quickLogin(String phone) async {
    _phoneController.text = phone;
    final code = await ref.read(authProvider.notifier).requestOtp(phone);
    if (code == null) return;
    await ref.read(authProvider.notifier).verifyOtp(phone, code);
    if (!mounted) return;
    context.go('/discover');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => context.canPop() ? context.pop() : context.go('/onboarding'),
                    icon: const Icon(Icons.arrow_back_rounded),
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                  ),
                  const Spacer(),
                  const Text('VÍ LÉP',
                      style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2.4, fontSize: 12, color: V.greenDark)),
                ],
              ),
              const SizedBox(height: 18),
              const WalletMascot(progress: 0.35, size: 96),
              const SizedBox(height: 20),
              Text(_otpSent ? 'Nhập mã OTP' : 'Đăng nhập bằng số điện thoại',
                  style: const TextStyle(fontSize: 28, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.9)),
              const SizedBox(height: 8),
              Text(
                _otpSent
                    ? 'Mã 6 số đã gửi tới $_phone. Ở chế độ dev, mã hiện ngay bên dưới.'
                    : 'Chúng mình dùng SĐT để bảo vệ bạn và chủ nợ. Không đăng bài công khai số của bạn.',
                style: const TextStyle(color: V.muted, height: 1.5, fontSize: 14),
              ),
              const SizedBox(height: 26),
              if (!_otpSent) ...[
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _requestOtp(),
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại',
                    hintText: '0901234567',
                    prefixIcon: Icon(Icons.phone_iphone_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _requestOtp,
                    child: _busy
                        ? const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: V.ink))
                        : const Text('Gửi mã OTP'),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _otpController,
                  focusNode: _otpFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 10),
                  textAlign: TextAlign.center,
                  onSubmitted: (_) => _verify(),
                  decoration: const InputDecoration(hintText: '••••••'),
                ),
                if (_devCode != null) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => setState(() => _otpController.text = _devCode!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: V.greenSoft, borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.science_outlined, size: 15, color: V.greenDark),
                          const SizedBox(width: 6),
                          Text('Mã dev: $_devCode (bấm để điền)',
                              style: const TextStyle(fontSize: 12, color: V.greenDark, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _verify,
                    child: _busy
                        ? const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: V.ink))
                        : const Text('Vào Ví Lép'),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _requestOtp,
                  child: const Text('Gửi lại mã'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: V.danger, fontSize: 13)),
              ],
              const SizedBox(height: 26),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('hoặc vào nhanh bản demo', style: TextStyle(fontSize: 12, color: V.muted)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DemoChip(label: 'Minh Anh · con nợ', onTap: () => _quickLogin('0900000001')),
                  _DemoChip(label: 'Lan Nhi · người cứu', onTap: () => _quickLogin('0900000002')),
                  _DemoChip(label: 'Admin Ví Lép', onTap: () => _quickLogin('0900000003')),
                ],
              ),
              const SizedBox(height: 28),
              const Text(
                'Bằng việc tiếp tục, bạn xác nhận mình từ 18 tuổi trở lên và đồng ý với Điều khoản sử dụng '
                'và Chính sách quyền riêng tư của Ví Lép.',
                style: TextStyle(fontSize: 11.5, color: V.muted, height: 1.5),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _openServerDialog(context, ref),
                  icon: const Icon(Icons.dns_outlined, size: 15, color: V.muted),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                  label: Text(
                    'Máy chủ: ${ref.watch(serverBaseProvider).replaceFirst('http://', '')}',
                    style: const TextStyle(fontSize: 11, color: V.muted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openServerDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: ref.read(serverBaseProvider));
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Địa chỉ máy chủ API'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'API base URL', hintText: 'http://192.168.1.30:5080'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Dùng 10.0.2.2 khi chạy trên Android emulator, hoặc IP LAN của máy tính khi chạy APK trên điện thoại.',
              style: TextStyle(fontSize: 11.5, color: V.muted, height: 1.45),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () async {
              await ref.read(serverBaseProvider.notifier).update(controller.text);
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == true && context.mounted) {
      showSnack(context, 'Đã đổi máy chủ API');
    }
  }
}

class _DemoChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DemoChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: onTap,
      backgroundColor: V.canvas,
      side: const BorderSide(color: V.line),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
