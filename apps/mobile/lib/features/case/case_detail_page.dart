import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../state.dart';
import '../../widgets.dart';

class CaseDetailPage extends ConsumerWidget {
  final String caseId;

  const CaseDetailPage({super.key, required this.caseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(caseDetailProvider(caseId));

    return async.when(
      loading: () => const Scaffold(body: LoadingView(label: 'Đang mở case...')),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          emoji: '🧐',
          title: 'Không mở được case',
          body: error is ApiException ? error.message : '$error',
          actionLabel: 'Thử lại',
          onAction: () => ref.invalidate(caseDetailProvider(caseId)),
        ),
      ),
      data: (detail) => _CaseBody(detail: detail),
    );
  }
}

class _CaseBody extends ConsumerWidget {
  final CaseDetail detail;

  const _CaseBody({required this.detail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = detail.summary;
    final tint = colorFromHex(s.coverColor);
    final canSupport = s.canContribute && s.state == 'funding';

    return Scaffold(
      backgroundColor: V.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 250,
            backgroundColor: tint,
            surfaceTintColor: Colors.transparent,
            leading: _RoundIconButton(icon: Icons.arrow_back_rounded, onTap: () => context.canPop() ? context.pop() : context.go('/discover')),
            actions: [
              _RoundIconButton(icon: Icons.ios_share_rounded, onTap: () => _share(context, ref, s)),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [tint, Color.lerp(tint, Colors.white, 0.5)!],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -20,
                      bottom: -30,
                      child: Opacity(opacity: 0.35, child: Text(s.coverEmoji, style: const TextStyle(fontSize: 190))),
                    ),
                    Positioned(
                      left: 20,
                      bottom: 20,
                      child: Row(
                        children: [
                          ModeChip(confirmed: s.isModeA),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(999)),
                            child: Text('${s.coverEmoji} ${categoryLabel(s.category)}',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title, style: const TextStyle(fontSize: 27, height: 1.18, fontWeight: FontWeight.w800, letterSpacing: -0.9)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      AvatarBubble(name: s.debtor?.nickname ?? '?', avatarKey: s.debtor?.avatarKey ?? 'x', size: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.debtor?.nickname ?? 'Người giấu tên',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            Text('Người đăng case · ${s.contributorCount} người đã cứu',
                                style: const TextStyle(fontSize: 12, color: V.muted)),
                          ],
                        ),
                      ),
                      if (s.state == 'closed' || s.state == 'paid')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: V.greenSoft, borderRadius: BorderRadius.circular(999)),
                          child: Text(stateLabel(s.state),
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: V.greenDark)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _ProgressBlock(detail: detail),
                  const SizedBox(height: 18),
                  InfoCard(
                    icon: s.isModeA ? Icons.verified_user_outlined : Icons.receipt_long_outlined,
                    title: 'Tiền sẽ về đâu',
                    body: detail.moneyDestination,
                    tint: s.isModeA ? const Color(0xFFF2FFF8) : const Color(0xFFFFFBF2),
                    trailing: s.isModeA
                        ? const Icon(Icons.arrow_forward_rounded, size: 18, color: V.greenDark)
                        : null,
                  ),
                  if (s.isModeA) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline_rounded, size: 14, color: V.muted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Chủ nợ ${s.creditorName.isEmpty ? '' : '${s.creditorName} '}đã xác nhận khoản nợ'
                              '${detail.creditorBankMasked.isEmpty ? '' : ' · TK ${detail.creditorBankMasked}'}',
                              style: const TextStyle(fontSize: 12, color: V.muted, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  const SectionHeader(title: 'Câu chuyện'),
                  Text(detail.story, style: const TextStyle(fontSize: 15, height: 1.65, color: V.inkSoft)),
                  const SizedBox(height: 26),
                  SectionHeader(title: 'Tường người cứu nợ (${detail.contributors.length})'),
                  if (detail.contributors.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(16)),
                      child: const Text('Chưa có ai góp. Bạn là người đầu tiên cứu ví này? 💚',
                          style: TextStyle(fontSize: 13, color: V.muted)),
                    )
                  else
                    ...detail.contributors.reversed.take(30).map((c) => _ContributorRow(contributor: c)),
                  const SizedBox(height: 24),
                  if (detail.isPaid)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(16), border: Border.all(color: V.line)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.receipt_long_rounded, size: 16, color: V.greenDark),
                              SizedBox(width: 6),
                              Text('Chứng từ chuyển tiền', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Mã: ${detail.payoutReceiptRef ?? 'đang cập nhật'}',
                              style: const TextStyle(fontSize: 12, color: V.muted)),
                          if (detail.certificateCode != null) ...[
                            const SizedBox(height: 4),
                            Text('Giấy chứng nhận: ${detail.certificateCode}',
                                style: const TextStyle(fontSize: 12, color: V.muted)),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 18),
                  TextButton.icon(
                    onPressed: () => _report(context, ref),
                    icon: const Icon(Icons.flag_outlined, size: 16),
                    label: const Text('Báo cáo case này', style: TextStyle(fontSize: 12.5, color: V.muted)),
                  ),
                  const SizedBox(height: 110),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(detail: detail, canSupport: canSupport),
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref, CaseSummary s) async {
    final url = '${kApiBase}/share/${s.code}';
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chia sẻ case', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Link đã copy. Gửi qua Zalo, Messenger hoặc cho chủ nợ mở.',
                style: TextStyle(color: V.muted, fontSize: 13)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(12)),
              child: Text(url, style: const TextStyle(fontSize: 12, color: V.inkSoft)),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () async {
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Mở trang chia sẻ'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final svg = '${kApiBase}/api/v1/cases/${s.id}/share-card.svg';
                final uri = Uri.parse(svg);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Mở thẻ meme'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      context.push('/login?next=${Uri.encodeComponent('/case/${detail.summary.id}')}');
      return;
    }
    final reasons = ['Thông tin sai sự thật', 'Nội dung xúc phạm', 'Nghi ngờ gian lận', 'Spam / quảng cáo', 'Khác'];
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Báo cáo case'),
        children: reasons
            .map((reason) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, reason),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(reason),
                  ),
                ))
            .toList(),
      ),
    );
    if (selected == null || !context.mounted) return;
    try {
      await ref.read(apiProvider).post('/api/v1/reports', body: {
        'targetType': 'case',
        'targetId': detail.summary.id,
        'reason': selected,
        'details': '',
      });
      if (!context.mounted) return;
      showSnack(context, 'Đã gửi báo cáo. Đội kiểm duyệt sẽ xem xét.');
    } on ApiException catch (e) {
      if (!context.mounted) return;
      showSnack(context, e.message, error: true);
    }
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.92),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 19, color: V.ink)),
        ),
      ),
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  final CaseDetail detail;

  const _ProgressBlock({required this.detail});

  @override
  Widget build(BuildContext context) {
    final s = detail.summary;
    final remaining = detail.remaining;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(money(s.raisedAmount),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1)),
            Padding(
              padding: const EdgeInsets.only(bottom: 5, left: 6),
              child: Text('đã góp / ${money(s.targetAmount)}',
                  style: const TextStyle(fontSize: 13, color: V.muted)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        WalletProgress(percent: s.percent, height: 12),
        const SizedBox(height: 10),
        Row(
          children: [
            Text('${s.percent}%',
                style: const TextStyle(fontWeight: FontWeight.w800, color: V.greenDark, fontSize: 14)),
            const Spacer(),
            if (s.state == 'funding')
              Text('còn ${money(remaining)} là chạm đích',
                  style: const TextStyle(fontSize: 12.5, color: V.muted, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _Metric(icon: Icons.people_alt_outlined, label: '${s.contributorCount} người cứu'),
            const SizedBox(width: 18),
            _Metric(icon: Icons.schedule_rounded, label: relativeDeadline(s.daysLeft)),
            const SizedBox(width: 18),
            _Metric(icon: Icons.shield_outlined, label: s.isModeA ? 'Escrow an toàn' : 'Cần bằng chứng'),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Metric({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: V.muted),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12, color: V.muted, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _ContributorRow extends StatelessWidget {
  final Contributor contributor;

  const _ContributorRow({required this.contributor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarBubble(name: contributor.name, avatarKey: contributor.avatarKey, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(contributor.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    ),
                    if (contributor.isLastToClose) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFFFF3D6), borderRadius: BorderRadius.circular(6)),
                        child: const Text('Người chốt hạ',
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFFA66A00))),
                      ),
                    ],
                  ],
                ),
                if (contributor.message != null && contributor.message!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '${contributor.sticker ?? ''} ${contributor.message}'.trim(),
                      style: const TextStyle(fontSize: 13, height: 1.45, color: V.inkSoft),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('${money(contributor.amount)} · ${timeAgo(contributor.createdAt)}',
                      style: const TextStyle(fontSize: 11.5, color: V.muted)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  final CaseDetail detail;
  final bool canSupport;

  const _BottomBar({required this.detail, required this.canSupport});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = detail.summary;
    return Container(
      decoration: const BoxDecoration(
        color: V.surface,
        border: Border(top: BorderSide(color: V.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              if (s.state == 'funding')
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(money(detail.remaining), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const Text('còn thiếu', style: TextStyle(fontSize: 11.5, color: V.muted)),
                    ],
                  ),
                )
              else
                const Spacer(),
              SizedBox(
                width: 240,
                child: FilledButton(
                  onPressed: () async {
                    if (!ref.read(authProvider).isLoggedIn) {
                      context.push('/login?next=${Uri.encodeComponent('/case/${s.id}')}');
                      return;
                    }
                    if (canSupport) {
                      final ok = await showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (context) => ContributeSheet(detail: detail),
                      );
                      if (ok == true) {
                        ref.invalidate(caseDetailProvider(s.id));
                        ref.invalidate(feedProvider);
                      }
                    } else if (s.state == 'closed' || s.state == 'paid') {
                      context.push('/certificate/${s.id}');
                    } else {
                      showSnack(context, 'Case đang ở trạng thái: ${stateLabel(s.state)}');
                    }
                  },
                  child: Text(
                    canSupport
                        ? 'Cứu khoản nợ này'
                        : s.state == 'closed' || s.state == 'paid'
                            ? 'Xem giấy chứng nhận'
                            : stateLabel(s.state),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ContributeSheet extends ConsumerStatefulWidget {
  final CaseDetail detail;

  const ContributeSheet({super.key, required this.detail});

  @override
  ConsumerState<ContributeSheet> createState() => _ContributeSheetState();
}

class _ContributeSheetState extends ConsumerState<ContributeSheet> {
  final _customController = TextEditingController();
  final _messageController = TextEditingController();

  int _amount = 0;
  int _tip = 0;
  bool _anonymous = false;
  bool _submitting = false;
  bool _done = false;
  bool _paid = false;
  String? _error;
  ContributionCreated? _created;
  String? _successState;

  int get _max => widget.detail.remaining > 0 ? widget.detail.remaining : widget.detail.summary.targetAmount;

  @override
  void initState() {
    super.initState();
    _amount = [20000, 35000, 50000, 100000]
        .firstWhere((value) => value >= widget.detail.minContribution && value <= _max, orElse: () => widget.detail.minContribution)
        .clamp(widget.detail.minContribution, _max == 0 ? widget.detail.minContribution : _max);
  }

  @override
  void dispose() {
    _customController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_amount < widget.detail.minContribution) {
      setState(() => _error = 'Tối thiểu ${money(widget.detail.minContribution)}');
      return;
    }
    if (_amount > _max) {
      setState(() => _error = 'Case chỉ còn thiếu ${money(_max)}');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiProvider).post(
        '/api/v1/cases/${widget.detail.summary.id}/contributions',
        idempotencyKey: randomIdempotencyKey(),
        body: {
          'amount': _amount,
          'tipAmount': _tip,
          'anonymous': _anonymous,
          'message': _messageController.text.trim().isEmpty ? null : _messageController.text.trim(),
          'sticker': '🧋',
        },
      ) as Map<String, dynamic>;
      setState(() {
        _created = ContributionCreated.fromJson(data);
        _done = true;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _simulatePay() async {
    final created = _created;
    if (created == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiProvider).post('/api/v1/dev/pay/${created.contributionId}') as Map<String, dynamic>;
      setState(() {
        _paid = true;
        _successState = data['caseState'] as String?;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, bottom: 20 + bottomInset),
      child: _paid ? _paidView() : (_done ? _checkoutView() : _formView()),
    );
  }

  Widget _formView() {
    final quick = [20000, 35000, 50000, 100000, 200000].where((v) => v <= _max && v >= widget.detail.minContribution).toList();
    final total = _amount + _tip;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Cứu ví lép', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
              const Spacer(),
              Text('còn ${money(_max)}', style: const TextStyle(fontSize: 12, color: V.muted)),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Nhập số tiền bạn muốn góp. Tiền vào giữ hộ, chuyển cho chủ nợ khi đủ mục tiêu.',
              style: TextStyle(fontSize: 12.5, color: V.muted, height: 1.45)),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...quick.map((value) => _AmountChip(
                    label: moneyShort(value),
                    selected: _amount == value,
                    onTap: () => setState(() {
                      _amount = value;
                      _customController.clear();
                    }),
                  )),
              _AmountChip(
                label: 'Khác',
                selected: !quick.contains(_amount),
                onTap: () => setState(() => _amount = 0),
              ),
            ],
          ),
          if (!quick.contains(_amount)) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customController,
              keyboardType: TextInputType.number,
              onChanged: (value) => setState(() => _amount = int.tryParse(value.replaceAll(RegExp(r'\D'), '')) ?? 0),
              decoration: const InputDecoration(labelText: 'Số tiền khác', hintText: 'VD: 15000', suffixText: 'đ'),
            ),
          ],
          const SizedBox(height: 20),
          const Text('Tip cho Ví Lép (tự nguyện)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          const Text('Không bắt buộc, có thể để 0. Tip được ghi riêng, không lẫn vào tiền xoá nợ.',
              style: TextStyle(fontSize: 11.5, color: V.muted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [0, 5000, 10000, 20000]
                .map((value) => _AmountChip(
                      label: value == 0 ? 'Không tip' : moneyShort(value),
                      selected: _tip == value,
                      onTap: () => setState(() => _tip = value),
                    ))
                .toList(),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _messageController,
            maxLength: 140,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Lời nhắn (tuỳ chọn)',
              hintText: 'Cứu ví lép, cứu luôn tuổi trẻ!',
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            value: _anonymous,
            onChanged: (value) => setState(() => _anonymous = value),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: V.green,
            title: const Text('Góp ẩn danh', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            subtitle: const Text('Tên của bạn sẽ không hiện trên tường người cứu nợ',
                style: TextStyle(fontSize: 11.5, color: V.muted)),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                _line('Tiền xoá nợ', money(_amount)),
                const SizedBox(height: 6),
                _line('Tip cho Ví Lép', money(_tip)),
                const SizedBox(height: 6),
                _line('Phí xử lý', '0đ'),
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
                _line('Tổng thanh toán', money(total), bold: true),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: V.danger, fontSize: 12.5)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: V.ink))
                  : Text('Tiếp tục · ${money(total)}'),
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text('Thanh toán qua cổng đối tác · dữ liệu được mã hoá',
                style: TextStyle(fontSize: 10.5, color: V.muted)),
          ),
        ],
      ),
    );
  }

  Widget _checkoutView() {
    final created = _created!;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quét QR để thanh toán', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
          const SizedBox(height: 4),
          Text('Số tiền ${money(created.total)} · ${created.provider == 'mock' ? 'cổng sandbox' : created.provider}',
              style: const TextStyle(fontSize: 12.5, color: V.muted)),
          const SizedBox(height: 18),
          Center(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: V.line),
              ),
              child: Column(
                children: [
                  _QrPlaceholder(payload: created.qrPayload),
                  const SizedBox(height: 12),
                  Text(created.qrPayload, style: const TextStyle(fontSize: 9.5, color: V.muted)),
                  const SizedBox(height: 6),
                  Text('Mã GD: ${created.contributionId.substring(0, 8).toUpperCase()}',
                      style: const TextStyle(fontSize: 10, color: V.muted, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFFFF8E6), borderRadius: BorderRadius.circular(14)),
            child: const Row(
              children: [
                Icon(Icons.science_outlined, size: 18, color: Color(0xFFB26A00)),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Đây là cổng thanh toán giả lập cho bản MVP. Bấm nút bên dưới để mô phỏng webhook thành công.',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF8A5200), height: 1.45)),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: V.danger, fontSize: 12.5)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _simulatePay,
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: V.ink))
                  : const Text('Tôi đã chuyển khoản'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Để sau'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paidView() {
    final funded = _successState == 'paid' || _successState == 'funded';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        ConfettiBurst(child: WalletMascot(progress: funded ? 1 : 0.7, size: 130)),
        const SizedBox(height: 16),
        Text(funded ? 'Ví đã phồng! 🎉' : 'Đã ghi nhận khoản góp 💚',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.7)),
        const SizedBox(height: 8),
        Text(
          funded
              ? 'Case đã đủ tiền. Ví Lép sẽ chuyển thẳng cho chủ nợ và bạn sẽ nhận thông báo khi hoàn tất.'
              : 'Cảm ơn bạn! Khoản góp đã vào giữ hộ, tiền chỉ chuyển cho chủ nợ khi case đủ mục tiêu.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: V.muted, fontSize: 13.5, height: 1.5),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(funded ? 'Tuyệt vời' : 'Đóng'),
          ),
        ),
      ],
    );
  }

  Widget _line(String label, String value, {bool bold = false}) {
    return Row(
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: bold ? V.ink : V.muted, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
        const Spacer(),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
      ],
    );
  }
}

