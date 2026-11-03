import 'package:flutter/material.dart';

import '../models/project.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../workspace/agent_tab.dart';
import '../workspace/files_tab.dart';
import '../workspace/preview_tab.dart';
import '../workspace/terminal_tab.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final project = state.projectById(widget.projectId);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              project: project,
              onBack: () => Navigator.of(context).pop(),
              onPreview: () => setState(() => _tab = 3),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  AgentTab(projectId: project.id),
                  FilesTab(projectId: project.id),
                  const TerminalTab(),
                  const PreviewTab(),
                ],
              ),
            ),
            _TabBar(index: _tab, onChanged: (i) => setState(() => _tab = i)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.project,
    required this.onBack,
    required this.onPreview,
  });

  final Project project;
  final VoidCallback onBack;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 8),
          child: Row(
            children: [
              IconAction(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: 'Back to projects',
                size: 17,
                color: Pal.text,
                onTap: onBack,
              ),
              const SizedBox(width: Sp.x1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Txt.title.copyWith(fontSize: 15.5),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.account_tree_outlined,
                          size: 11,
                          color: Pal.textDim,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${project.branch} · ${project.kind.label}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Txt.meta.copyWith(fontSize: 10.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconAction(
                icon: Icons.play_arrow_rounded,
                tooltip: 'Open preview',
                color: Pal.ember,
                size: 24,
                onTap: onPreview,
              ),
            ],
          ),
        ),
        const Hairline(),
      ],
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _items = [
    (Icons.auto_awesome_outlined, 'Agent'),
    (Icons.folder_outlined, 'Files'),
    (Icons.terminal_rounded, 'Shell'),
    (Icons.phone_iphone_rounded, 'Preview'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Pal.canvas,
        border: Border(top: BorderSide(color: Pal.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _TabItem(
                    icon: _items[i].$1,
                    label: _items[i].$2,
                    active: index == i,
                    onTap: () => onChanged(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: active,
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Motion.base,
          curve: Motion.ease,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? Pal.ember.withOpacity(0.09) : Colors.transparent,
            borderRadius: Rd.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: active ? Pal.ember : Pal.textDim,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Txt.meta.copyWith(
                  fontSize: 9.5,
                  letterSpacing: 0.6,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? Pal.ember : Pal.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
