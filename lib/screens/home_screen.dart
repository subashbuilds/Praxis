import 'package:flutter/material.dart';

import '../models/project.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/ember_button.dart';
import '../widgets/project_card.dart';
import 'settings_screen.dart';
import 'workspace_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _newProject(BuildContext context, AppState state) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _NewProjectSheet(
          onCreate: (name, kind) {
            final project = state.createProject(name, kind);
            Navigator.of(sheetContext).pop();
            _push(context, WorkspaceScreen(projectId: project.id));
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x2, Sp.page, Sp.x8),
          children: [
            Row(
              children: [
                const Wordmark(size: 21),
                const Spacer(),
                IconAction(
                  icon: Icons.settings_outlined,
                  tooltip: 'Settings',
                  onTap: () => _push(context, const SettingsScreen()),
                ),
              ],
            ),
            const SizedBox(height: Sp.x8 + 4),
            Row(
              children: [
                Text('PROJECTS',
                    style: Txt.overline.copyWith(color: Pal.ember)),
                const Spacer(),
                Text('${state.projects.length} on device', style: Txt.meta),
              ],
            ),
            const SizedBox(height: Sp.x3),
            const Text('Your workbench.', style: Txt.headline),
            const SizedBox(height: Sp.x2),
            const Text(
              'Agent, shell and preview, running on this phone. '
              'Keys stay on the device.',
              style: Txt.bodySoft,
            ),
            const SizedBox(height: Sp.x5 + 2),
            EmberButton(
              label: 'New project',
              icon: Icons.add_rounded,
              onPressed: () => _newProject(context, state),
            ),
            const SizedBox(height: Sp.x6 + 4),
            const Row(
              children: [
                Text('RECENT', style: Txt.overline),
                Spacer(),
                Text('branch · updated', style: Txt.meta),
              ],
            ),
            const SizedBox(height: Sp.x3),
            for (final project in state.projects) ...[
              ProjectCard(
                project: project,
                onTap: () =>
                    _push(context, WorkspaceScreen(projectId: project.id)),
              ),
              const SizedBox(height: Sp.x2 + 2),
            ],
            const SizedBox(height: Sp.x3),
            _DeviceSlot(
              state: state,
              onTap: () => _push(context, const SettingsScreen()),
            ),
            const SizedBox(height: Sp.x8),
            const Center(
                child: Text('PolyDev 1.0.0 · build 13', style: Txt.meta)),
            const SizedBox(height: Sp.x1),
            Center(
              child: Text(
                'Local-first · rebuilt from the shipped build',
                textAlign: TextAlign.center,
                style: Txt.meta.copyWith(color: Pal.textDim.withOpacity(0.8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceSlot extends StatelessWidget {
  const _DeviceSlot({required this.state, required this.onTap});

  final AppState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Panel(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        child: Row(
          children: [
            const GlyphBadge(
              icon: Icons.devices_rounded,
              color: Pal.amber,
              size: 34,
              iconSize: 17,
            ),
            const SizedBox(width: Sp.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: Sp.x2,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${state.devicesUsed} of ${state.devicesMax} devices',
                        style: Txt.body.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const StatusPill('PRO', color: Pal.ember),
                    ],
                  ),
                  const SizedBox(height: 3),
                  const Text('One more install fits this plan.',
                      style: Txt.meta),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Pal.textDim,
            ),
          ],
        ),
      ),
    );
  }
}

class _NewProjectSheet extends StatefulWidget {
  const _NewProjectSheet({required this.onCreate});

  final void Function(String name, ProjectKind kind) onCreate;

  @override
  State<_NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends State<_NewProjectSheet> {
  final _controller = TextEditingController();
  ProjectKind _kind = ProjectKind.flutter;
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final valid = _controller.text.trim().isNotEmpty;
      if (valid != _valid) setState(() => _valid = valid);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New project', style: Txt.headline.copyWith(fontSize: 22)),
              const SizedBox(height: 6),
              Text(
                'A folder on this device, with Alpine and a shell already running.',
                style: Txt.bodySoft.copyWith(fontSize: 13),
              ),
              const SizedBox(height: Sp.x5),
              const Text('NAME', style: Txt.overline),
              const SizedBox(height: Sp.x2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Pal.raised,
                  borderRadius: Rd.md,
                  border: Border.all(color: Pal.lineStrong),
                ),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  style: Txt.body.copyWith(fontSize: 14),
                  cursorColor: Pal.ember,
                  onSubmitted: (_) {
                    if (_valid) {
                      widget.onCreate(_controller.text, _kind);
                    }
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    hintText: 'polydev-web',
                    hintStyle: Txt.bodySoft.copyWith(color: Pal.textDim),
                  ),
                ),
              ),
              const SizedBox(height: Sp.x5),
              const Text('TEMPLATE', style: Txt.overline),
              const SizedBox(height: Sp.x2 + 2),
              Row(
                children: [
                  for (final kind in ProjectKind.values) ...[
                    Expanded(
                      child: _KindChip(
                        kind: kind,
                        selected: _kind == kind,
                        onTap: () => setState(() => _kind = kind),
                      ),
                    ),
                    if (kind != ProjectKind.values.last)
                      const SizedBox(width: Sp.x2),
                  ],
                ],
              ),
              const SizedBox(height: Sp.x6),
              EmberButton(
                label: 'Create project',
                icon: Icons.arrow_forward_rounded,
                onPressed: _valid
                    ? () => widget.onCreate(_controller.text, _kind)
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final ProjectKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Pal.ember.withOpacity(0.10) : Pal.raised,
          borderRadius: Rd.sm,
          border: Border.all(
            color: selected ? Pal.ember.withOpacity(0.55) : Pal.line,
          ),
        ),
        child: Column(
          children: [
            Icon(kind.glyph,
                size: 17, color: selected ? Pal.ember : Pal.textMuted),
            const SizedBox(height: 6),
            Text(
              kind.label,
              style: Txt.meta.copyWith(
                color: selected ? Pal.text : Pal.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