class _AmountChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AmountChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? V.green : V.canvas,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? V.green : V.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: selected ? const Color(0xFF04170E) : V.inkSoft,
          ),
        ),
      ),
    );
  }
}

class _QrPlaceholder extends StatelessWidget {
  final String payload;

  const _QrPlaceholder({required this.payload});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      height: 168,
      child: CustomPaint(painter: _QrPainter(payload)),
    );
  }
}

class _QrPainter extends CustomPainter {
  final String payload;

  _QrPainter(this.payload);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.white);
    const modules = 21;
    final cell = size.width / modules;
    final seed = payload.codeUnits.fold<int>(7, (acc, c) => (acc * 31 + c) & 0x7fffffff);
    final paint = Paint()..color = V.ink;
    for (var y = 0; y < modules; y++) {
      for (var x = 0; x < modules; x++) {
        final value = (seed >> ((x * 3 + y * 7) % 24)) & 1;
        final pseudo = ((x * 31 + y * 17 + seed) % 5) < 2 || value == 1;
        final finder = (x < 7 && y < 7) || (x > 13 && y < 7) || (x < 7 && y > 13);
        if (finder) {
          final isBorder = x == 0 || y == 0 || x == 6 || y == 6 || x == 14 || y == 14 || x == 20 || y == 20;
          final inCorner = (x < 7 && y < 7) || (x >= 14 && y < 7) || (x < 7 && y >= 14);
          if (inCorner) {
            final localX = x < 7 ? x : x - 14;
            final localY = y < 7 ? y : y - 14;
            final ring = localX == 0 || localY == 0 || localX == 6 || localY == 6;
            final core = localX >= 2 && localX <= 4 && localY >= 2 && localY <= 4;
            if (ring || core) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
            continue;
          }
          if (!isBorder) continue;
        }
        if (pseudo) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) => oldDelegate.payload != payload;
}
