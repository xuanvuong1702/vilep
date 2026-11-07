import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../state.dart';
import '../../widgets.dart';

class KycPage extends ConsumerStatefulWidget {
  const KycPage({super.key});

  @override
  ConsumerState<KycPage> createState() => _KycPageState();
}

class _KycPageState extends ConsumerState<KycPage> {
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _dobController = TextEditingController();
  int _tier = 1;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_nameController.text.trim().length < 5) {
      setState(() => _error = 'Nhập họ tên đầy đủ như trên CCCD');
      return;
    }
    if (_idController.text.trim().length < 9) {
      setState(() => _error = 'Số CCCD không hợp lệ');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).submitKyc(
            tier: _tier,
            fullName: _nameController.text.trim(),
            idNumber: _idController.text.trim(),
            dob: _dobController.text.trim().isEmpty ? null : _dobController.text.trim(),
          );
      if (!mounted) return;
      showSnack(context, 'Xác minh thành công');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final verified = (user?.kycTier ?? 0) >= 1;

    return Scaffold(
      backgroundColor: V.surface,
      appBar: AppBar(title: const Text('Xác minh danh tính')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          if (verified)
            InfoCard(
              icon: Icons.verified_user_rounded,
              title: 'Bạn đã xác minh bậc ${user?.kycTier}',
              body: 'Bạn có thể mở case chế độ A và nhận hoàn tiền. Bậc 2 cần thêm đối chiếu tài khoản ngân hàng chính chủ.',
              tint: V.greenSoft,
            ),
          const SizedBox(height: 18),
          const Text('Vì sao cần eKYC?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          const SizedBox(height: 6),
          const Text('Ví Lép cần biết bạn là người thật để bảo vệ cả con nợ và chủ nợ. '
              'Dữ liệu CCCD được băm/mã hoá, không hiển thị công khai.',
              style: TextStyle(color: V.muted, fontSize: 13.5, height: 1.55)),
          const SizedBox(height: 20),
          _tierRow(1, 'Bậc 1 · eKYC nhẹ', 'CCCD + selfie · đủ để mở case chế độ A'),
          const SizedBox(height: 8),
          _tierRow(2, 'Bậc 2 · eKYC đầy đủ', 'Đối chiếu tài khoản ngân hàng chính chủ · cần cho rút tiền chế độ B'),
          const SizedBox(height: 20),
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Họ và tên trên CCCD')),
          const SizedBox(height: 12),
          TextField(
            controller: _idController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Số CCCD', hintText: '079200001234'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dobController,
            keyboardType: TextInputType.datetime,
            decoration: const InputDecoration(labelText: 'Ngày sinh (yyyy-mm-dd, tuỳ chọn)', hintText: '2000-01-01'),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(14)),
            child: const Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: V.muted),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Bản MVP dùng eKYC giả lập: hồ sơ được duyệt tự động. '
                      'Khi nối nhà cung cấp eKYC thật, bước này sẽ chụp CCCD + selfie.',
                      style: TextStyle(fontSize: 11.5, color: V.muted, height: 1.45)),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: V.danger, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: V.ink))
                : Text('Gửi hồ sơ bậc $_tier'),
          ),
        ],
      ),
    );
  }

  Widget _tierRow(int tier, String title, String subtitle) {
    final active = _tier == tier;
    return GestureDetector(
      onTap: () => setState(() => _tier = tier),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? V.greenSoft : V.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? V.green : V.line),
        ),
        child: Row(
          children: [
            Icon(active ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18, color: active ? V.greenDark : V.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11.5, color: V.muted, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
