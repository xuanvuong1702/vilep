import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../state.dart';
import '../../widgets.dart';

class CreditorPage extends ConsumerStatefulWidget {
  final String token;

  const CreditorPage({super.key, required this.token});

  @override
  ConsumerState<CreditorPage> createState() => _CreditorPageState();
}

class _CreditorPageState extends ConsumerState<CreditorPage> {
  final _nameController = TextEditingController();
  final _accountController = TextEditingController();
  String _bank = 'VCB';
  bool _busy = false;
  bool _done = false;
  String? _error;

  static const _banks = [
    ('VCB', 'Vietcombank'),
    ('TCB', 'Techcombank'),
    ('MB', 'MB Bank'),
    ('ACB', 'ACB'),
    ('BIDV', 'BIDV'),
    ('TPB', 'TPBank'),
    ('VIB', 'VIB'),
    ('STB', 'Sacombank'),
    ('MOMO', 'MoMo'),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  Future<void> _confirm(CreditorInvite invite) async {
    if (_busy) return;
    if (_nameController.text.trim().length < 3) {
      setState(() => _error = 'Nhập tên chủ tài khoản');
      return;
    }
    if (_accountController.text.trim().length < 6) {
      setState(() => _error = 'Số tài khoản không hợp lệ');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).post('/api/v1/creditor/invite/${widget.token}/confirm', body: {
        'accountName': _nameController.text.trim(),
        'bankCode': _bank,
        'accountNo': _accountController.text.trim(),
      });
      setState(() => _done = true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(creditorInviteProvider(widget.token));

    return Scaffold(
      backgroundColor: V.surface,
      body: async.when(
        loading: () => const LoadingView(label: 'Đang mở lời mời...'),
        error: (e, _) => Scaffold(
          appBar: AppBar(),
          body: EmptyState(
            emoji: '🔗',
            title: 'Link không hợp lệ',
            body: e is ApiException ? e.message : '$e',
          ),
        ),
        data: (invite) {
          if (_done || invite.confirmed) return _success(invite);
          if (invite.expired) {
            return SafeArea(
              child: EmptyState(
                emoji: '⌛',
                title: 'Lời mời đã hết hạn',
                body: 'Link xác nhận chỉ có hiệu lực 72 giờ. Hãy nhờ người đăng case gửi lại link mới.',
              ),
            );
          }
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                const Row(
                  children: [
                    Text('VÍ LÉP',
                        style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2.4, fontSize: 12, color: V.greenDark)),
                    Spacer(),
                    Icon(Icons.lock_outline_rounded, size: 14, color: V.muted),
                    SizedBox(width: 4),
                    Text('Link bảo mật', style: TextStyle(fontSize: 11, color: V.muted)),
                  ],
                ),
                const SizedBox(height: 24),
                const WalletMascot(progress: 0.2, size: 96),
                const SizedBox(height: 14),
                Text('${invite.debtorName} nhờ bạn xác nhận',
                    style: const TextStyle(fontSize: 26, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                const SizedBox(height: 8),
                const Text('Bạn là chủ nợ của khoản nợ dưới đây. Xác nhận để case mở gây quỹ — '
                    'tiền góp được giữ hộ và chuyển cho bạn khi đủ mục tiêu.',
                    style: TextStyle(fontSize: 13.5, height: 1.55, color: V.muted)),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(18), border: Border.all(color: V.line)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(invite.caseTitle,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(money(invite.amount),
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: V.greenSoft, borderRadius: BorderRadius.circular(8)),
                            child: const Text('Chế độ A',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: V.greenDark)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Khoản nợ ghi nhận: ${money(invite.debtAmount)} · Mã case ${invite.caseCode}',
                          style: const TextStyle(fontSize: 11.5, color: V.muted)),
                      if (invite.story.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text('"${invite.story}"',
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, height: 1.5, color: V.inkSoft, fontStyle: FontStyle.italic)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const Text('Tài khoản nhận tiền', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Tiền chỉ chuyển tới tài khoản này, đúng một lần, khi case đủ mục tiêu.',
                    style: TextStyle(fontSize: 12, color: V.muted)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _bank,
                  items: _banks.map((b) => DropdownMenuItem(value: b.$1, child: Text('${b.$2} (${b.$1})'))).toList(),
                  onChanged: (value) => setState(() => _bank = value ?? _bank),
                  decoration: const InputDecoration(labelText: 'Ngân hàng / ví'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _accountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Số tài khoản'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Tên chủ tài khoản', hintText: 'NGUYEN VAN A'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: V.danger, fontSize: 13)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : () => _confirm(invite),
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: V.ink))
                      : const Text('Xác nhận khoản nợ'),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Bằng việc xác nhận, bạn đồng ý nhận tiền qua Ví Lép và cho phép nền tảng thông báo cho bạn khi tiền được chuyển.',
                  style: TextStyle(fontSize: 10.5, color: V.muted, height: 1.5),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _success(CreditorInvite invite) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          const Center(child: WalletMascot(progress: 0.7, size: 140)),
          const SizedBox(height: 18),
          const Text('Đã xác nhận ✅',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.9)),
          const SizedBox(height: 8),
          Text(
            invite.confirmed || _done
                ? 'Case "${invite.caseTitle}" đã mở gây quỹ. Khi đủ ${money(invite.amount)}, Ví Lép chuyển tiền vào tài khoản bạn khai và thông báo cho bạn.'
                : 'Đã ghi nhận xác nhận của bạn.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: V.muted, fontSize: 13.5, height: 1.55),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('Link theo dõi case', style: TextStyle(fontSize: 12, color: V.muted)),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: '${kApiBase}/share/${invite.caseCode}'));
                        if (!mounted) return;
                        showSnack(context, 'Đã copy link case');
                      },
                      child: const Text('Copy'),
                    ),
                  ],
                ),
                Text('${kApiBase}/share/${invite.caseCode}',
                    style: const TextStyle(fontSize: 11.5, color: V.inkSoft)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
