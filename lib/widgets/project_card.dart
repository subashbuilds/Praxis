import 'package:flutter/material.dart';

import '../models/project.dart';
import '../theme/tokens.dart';
import 'common.dart';

class ProjectCard extends StatefulWidget {
  const ProjectCard({super.key, required this.project, required this.onTap});

  final Project project;
  final VoidCallback onTap;

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final kind = project.kind;

    return Semantics(
      button: true,
      label: '${project.name}, ${kind.label}, branch ${project.branch}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.ease,
          padding: const EdgeInsets.all(Sp.x3 + 2),
          decoration: BoxDecoration(
            color: _pressed ? Pal.raised : Pal.surface,
            borderRadius: Rd.md,
            border: Border.all(color: _pressed ? Pal.lineStrong : Pal.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GlyphBadge(icon: kind.glyph, color: kind.tint),
                  const SizedBox(width: Sp.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.title.copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          project.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.meta,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Sp.x2),
                  const Icon(Icons.chevron_right_rounded,
                      size: 20, color: Pal.textDim),
                ],
              ),
              const SizedBox(height: Sp.x3),
              Row(
                children: [
                  Flexible(
                    child: MonoChip(
                      project.branch,
                      icon: Icons.account_tree_outlined,
                      tint: Pal.textMuted,
                    ),
                  ),
                  const SizedBox(width: Sp.x2),
                  Flexible(
                    child: Text(
                      project.updated,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Txt.meta,
                    ),
                  ),
                  const Spacer(),
                  if (project.running)
                    const StatusPill('running', color: Pal.mint)
                  else
                    MonoChip(kind.label, tint: kind.tint),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
