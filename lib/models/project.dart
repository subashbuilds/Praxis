import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum ProjectKind { flutter, node, python }

extension ProjectKindX on ProjectKind {
  String get label => switch (this) {
        ProjectKind.flutter => 'Flutter',
        ProjectKind.node => 'Node',
        ProjectKind.python => 'Python',
      };

  IconData get glyph => switch (this) {
        ProjectKind.flutter => Icons.flutter_dash,
        ProjectKind.node => Icons.javascript,
        ProjectKind.python => Icons.code,
      };

  Color get tint => switch (this) {
        ProjectKind.flutter => Pal.sky,
        ProjectKind.node => Pal.mint,
        ProjectKind.python => Pal.amber,
      };
}

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.path,
    required this.branch,
    required this.kind,
    required this.updated,
    this.running = false,
  });

  final String id;
  final String name;
  final String path;
  final String branch;
  final ProjectKind kind;
  final String updated;
  final bool running;
}
