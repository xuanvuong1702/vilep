import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'core/format.dart';
import 'core/models.dart';
import 'core/theme.dart';

/// Small press-scale wrapper so cards and chips feel physical without a
/// package dependency.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const PressableScale({super.key, required this.child, this.onTap, this.pressedScale = 0.985});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _pressed = false),
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class AvatarBubble extends StatelessWidget {
  final String name;
  final String avatarKey;
  final double size;
  final bool ring;

  const AvatarBubble({super.key, required this.name, required this.avatarKey, this.size = 36, this.ring = false});

  static const _palettes = [
    [Color(0xFFCDB4DB), Color(0xFF8E7DBE)],
    [Color(0xFFB7E4C7), Color(0xFF4EA87C)],
    [Color(0xFFFFD166), Color(0xFFE39A2B)],
    [Color(0xFFA2D2FF), Color(0xFF4C8FCC)],
    [Color(0xFFFFB4A2), Color(0xFFD9694F)],
    [Color(0xFFD0F4DE), Color(0xFF3FAE7A)],
    [Color(0xFFFBC4AB), Color(0xFFCE7B57)],
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
        border: ring ? Border.all(color: Colors.white, width: 2) : null,
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

    canvas.drawRRect(rect, Paint()..color = const Color(0xFF1B1B1B));

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
    canvas.drawCircle(Offset(clasp.center.dx, clasp.center.dy), claspW * 0.08, Paint()..color = V.greenInk);

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
  final Color? trackColor;

  const WalletProgress({super.key, required this.percent, this.height = 10, this.color, this.trackColor});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(V.rPill),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Container(height: height, color: trackColor ?? const Color(0xFFEDEDE8)),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: percent.clamp(0, 100) / 100),
              duration: const Duration(milliseconds: 750),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value <= 0 ? 0.001 : value,
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: color ?? V.green,
                    borderRadius: BorderRadius.circular(V.rPill),
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
    final bg = confirmed ? V.greenSoft : V.amberSoft;
    final fg = confirmed ? V.greenDark : const Color(0xFF9A6400);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 4 : 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(V.rPill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(
            confirmed ? 'Chủ nợ đã xác nhận' : 'Cần bằng chứng trả nợ',
            style: TextStyle(fontSize: compact ? 9.5 : 11, fontWeight: FontWeight.w700, color: fg, letterSpacing: -0.1),
          ),
        ],
      ),
    );
  }
}

class PercentPill extends StatelessWidget {
  final int percent;

  const PercentPill({super.key, required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: V.greenSoft, borderRadius: BorderRadius.circular(V.rPill)),
      child: Text(
        '$percent%',
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: V.greenDark, letterSpacing: -0.2),
      ),
    );
  }
}

class CaseCover extends StatelessWidget {
  final CaseSummary item;
  final double height;
  final bool showChip;
  final BorderRadius? radius;
  final bool hero;

  const CaseCover({
    super.key,
    required this.item,
    this.height = 150,
    this.showChip = true,
    this.radius,
    this.hero = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius ?? const BorderRadius.vertical(top: Radius.circular(V.r20)),
        gradient: coverGradient(item.coverColor),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: CustomPaint(painter: _CoverPatternPainter(seed: item.code))),
          Positioned(
            left: -height * 0.35,
            top: -height * 0.55,
            child: Container(
              width: height * 1.2,
              height: height * 1.2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Colors.white.withValues(alpha: 0.5), Colors.white.withValues(alpha: 0)]),
              ),
            ),
          ),
          Positioned(
            right: height * 0.02,
            bottom: -height * 0.12,
            child: Text(item.coverEmoji, style: TextStyle(fontSize: height * 0.62)),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(V.rPill)),
              child: Text(
                categoryLabel(item.category),
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: V.ink),
              ),
            ),
          ),
          if (showChip)
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(V.rPill)),
                child: ModeChip(confirmed: item.isModeA, compact: true),
              ),
            ),
        ],
      ),
    );

    return hero ? Hero(tag: 'cover-${item.id}', child: content) : content;
  }
}

class CaseCard extends StatelessWidget {
  final CaseSummary item;
  final VoidCallback? onTap;
  final bool horizontal;

  const CaseCard({super.key, required this.item, this.onTap, this.horizontal = false});

