import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'settings.dart';
import 'workspace.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Sp.page, Sp.x2, Sp.page, Sp.x8),
          children: [
            Row(
              children: [
                const Wordmark(),
                const Spacer(),
                IconAction(
                  icon: Icons.tune_rounded,
                  tooltip: 'Settings',
                  onTap: () => _openSettings(context),
                ),
              ],
            ),
            const SizedBox(height: 30),
            const Text('Your pocket\ndev box.', style: Txt.display),
            const SizedBox(height: 12),
            const Text(
              'Edit files, run a shell, preview the app, and let an agent change '
              'it — all on this phone, in one folder you can read.',
              style: Txt.bodySoft,
            ),
            const SizedBox(height: 18),
            _ModelLine(
                provider: state.activeProvider,
                onTap: () => _openSettings(context)),
            const SizedBox(height: 18),
            EmberButton(
              label: 'New project',
              icon: Icons.add_rounded,
              onTap: () => _newProject(context),
            ),
            SectionLabel(
              'PROJECTS',
              trailing: Text('${state.projects.length}', style: Txt.meta),
            ),
            if (state.projects.isEmpty)
              const Panel(
                child: EmptyState(
                  icon: Icons.folder_open_rounded,
                  title: 'No projects yet',
                  body:
                      'Create one and it appears here as a real folder on disk.',
                ),
              )
            else
              for (final project in state.projects)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ProjectCard(
                    project: project,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WorkspaceScreen(project: project),
                      ),
                    ),
                    onDelete: () => _confirmDelete(context, state, project),
                  ),
                ),
            const SizedBox(height: Sp.x5),
            const Text(
              'Files, keys and chats stay on this device.',
              style: Txt.meta,
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  Future<void> _newProject(BuildContext context) async {
    final navigator = Navigator.of(context);
    final created = await showModalBottomSheet<Project>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.surface,
      builder: (_) => const _NewProjectSheet(),
    );
    if (created != null && navigator.mounted) {
      await navigator.push(
        MaterialPageRoute(builder: (_) => WorkspaceScreen(project: created)),
      );
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, AppState state, Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: const Text('Delete project?'),
        content: Text(
          'This deletes ${project.name} and every file in it from this device. '
          'It cannot be undone.',
          style: Txt.bodySoft,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Pal.rose),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await state.deleteProject(project);
    }
  }
}

class _ModelLine extends StatelessWidget {
  const _ModelLine({required this.provider, required this.onTap});

  final ProviderConfig provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ready = provider.isConfigured;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              ready ? Icons.bolt_rounded : Icons.key_off_rounded,
              size: 17,
              color: ready ? Pal.mint : Pal.amber,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ready
                    ? '${provider.name} · ${provider.model}'
                    : 'Connect a model',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Txt.label.copyWith(
                  color: ready ? Pal.textMuted : Pal.amber,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(ready ? 'ready' : 'set up', style: Txt.meta),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: Pal.textDim),
          ],
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.onTap,
    required this.onDelete,
  });

  final Project project;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final kind = project.kind;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(Sp.x3 + 2),
        decoration: BoxDecoration(
          color: Pal.surface,
          borderRadius: Rd.md,
          border: Border.all(color: Pal.line),
        ),
        child: Row(
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
                    style: Txt.title,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${kind.label} · ${relativeTime(project.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.meta,
                  ),
                ],
              ),
            ),
            IconAction(
              icon: Icons.more_horiz_rounded,
              tooltip: 'Project options',
              size: 18,
              onTap: onDelete,
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: Pal.textDim),
          ],
        ),
      ),
    );
  }
}

class _NewProjectSheet extends StatefulWidget {
  const _NewProjectSheet();

  @override
  State<_NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends State<_NewProjectSheet> {
  final _name = TextEditingController(text: 'my-project');
  ProjectKind _kind = ProjectKind.web;
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    final state = AppScope.of(context);
    final navigator = Navigator.of(context);
    final project = await state.createProject(_name.text, _kind);
    if (!mounted) return;
    navigator.pop(project);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            const Text('Create project', style: Txt.headline),
            const SizedBox(height: 6),
            const Text(
              'A folder is created under the app’s documents directory. '
              'Everything works offline except model calls.',
              style: Txt.bodySoft,
            ),
            const SizedBox(height: Sp.x4),
            TextField(
              controller: _name,
              style: Txt.body,
              cursorColor: Pal.ember,
              textInputAction: TextInputAction.done,
              decoration: appField('project name'),
            ),
            const SizedBox(height: Sp.x4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in ProjectKind.values)
                  _KindChip(
                    kind: kind,
                    selected: kind == _kind,
                    onTap: () => setState(() => _kind = kind),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(_kind.blurb, style: Txt.meta),
            const SizedBox(height: Sp.x5),
            EmberButton(
              label: 'Create project',
              icon: Icons.arrow_forward_rounded,
              loading: _creating,
              onTap: _create,
            ),
          ],
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip(
      {required this.kind, required this.selected, required this.onTap});

  final ProjectKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? kind.tint.withOpacity(0.14) : Pal.raised,
          borderRadius: Rd.sm,
          border: Border.all(color: selected ? kind.tint : Pal.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(kind.glyph,
                size: 15, color: selected ? kind.tint : Pal.textDim),
            const SizedBox(width: 7),
            Text(
              kind.label,
              style: Txt.label.copyWith(
                color: selected ? Pal.text : Pal.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
