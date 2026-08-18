/// আমার ডায়েট — widget kit (v2 Cosmos).
///
/// Every widget assumes a dark canvas with drifting gradient blobs behind it.
/// Surfaces are frosted glass, brand chrome is gradient, and motion is
/// generous: lift on press, count-up on stat, shimmer on loading, drift on
/// backdrops. All tokens come from [AppTheme].
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

// ────────────────────────────────────────────────────────────────────────────
// Backgrounds
// ────────────────────────────────────────────────────────────────────────────

/// Drifting gradient blobs behind everything. Use as a `Stack` base layer
/// inside a screen so the cosmos "breathes" while the user interacts.
class GradientBackdrop extends StatefulWidget {
  final List<RadialGradient> blobs;
  final Widget? child;
  final double intensity;
  final Duration period;

  const GradientBackdrop({
    super.key,
    this.blobs = const [
      AppGradients.blobCyan,
      AppGradients.blobViolet,
      AppGradients.blobMint
    ],
    this.child,
    this.intensity = 1.0,
    this.period = AppMotion.gradientDrift,
  });

  @override
  State<GradientBackdrop> createState() => _GradientBackdropState();
}

class _GradientBackdropState extends State<GradientBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.period)..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return CustomPaint(
              painter: _BlobPainter(
                t: _c.value,
                blobs: widget.blobs,
                intensity: widget.intensity,
              ),
            );
          },
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _BlobPainter extends CustomPainter {
  final double t;
  final List<RadialGradient> blobs;
  final double intensity;
  _BlobPainter({required this.t, required this.blobs, required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    
    // Static base cosmos
    final basePaint = Paint()
      ..shader = AppGradients.cosmos.createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, basePaint);

    for (int i = 0; i < blobs.length; i++) {
      final phase = (t + i / blobs.length) % 1.0;
      final dx = math.sin(phase * math.pi * 2) * 0.18;
      final dy = math.cos(phase * math.pi * 2 + 1.3) * 0.16;
      
      // Scale down the draw call to avoid massive overdraw if the driver is struggling.
      final paint = Paint()
        ..blendMode = BlendMode.srcOver
        ..shader = blobs[i].createShader(Offset.zero & size);
      
      canvas.save();
      canvas.translate(dx * size.width, dy * size.height);
      canvas.drawRect(Offset.zero & size, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) =>
      old.t != t || old.blobs != blobs || old.intensity != intensity;
}

// ────────────────────────────────────────────────────────────────────────────
// Glass surface (drop-in for MonoCard)
// ────────────────────────────────────────────────────────────────────────────

/// Frosted glass card. Use as a drop-in replacement for [MonoCard].
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final BorderRadiusGeometry? borderRadius;
  final Color? tint;
  final double blurSigma;
  final bool highlight;
  final bool borderless;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.borderRadius,
    this.tint,
    this.blurSigma = AppGlass.blurMed,
    this.highlight = false,
    this.borderless = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.lg);
    final t = tint ?? (highlight ? AppGlass.tintHigh : AppGlass.tint);
    final borderColor = borderless
        ? Colors.transparent
        : (highlight ? AppGlass.borderHigh : AppGlass.border);

    Widget body(Widget w) {
      final card = ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            if (blurSigma > 0)
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: const SizedBox.expand(),
              ),
            Positioned.fill(
                child: DecoratedBox(decoration: BoxDecoration(color: t))),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: borderColor, width: 1.2),
                ),
              ),
            ),
            Padding(padding: padding, child: w),
          ],
        ),
      );
      // Soft elevation shadow — sits outside the clip so it isn't cut off.
      // This is what reads as "depth" now that we've dropped glass blur.
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: highlight
              ? AppGlass.shadow(opacity: 0.10, blur: 28, y: 12)
              : AppGlass.shadow(opacity: 0.05, blur: 18, y: 6),
        ),
        child: card,
      );
    }

    if (onTap == null) return body(child);

    return Pressable(
      onTap: onTap,
      pressScale: 0.985,
      child: body(child),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Primitives
// ────────────────────────────────────────────────────────────────────────────

/// Ink-free, spring-based press feedback. Use wherever we want a premium
/// tactile feel without Material's ripple.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressScale;
  final Duration duration;
  final BorderRadius? borderRadius;
  final HitTestBehavior behavior;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressScale = 0.97,
    this.duration = AppMotion.micro,
    this.borderRadius,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: (_) {
        if (widget.onTap == null && widget.onLongPress == null) return;
        setState(() => _down = true);
        HapticFeedback.selectionClick();
      },
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        duration: widget.duration,
        curve: AppMotion.emphasized,
        scale: _down ? widget.pressScale : 1.0,
        child: widget.child,
      ),
    );
  }
}

