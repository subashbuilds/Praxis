import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import '../workspace/agent_tab.dart';
import '../workspace/files_tab.dart';
import '../workspace/preview_tab.dart';
import '../workspace/terminal_tab.dart';
import 'settings.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, required this.project});

  final Project project;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final provider = state.activeProvider;
    final ready = provider.isConfigured;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(Sp.x2, Sp.x2, Sp.x2, Sp.x2),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Pal.line)),
              ),
              child: Row(
                children: [
                  IconAction(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.title,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.project.kind.label} · ~/${widget.project.id}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.meta.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: StatusPill(
                      ready ? provider.model : 'Connect a model',
                      color: ready ? Pal.mint : Pal.amber,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (_tab) {
                0 => AgentTab(project: widget.project),
                1 => FilesTab(project: widget.project),
                2 => TerminalTab(project: widget.project),
                _ => PreviewTab(project: widget.project),
              },
            ),
            _TabBar(
              current: _tab,
              onSelect: (value) => setState(() => _tab = value),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onSelect});

  final int current;
  final ValueChanged<int> onSelect;

  static const _tabs = [
    (Icons.auto_awesome_rounded, 'Agent'),
    (Icons.folder_open_rounded, 'Files'),
    (Icons.terminal_rounded, 'Shell'),
    (Icons.play_circle_outline_rounded, 'Preview'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Pal.surface,
        border: Border(top: BorderSide(color: Pal.line)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _tabs[i].$1,
                        size: 20,
                        color: i == current ? Pal.ember : Pal.textDim,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _tabs[i].$2,
                        style: Txt.meta.copyWith(
                          fontSize: 10,
                          color: i == current ? Pal.text : Pal.textDim,
                          fontWeight:
                              i == current ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
