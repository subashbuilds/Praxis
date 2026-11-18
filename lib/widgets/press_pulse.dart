import 'package:flutter/material.dart';

/// A quiet long-press confirmation: the surface dips and springs back while the
/// callback opens its menu, so the press reads as registered before the sheet
/// covers the row.
class PressPulse extends StatefulWidget {
  const PressPulse({
    super.key,
    this.onTap,
    required this.onLongPress,
    required this.child,
  });

  final VoidCallback? onTap;
  final VoidCallback onLongPress;
  final Widget child;

  @override
  State<PressPulse> createState() => _PressPulseState();
}

class _PressPulseState extends State<PressPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 1, end: 0.972)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 36,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 0.972, end: 1.006)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 36,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.006, end: 1)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: 28,
    ),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleLongPress() {
    _controller.forward(from: 0);
    widget.onLongPress();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: _handleLongPress,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
