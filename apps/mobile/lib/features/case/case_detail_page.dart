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
      loading: () => const Scaffold(body: CaseDetailSkeleton()),
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
      body: PageFrame(
        child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 284,
            backgroundColor: tint,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leadingWidth: 64,
            leading: Padding(
              padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
              child: _RoundIconButton(icon: Icons.arrow_back_rounded, onTap: () => context.canPop() ? context.pop() : context.go('/discover')),
            ),
            actions: [
              _RoundIconButton(icon: Icons.ios_share_rounded, onTap: () => _share(context, ref, s)),
              const SizedBox(width: 16),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: Hero(
                tag: 'cover-${s.id}',
                child: Container(
                  decoration: BoxDecoration(gradient: coverGradient(s.coverColor, deep: true)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        left: -120,
                        top: -160,
                        child: Container(
                          width: 320,
                          height: 320,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0)]),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 4,
                        bottom: 52,
                        child: Text(s.coverEmoji, style: const TextStyle(fontSize: 128)),
                      ),
                      // readability scrim at the bottom of the hero
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 130,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.32)],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        bottom: 42,
                        child: Row(
                          children: [
                            ModeChip(confirmed: s.isModeA),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(V.rPill),
                              ),
                              child: Text('${s.coverEmoji} ${categoryLabel(s.category)}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: V.ink)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 40,
                  child: DecoratedBox(decoration: BoxDecoration(gradient: coverGradient(s.coverColor, deep: true))),
                ),
                Container(
                margin: const EdgeInsets.only(top: 26),
                decoration: const BoxDecoration(
                  color: V.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(stateLabel(s.state).toUpperCase(),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: s.state == 'funding' ? V.greenDark : V.muted,
                            )),
                        const SizedBox(width: 8),
                        if (s.state == 'funding') ...[
                          const Icon(Icons.circle, size: 5, color: V.faint),
                          const SizedBox(width: 8),
                          Text(relativeDeadline(s.daysLeft), style: const TextStyle(fontSize: 11, color: V.muted)),
                        ],
                        const Spacer(),
                        Text('Mã ${s.code.toUpperCase()}',
                            style: const TextStyle(fontSize: 10.5, color: V.faint, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(s.title,
                        style: const TextStyle(fontSize: 27, height: 1.16, fontWeight: FontWeight.w800, letterSpacing: -1.0)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        AvatarBubble(name: s.debtor?.nickname ?? '?', avatarKey: s.debtor?.avatarKey ?? 'x', size: 36),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.debtor?.nickname ?? 'Người giấu tên',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                              Text('Người đăng · ${s.contributorCount} người đã cứu',
                                  style: const TextStyle(fontSize: 11.5, color: V.muted)),
                            ],
                          ),
                        ),
                        if (s.state == 'closed' || s.state == 'paid')
                          GestureDetector(
                            onTap: () => context.push('/certificate/${s.id}'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: V.greenSoft, borderRadius: BorderRadius.circular(V.rPill)),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.workspace_premium_rounded, size: 14, color: V.greenDark),
                                  SizedBox(width: 4),
                                  Text('Chứng nhận',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: V.greenDark)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _FundingPanel(detail: detail),
                    const SizedBox(height: 18),
                    InfoCard(
                      icon: s.isModeA ? Icons.verified_user_outlined : Icons.receipt_long_outlined,
                      title: 'Tiền sẽ về đâu',
                      body: detail.moneyDestination,
                      tint: s.isModeA ? const Color(0xFFF4FFF9) : V.amberSoft,
                      iconColor: s.isModeA ? V.greenDark : const Color(0xFF9A6400),
                      trailing: Icon(Icons.arrow_forward_rounded, size: 18, color: s.isModeA ? V.greenDark : const Color(0xFF9A6400)),
                    ),
                    const SizedBox(height: 12),
                    _TrustStrip(detail: detail),
                    const SizedBox(height: 30),
                    const SectionHeader(title: 'Câu chuyện'),
                    Text(detail.story, style: const TextStyle(fontSize: 15, height: 1.7, color: V.ink2)),
                    const SizedBox(height: 30),
                    SectionHeader(
                      title: 'Người đã cứu',
                      subtitle: '${detail.contributors.length} người góp · minh bạch từng khoản',
                    ),
                    if (detail.contributors.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(V.r16)),
                        child: const Text('Chưa có ai góp. Bạn là người đầu tiên cứu ví này? 💚',
                            style: TextStyle(fontSize: 13, color: V.muted, height: 1.5)),
                      )
                    else ...[
                      _ContributorStack(contributors: detail.contributors),
                      const SizedBox(height: 14),
                      ...detail.contributors.reversed.take(30).map((c) => _ContributorRow(contributor: c)),
                    ],
                    const SizedBox(height: 22),
                    if (detail.isPaid) _ReceiptBlock(detail: detail),
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => _report(context, ref),
                        icon: const Icon(Icons.flag_outlined, size: 15),
                        label: const Text('Báo cáo case này', style: TextStyle(fontSize: 12, color: V.muted)),
                      ),
                    ),
                    const SizedBox(height: 120),
                  ],
                ),
              ),
              ],
            ),
          ),
        ],
      ),
      ),
      bottomNavigationBar: _BottomBar(detail: detail, canSupport: canSupport),
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref, CaseSummary s) async {
    final url = '$kApiBase/share/${s.code}';
    await Clipboard.setData(ClipboardData(text: url));
    HapticFeedback.selectionClick();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: V.line, borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const Text('Chia sẻ case', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
            const SizedBox(height: 6),
            const Text('Link đã copy. Gửi qua Zalo, Messenger hoặc cho chủ nợ mở.',
                style: TextStyle(color: V.muted, fontSize: 13, height: 1.5)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(V.r12)),
              child: Text(url, style: const TextStyle(fontSize: 12, color: V.ink2)),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () async {
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Mở trang chia sẻ'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse('$kApiBase/api/v1/cases/${s.id}/share-card.svg');
                if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 19, color: V.ink)),
      ),
    );
  }
}

