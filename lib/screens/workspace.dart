import 'package:flutter/material.dart';

import '../core/model_info.dart';
import '../core/usage.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/model_sheet.dart';
import '../widgets/ui.dart';
import '../workspace/agent_tab.dart';
import '../workspace/files_tab.dart';
import '../workspace/preview_tab.dart';
import '../workspace/terminal_tab.dart';
import 'usage_screen.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, required this.project});

  final Project project;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  int _tab = 0;

  void _selectTab(int tab) {
    setState(() => _tab = _tab == tab ? 0 : tab);
  }

  void _back() {
    if (_tab != 0) {
      setState(() => _tab = 0);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final project = state.projectById(widget.project.id);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(Sp.x2, Sp.x2, Sp.x2, Sp.x2),
              decoration: BoxDecoration(
                color: Pal.canvas,
                border: Border(bottom: BorderSide(color: Pal.line)),
              ),
              child: Row(
                children: [
                  IconAction(
                    icon: Icons.arrow_back_rounded,
                    tooltip: _tab == 0 ? 'Back' : 'Conversation',
                    onTap: _back,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _tab = 0),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Txt.title,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${project.kind.label} · ${project.branch}'
                            '${project.repo.isEmpty ? '' : ' · ${project.repo}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Txt.meta.copyWith(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _TabIcon(
                    icon: Icons.folder_open_rounded,
                    label: 'Files',
                    active: _tab == 1,
                    onTap: () => _selectTab(1),
                  ),
                  _TabIcon(
                    icon: Icons.terminal_rounded,
                    label: 'Shell',
                    active: _tab == 2,
                    onTap: () => _selectTab(2),
                  ),
                  _TabIcon(
                    icon: Icons.play_circle_outline_rounded,
                    label: 'Preview',
                    active: _tab == 3,
                    onTap: () => _selectTab(3),
                  ),
                ],
              ),
            ),
            if (_tab == 0)
              _AgentStatusBar(
                state: state,
                project: project,
                onModels: () => showModelSheet(context),
                onUsage: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UsageScreen()),
                ),
              ),
            Expanded(
              child: switch (_tab) {
                0 => AgentTab(project: project),
                1 => FilesTab(project: project),
                2 => TerminalTab(project: project),
                _ => PreviewTab(project: project),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TabIcon extends StatelessWidget {
  const _TabIcon({
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
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: Motion.fast,
            margin: const EdgeInsets.only(left: 2),
            width: 40,
            height: 38,
            decoration: BoxDecoration(
              color: active ? Pal.ember.withOpacity(0.12) : Colors.transparent,
              borderRadius: Rd.sm,
              border: Border.all(
                color:
                    active ? Pal.ember.withOpacity(0.35) : Colors.transparent,
              ),
            ),
            child: Icon(
              icon,
              size: 19,
              color: active ? Pal.ember : Pal.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentStatusBar extends StatelessWidget {
  const _AgentStatusBar({
    required this.state,
    required this.project,
    required this.onModels,
    required this.onUsage,
  });

  final AppState state;
  final Project project;
  final VoidCallback onModels;
  final VoidCallback onUsage;

  @override
  Widget build(BuildContext context) {
    final provider = state.activeProvider;
    final ready = provider.isConfigured;
    final projectUsage = state.usageForProject(project.id);
    final total = projectUsage.totalTokens;
    final today = projectUsage.todayTokens;
    final used = state.contextUsedFor(
      provider.id,
      provider.model,
      projectId: project.id,
    );
    final context = contextLabel(provider.model, used);

    return Container(
      decoration: BoxDecoration(
        color: Pal.surface,
        border: Border(bottom: BorderSide(color: Pal.line)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onUsage,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Sp.x4, 7, Sp.x4, 5),
              child: Row(
                children: [
                  Text(
                    compactTokens(total),
                    style: Txt.title.copyWith(
                      fontFamily: Txt.mono,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'PROJECT TOKENS',
                    style: Txt.overline.copyWith(fontSize: 8.5),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    total == 0
                        ? 'this project'
                        : today == 0
                            ? 'this project · no usage today'
                            : '+${compactTokens(today)} today',
                    style: Txt.meta.copyWith(fontSize: 9.5),
                  ),
                  const Spacer(),
                  Text('usage', style: Txt.meta.copyWith(fontSize: 9)),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded,
                      size: 14, color: Pal.textDim),
                ],
              ),
            ),
          ),
          const Hairline(),
          InkWell(
            onTap: onModels,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Sp.x4, 6, Sp.x4, 7),
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: ready ? Pal.mint : Pal.amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      ready
                          ? '${provider.name} · ${provider.model}'
                          : 'Connect a provider to start',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Txt.meta.copyWith(
                        fontSize: 10.5,
                        color: ready ? Pal.textMuted : Pal.amber,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context,
                    style: Txt.meta.copyWith(
                      fontSize: 9.5,
                      color: context.contains('/') ? Pal.textDim : Pal.textDim,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.unfold_more_rounded, size: 14, color: Pal.textDim),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
