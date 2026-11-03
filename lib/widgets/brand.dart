import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';

import '../theme/tokens.dart';

/// The mark shipped in the APK, tinted with the current brand color.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 22, this.color = Pal.ember});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/polydev.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
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
          BrandMark(size: size * 1.05),
          const SizedBox(width: 9),
        ],
        Text(
          'PolyDev',
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
