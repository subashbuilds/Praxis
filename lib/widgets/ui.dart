import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A terminal prompt inside a rounded frame: the mark for DevNest.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 24, this.color = Pal.ember});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(color),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final inset = stroke / 2;
    final frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - stroke, size.height - stroke),
      Radius.circular(size.width * 0.27),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawRRect(frame, paint);
    final chevron = Path()
      ..moveTo(size.width * 0.33, size.height * 0.35)
      ..lineTo(size.width * 0.46, size.height * 0.5)
      ..lineTo(size.width * 0.33, size.height * 0.65);
    canvas.drawPath(chevron, paint);
    canvas.drawLine(
      Offset(size.width * 0.55, size.height * 0.66),
      Offset(size.width * 0.71, size.height * 0.66),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 20, this.showMark = true});

  final double size;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showMark) ...[
          BrandMark(size: size * 1.2),
          const SizedBox(width: 9),
        ],
        Text(
          'DevNest',
          style: TextStyle(
            fontFamily: Txt.serif,
            fontSize: size * 0.95,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.2,
            color: Pal.text,
          ),
        ),
      ],
    );
  }
}

class Hairline extends StatelessWidget {
  const Hairline({super.key, this.color, this.inset = 0});

  final Color? color;
  final double inset;

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: EdgeInsets.symmetric(horizontal: inset),
        color: color ?? Pal.line,
      );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.color});

  final String text;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Sp.x6, bottom: Sp.x2 + 2),
      child: Row(
        children: [
          Text(text, style: Txt.overline.copyWith(color: color ?? Pal.textDim)),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.radius,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final BorderRadius? radius;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(Sp.x4),
      decoration: BoxDecoration(
        color: color ?? Pal.surface,
        borderRadius: radius ?? Rd.md,
        border: Border.all(color: borderColor ?? Pal.line),
      ),
      child: child,
    );
  }
}

class MonoChip extends StatelessWidget {
  const MonoChip(this.text,
      {super.key, this.icon, this.tint, this.iconSize = 12});

  final String text;
  final IconData? icon;
  final Color? tint;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: Rd.pill,
        border: Border.all(color: Pal.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: iconSize, color: tint ?? Pal.textDim),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Txt.meta.copyWith(color: tint ?? Pal.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text,
      {super.key, required this.color, this.solid = false});

  final String text;
  final Color color;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? color : color.withOpacity(0.12),
        borderRadius: Rd.pill,
        border: Border.all(color: color.withOpacity(solid ? 1 : 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: solid ? Pal.canvas : color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: Txt.meta.copyWith(
              color: solid ? Pal.canvas : color,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class GlyphBadge extends StatelessWidget {
  const GlyphBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 38,
    this.iconSize = 19,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: const BorderRadius.all(Radius.circular(11)),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.color,
    this.size = 20,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, size: size, color: color ?? Pal.textMuted),
          ),
        ),
      ),
    );
  }
}

class EmberButton extends StatelessWidget {
  const EmberButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.loading = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: Motion.fast,
        opacity: enabled ? 1 : 0.55,
        child: Container(
          height: compact ? 40 : 52,
          padding: EdgeInsets.symmetric(horizontal: compact ? Sp.x4 : Sp.x5),
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Pal.ember,
            borderRadius: Rd.md,
          ),
          child: Row(
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Pal.onEmber,
                  ),
                )
              else if (icon != null)
                Icon(icon, size: 17, color: Pal.onEmber),
              if (loading || icon != null) const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.button,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, this.onTap, this.icon});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: Sp.x3),
        decoration: BoxDecoration(
          borderRadius: Rd.sm,
          border: Border.all(color: Pal.lineStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: Pal.textMuted),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: Txt.label.copyWith(
                color: Pal.text,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 14),
        decoration:
            const BoxDecoration(color: Pal.lineStrong, borderRadius: Rd.pill),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlyphBadge(icon: icon, color: Pal.textDim, size: 34, iconSize: 17),
        const SizedBox(height: Sp.x3),
        Text(title, style: Txt.title),
        const SizedBox(height: 4),
        Text(body, style: Txt.bodySoft),
      ],
    );
  }
}

InputDecoration appField(String hint, {Widget? suffix, String? label}) =>
    InputDecoration(
      isDense: true,
      labelText: label,
      hintText: hint,
      hintStyle: Txt.bodySoft.copyWith(color: Pal.textDim),
      labelStyle: Txt.label.copyWith(color: Pal.textDim),
      suffixIcon: suffix,
      filled: true,
      fillColor: Pal.raised,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: Sp.x3, vertical: Sp.x3 + 2),
      border: const OutlineInputBorder(
        borderRadius: Rd.sm,
        borderSide: BorderSide(color: Pal.line),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: Rd.sm,
        borderSide: BorderSide(color: Pal.line),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: Rd.sm,
        borderSide: BorderSide(color: Pal.ember),
      ),
    );

String relativeTime(DateTime time) {
  final delta = DateTime.now().difference(time);
  if (delta.inMinutes < 1) return 'just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  if (delta.inDays == 1) return 'yesterday';
  if (delta.inDays < 7) return '${delta.inDays}d ago';
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}

String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