class _FundingPanel extends StatelessWidget {
  final CaseDetail detail;

  const _FundingPanel({required this.detail});

  @override
  Widget build(BuildContext context) {
    final s = detail.summary;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: V.surface,
        borderRadius: BorderRadius.circular(V.r20),
        border: Border.all(color: V.line),
        boxShadow: V.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyCounter(
                amount: s.raisedAmount,
                style: const TextStyle(fontSize: 31, fontWeight: FontWeight.w800, letterSpacing: -1.4, height: 1),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 8),
                child: Text('đã góp / ${money(s.targetAmount)}',
                    style: const TextStyle(fontSize: 12.5, color: V.muted, fontWeight: FontWeight.w500)),
              ),
              const Spacer(),
              PercentPill(percent: s.percent),
            ],
          ),
          const SizedBox(height: 14),
          WalletProgress(percent: s.percent, height: 10),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(s.state == 'funding' ? Icons.trending_up_rounded : Icons.check_circle_rounded,
                  size: 14, color: V.greenDark),
              const SizedBox(width: 5),
              Text(
                s.state == 'funding' ? 'Còn ${money(detail.remaining)} là chạm đích' : 'Đã chạm đích ${money(s.targetAmount)}',
                style: const TextStyle(fontSize: 12, color: V.ink2, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              const Icon(Icons.schedule_rounded, size: 13, color: V.faint),
              const SizedBox(width: 3),
              Text(relativeDeadline(s.daysLeft), style: const TextStyle(fontSize: 11.5, color: V.muted)),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              _Metric(icon: Icons.people_alt_outlined, value: '${s.contributorCount}', label: 'người cứu'),
              _dividerDot(),
              _Metric(icon: Icons.shield_outlined, value: s.isModeA ? 'An toàn' : 'Bằng chứng', label: s.isModeA ? 'escrow' : 'bắt buộc'),
              _dividerDot(),
              _Metric(icon: Icons.payments_outlined, value: moneyShort(s.targetAmount), label: 'mục tiêu'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dividerDot() => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        color: V.line,
      );
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _Metric({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 15, color: V.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                Text(label, style: const TextStyle(fontSize: 9.5, color: V.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustStrip extends StatelessWidget {
  final CaseDetail detail;

  const _TrustStrip({required this.detail});

  @override
  Widget build(BuildContext context) {
    final s = detail.summary;
    if (!s.isModeA) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: V.amberSoft, borderRadius: BorderRadius.circular(V.r14)),
        child: Row(
          children: [
            const Icon(Icons.receipt_long_rounded, size: 16, color: Color(0xFF9A6400)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Case chế độ B: tiền về ví con nợ, mở khoá theo bằng chứng trả nợ.',
                style: TextStyle(fontSize: 11.5, color: const Color(0xFF9A6400).withValues(alpha: 0.95), height: 1.45),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(V.r14), border: Border.all(color: V.line)),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(color: V.surface, shape: BoxShape.circle),
            child: const Icon(Icons.lock_outline_rounded, size: 15, color: V.ink2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Chủ nợ ${s.creditorName} đã xác nhận khoản nợ',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: -0.1)),
                const SizedBox(height: 2),
                Text(
                  detail.creditorBankMasked.isEmpty
                      ? 'Tiền chỉ chuyển cho tài khoản chủ nợ đã khai, đúng một lần.'
                      : 'Tài khoản nhận ${detail.creditorBankMasked} · chuyển đúng một lần khi đủ mục tiêu.',
                  style: const TextStyle(fontSize: 10.5, color: V.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContributorStack extends StatelessWidget {
  final List<Contributor> contributors;

  const _ContributorStack({required this.contributors});

  @override
  Widget build(BuildContext context) {
    final shown = contributors.take(5).toList();
    return Row(
      children: [
        SizedBox(
          width: 22.0 + (shown.length - 1) * 16,
          height: 30,
          child: Stack(
            children: [
              for (var i = 0; i < shown.length; i++)
                Positioned(
                  left: i * 16,
                  child: AvatarBubble(
                    name: shown[i].name,
                    avatarKey: shown[i].avatarKey,
                    size: 30,
                    ring: true,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            contributors.length == 1
                ? '${contributors.first.name} là người đầu tiên'
                : '${contributors.first.name} và ${contributors.length - 1} người khác đã góp',
            style: const TextStyle(fontSize: 12, color: V.muted, fontWeight: FontWeight.w500),
          ),
        ),
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarBubble(name: contributor.name, avatarKey: contributor.avatarKey, size: 36),
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
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                    if (contributor.isLastToClose) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: V.amberSoft, borderRadius: BorderRadius.circular(6)),
                        child: const Text('Người chốt hạ',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF9A6400))),
                      ),
                    ],
                    const Spacer(),
                    Text(money(contributor.amount), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  ],
                ),
                if (contributor.message != null && contributor.message!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${contributor.sticker ?? ''} ${contributor.message}'.trim(),
                      style: const TextStyle(fontSize: 12.5, height: 1.45, color: V.ink2),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(timeAgo(contributor.createdAt), style: const TextStyle(fontSize: 10.5, color: V.faint)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptBlock extends StatelessWidget {
  final CaseDetail detail;

  const _ReceiptBlock({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: V.greenSoft.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(V.r16),
        border: Border.all(color: const Color(0xFFCFEFDF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_rounded, size: 15, color: V.greenDark),
              SizedBox(width: 6),
              Text('Chứng từ chuyển tiền', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 8),
          Text('Mã giao dịch: ${detail.payoutReceiptRef ?? 'đang cập nhật'}',
              style: const TextStyle(fontSize: 11.5, color: V.muted, height: 1.5)),
          if (detail.certificateCode != null)
            Text('Giấy chứng nhận: ${detail.certificateCode}',
                style: const TextStyle(fontSize: 11.5, color: V.muted, height: 1.5)),
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
      decoration: BoxDecoration(
        color: V.surface,
        border: const Border(top: BorderSide(color: V.line)),
        boxShadow: V.floatingShadow,
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
                      Text(money(detail.remaining),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: -0.4)),
                      const Text('còn thiếu để chạm đích', style: TextStyle(fontSize: 10.5, color: V.muted)),
                    ],
                  ),
                )
              else
                const Spacer(),
              SizedBox(
                width: 236,
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
    final presets = [20000, 35000, 50000, 100000, 200000].where((v) => v <= _max && v >= widget.detail.minContribution).toList();
    _amount = presets.isNotEmpty
        ? presets.first
        : (_max >= widget.detail.minContribution ? _max : widget.detail.minContribution);
  }

  @override
  void dispose() {
    _customController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    HapticFeedback.selectionClick();
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
      HapticFeedback.mediumImpact();
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
      padding: EdgeInsets.only(left: 20, right: 20, bottom: 20 + bottomInset + MediaQuery.paddingOf(context).bottom),
      child: _paid ? _paidView() : (_done ? _checkoutView() : _formView()),
    );
  }

  Widget _handle() => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(color: V.line, borderRadius: BorderRadius.circular(99)),
        ),
      );

  Widget _formView() {
    final presets = [20000, 35000, 50000, 100000, 200000].where((v) => v <= _max && v >= widget.detail.minContribution).toList();
    final total = _amount + _tip;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _handle(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cứu ví lép', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.7)),
                    SizedBox(height: 3),
                    Text('Tiền vào giữ hộ, chuyển cho chủ nợ khi đủ mục tiêu.',
                        style: TextStyle(fontSize: 12, color: V.muted, height: 1.45)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(V.rPill)),
                child: Text('còn ${moneyShort(_max)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: V.ink2)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...presets.map((value) => _AmountChip(
                    label: moneyShort(value),
                    selected: _amount == value,
                    onTap: () => setState(() {
                      _amount = value;
                      _customController.clear();
                    }),
                  )),
              _AmountChip(
                label: 'Khác',
                selected: !presets.contains(_amount),
                onTap: () => setState(() => _amount = 0),
              ),
              if (_max >= widget.detail.minContribution)
                _AmountChip(
                  label: 'Đủ phần còn thiếu',
                  selected: _amount == _max,
                  onTap: () => setState(() {
                    _amount = _max;
                    _customController.clear();
                  }),
                  emphasis: true,
                ),
            ],
          ),
          if (!presets.contains(_amount) && _amount != _max) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customController,
              keyboardType: TextInputType.number,
              onChanged: (value) => setState(() => _amount = int.tryParse(value.replaceAll(RegExp(r'\D'), '')) ?? 0),
              decoration: const InputDecoration(labelText: 'Số tiền khác', hintText: 'VD: 15000', suffixText: 'đ'),
            ),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              const Text('Tip cho Ví Lép', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('tự nguyện', style: TextStyle(fontSize: 11, color: V.faint, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text('không bắt buộc', style: TextStyle(fontSize: 10.5, color: V.faint)),
            ],
          ),
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
          const SizedBox(height: 4),
          SwitchListTile.adaptive(
            value: _anonymous,
            onChanged: (value) => setState(() => _anonymous = value),
            contentPadding: EdgeInsets.zero,
            title: const Text('Góp ẩn danh', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            subtitle: const Text('Tên của bạn sẽ không hiện trên tường người cứu nợ',
                style: TextStyle(fontSize: 11, color: V.muted)),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: V.canvas, borderRadius: BorderRadius.circular(V.r16)),
            child: Column(
              children: [
                _line('Tiền xoá nợ', money(_amount)),
                const SizedBox(height: 7),
                _line('Tip cho Ví Lép', money(_tip)),
                const SizedBox(height: 7),
                _line('Phí xử lý', '0đ'),
                const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
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
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: V.greenInk))
                  : Text('Tiếp tục · ${money(total)}'),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('Thanh toán qua cổng đối tác · dữ liệu được mã hoá',
                style: TextStyle(fontSize: 10, color: V.faint)),
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
          _handle(),
          const Text('Quét QR để thanh toán', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.7)),
          const SizedBox(height: 4),
          Text('Số tiền ${money(created.total)} · ${created.provider == 'mock' ? 'cổng sandbox' : created.provider}',
              style: const TextStyle(fontSize: 12.5, color: V.muted)),
          const SizedBox(height: 18),
          Center(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(V.r20),
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
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: V.amberSoft, borderRadius: BorderRadius.circular(V.r14)),
            child: const Row(
              children: [
                Icon(Icons.science_outlined, size: 17, color: Color(0xFF9A6400)),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Cổng thanh toán giả lập cho bản MVP. Bấm nút bên dưới để mô phỏng webhook thành công.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF8A5200), height: 1.45)),
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
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: V.greenInk))
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
        _handle(),
        ConfettiBurst(child: WalletMascot(progress: funded ? 1 : 0.7, size: 132)),
        const SizedBox(height: 16),
        Text(funded ? 'Ví đã phồng! 🎉' : 'Đã ghi nhận khoản góp 💚',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.7)),
        const SizedBox(height: 8),
        Text(
          funded
              ? 'Case đã đủ tiền. Ví Lép chuyển thẳng cho chủ nợ và bạn sẽ nhận thông báo khi hoàn tất.'
              : 'Cảm ơn bạn! Khoản góp đã vào giữ hộ, tiền chỉ chuyển cho chủ nợ khi case đủ mục tiêu.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: V.muted, fontSize: 13, height: 1.55),
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
        Text(label,
            style: TextStyle(
                fontSize: 12.5, color: bold ? V.ink : V.muted, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
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
  final bool emphasis;

  const _AmountChip({required this.label, required this.selected, required this.onTap, this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: V.fast,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? V.green : (emphasis ? V.greenSoft : V.canvas),
          borderRadius: BorderRadius.circular(V.rPill),
          border: Border.all(color: selected ? V.green : (emphasis ? const Color(0xFFCBEFDD) : V.line)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? V.greenInk : (emphasis ? V.greenDark : V.ink2),
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
          final inCorner = (x < 7 && y < 7) || (x >= 14 && y < 7) || (x < 7 && y >= 14);
          if (inCorner) {
            final localX = x < 7 ? x : x - 14;
            final localY = y < 7 ? y : y - 14;
            final ring = localX == 0 || localY == 0 || localX == 6 || localY == 6;
            final core = localX >= 2 && localX <= 4 && localY >= 2 && localY <= 4;
            if (ring || core) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
            continue;
          }
        }
        if (pseudo) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) => oldDelegate.payload != payload;
}
