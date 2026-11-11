import 'package:flutter/material.dart';

import '../core/integrations.dart';
import '../core/linux_environment.dart';
import '../core/project_templates.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/project_kind_mark.dart';
import '../widgets/ui.dart';
import 'settings.dart';
import 'workspace.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final projects = state.projectsByActivity;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Sp.page, Sp.x2, Sp.page, Sp.x1),
              child: Row(
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
            ),
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(Sp.page, Sp.x5, Sp.page, Sp.x8),
                children: [
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
                    trailing: Text('${projects.length}', style: Txt.meta),
                  ),
                  if (projects.isEmpty)
                    const Panel(
                      child: EmptyState(
                        icon: Icons.folder_open_rounded,
                        title: 'No projects yet',
                        body:
                            'Create one and it appears here as a real folder on disk.',
                      ),
                    )
                  else
                    for (final project in projects)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ProjectCard(
                          project: project,
                          lastActivity: state.lastActivityFor(project),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => WorkspaceScreen(project: project),
                            ),
                          ),
                          onDelete: () =>
                              _confirmDelete(context, state, project),
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
    required this.lastActivity,
    required this.onTap,
    required this.onDelete,
  });

  final Project project;
  final DateTime lastActivity;
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
            ProjectKindBadge(kind: kind),
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
                    '${kind.label} · ${relativeTime(lastActivity)}',
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
  ProjectTemplate? _template;
  TemplateRuntime? _expandedRuntime;
  bool _creating = false;
  bool _loadingBranches = false;
  bool _loadingRepos = false;
  String? _error;
  String? _branchError;
  List<String> _branches = const [];
  IntegrationAccount? _cloneAccount;

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
      final account = _cloneAccount ?? state.activeGithub;
      final branches = await state.cloneBranches(
        _repo.text,
        token: account?.token ?? '',
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

  Future<void> _chooseRepo() async {
    if (_loadingRepos) return;
    final state = AppScope.of(context);
    final accounts = state.integrations.ofKind(IntegrationKind.github);
    if (accounts.isEmpty) {
      setState(() => _error = 'Connect GitHub in Integrations first.');
      return;
    }
    setState(() {
      _loadingRepos = true;
      _error = null;
    });
    try {
      final groups = await Future.wait(accounts.map((account) async {
        try {
          return _RepositoryGroup(
            account: account,
            repos: await state.githubRepositories(account),
          );
        } catch (error) {
          return _RepositoryGroup(account: account, error: '$error');
        }
      }));
      if (!mounted) return;
      final chosen = await showModalBottomSheet<_RepositoryChoice>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: Pal.surface,
        builder: (_) => _RepositoryPickerSheet(groups: groups),
      );
      if (chosen == null || !mounted) return;
      await state.activateAccount(chosen.account);
      if (!mounted) return;
      setState(() {
        _cloneAccount = chosen.account;
        _repo.text =
            'https://github.com/${chosen.repo.owner}/${chosen.repo.name}';
        _branch.text = chosen.repo.defaultBranch;
        _branches = const [];
      });
      await _loadBranches();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not load repositories: $error');
      }
    } finally {
      if (mounted) setState(() => _loadingRepos = false);
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

  TemplateRuntime? _templateRuntime(LinuxRuntime runtime) => switch (runtime) {
        LinuxRuntime.node => TemplateRuntime.node,
        LinuxRuntime.python => TemplateRuntime.python,
        _ => null,
      };

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
    final cloneAccount = _cloneAccount ?? state.activeGithub;
    try {
      final project = _clone
          ? await state.cloneProject(
              name: _name.text,
              repoUrl: _repo.text,
              branch:
                  _branch.text.trim().isEmpty ? 'main' : _branch.text.trim(),
              token: cloneAccount?.token ?? '',
            )
          : await state.createProject(
              _name.text,
              _template?.kind ?? _kind,
              template: _template,
            );
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
    final state = AppScope.of(context);
    final githubAccounts = state.integrations.ofKind(IntegrationKind.github);
    final cloneAccount = _cloneAccount ?? state.activeGithub;
    final installedRuntimes = [
      for (final runtime in LinuxRuntime.values)
        if (state.linux?.runtimes[runtime]?.installed ?? false) runtime,
    ];
    final runtimeKinds = <ProjectKind>[
      if (installedRuntimes.contains(LinuxRuntime.node)) ProjectKind.node,
      if (installedRuntimes.contains(LinuxRuntime.python)) ProjectKind.python,
      if (installedRuntimes.contains(LinuxRuntime.php)) ProjectKind.php,
      if (installedRuntimes.contains(LinuxRuntime.go)) ProjectKind.go,
    ];
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
                  ? 'Pick a private or public repository from any connected '
                      'GitHub account, then clone the branch as a real project.'
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
                onChanged: (_) {
                  if (_cloneAccount != null) {
                    setState(() => _cloneAccount = null);
                  }
                },
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
              Align(
                alignment: Alignment.centerRight,
                child: GhostButton(
                  label: _loadingRepos
                      ? 'Loading repositories…'
                      : 'Select from GitHub',
                  icon: Icons.folder_open_outlined,
                  onTap: _loadingRepos ? null : _chooseRepo,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                githubAccounts.isEmpty
                    ? 'Connect a GitHub account in Integrations to browse '
                        'private repositories.'
                    : cloneAccount == null
                        ? '${githubAccounts.length} GitHub account'
                            '${githubAccounts.length == 1 ? '' : 's'} connected. '
                            'Private repositories are included.'
                        : 'Using @${cloneAccount.displayName}. Private and public '
                            'repositories are included.',
                style: Txt.meta.copyWith(
                  fontSize: 9.5,
                  color: githubAccounts.isEmpty ? Pal.amber : Pal.textDim,
                  height: 1.4,
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
                  for (final kind in const [
                    ProjectKind.web,
                    ProjectKind.flutter,
                    ProjectKind.blank,
                  ])
                    _KindChip(
                      kind: kind,
                      selected: _template == null && kind == _kind,
                      onTap: () => setState(() {
                        _kind = kind;
                        _template = null;
                        _expandedRuntime = null;
                      }),
                    ),
                ],
              ),
              if (runtimeKinds.isNotEmpty) ...[
                const SizedBox(height: Sp.x3),
                Text('INSTALLED RUNTIME TEMPLATES',
                    style: Txt.overline.copyWith(fontSize: 8.5)),
                const SizedBox(height: 7),
                for (final runtime in installedRuntimes)
                  if (_templateRuntime(runtime) != null)
                    _RuntimeTemplateGroup(
                      runtime: _templateRuntime(runtime)!.label,
                      icon: runtime == LinuxRuntime.python
                          ? Icons.code_rounded
                          : Icons.hexagon_outlined,
                      templates: templatesFor(_templateRuntime(runtime)!),
                      expanded: _expandedRuntime == _templateRuntime(runtime),
                      selectedId: _template?.id,
                      onToggle: () => setState(() {
                        _expandedRuntime =
                            _expandedRuntime == _templateRuntime(runtime)
                                ? null
                                : _templateRuntime(runtime);
                      }),
                      onSelect: (template) => setState(() {
                        _template = template;
                        _kind = template.kind;
                      }),
                    ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  'Install a runtime from the Linux environment to add its '
                  'starter template here.',
                  style: Txt.meta.copyWith(fontSize: 9),
                ),
              ],
              const SizedBox(height: 10),
              Text(_template?.description ?? _kind.blurb, style: Txt.meta),
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

class _RuntimeTemplateGroup extends StatelessWidget {
  const _RuntimeTemplateGroup({
    required this.runtime,
    required this.icon,
    required this.templates,
    required this.expanded,
    required this.selectedId,
    required this.onToggle,
    required this.onSelect,
  });

  final String runtime;
  final IconData icon;
  final List<ProjectTemplate> templates;
  final bool expanded;
  final String? selectedId;
  final VoidCallback onToggle;
  final ValueChanged<ProjectTemplate> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = templates.where((template) => template.id == selectedId);
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: Rd.sm,
        border: Border.all(
          color: selected.isNotEmpty ? Pal.mint.withOpacity(0.45) : Pal.line,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: Rd.sm,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Icon(icon, size: 15, color: Pal.mint),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      selected.isEmpty ? runtime : selected.first.name,
                      style: Txt.label.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text('${templates.length}',
                      style: Txt.meta.copyWith(fontSize: 9)),
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 17,
                    color: Pal.textDim,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            for (final template in templates)
              InkWell(
                onTap: () => onSelect(template),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(26, 7, 10, 7),
                  child: Row(
                    children: [
                      Icon(
                        template.id == selectedId
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 14,
                        color:
                            template.id == selectedId ? Pal.mint : Pal.textDim,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          template.name,
                          style: Txt.meta.copyWith(
                            fontSize: 10.5,
                            color: template.id == selectedId
                                ? Pal.text
                                : Pal.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _RepositoryGroup {
  const _RepositoryGroup({
    required this.account,
    this.repos = const [],
    this.error = '',
  });

  final IntegrationAccount account;
  final List<GitHubRepo> repos;
  final String error;
}

class _RepositoryChoice {
  const _RepositoryChoice(this.account, this.repo);

  final IntegrationAccount account;
  final GitHubRepo repo;
}

class _RepositoryPickerSheet extends StatelessWidget {
  const _RepositoryPickerSheet({required this.groups});

  final List<_RepositoryGroup> groups;

  @override
  Widget build(BuildContext context) {
    final total = groups.fold<int>(0, (sum, group) => sum + group.repos.length);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x2),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your repositories',
                            style: Txt.headline.copyWith(fontSize: 21)),
                        const SizedBox(height: 2),
                        Text(
                          '$total from ${groups.length} connected GitHub '
                          'account${groups.length == 1 ? '' : 's'}',
                          style: Txt.meta,
                        ),
                      ],
                    ),
                  ),
                  StatusPill('Private included', color: Pal.mint),
                ],
              ),
            ),
            const Hairline(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: Sp.x4),
                children: [
                  if (total == 0)
                    const EmptyState(
                      icon: Icons.folder_off_outlined,
                      title: 'No repositories',
                      body: 'These GitHub accounts have no repositories to '
                          'clone. Check the account token in Integrations.',
                    ),
                  for (final group in groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Sp.page,
                        Sp.x3,
                        Sp.page,
                        3,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.account_circle_outlined,
                              size: 16, color: Pal.textDim),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '@${group.account.displayName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Txt.label.copyWith(
                                color: Pal.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text('${group.repos.length}', style: Txt.meta),
                        ],
                      ),
                    ),
                    if (group.error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Sp.page,
                          4,
                          Sp.page,
                          4,
                        ),
                        child: Text(
                          group.error,
                          style:
                              Txt.meta.copyWith(color: Pal.rose, height: 1.4),
                        ),
                      )
                    else if (group.repos.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Sp.page,
                          4,
                          Sp.page,
                          4,
                        ),
                        child: Text(
                          'No repositories in this account.',
                          style: Txt.meta,
                        ),
                      )
                    else
                      for (final repo in group.repos)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            repo.private
                                ? Icons.lock_outline_rounded
                                : Icons.folder_open_outlined,
                            size: 17,
                            color: repo.private ? Pal.amber : Pal.textDim,
                          ),
                          title: Text(
                            '${repo.owner}/${repo.name}',
                            style: Txt.code.copyWith(fontSize: 12),
                          ),
                          subtitle: Text(
                            '${repo.private ? 'Private' : 'Public'} · '
                            '${repo.defaultBranch}',
                            style: Txt.meta,
                          ),
                          trailing: Icon(Icons.chevron_right_rounded,
                              size: 17, color: Pal.textDim),
                          onTap: () => Navigator.of(context).pop(
                            _RepositoryChoice(group.account, repo),
                          ),
                        ),
                  ],
                ],
              ),
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
            ProjectKindMark(
              kind: kind,
              size: 15,
            ),
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
