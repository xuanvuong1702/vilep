import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'core/format.dart';
import 'core/models.dart';
import 'core/theme.dart';

class AvatarBubble extends StatelessWidget {
  final String name;
  final String avatarKey;
  final double size;

  const AvatarBubble({super.key, required this.name, required this.avatarKey, this.size = 36});

  static const _palettes = [
    [Color(0xFFCDB4DB), Color(0xFF8E7DBE)],
    [Color(0xFFB7E4C7), Color(0xFF74C69D)],
    [Color(0xFFFFD166), Color(0xFFF2A03D)],
    [Color(0xFFA2D2FF), Color(0xFF5B9BD5)],
    [Color(0xFFFFB4A2), Color(0xFFE07A5F)],
    [Color(0xFFD0F4DE), Color(0xFF57CC99)],
  ];

  @override
  Widget build(BuildContext context) {
    final palette = _palettes[avatarKey.hashCode.abs() % _palettes.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: palette, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

/// The Ví Lép mascot: a sad flat wallet that puffs up as the case fills.
class WalletMascot extends StatelessWidget {
  final double progress; // 0..1
  final double size;
  final bool angry;

  const WalletMascot({super.key, required this.progress, this.size = 120, this.angry = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.8,
      child: CustomPaint(painter: _WalletPainter(progress.clamp(0.0, 1.0), angry)),
    );
  }
}

class _WalletPainter extends CustomPainter {
  final double progress;
  final bool angry;

  _WalletPainter(this.progress, this.angry);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.78;
    final h = size.width * (0.58 + progress * 0.16);
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;
    final rect = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, h), Radius.circular(w * 0.14));

    final body = Paint()..color = const Color(0xFF1B1B1B);
    canvas.drawRRect(rect, body);

    // belly (green pouch filling up)
    final pad = w * 0.06;
    final bellyRect = Rect.fromLTWH(left + pad, top + h * 0.4, w - pad * 2, h * 0.54);
    final belly = RRect.fromRectAndRadius(bellyRect, Radius.circular(w * 0.1));
    canvas.save();
    canvas.clipRRect(belly);
    final fillHeight = bellyRect.height * (0.12 + progress * 0.88);
    canvas.drawRect(
      Rect.fromLTWH(bellyRect.left, bellyRect.bottom - fillHeight, bellyRect.width, fillHeight),
      Paint()..color = V.green,
    );
    canvas.restore();

    // clasp
    final claspW = w * 0.22;
    final clasp = RRect.fromRectAndRadius(
      Rect.fromLTWH(left + w * 0.8, top + h * 0.38, w * 0.22, h * 0.22),
      Radius.circular(claspW * 0.25),
    );
    canvas.drawRRect(clasp, Paint()..color = V.green);
    canvas.drawCircle(
      Offset(clasp.center.dx, clasp.center.dy),
      claspW * 0.08,
      Paint()..color = const Color(0xFF04170E),
    );

    // eyes
    final eyeY = top + h * 0.2;
    final eyePaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(left + w * 0.3, eyeY), w * 0.045, eyePaint);
    canvas.drawCircle(Offset(left + w * 0.56, eyeY), w * 0.045, eyePaint);

    // mouth: frown when empty, grin when full
    final mouth = Path();
    final cx = left + w * 0.43;
    final my = top + h * 0.31;
    if (angry) {
      mouth.moveTo(cx - w * 0.07, my);
      mouth.lineTo(cx + w * 0.07, my);
    } else if (progress > 0.85) {
      mouth.moveTo(cx - w * 0.08, my - h * 0.01);
      mouth.quadraticBezierTo(cx, my + h * 0.07, cx + w * 0.08, my - h * 0.01);
    } else {
      mouth.moveTo(cx - w * 0.07, my + h * 0.03);
      mouth.quadraticBezierTo(cx, my - h * 0.03, cx + w * 0.07, my + h * 0.03);
    }
    canvas.drawPath(
      mouth,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.018
        ..strokeCap = StrokeCap.round,
    );

    // shine
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left + w * 0.1, top + h * 0.08, w * 0.12, h * 0.06), const Radius.circular(8)),
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(covariant _WalletPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.angry != angry;
}

class WalletProgress extends StatelessWidget {
  final int percent;
  final double height;
  final Color? color;

  const WalletProgress({super.key, required this.percent, this.height = 10, this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Container(height: height, color: const Color(0xFFEDEDEA)),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: percent.clamp(0, 100) / 100),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value <= 0 ? 0.001 : value,
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: color ?? V.green,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ModeChip extends StatelessWidget {
  final bool confirmed;
  final bool compact;

  const ModeChip({super.key, required this.confirmed, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 4 : 6),
      decoration: BoxDecoration(
        color: confirmed ? const Color(0xFFE9FBF2) : const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            confirmed ? Icons.verified_rounded : Icons.receipt_long_rounded,
            size: compact ? 11 : 13,
            color: confirmed ? const Color(0xFF067647) : const Color(0xFFB26A00),
          ),
          const SizedBox(width: 4),
          Text(
            confirmed ? 'Chủ nợ đã xác nhận' : 'Cần bằng chứng trả nợ',
            style: TextStyle(
              fontSize: compact ? 10 : 11.5,
              fontWeight: FontWeight.w700,
              color: confirmed ? const Color(0xFF067647) : const Color(0xFFB26A00),
            ),
          ),
        ],
      ),
    );
  }
}

