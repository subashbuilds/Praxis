import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class EmberButton extends StatefulWidget {
  const EmberButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.expand = true,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expand;
  final bool dense;

  @override
  State<EmberButton> createState() => _EmberButtonState();
}

class _EmberButtonState extends State<EmberButton> {
  bool _down = false;

  void _set(bool value) {
    if (_down == value || widget.onPressed == null) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _down ? 0.985 : 1,
          duration: Motion.fast,
          curve: Motion.ease,
          child: Container(
            height: widget.dense ? 40 : 50,
            width: widget.expand ? double.infinity : null,
            padding:
                EdgeInsets.symmetric(horizontal: widget.expand ? Sp.x4 : Sp.x4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: enabled
                    ? const [Pal.ember, Pal.emberDeep]
                    : const [Pal.overlay, Pal.overlay],
              ),
              borderRadius: Rd.md,
              border: enabled ? null : Border.all(color: Pal.lineStrong),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: Pal.ember.withOpacity(0.20),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: widget.dense ? 16 : 18,
                    color: enabled ? Pal.onEmber : Pal.textDim,
                  ),
                  const SizedBox(width: Sp.x2),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.button.copyWith(
                      color: enabled ? Pal.onEmber : Pal.textDim,
                      fontSize: widget.dense ? 13 : 14.5,
                    ),
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

class GhostButton extends StatefulWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.expand = false,
    this.dense = false,
    this.tint,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expand;
  final bool dense;
  final Color? tint;

  @override
  State<GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<GhostButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final tint = widget.tint ?? Pal.textMuted;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: Motion.fast,
          height: widget.dense ? 38 : 46,
          width: widget.expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: Sp.x3 + 2),
          decoration: BoxDecoration(
            color: _down ? Pal.overlay : Colors.transparent,
            borderRadius: Rd.md,
            border: Border.all(color: _down ? Pal.lineStrong : Pal.line),
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 16, color: tint),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.label.copyWith(
                    color: tint,
                    fontWeight: FontWeight.w600,
                    fontSize: widget.dense ? 12 : 13,
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
