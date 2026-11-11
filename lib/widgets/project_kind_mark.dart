import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models.dart';

/// Project-kind marks use the official language artwork where Praxis ships it.
/// The Python mark is deliberately not tinted: its blue and yellow artwork is
/// recognisable on every theme.
class ProjectKindMark extends StatelessWidget {
  const ProjectKindMark({
    super.key,
    required this.kind,
    this.size = 16,
  });

  final ProjectKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (kind == ProjectKind.python) {
      return SvgPicture.asset(
        'assets/icons/files/python.svg',
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }
    return Icon(kind.glyph, size: size, color: kind.tint);
  }
}

class ProjectKindBadge extends StatelessWidget {
  const ProjectKindBadge({
    super.key,
    required this.kind,
    this.size = 38,
    this.iconSize = 19,
  });

  final ProjectKind kind;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kind.tint.withOpacity(0.10),
        borderRadius: const BorderRadius.all(Radius.circular(11)),
        border: Border.all(color: kind.tint.withOpacity(0.22)),
      ),
      child: ProjectKindMark(kind: kind, size: iconSize),
    );
  }
}