class CaseCover extends StatelessWidget {
  final CaseSummary item;
  final double height;
  final bool showChip;
  final BorderRadius? radius;

  const CaseCover({super.key, required this.item, this.height = 132, this.showChip = true, this.radius});

  @override
  Widget build(BuildContext context) {
    final tint = colorFromHex(item.coverColor);
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius ?? const BorderRadius.vertical(top: Radius.circular(V.radius)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint, Color.lerp(tint, Colors.white, 0.45)!],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            bottom: -18,
            child: Opacity(
              opacity: 0.28,
              child: Text(item.coverEmoji, style: TextStyle(fontSize: height * 0.55)),
            ),
          ),
          Positioned(
            left: 14,
            top: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(999)),
              child: Text(
                '${item.coverEmoji} ${categoryLabel(item.category)}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: V.ink),
              ),
            ),
          ),
          if (showChip) Positioned(left: 14, bottom: 14, child: ModeChip(confirmed: item.isModeA, compact: true)),
        ],
      ),
    );
  }
}

class CaseCard extends StatelessWidget {
  final CaseSummary item;
  final VoidCallback? onTap;
  final bool horizontal;

  const CaseCard({super.key, required this.item, this.onTap, this.horizontal = false});

  @override
  Widget build(BuildContext context) {
    if (horizontal) return _horizontal(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: V.surface,
        borderRadius: BorderRadius.circular(V.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(V.radius),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(V.radius),
              border: Border.all(color: V.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CaseCover(item: item),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, height: 1.25, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                      const SizedBox(height: 12),
                      WalletProgress(percent: item.percent),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(money(item.raisedAmount),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          Text(' / ${money(item.targetAmount)}',
                              style: const TextStyle(color: V.muted, fontSize: 13)),
                          const Spacer(),
                          Text('${item.percent}%', style: const TextStyle(fontWeight: FontWeight.w800, color: V.greenDark)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          AvatarBubble(name: item.debtor?.nickname ?? '?', avatarKey: item.debtor?.avatarKey ?? 'x', size: 22),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${item.debtor?.nickname ?? 'Ẩn danh'} · ${item.contributorCount} người đã cứu',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: V.muted, fontWeight: FontWeight.w500),
                            ),
                          ),
                          const Icon(Icons.schedule_rounded, size: 13, color: V.muted),
                          const SizedBox(width: 3),
                          Text(relativeDeadline(item.daysLeft), style: const TextStyle(fontSize: 12, color: V.muted)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _horizontal(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Material(
        color: V.surface,
        borderRadius: BorderRadius.circular(V.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(V.radius),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(V.radius),
              border: Border.all(color: V.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CaseCover(item: item, height: 104),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 40,
                        child: Text(item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, height: 1.25, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 8),
                      WalletProgress(percent: item.percent, height: 7),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(money(item.raisedAmount),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                          const Spacer(),
                          Text('${item.percent}%', style: const TextStyle(fontSize: 11, color: V.muted)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          AvatarBubble(name: item.debtor?.nickname ?? '?', avatarKey: item.debtor?.avatarKey ?? 'x', size: 18),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              item.debtor?.nickname ?? 'Ẩn danh',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10.5, color: V.muted),
                            ),
                          ),
                          const Icon(Icons.schedule_rounded, size: 11, color: V.muted),
                          const SizedBox(width: 3),
                          Text(relativeDeadline(item.daysLeft), style: const TextStyle(fontSize: 10.5, color: V.muted)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const SectionHeader({super.key, required this.title, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          const Spacer(),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: Text(action!, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: V.greenDark)),
            ),
        ],
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color? tint;
  final Widget? trailing;

  const InfoCard({super.key, required this.icon, required this.title, required this.body, this.tint, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint ?? V.canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: V.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: V.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                const SizedBox(height: 3),
                Text(body, style: const TextStyle(fontSize: 13, height: 1.45, color: V.muted)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({super.key, required this.emoji, required this.title, required this.body, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center, style: const TextStyle(color: V.muted, height: 1.5)),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: 220,
                child: FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  final String label;

  const LoadingView({super.key, this.label = 'Đang tải...'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: V.green),
          ),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(color: V.muted, fontSize: 13)),
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? V.danger : V.ink,
    ),
  );
}

class GradientScaffold extends StatelessWidget {
  final Widget child;

  const GradientScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF2FFF8), V.surface],
          stops: [0, 0.35],
        ),
      ),
      child: child,
    );
  }
}

class ConfettiBurst extends StatefulWidget {
  final Widget child;

  const ConfettiBurst({super.key, required this.child});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 4))..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              if (_controller.value >= 1) return const SizedBox.shrink();
              return CustomPaint(
                size: MediaQuery.sizeOf(context),
                painter: _ConfettiPainter(_controller.value),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double t;

  _ConfettiPainter(this.t);

  static const colors = [V.green, Color(0xFFFFD166), Color(0xFF8ECAE6), Color(0xFFFFB4A2), Color(0xFFCDB4DB)];

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(7);
    for (var i = 0; i < 70; i++) {
      final startX = random.nextDouble() * size.width;
      final speed = 0.4 + random.nextDouble() * 0.9;
      final y = -20 + (size.height * 0.9) * t * speed;
      final x = startX + math.sin((t * 6 + i) * 1.2) * 26;
      final color = colors[i % colors.length];
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * 8 + i);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 7, height: 11), const Radius.circular(2)),
        Paint()..color = color.withValues(alpha: (1 - t).clamp(0.1, 1)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.t != t;
}