/// Fades + slides a child into place.
class RevealOnEnter extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double dy;
  final bool enabled;
  const RevealOnEnter({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.medium,
    this.dy = 14,
    this.enabled = true,
  });

  @override
  State<RevealOnEnter> createState() => _RevealOnEnterState();
}

class _RevealOnEnterState extends State<RevealOnEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _c, curve: AppMotion.standard);
    _slide = Tween<Offset>(begin: Offset(0, widget.dy / 100), end: Offset.zero)
        .animate(CurvedAnimation(parent: _c, curve: AppMotion.emphasized));
    if (widget.enabled) {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If not enabled, we still want to show the child at 100% opacity 
    // and skip the animation.
    if (!widget.enabled) return widget.child;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Staggered fade-up helper for ListView children.
class StaggeredReveal extends StatelessWidget {
  final int index;
  final Widget child;
  final Duration baseDelay;
  final Duration step;
  const StaggeredReveal({
    super.key,
    required this.index,
    required this.child,
    this.baseDelay = const Duration(milliseconds: 60),
    this.step = const Duration(milliseconds: 70),
  });

  @override
  Widget build(BuildContext context) {
    return RevealOnEnter(
      delay: baseDelay + step * index,
      child: child,
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Buttons
// ────────────────────────────────────────────────────────────────────────────

enum MonoButtonVariant { primary, ghost, outline, gradient }

class MonoButton extends StatelessWidget {
  final String label;
  final IconData? leading;
  final IconData? trailing;
  final VoidCallback? onPressed;
  final MonoButtonVariant variant;
  final bool loading;
  final EdgeInsets padding;
  final LinearGradient? gradient;

  const MonoButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = MonoButtonVariant.primary,
    this.leading,
    this.trailing,
    this.loading = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final isPrimary = variant == MonoButtonVariant.primary;
    final isOutline = variant == MonoButtonVariant.outline;
    final isGradient = variant == MonoButtonVariant.gradient;
    final grad = gradient ?? AppGradients.aurora;
    final fg = (isPrimary || isGradient) ? AppColors.void1 : AppColors.text;
    final borderColor = isOutline ? AppGlass.border : Colors.transparent;

    return Pressable(
      onTap: loading || onPressed == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onPressed!();
            },
      child: AnimatedContainer(
        duration: AppMotion.short,
        curve: AppMotion.standard,
        height: 62,
        padding: padding,
        decoration: BoxDecoration(
          gradient: isGradient ? grad : null,
          color: isPrimary
              ? AppColors.cyan
              : (isOutline
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.transparent),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: borderColor, width: 1.4),
          boxShadow: (isPrimary || isGradient)
              ? [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.45),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(fg),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leading != null) ...[
                    Icon(leading, color: fg, size: 22),
                    const SizedBox(width: 12),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: fg,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        // Subtle drop shadow on dark gradient buttons so
                        // the label reads cleanly over the aurora gradient.
                        shadows: (isPrimary || isGradient)
                            ? const [
                                Shadow(
                                  color: Color(0x55000000),
                                  offset: Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    Icon(trailing, color: fg, size: 22),
                  ],
                ],
              ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Surface cards
// ────────────────────────────────────────────────────────────────────────────

/// A precise monogram / mark that breathes — used as the brand anchor.
class BrandMark extends StatefulWidget {
  final double size;
  final double ringStroke;
  final Duration period;

  const BrandMark({
    super.key,
    this.size = 96,
    this.ringStroke = 1.6,
    this.period = const Duration(seconds: 7),
  });

  @override
  State<BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<BrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.period)..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return CustomPaint(
            painter: _BrandMarkPainter(t: _c.value, stroke: widget.ringStroke),
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Center(
                child: Icon(
                  Icons.grain,
                  size: widget.size * 0.46,
                  color: AppColors.void1,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  final double t;
  final double stroke;
  _BrandMarkPainter({required this.t, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = AppGradients.aurora
          .createShader(Rect.fromCircle(center: c, radius: r));
    // Slowly rotating arc for life.
    final start = t * math.pi * 2;
    const sweep = math.pi * 0.9;
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - stroke), start, sweep, false, p);
    // Inner static ring gives the mark definition.
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.5
      ..color = AppColors.line;
    canvas.drawCircle(c, r - stroke * 2.5, inner);
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter old) => old.t != t;
}

/// Outlined surface used wherever the rest of the app previously used [Card].
/// Now an alias for [GlassCard] with backwards-compat fields.
class MonoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final BorderRadiusGeometry? borderRadius;
  final Color? background;
  final bool invert;
  final bool borderless;
  const MonoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.borderRadius,
    this.background,
    this.invert = false,
    this.borderless = false,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: padding,
      onTap: onTap,
      borderRadius: borderRadius,
      tint: background,
      borderless: borderless,
      highlight: invert,
      child: child,
    );
  }
}

/// Wide horizontal divider with optional centered glyph — used as a section
/// separator in editorial layouts.
class SectionRule extends StatelessWidget {
  final String? label;
  const SectionRule({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    if (label == null) {
      return const Divider(color: AppColors.line, height: 24);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.transparent,
                  AppColors.cyan.withValues(alpha: 0.6),
                ]),
              ),
            ),
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  AppColors.violet.withValues(alpha: 0.6),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small all-caps section label with built-in underline rule.
class Overline extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;
  const Overline(this.text,
      {super.key, this.padding = const EdgeInsets.only(top: 4, bottom: 12)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(
            width: 18,
            height: 1.4,
            decoration: BoxDecoration(
              gradient: AppGradients.aurora,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Segmented control (used for login ↔ signup, day navigation, etc.)
// ────────────────────────────────────────────────────────────────────────────

class MonoSegmented<T> extends StatelessWidget {
  final List<({T value, String label})> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final Duration duration;

  const MonoSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.duration = AppMotion.short,
  });

  @override
  Widget build(BuildContext context) {
    // Segments equal-share the row if they fit, or scroll if they don't.
    // FittedBox + maxLines:1 helps them shrink before we hit overflow.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.line),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final o in options) _segment(o),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segment(({T value, String label}) o) {
    final isSel = o.value == selected;
    return Pressable(
      onTap: () {
        if (isSel) return;
        HapticFeedback.selectionClick();
        onChanged(o.value);
      },
      child: AnimatedContainer(
        duration: duration,
        curve: AppMotion.standard,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        constraints: const BoxConstraints(minWidth: 60),
        decoration: BoxDecoration(
          gradient: isSel ? AppGradients.aurora : null,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: isSel
              ? [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          o.label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            color: isSel ? AppColors.void1 : AppColors.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Empty / loading states
// ────────────────────────────────────────────────────────────────────────────

class LoadingMark extends StatefulWidget {
  final double size;
  const LoadingMark({super.key, this.size = 28});

  @override
  State<LoadingMark> createState() => _LoadingMarkState();
}

class _LoadingMarkState extends State<LoadingMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: CircularProgressIndicator(
          valueColor: const AlwaysStoppedAnimation(AppColors.cyan),
          strokeWidth: 2.2,
          value: null,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? action;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: AppGradients.aurora,
                borderRadius: BorderRadius.circular(44),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(icon, color: AppColors.void1, size: 38),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textMuted,
                height: 1.4,
              ),
            ),
            if (action != null && onAction != null) ...[
              const SizedBox(height: 22),
              MonoButton(
                label: action!,
                variant: MonoButtonVariant.gradient,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Numeric / progress atoms
// ────────────────────────────────────────────────────────────────────────────

/// A 0→1 progress arc, animated to value changes.
class MonoRing extends StatefulWidget {
  final double value; // 0..1
  final double size;
  final double stroke;
  final Duration duration;
  final Color track;
  final Color fill;
  final Gradient? fillGradient;
  final Widget? child;

  const MonoRing({
    super.key,
    required this.value,
    this.size = 110,
    this.stroke = 10,
    this.duration = AppMotion.long,
    this.track = AppColors.surfaceHigh,
    this.fill = AppColors.cyan,
    this.fillGradient,
    this.child,
  });

  @override
  State<MonoRing> createState() => _MonoRingState();
}

class _MonoRingState extends State<MonoRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late Animation<double> _anim;
  double _from = 0;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    _anim = AlwaysStoppedAnimation(widget.value.clamp(0.0, 1.0));
    _c.value = 1;
  }

  @override
  void didUpdateWidget(covariant MonoRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _from = _anim.value;
      _anim = Tween<double>(begin: _from, end: widget.value.clamp(0.0, 1.0))
          .animate(CurvedAnimation(parent: _c, curve: AppMotion.emphasized));
      _c
        ..duration = widget.duration
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          return CustomPaint(
            painter: _RingPainter(
              value: _anim.value,
              stroke: widget.stroke,
              track: widget.track,
              fill: widget.fill,
              fillGradient: widget.fillGradient,
            ),
            child: child,
          );
        },
        child: Center(child: widget.child ?? const SizedBox.shrink()),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final double stroke;
  final Color track;
  final Color fill;
  final Gradient? fillGradient;
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.track,
    required this.fill,
    this.fillGradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - stroke / 2;
    final trackP = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track
      ..strokeCap = StrokeCap.round;
    final fillP = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (fillGradient != null) {
      fillP.shader =
          fillGradient!.createShader(Rect.fromCircle(center: c, radius: r));
    } else {
      fillP.color = fill;
    }
    canvas.drawCircle(c, r, trackP);
    final sweep = math.pi * 2 * value;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, sweep,
        false, fillP);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value ||
      old.stroke != stroke ||
      old.fill != fill ||
      old.fillGradient != fillGradient ||
      old.track != track;
}

/// Animated counter for big stats.
class MonoCounter extends StatefulWidget {
  final num value;
  final TextStyle? style;
  final String suffix;
  final String prefix;
  final Duration duration;
  final int fractionDigits;

  const MonoCounter({
    super.key,
    required this.value,
    this.style,
    this.suffix = '',
    this.prefix = '',
    this.duration = AppMotion.long,
    this.fractionDigits = 0,
  });

  @override
  State<MonoCounter> createState() => _MonoCounterState();
}

class _MonoCounterState extends State<MonoCounter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late Animation<double> _anim;
  double _from = 0;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    _anim = AlwaysStoppedAnimation(widget.value.toDouble());
    _c.value = 1;
  }

  @override
  void didUpdateWidget(covariant MonoCounter old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _from = _anim.value;
      _anim = Tween<double>(begin: _from, end: widget.value.toDouble())
          .animate(CurvedAnimation(parent: _c, curve: AppMotion.emphasized));
      _c
        ..duration = widget.duration
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final v = widget.fractionDigits == 0
            ? _anim.value.round().toString()
            : _anim.value.toStringAsFixed(widget.fractionDigits);
        return Text(
          '${widget.prefix}$v${widget.suffix}',
          style: widget.style,
        );
      },
    );
  }
}

/// A clean monochrome badge with an icon + text label.
class MonoBadge extends StatelessWidget {
  final String text;
  final IconData? icon;
  final bool invert;
  final LinearGradient? gradient;
  final EdgeInsetsGeometry padding;
  const MonoBadge({
    super.key,
    required this.text,
    this.icon,
    this.invert = false,
    this.gradient,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final fg = invert ? AppColors.void1 : AppColors.text;
    final bg = invert ? AppColors.cyan : AppColors.surfaceHigh;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? bg : null,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: gradient == null ? Border.all(color: AppColors.line) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: fg, size: 16),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// A 0..1 horizontal bar with animated fill (used for dashboard macros).
class MonoBar extends StatefulWidget {
  final double value; // 0..1
  final double height;
  final Color fill;
  final Gradient? fillGradient;
  final Color track;
  final Duration duration;

  const MonoBar({
    super.key,
    required this.value,
    this.height = 10,
    this.fill = AppColors.cyan,
    this.fillGradient,
    this.track = AppColors.surfaceHigh,
    this.duration = AppMotion.medium,
  });

  @override
  State<MonoBar> createState() => _MonoBarState();
}

class _MonoBarState extends State<MonoBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    _anim = AlwaysStoppedAnimation(widget.value.clamp(0.0, 1.0));
    _c.value = 1;
  }

  @override
  void didUpdateWidget(covariant MonoBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final from = _anim.value;
      _anim = Tween<double>(begin: from, end: widget.value.clamp(0.0, 1.0))
          .animate(CurvedAnimation(parent: _c, curve: AppMotion.emphasized));
      _c
        ..duration = widget.duration
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.height),
      child: SizedBox(
        height: widget.height,
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            return Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: widget.track)),
                FractionallySizedBox(
                  widthFactor: _anim.value,
                  child: widget.fillGradient != null
                      ? DecoratedBox(
                          decoration:
                              BoxDecoration(gradient: widget.fillGradient))
                      : ColoredBox(color: widget.fill),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// AnimatedCheck: a circular mark that pulses when value goes true
// ────────────────────────────────────────────────────────────────────────────

class AnimatedCheck extends StatelessWidget {
  final bool done;
  final double size;
  final Duration duration;
  const AnimatedCheck(
      {super.key,
      required this.done,
      this.size = 44,
      this.duration = AppMotion.short});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      curve: AppMotion.emphasized,
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: done ? AppGradients.mintGlow : null,
        color: done ? null : AppColors.surfaceHigh,
        shape: BoxShape.circle,
        border: Border.all(
          color: done ? Colors.transparent : AppGlass.border,
          width: 1.4,
        ),
        boxShadow: done
            ? [
                BoxShadow(
                  color: AppColors.mint.withValues(alpha: 0.45),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: AnimatedScale(
        duration: duration,
        curve: AppMotion.overshoot,
        scale: done ? 1 : 0.0,
        child: Icon(Icons.check_rounded,
            color: AppColors.void1, size: size * 0.55),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Geometric pattern primitives — unique formations, structural not decorative
// ────────────────────────────────────────────────────────────────────────────

enum MonoPatternKind { grid, dots, stripes, arcs }

/// A geometric pattern that gives the app a distinctive identity without
/// using imagery. Use on hero cards, account headers, or as background detail.
///
/// All patterns are drawn with [CustomPainter] — no PNGs, no gradients.
class MonoPattern extends StatelessWidget {
  final MonoPatternKind kind;
  final Color color;
  final double opacity;
  final double stroke;
  final double spacing;
  final Widget? child;

  const MonoPattern({
    super.key,
    required this.kind,
    this.color = AppColors.cyan,
    this.opacity = 0.06,
    this.stroke = 1.0,
    this.spacing = 14,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _PatternPainter(
              kind: kind,
              color: color.withValues(alpha: opacity),
              stroke: stroke,
              spacing: spacing,
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}

class _PatternPainter extends CustomPainter {
  final MonoPatternKind kind;
  final Color color;
  final double stroke;
  final double spacing;

  _PatternPainter({
    required this.kind,
    required this.color,
    required this.stroke,
    required this.spacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    switch (kind) {
      case MonoPatternKind.grid:
        for (double x = 0; x <= size.width; x += spacing) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (double y = 0; y <= size.height; y += spacing) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        break;
      case MonoPatternKind.dots:
        final fill = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        for (double x = spacing / 2; x < size.width; x += spacing) {
          for (double y = spacing / 2; y < size.height; y += spacing) {
            canvas.drawCircle(Offset(x, y), stroke * 1.4, fill);
          }
        }
        break;
      case MonoPatternKind.stripes:
        for (double y = -size.width;
            y < size.height + size.width;
            y += spacing) {
          canvas.drawLine(
              Offset(y, 0), Offset(y + size.height, size.height), paint);
        }
        break;
      case MonoPatternKind.arcs:
        final cx = -size.width * 0.2;
        final cy = size.height * 1.1;
        for (double r = spacing * 2; r < size.width * 2.5; r += spacing) {
          canvas.drawCircle(Offset(cx, cy), r, paint);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) =>
      old.kind != kind ||
      old.color != color ||
      old.stroke != stroke ||
      old.spacing != spacing;
}

/// A signature composition — gradient block on the left, content on the right.
/// Used as the "hero" element on Profile / Dashboard / Meal Plan for a layout
/// that feels composed and unique rather than stacked cards.
class SplitHeroCard extends StatelessWidget {
  final double blockFraction;
  final Color blockColor;
  final Gradient? blockGradient;
  final Widget blockContent;
  final Widget content;
  final EdgeInsets contentPadding;
  final double radius;

  const SplitHeroCard({
    super.key,
    required this.blockContent,
    required this.content,
    this.blockFraction = 0.34,
    this.blockColor = AppColors.cyan,
    this.blockGradient,
    this.contentPadding = const EdgeInsets.fromLTRB(20, 22, 22, 22),
    this.radius = AppRadius.lg,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: GlassCard(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(radius),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                flex: (blockFraction * 100).round(),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: blockGradient,
                    color: blockGradient == null ? blockColor : null,
                  ),
                  child: blockContent,
                ),
              ),
              Expanded(
                flex: 100 - (blockFraction * 100).round(),
                child: Padding(padding: contentPadding, child: content),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small accent tag — glows with mint by default. Use sparingly.
class AccentTag extends StatelessWidget {
  final String label;
  final IconData? icon;
  final LinearGradient? gradient;
  const AccentTag({super.key, required this.label, this.icon, this.gradient});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: gradient ?? AppGradients.mintGlow,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.mint.withValues(alpha: 0.4),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: AppColors.void1, size: 14),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: const TextStyle(
                color: AppColors.void1,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable gradient pill for headers/titles — sits on glass surfaces.
class GradientTitle extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Gradient? gradient;
  const GradientTitle(this.text, {super.key, this.style, this.gradient});

  @override
  Widget build(BuildContext context) {
    final base =
        style ?? const TextStyle(fontSize: 22, fontWeight: FontWeight.w800);
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) =>
          (gradient ?? AppGradients.aurora).createShader(rect),
      child: Text(text, style: base.copyWith(color: AppColors.void1)),
    );
  }
}

/// A primary gradient button. Use for hero CTAs.
class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Gradient? gradient;
  final EdgeInsets padding;
  final double radius;

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.gradient,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return AnimatedScale(
      duration: const Duration(milliseconds: 120),
      scale: 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: disabled ? null : onPressed,
          child: Opacity(
            opacity: disabled ? 0.5 : 1.0,
            child: Ink(
              decoration: BoxDecoration(
                gradient: gradient ?? AppGradients.aurora,
                borderRadius: BorderRadius.circular(radius),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.3),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: padding,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: AppColors.void1, size: 18),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.void1,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        shadows: [
                          Shadow(
                            color: Color(0x66000000),
                            offset: Offset(0, 1),
                            blurRadius: 2,
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
      ),
    );
  }
}
