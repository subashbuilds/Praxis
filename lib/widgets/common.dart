import 'package:flutter/material.dart';

import '../theme/tokens.dart';

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

class MonoChip extends StatelessWidget {
  const MonoChip(
    this.text, {
    super.key,
    this.icon,
    this.tint,
    this.iconSize = 12,
  });

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

/// A bordered inset card: the app's only container shape.
class Panel extends StatelessWidget {
  const Panel(
      {super.key, required this.child, this.padding, this.color, this.radius});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(Sp.x4),
      decoration: BoxDecoration(
        color: color ?? Pal.surface,
        borderRadius: radius ?? Rd.md,
        border: Border.all(color: Pal.line),
      ),
      child: child,
    );
  }
}
