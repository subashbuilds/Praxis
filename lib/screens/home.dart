import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/confirm_dialog.dart';
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
            Text('Your pocket\ndev box.', style: Txt.display),
            const SizedBox(height: 12),
            Text(
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
            const SizedBox(height: 8),
            GhostButton(
              label: 'Clone a repository',
              icon: Icons.call_split_rounded,
              onTap: () => _newProject(context, clone: true),
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
            Text(
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

  Future<void> _newProject(BuildContext context, {bool clone = false}) async {
    final navigator = Navigator.of(context);
    final created = await showModalBottomSheet<Project>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      builder: (_) => _NewProjectSheet(clone: clone),
    );
    if (created != null && navigator.mounted) {
      await navigator.push(
        MaterialPageRoute(builder: (_) => WorkspaceScreen(project: created)),
      );
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, AppState state, Project project) async {
    final confirmed = await showPraxisConfirm(
      context,
      title: 'Delete project?',
      body:
          'This deletes ${project.name} and every file in it from this device. '
          'It cannot be undone.',
      confirmLabel: 'Delete project',
      destructive: true,
      icon: Icons.delete_outline_rounded,
      details: [ConfirmDetail('Project', project.name)],
    );
    if (confirmed) {
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
            Icon(Icons.chevron_right_rounded, size: 16, color: Pal.textDim),
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
            Icon(Icons.chevron_right_rounded, size: 18, color: Pal.textDim),
          ],
        ),
      ),
    );
  }
}

class _NewProjectSheet extends StatefulWidget {
  const _NewProjectSheet({this.clone = false});

  final bool clone;

  @override
  State<_NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends State<_NewProjectSheet> {
  late final TextEditingController _name;
  final _repo = TextEditingController();
  final _branch = TextEditingController(text: 'main');
  late bool _clone;
  ProjectKind _kind = ProjectKind.web;
  bool _creating = false;
  bool _loadingBranches = false;
  String? _error;
  String? _branchError;
  List<String> _branches = const [];

  @override
  void initState() {
    super.initState();
    _clone = widget.clone;
    _name = TextEditingController(
      text: widget.clone ? '' : 'my-project',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _repo.dispose();
    _branch.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    if (_loadingBranches || _repo.text.trim().isEmpty) return;
    final state = AppScope.of(context);
    setState(() {
      _loadingBranches = true;
      _branchError = null;
    });
    try {
      final branches = await state.cloneBranches(
        _repo.text,
        token: state.activeGithub?.token ?? '',
      );
      if (!mounted) return;
      setState(() {
        _branches = branches;
        if (branches.isNotEmpty && !branches.contains(_branch.text.trim())) {
          _branch.text = branches.contains('main') ? 'main' : branches.first;
        }
        if (branches.isEmpty) {
          _branchError = 'This repository has no branches to choose from.';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _branchError = '$error');
    } finally {
      if (mounted) setState(() => _loadingBranches = false);
    }
  }

  Future<void> _chooseBranch() async {
    if (_branches.isEmpty) await _loadBranches();
    if (!mounted || _branches.isEmpty) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      builder: (_) => _CloneBranchSheet(
        branches: _branches,
        current: _branch.text.trim(),
      ),
    );
    if (chosen != null && mounted) setState(() => _branch.text = chosen);
  }

  Future<void> _create() async {
    if (_creating) return;
    if (_clone && _branches.isEmpty) {
      await _loadBranches();
      if (!mounted) return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    final state = AppScope.of(context);
    final navigator = Navigator.of(context);
    try {
      final project = _clone
          ? await state.cloneProject(
              name: _name.text,
              repoUrl: _repo.text,
              branch:
                  _branch.text.trim().isEmpty ? 'main' : _branch.text.trim(),
              token: state.activeGithub?.token ?? '',
            )
          : await state.createProject(_name.text, _kind);
      if (!mounted) return;
      navigator.pop(project);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = '$error';
      });
    }
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    _clone ? 'Clone a repository' : 'Create project',
                    style: Txt.headline,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _clone = !_clone),
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    _clone ? 'Start blank' : 'Clone repo',
                    style: Txt.meta.copyWith(color: Pal.ember),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _clone
                  ? 'The selected GitHub branch is downloaded as a real project. '
                      'It uses your active GitHub account for private repositories.'
                  : 'A folder is created under the app’s documents directory. '
                      'Everything works offline except model calls.',
              style: Txt.bodySoft,
            ),
            const SizedBox(height: Sp.x4),
            if (_clone) ...[
              TextField(
                controller: _repo,
                autofocus: true,
                style: Txt.body,
                cursorColor: Pal.ember,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _loadBranches(),
                decoration: appField(
                  'owner/repo or github.com URL',
                  label: 'Repository',
                  suffix: _loadingBranches
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : IconAction(
                          icon: Icons.account_tree_outlined,
                          tooltip: 'Load branches',
                          size: 17,
                          onTap: _loadBranches,
                        ),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _chooseBranch,
                behavior: HitTestBehavior.opaque,
                child: InputDecorator(
                  decoration: appField('main', label: 'Branch').copyWith(
                    suffixIcon: Icon(
                      Icons.unfold_more_rounded,
                      size: 18,
                      color: Pal.textDim,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_tree_outlined,
                          size: 15, color: Pal.textDim),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _branch.text.trim().isEmpty
                              ? 'Choose a branch'
                              : _branch.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.code.copyWith(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_branchError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _branchError!,
                  style: Txt.meta.copyWith(color: Pal.rose, height: 1.35),
                ),
              ],
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _name,
              style: Txt.body,
              cursorColor: Pal.ember,
              textInputAction: TextInputAction.done,
              decoration: appField(
                _clone
                    ? 'Optional — defaults to repository name'
                    : 'project name',
                label: _clone ? 'Project name (optional)' : null,
              ),
            ),
            if (!_clone) ...[
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
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: Txt.bodySoft.copyWith(color: Pal.rose)),
            ],
            const SizedBox(height: Sp.x5),
            EmberButton(
              label: _clone ? 'Clone repository' : 'Create project',
              icon:
                  _clone ? Icons.download_rounded : Icons.arrow_forward_rounded,
              loading: _creating,
              onTap: _create,
            ),
          ],
        ),
      ),
    );
  }
}

class _CloneBranchSheet extends StatelessWidget {
  const _CloneBranchSheet({required this.branches, required this.current});

  final List<String> branches;
  final String current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose a branch',
                    style: Txt.headline.copyWith(fontSize: 21)),
                const SizedBox(height: 3),
                Text('The repository is downloaded at this branch.',
                    style: Txt.meta),
              ],
            ),
          ),
          const Hairline(),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: branches.length,
              itemBuilder: (context, index) {
                final branch = branches[index];
                final active = branch == current;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.account_tree_outlined,
                    size: 18,
                    color: active ? Pal.ember : Pal.textDim,
                  ),
                  title: Text(branch, style: Txt.code.copyWith(fontSize: 12.5)),
                  trailing: active
                      ? Icon(Icons.check_rounded, size: 17, color: Pal.ember)
                      : null,
                  onTap: () => Navigator.of(context).pop(branch),
                );
              },
            ),
          ),
        ],
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