  @override
  Widget build(BuildContext context) {
    if (horizontal) return _featured(context);
    return PressableScale(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: V.surface,
          borderRadius: BorderRadius.circular(V.r20),
          border: Border.all(color: V.line),
          boxShadow: V.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CaseCover(item: item, height: 152),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, height: 1.24, fontWeight: FontWeight.w800, letterSpacing: -0.42),
                        ),
                      ),
                      const SizedBox(width: 10),
                      PercentPill(percent: item.percent),
                    ],
                  ),
                  const SizedBox(height: 12),
                  WalletProgress(percent: item.percent, height: 7),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Text(money(item.raisedAmount),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, letterSpacing: -0.2)),
                      Text(' / ${money(item.targetAmount)}',
                          style: const TextStyle(color: V.faint, fontSize: 12.5, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      const Icon(Icons.schedule_rounded, size: 12.5, color: V.faint),
                      const SizedBox(width: 3),
                      Text(relativeDeadline(item.daysLeft), style: const TextStyle(fontSize: 11.5, color: V.muted)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      AvatarBubble(name: item.debtor?.nickname ?? '?', avatarKey: item.debtor?.avatarKey ?? 'x', size: 22),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '${item.debtor?.nickname ?? 'Ẩn danh'} · ${item.contributorCount} người đã cứu',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: V.muted, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featured(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: 246,
        decoration: BoxDecoration(
          color: V.surface,
          borderRadius: BorderRadius.circular(V.r20),
          border: Border.all(color: V.line),
          boxShadow: V.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CaseCover(item: item, height: 112, hero: false),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, height: 1.26, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                  const SizedBox(height: 10),
                  WalletProgress(percent: item.percent, height: 7),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(money(item.raisedAmount), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                      Text(' / ${moneyShort(item.targetAmount)}',
                          style: const TextStyle(fontSize: 11, color: V.faint, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      Text(relativeDeadline(item.daysLeft), style: const TextStyle(fontSize: 10.5, color: V.muted)),
                    ],
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

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  const SectionHeader({super.key, required this.title, this.subtitle, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: V.muted)),
                  ),
              ],
            ),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(action!, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: V.greenDark)),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_forward_rounded, size: 14, color: V.greenDark),
                ],
              ),
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
  final Color? iconColor;
  final Widget? trailing;

  const InfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.tint,
    this.iconColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint ?? V.canvas,
        borderRadius: BorderRadius.circular(V.r16),
        border: Border.all(color: V.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: V.surface, borderRadius: BorderRadius.circular(V.r12)),
            child: Icon(icon, size: 19, color: iconColor ?? V.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: -0.2)),
                const SizedBox(height: 3),
                Text(body, style: const TextStyle(fontSize: 12.5, height: 1.5, color: V.muted)),
              ],
            ),
          ),
          if (trailing != null) Padding(padding: const EdgeInsets.only(left: 8), child: trailing!),
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
            Container(
              width: 92,
              height: 92,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: V.canvas, shape: BoxShape.circle),
              child: Text(emoji, style: const TextStyle(fontSize: 40)),
            ),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 7),
            Text(body, textAlign: TextAlign.center, style: const TextStyle(color: V.muted, height: 1.55, fontSize: 13.5)),
            if (actionLabel != null) ...[
              const SizedBox(height: 22),
              SizedBox(width: 220, child: FilledButton(onPressed: onAction, child: Text(actionLabel!))),
            ],
          ],
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  final String? label;

  const LoadingView({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: V.green),
          ),
          if (label != null) ...[
            const SizedBox(height: 12),
            Text(label!, style: const TextStyle(color: V.muted, fontSize: 12.5)),
          ],
        ],
      ),
    );
  }
}

class SkeletonCard extends StatefulWidget {
  const SkeletonCard({super.key});

