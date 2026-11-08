import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../state.dart';
import '../../widgets.dart';

class CreateCasePage extends ConsumerStatefulWidget {
  const CreateCasePage({super.key});

  @override
  ConsumerState<CreateCasePage> createState() => _CreateCasePageState();
}

class _CreateCasePageState extends ConsumerState<CreateCasePage> {
  final _titleController = TextEditingController();
  final _storyController = TextEditingController();
  final _amountController = TextEditingController();
  final _creditorNameController = TextEditingController();
  final _creditorPhoneController = TextEditingController();

  int _step = 0;
  DebtTemplate? _template;
  String _displayMode = 'nickname';
  bool _submitting = false;
  String? _error;

  String? _caseId;
  String? _inviteUrl;
  String? _shareUrl;

  @override
  void dispose() {
    _titleController.dispose();
    _storyController.dispose();
    _amountController.dispose();
    _creditorNameController.dispose();
    _creditorPhoneController.dispose();
    super.dispose();
  }

  int get _amount => int.tryParse(_amountController.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  void _applyTemplate(DebtTemplate template, MetaConfig meta) {
    setState(() {
      _template = template;
      _titleController.text = template.title;
      _storyController.text = template.story;
      _amountController.text = template.amount.toString();
      _step = 1;
    });
  }

  Future<void> _finish(MetaConfig meta) async {
    if (_submitting) return;
    final title = _titleController.text.trim();
    final story = _storyController.text.trim();
    if (title.length < 6) {
      setState(() => _error = 'Tiêu đề cần ít nhất 6 ký tự');
      return;
    }
    if (story.length < 20) {
      setState(() => _error = 'Lời kể cần ít nhất 20 ký tự, kể rõ hơn chút nhé');
      return;
    }
    if (_amount < meta.funModeAMin || _amount > meta.funModeAMax) {
      setState(() => _error = 'Số tiền phải từ ${money(meta.funModeAMin)} đến ${money(meta.funModeAMax)}');
      return;
    }
    if (_creditorNameController.text.trim().isEmpty || _creditorPhoneController.text.trim().length < 9) {
      setState(() => _error = 'Nhập tên và số điện thoại chủ nợ để gửi link xác nhận');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final created = await api.post('/api/v1/my/cases', body: {
        'title': title,
        'story': story,
        'category': _template?.category ?? 'khac',
        'debtAmount': _amount,
        'targetAmount': _amount,
        'displayMode': _displayMode,
        'templateKey': _template?.key ?? '',
      }) as Map<String, dynamic>;
      final caseId = created['id'] as String;
      final invite = await api.post('/api/v1/my/cases/$caseId/invite-creditor', body: {
        'name': _creditorNameController.text.trim(),
        'phone': _creditorPhoneController.text.trim(),
      }) as Map<String, dynamic>;

      setState(() {
        _caseId = caseId;
        _inviteUrl = invite['inviteUrl'] as String?;
        _shareUrl = invite['shortUrl'] as String?;
        _step = 3;
      });
      ref.invalidate(myCasesProvider);
      ref.invalidate(feedProvider);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metaAsync = ref.watch(metaProvider);
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: V.surface,
      appBar: AppBar(
        title: Text(_step == 3 ? 'Case đã mở' : 'Tạo case'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => _step == 0 ? context.pop() : setState(() => _step -= 1),
        ),
        bottom: _step >= 3
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(22),
                child: _StepProgress(step: _step),
              ),
      ),
      body: PageFrame(
        child: metaAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => EmptyState(emoji: '📡', title: 'Không tải được cấu hình', body: '$e'),
        data: (meta) {
          if (!auth.isLoggedIn) {
            return EmptyState(
              emoji: '🔐',
              title: 'Đăng nhập để tạo case',
              body: 'Bạn cần tài khoản để đứng tên khoản nợ và nhận tiền cứu.',
              actionLabel: 'Đăng nhập',
              onAction: () => context.push('/login?next=${Uri.encodeComponent('/create')}'),
            );
          }
          return switch (_step) {
            0 => _templateStep(meta),
            1 => _detailStep(meta),
            2 => _creditorStep(meta),
            _ => _successStep(),
          };
        },
      ),
      ),
    );
  }

  Widget _templateStep(MetaConfig meta) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
      physics: const BouncingScrollPhysics(),
      children: [
        const Text('Chọn mẫu nợ vui',
            style: TextStyle(fontSize: 30, height: 1.08, fontWeight: FontWeight.w800, letterSpacing: -1.0)),
        const SizedBox(height: 6),
        const Text('Điền sẵn tiêu đề, số tiền và lời kể — bạn sửa lại được ở bước sau.',
            style: TextStyle(color: V.muted, fontSize: 13, height: 1.5)),
        const SizedBox(height: 20),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: meta.templates.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.24,
          ),
          itemBuilder: (context, index) {
            final template = meta.templates[index];
            return _TemplateTile(template: template, onTap: () => _applyTemplate(template, meta));
          },
        ),
        const SizedBox(height: 18),
        const InfoCard(
          icon: Icons.lightbulb_outline_rounded,
          title: 'Không thấy mẫu hợp?',
          body: 'Cứ chọn mẫu gần nhất rồi sửa tiêu đề và lời kể ở bước sau. Mẫu chỉ để điền sẵn cho nhanh.',
        ),
      ],
    );
  }

  Widget _detailStep(MetaConfig meta) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        const Text('Kể câu chuyện của bạn', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
        const SizedBox(height: 6),
        const Text('Càng cụ thể càng dễ được cứu. Đừng buồn quá, kể hài hài một chút.',
            style: TextStyle(color: V.muted, fontSize: 13.5, height: 1.5)),
        const SizedBox(height: 18),
        TextField(
          controller: _titleController,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Tiêu đề', counterText: ''),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _storyController,
          maxLines: 5,
          maxLength: 1200,
          decoration: const InputDecoration(
            labelText: 'Lời kể',
            alignLabelWithHint: true,
            counterText: '',
            hintText: 'Ví mình lép vì...',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Số tiền cần cứu',
            suffixText: 'đ',
            helperText: 'Từ ${money(meta.funModeAMin)} đến ${money(meta.funModeAMax)}',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [35000, 50000, 100000, 200000, 300000]
              .where((v) => v >= meta.funModeAMin && v <= meta.funModeAMax)
              .map((value) => ActionChip(
                    onPressed: () => setState(() => _amountController.text = '$value'),
                    label: Text(moneyShort(value), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    backgroundColor: _amount == value ? V.greenSoft : V.canvas,
                    side: BorderSide(color: _amount == value ? V.green : V.line),
                  ))
              .toList(),
        ),
        const SizedBox(height: 20),
        const Text('Hiển thị tên', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 8),
        Row(
          children: [
            _modeChip('nickname', 'Biệt danh'),
            const SizedBox(width: 8),
            _modeChip('real', 'Tên thật'),
            const SizedBox(width: 8),
            _modeChip('anonymous', 'Ẩn danh'),
          ],
        ),
        const SizedBox(height: 20),
        InfoCard(
          icon: Icons.info_outline_rounded,
          title: 'Vì sao cần chủ nợ xác nhận?',
          body: 'Ở chế độ A, chủ nợ mở link xác nhận khoản nợ và khai tài khoản nhận. '
              'Tiền giữ hộ và chuyển thẳng cho họ khi đủ mục tiêu — minh bạch cả hai phía.',
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: V.danger, fontSize: 13)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            setState(() {
              _error = null;
              _step = 2;
            });
          },
          child: const Text('Tiếp tục'),
        ),
      ],
    );
  }

  Widget _creditorStep(MetaConfig meta) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        const Text('Mời chủ nợ xác nhận', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
        const SizedBox(height: 6),
        const Text('Chủ nợ không cần cài app. Họ mở link, xác nhận bạn đúng là con nợ và khai tài khoản nhận tiền.',
            style: TextStyle(color: V.muted, fontSize: 13.5, height: 1.55)),
        const SizedBox(height: 20),
        TextField(
          controller: _creditorNameController,
          decoration: const InputDecoration(labelText: 'Tên chủ nợ', hintText: 'VD: Cô Lan quán cà phê'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _creditorPhoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Số điện thoại / Zalo', hintText: '0912345678'),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(16), border: Border.all(color: V.line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tóm tắt case', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 10),
              _row('Tiêu đề', _titleController.text),
              _row('Số tiền', money(_amount)),
              _row('Hạn gây quỹ', '30 ngày'),
              _row('Chế độ', 'A · trả thẳng chủ nợ'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        InfoCard(
          icon: Icons.timer_outlined,
          title: 'Chủ nợ có 72 giờ để xác nhận',
          body: 'Quá hạn mà chưa xác nhận, case tự huỷ và chưa có tiền nào bị giữ.',
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: V.danger, fontSize: 13)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _submitting ? null : () => _finish(meta),
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: V.ink))
              : const Text('Tạo case & lấy link mời'),
        ),
      ],
    );
  }

  Widget _successStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const Center(child: WalletMascot(progress: 0.12, size: 140)),
        const SizedBox(height: 16),
        const Text('Case đang chờ chủ nợ xác nhận',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.7)),
        const SizedBox(height: 8),
        const Text('Gửi link này cho chủ nợ. Khi họ bấm xác nhận, case tự mở gây quỹ và hiện trên feed.',
            textAlign: TextAlign.center, style: TextStyle(color: V.muted, fontSize: 13.5, height: 1.5)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(14), border: Border.all(color: V.line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Link xác nhận cho chủ nợ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: V.muted)),
              const SizedBox(height: 6),
              Text(_inviteUrl ?? '', style: const TextStyle(fontSize: 12, height: 1.45)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _inviteUrl ?? ''));
            if (!mounted) return;
            showSnack(context, 'Đã copy link mời chủ nợ');
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy link mời chủ nợ'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _shareUrl ?? _inviteUrl ?? ''));
            if (!mounted) return;
            showSnack(context, 'Đã copy link case để chia sẻ');
          },
          icon: const Icon(Icons.link_rounded, size: 18),
          label: const Text('Copy link case'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            if (_caseId != null) context.pushReplacement('/case/$_caseId');
          },
          child: const Text('Xem case của tôi'),
        ),
      ],
    );
  }

  Widget _modeChip(String value, String label) {
    final active = _displayMode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _displayMode = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? V.greenSoft : V.canvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? V.green : V.line),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active ? V.greenDark : V.muted,
              )),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: V.muted)),
          const Spacer(),
          Flexible(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  final DebtTemplate template;
  final VoidCallback onTap;

  const _TemplateTile({required this.template, required this.onTap});

  static const _tints = <String, String>{
    'tra-sua': '#F6D7CE',
    'nhau': '#F8DFA8',
    'ca-cuoc': '#C9E4F5',
    'an-uong': '#CDEBD9',
    'qua-sinh-nhat': '#E4D3F0',
    'muon-tien': '#CFE0FA',
  };

  @override
  Widget build(BuildContext context) {
    final tint = _tints[template.category] ?? '#D9F2E4';
    return PressableScale(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: V.surface,
          borderRadius: BorderRadius.circular(V.r20),
          border: Border.all(color: V.line),
          boxShadow: V.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 68,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: coverGradient(tint),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(V.r20)),
              ),
              child: Text(template.emoji, style: const TextStyle(fontSize: 32)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 36,
                    child: Text(
                      template.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, height: 1.28, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(money(template.amount),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: V.greenDark)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepProgress extends StatelessWidget {
  final int step;

  const _StepProgress({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: AnimatedContainer(
                duration: V.fast,
                height: 3,
                decoration: BoxDecoration(
                  color: i <= step ? V.green : V.line,
                  borderRadius: BorderRadius.circular(V.rPill),
                ),
              ),
            ),
          ],
          const SizedBox(width: 10),
          Text('${step + 1}/3', style: const TextStyle(fontSize: 10.5, color: V.muted, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
