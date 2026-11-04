import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models.dart';
import '../screens/provider_form.dart';
import '../screens/settings.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import '../workspace/agent_tab.dart';
import '../workspace/files_tab.dart';
import '../workspace/preview_tab.dart';
import '../workspace/terminal_tab.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, required this.project});

  final Project project;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  int _tab = 0;

  Future<void> _openProviders() async {
    final state = AppScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.surface,
      builder: (sheetContext) => _ProvidersSheet(
        state: state,
        onPick: (provider) {
          Navigator.of(sheetContext).pop();
          if (!provider.isConfigured) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _editProvider(provider);
            });
            return;
          }
          state.setActiveProvider(provider.id);
        },
        onSettings: () {
          Navigator.of(sheetContext).pop();
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        },
      ),
    );
  }

  Future<void> _editProvider(ProviderConfig provider) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.surface,
      builder: (_) => ProviderFormSheet(provider: provider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final configured = state.configuredProviders;

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
                    onTap: _openProviders,
                    behavior: HitTestBehavior.opaque,
                    child: StatusPill(
                      'Providers',
                      color: configured.isEmpty ? Pal.amber : Pal.ember,
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
              ),
            ),
            if (configured.isNotEmpty)
              Container(
                height: 42,
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Pal.line)),
                ),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Sp.x3,
                    vertical: 7,
                  ),
                  itemCount: configured.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 7),
                  itemBuilder: (context, index) {
                    final provider = configured[index];
                    final active = provider.id == state.activeProviderId;
                    return GestureDetector(
                      onTap: () => state.setActiveProvider(provider.id),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color:
                              active ? Pal.ember.withOpacity(0.12) : Pal.raised,
                          borderRadius: Rd.pill,
                          border: Border.all(
                            color: active ? Pal.ember : Pal.line,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${provider.name} · ${provider.model}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Txt.meta.copyWith(
                              fontSize: 10,
                              color: active ? Pal.text : Pal.textMuted,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
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

class _ProvidersSheet extends StatelessWidget {
  const _ProvidersSheet({
    required this.state,
    required this.onPick,
    required this.onSettings,
  });

  final AppState state;
  final ValueChanged<ProviderConfig> onPick;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final sorted = [...state.providers]..sort((a, b) {
        if (a.ready != b.ready) return a.ready ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x2),
              child: Row(
                children: [
                  Text('Providers', style: Txt.headline.copyWith(fontSize: 22)),
                  const Spacer(),
                  Text(
                    '${state.configuredProviders.length} ready',
                    style: Txt.meta,
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x3),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pick the provider the agent should use. Ones with a key show '
                  'as pills inside the project.',
                  style: Txt.bodySoft,
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: Sp.page),
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const Hairline(),
                itemBuilder: (context, index) {
                  final provider = sorted[index];
                  final active = provider.id == state.activeProviderId;
                  return InkWell(
                    onTap: () => onPick(provider),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: SvgPicture.asset(
                              provider.icon,
                              colorFilter: ColorFilter.mode(
                                provider.ready ? Pal.text : Pal.textDim,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                          const SizedBox(width: Sp.x3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  provider.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Txt.title.copyWith(fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  provider.model.isEmpty
                                      ? 'No model set'
                                      : '${provider.model} · ${provider.keys.where((key) => key.trim().isNotEmpty).length} key${provider.keys.where((key) => key.trim().isNotEmpty).length == 1 ? '' : 's'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Txt.meta,
                                ),
                              ],
                            ),
                          ),
                          StatusPill(
                            active
                                ? 'in use'
                                : provider.ready
                                    ? 'ready'
                                    : 'add key',
                            color: active
                                ? Pal.ember
                                : provider.ready
                                    ? Pal.mint
                                    : Pal.amber,
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 17,
                            color: Pal.textDim,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Sp.page, Sp.x3, Sp.page, Sp.x3),
              child: Row(
                children: [
                  GhostButton(
                    label: 'All settings',
                    icon: Icons.tune_rounded,
                    onTap: onSettings,
                  ),
                  const Spacer(),
                  GhostButton(
                    label: 'Add custom',
                    icon: Icons.add_rounded,
                    onTap: () => onPick(state.newCustomProvider()),
                  ),
                ],
              ),
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
