import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../state.dart';
import '../../widgets.dart';

class BankAccountsPage extends ConsumerStatefulWidget {
  const BankAccountsPage({super.key});

  @override
  ConsumerState<BankAccountsPage> createState() => _BankAccountsPageState();
}

class _BankAccountsPageState extends ConsumerState<BankAccountsPage> {
  final _accountsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
    final data = await ref.watch(apiProvider).get('/api/v1/me/bank-accounts') as Map<String, dynamic>;
    return ((data['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
  });

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
  Widget build(BuildContext context) {
    final accounts = ref.watch(_accountsProvider);

    return Scaffold(
      backgroundColor: V.surface,
      appBar: AppBar(title: const Text('Tài khoản nhận tiền')),
      body: accounts.when(
        loading: () => const LoadingView(),
        error: (e, _) => EmptyState(emoji: '📡', title: 'Không tải được', body: e is ApiException ? e.message : '$e'),
        data: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            InfoCard(
              icon: Icons.account_balance_outlined,
              title: 'Tài khoản mang tên bạn',
              body: 'Dùng để nhận hoàn tiền khi case không đủ mục tiêu. Chế độ B yêu cầu tài khoản khớp tên với CCCD.',
            ),
            const SizedBox(height: 18),
            if (items.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(16)),
                child: const Text('Chưa có tài khoản nào. Thêm tài khoản để nhận tiền.',
                    style: TextStyle(fontSize: 13, color: V.muted)),
              )
            else
              ...items.map((account) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: V.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: V.line)),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: V.greenSoft, borderRadius: BorderRadius.circular(12)),
                          child: Text('${account['bankCode']}',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: V.greenDark)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${account['accountNoMasked']} · ${account['accountName']}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              const SizedBox(height: 2),
                              Text(
                                account['nameMatchedKyc'] == true ? 'Khớp tên với CCCD ✓' : 'Chưa khớp tên CCCD',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: account['nameMatchedKyc'] == true ? V.greenDark : V.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () async {
                            try {
                              await ref.read(apiProvider).delete('/api/v1/me/bank-accounts/${account['id']}');
                              ref.invalidate(_accountsProvider);
                            } on ApiException catch (e) {
                              if (!context.mounted) return;
                              showSnack(context, e.message, error: true);
                            }
                          },
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: V.muted),
                        ),
                      ],
                    ),
                  )),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _addAccount(context, ref, items),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Thêm tài khoản'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addAccount(BuildContext context, WidgetRef ref, List<Map<String, dynamic>> existing) async {
    final numberController = TextEditingController();
    final nameController = TextEditingController();
    String bank = _banks.first.$1;

    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, bottom: 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Thêm tài khoản nhận tiền', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: bank,
                items: _banks.map((b) => DropdownMenuItem(value: b.$1, child: Text('${b.$2} (${b.$1})'))).toList(),
                onChanged: (value) => setModalState(() => bank = value ?? bank),
                decoration: const InputDecoration(labelText: 'Ngân hàng / ví'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: numberController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Số tài khoản'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Tên chủ tài khoản', hintText: 'NGUYEN MINH ANH'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    try {
                      await ref.read(apiProvider).post('/api/v1/me/bank-accounts', body: {
                        'bankCode': bank,
                        'accountNo': numberController.text.trim(),
                        'accountName': nameController.text.trim(),
                      });
                      if (context.mounted) Navigator.pop(context, true);
                    } on ApiException catch (e) {
                      if (context.mounted) showSnack(context, e.message, error: true);
                    }
                  },
                  child: const Text('Lưu tài khoản'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    numberController.dispose();
    nameController.dispose();
    if (added == true) {
      ref.invalidate(_accountsProvider);
      if (context.mounted) showSnack(context, 'Đã thêm tài khoản');
    }
  }
}