  @override
  State<SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<SkeletonCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: V.surface,
            borderRadius: BorderRadius.circular(V.r20),
            border: Border.all(color: V.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bone(height: 152, radius: const BorderRadius.vertical(top: Radius.circular(V.r20)), t: t),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: _bone(height: 15, t: t)),
                      const SizedBox(width: 12),
                      _bone(width: 42, height: 15, t: t),
                    ]),
                    const SizedBox(height: 10),
                    _bone(width: 180, height: 12, t: t),
                    const SizedBox(height: 16),
                    _bone(height: 7, radius: BorderRadius.circular(V.rPill), t: t),
                    const SizedBox(height: 12),
                    _bone(width: 130, height: 12, t: t),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bone({double? width, double? height, BorderRadius? radius, required double t}) {
    final shift = (t * 2 - 1) * 120;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius ?? BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [Color(0xFFF1F1EE), Color(0xFFF8F8F5), Color(0xFFF1F1EE)],
          stops: const [0.25, 0.5, 0.75],
          transform: _SlideGradient(shift),
        ),
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  final double dx;

  const _SlideGradient(this.dx);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(dx, 0, 0);
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(error ? Icons.error_rounded : Icons.check_circle_rounded, size: 18, color: error ? V.danger : V.green),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: V.ink,
    ),
  );
}

class StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const StatTile({super.key, required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: V.surface,
          borderRadius: BorderRadius.circular(V.r16),
          border: Border.all(color: V.line),
        ),
        child: Column(
          children: [
            Icon(icon, size: 17, color: V.greenDark),
            const SizedBox(height: 7),
            Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: V.muted, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
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


/// Soft out-of-focus blobs + grain so covers feel photographed, not flat.
class _CoverPatternPainter extends CustomPainter {
  final String seed;

  _CoverPatternPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed.hashCode);
    for (var i = 0; i < 3; i++) {
      final center = Offset(random.nextDouble() * size.width, random.nextDouble() * size.height);
      final radius = size.shortestSide * (0.28 + random.nextDouble() * 0.42);
      final light = i.isEven;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = (light ? Colors.white : Colors.black).withValues(alpha: light ? 0.16 : 0.05)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
      );
    }
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.22);
    for (var i = 0; i < 16; i++) {
      canvas.drawCircle(
        Offset(random.nextDouble() * size.width, random.nextDouble() * size.height),
        1.1 + random.nextDouble() * 0.6,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CoverPatternPainter oldDelegate) => oldDelegate.seed != seed;
}

/// Fade + slide entrance, staggered by list index. Pure widget animation: no
/// controllers to leak, no timers.
class Entrance extends StatelessWidget {
  final int index;
  final Widget child;

  const Entrance({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final start = (index.clamp(0, 6) * 0.06).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 640),
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, (1 - value) * 14), child: child),
      ),
      child: child,
    );
  }
}

/// Count-up money label used on the case detail hero panel.
class MoneyCounter extends StatelessWidget {
  final int amount;
  final TextStyle? style;

  const MoneyCounter({super.key, required this.amount, this.style});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: amount.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => Text(money(value.round()), style: style),
    );
  }
}

/// Centres content on wide screens (web/tablet) while keeping mobile full-bleed.
class PageFrame extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final Color? background;
  final Color? surface;

  const PageFrame({super.key, required this.child, this.maxWidth = 620, this.background, this.surface});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 700;
    return ColoredBox(
      color: background ?? (wide ? V.canvas : V.surface),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ColoredBox(color: surface ?? V.surface, child: child),
        ),
      ),
    );
  }
}

/// Loading placeholder for the case detail screen.
class CaseDetailSkeleton extends StatelessWidget {
  const CaseDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bone({double? width, double? height, double radius = 8}) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(color: const Color(0xFFF1F1EE), borderRadius: BorderRadius.circular(radius)),
        );

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Container(height: 284, color: const Color(0xFFF1F1EE)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bone(width: 120, height: 10),
              const SizedBox(height: 14),
              bone(height: 26, radius: 10),
              const SizedBox(height: 10),
              bone(width: 220, height: 26, radius: 10),
              const SizedBox(height: 22),
              bone(height: 132, radius: 20),
              const SizedBox(height: 16),
              bone(height: 72, radius: 16),
              const SizedBox(height: 12),
              bone(height: 58, radius: 16),
              const SizedBox(height: 26),
              bone(width: 140, height: 18, radius: 8),
              const SizedBox(height: 14),
              bone(height: 12),
              const SizedBox(height: 8),
              bone(height: 12),
              const SizedBox(height: 8),
              bone(width: 240, height: 12),
            ],
          ),
        ),
      ],
    );
  }
}
