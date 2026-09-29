import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoSlidingSegmentedControl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Small building blocks that give every screen the same calm, Apple-like feel:
/// large titles, soft cards, spring-y presses, generous spacing.

/// White rounded surface with a whisper of shadow.
class IosCard extends StatelessWidget {
  const IosCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.color = Colors.white,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: child,
    );
    final content = onTap == null ? card : PressableScale(onTap: onTap!, child: card);
    return semanticLabel == null ? content : Semantics(container: true, label: semanticLabel, child: content);
  }
}

/// Shrinks slightly while pressed, like a native control.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, required this.onTap, this.scale = 0.97});
  final Widget child;
  final VoidCallback onTap;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Big bold page title with an optional subtitle and trailing actions.
class LargeTitle extends StatelessWidget {
  const LargeTitle({super.key, required this.title, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null)
                Text(subtitle!.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppColors.textTertiary)),
              Semantics(
                header: true,
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1, color: AppColors.textPrimary)),
              ),
            ],
          ),
        ),
        ...actions,
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A 44-pt circular icon button (the minimum comfortable touch target).
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.color});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, size: 19, color: color ?? AppColors.textPrimary, semanticLabel: tooltip),
          ),
        ),
      ),
    );
  }
}

/// Circular progress that animates smoothly when its value changes.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    required this.color,
    this.size = 180,
    this.strokeWidth = 16,
    this.child,
  });

  /// 0..1 (values above 1 keep the ring full).
  final double progress;
  final Color color;
  final double size;
  final double strokeWidth;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(value, color, strokeWidth),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.stroke);
  final double value;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: 0.12);
    canvas.drawCircle(center, radius, track);
    if (value <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [color.withValues(alpha: 0.75), color],
      ).createShader(rect);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, 2 * math.pi * value, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.stroke != stroke;
}

/// One metric: icon, big number, unit, label, optional data source.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.unit,
    required this.label,
    this.footnote,
  });

  final IconData icon;
  final MaterialColor color;
  final String value;
  final String unit;
  final String label;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label: $value $unit${footnote == null ? '' : ', $footnote'}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 18, color: color.shade600),
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(value,
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.8, color: AppColors.textPrimary)),
                    const SizedBox(width: 4),
                    Text(unit,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              if (footnote != null) ...[
                const SizedBox(height: 4),
                Text(footnote!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textTertiary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "No data yet" panel used instead of any placeholder numbers.
class EmptyPanel extends StatelessWidget {
  const EmptyPanel({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Icon(icon, size: 30, color: AppColors.textTertiary),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, height: 1.45, color: AppColors.textSecondary)),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

/// Small pill telling where a number came from.
class SourceChip extends StatelessWidget {
  const SourceChip(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(10)),
      child: Text(label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
    );
  }
}

/// Filled, rounded primary button (iOS "prominent" style).
class ProminentButton extends StatelessWidget {
  const ProminentButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = AppColors.primary,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ]),
      ),
    );
  }
}

/// iOS-style sliding segmented control.
class Segmented<T extends Object> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoSlidingSegmentedControl<T>(
      groupValue: value,
      backgroundColor: const Color(0xFFEDEEF1),
      thumbColor: Colors.white,
      children: {
        for (final e in options.entries)
          e.key: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            child: Text(e.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
      },
      onValueChanged: (v) {
        if (v != null) {
          HapticFeedback.selectionClick();
          onChanged(v);
        }
      },
    );
  }
}
