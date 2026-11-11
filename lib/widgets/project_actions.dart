import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/integrations.dart';
import '../models.dart';
import '../screens/integrations_screen.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/ui.dart';
import 'push_sheet.dart';

/// Git actions live in Files now: branch, export, commit/push and deploy.
class ProjectActionsBar extends StatefulWidget {
  const ProjectActionsBar({
    super.key,
    required this.project,
    this.onChanged,
  });

  final Project project;
  final VoidCallback? onChanged;

  @override
  State<ProjectActionsBar> createState() => _ProjectActionsBarState();
}

class _ProjectActionsBarState extends State<ProjectActionsBar> {
  bool _metaLoaded = false;
  int _pending = 0;
  bool _exporting = false;
  bool _branchBusy = false;
  bool _pulling = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_metaLoaded) {
      _metaLoaded = true;
      _refreshMeta();
    }
  }

  Future<void> _refreshMeta() async {
    final state = AppScope.of(context);
    final project = state.projectById(widget.project.id);
    try {
      // The explorer owns change detection so a big project is hashed once,
      // not again every time this action bar rebuilds.
      final pending = await state.pendingCommitsFor(project);
      if (!mounted) return;
      setState(() => _pending = pending);
    } catch (_) {
      // A read error leaves the counts at their last known values.
    }
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final state = AppScope.of(context);
    try {
      final bytes = await state.exportZip(state.projectById(widget.project.id));
      if (!mounted) return;
      final suggested =
          '${widget.project.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')}.zip';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export project',
        fileName: suggested,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        bytes: Uint8List.fromList(bytes),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path == null
                ? 'Export cancelled.'
                : 'Exported ${humanSize(bytes.length)} to $path',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _snack('Could not export: $error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _selectBranch() async {
    if (_branchBusy) return;
    final state = AppScope.of(context);
    final project = state.projectById(widget.project.id);
    final account = state.activeGithub;
    final parts = project.repo.split('/');
    if (account == null || parts.length != 2) {
      _snack('Connect this project to GitHub from Push first.');
      return;
    }
    setState(() => _branchBusy = true);
    var branches = <String>[];
    try {
      branches = await state.githubBranches(account, parts.first, parts.last);
    } catch (error) {
      if (!mounted) return;
      setState(() => _branchBusy = false);
      _snack('Could not load branches: $error');
      return;
    }
    if (!mounted) return;
    setState(() => _branchBusy = false);
    if (branches.isEmpty) branches = [project.branch];
    final result = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      builder: (_) => _BranchPickerSheet(
        title: 'Project branch',
        branches: branches,
        current: project.branch,
      ),
    );
    if (result == null || result == project.branch || !mounted) return;
    await state.updateProjectGit(project, branch: result);
    await _refreshMeta();
    widget.onChanged?.call();
  }

  Future<void> _push() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (_) => PushSheet(project: widget.project),
    );
    if (!mounted || result != true) return;
    await _refreshMeta();
    widget.onChanged?.call();
    _snack('Branch pushed to GitHub.');
  }

  Future<void> _pull() async {
    if (_pulling) return;
    final state = AppScope.of(context);
    final project = state.projectById(widget.project.id);
    final account = state.activeGithub;
    final parts = project.repo.split('/');
    if (account == null || parts.length != 2) {
      _snack('Connect this project to GitHub from Push first.');
      return;
    }
    final approved = await showPraxisConfirm(
      context,
      title: 'Pull latest commit?',
      body: 'Merge the newest commit from GitHub into this project.',
      confirmLabel: 'Pull changes',
      icon: Icons.cloud_download_outlined,
      details: [
        ConfirmDetail('Repository', project.repo),
        ConfirmDetail('Branch', project.branch),
      ],
      note: 'Local edits are kept when GitHub has not touched the same file. '
          'If both sides changed a file, Praxis stops before overwriting it.',
    );
    if (!approved || !mounted) return;
    setState(() => _pulling = true);
    try {
      final result = await state.pullProject(project, account);
      if (!mounted) return;
      _snack('Pulled ${project.branch}: ${result.summary}.');
      await _refreshMeta();
      widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      _snack('$error');
    } finally {
      if (mounted) setState(() => _pulling = false);
    }
  }

  Future<void> _deploy() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (_) => _DeploySheet(project: widget.project),
    );
    if (!mounted || result != true) return;
    widget.onChanged?.call();
    _snack('Deployment sent.');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final project = state.projectById(widget.project.id);
    final repoLabel =
        project.repo.isEmpty ? project.name : project.repo.split('/').last;
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 5, 5),
      decoration: BoxDecoration(
        color: Pal.surface,
        border: Border(bottom: BorderSide(color: Pal.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _selectBranch,
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Pal.raised,
                  borderRadius: Rd.sm,
                  border: Border.all(color: Pal.line),
                ),
                child: Row(
                  children: [
                    if (_branchBusy)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    else
                      Icon(Icons.account_tree_outlined,
                          size: 13, color: Pal.textDim),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        project.branch,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.meta.copyWith(
                          color: Pal.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.expand_more_rounded,
                        size: 13, color: Pal.textDim),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        repoLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.meta.copyWith(fontSize: 9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          if (_exporting)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            )
          else
            IconAction(
              icon: Icons.ios_share_rounded,
              tooltip: 'Export project as ZIP',
              size: 17,
              onTap: _export,
            ),
          const SizedBox(width: 2),
          if (_pulling)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
            )
          else
            IconAction(
              icon: Icons.cloud_download_outlined,
              tooltip: 'Pull latest commit',
              size: 17,
              onTap: _pull,
            ),
          const SizedBox(width: 2),
          _BarButton(
            icon: Icons.commit_rounded,
            label: _pending > 0 ? 'Push ($_pending)' : 'Push',
            accent: true,
            onTap: _push,
          ),
          const SizedBox(width: 5),
          _BarButton(
            icon: Icons.rocket_launch_outlined,
            label: 'Deploy',
            onTap: _deploy,
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: accent ? Pal.ember.withOpacity(0.12) : Colors.transparent,
          borderRadius: Rd.sm,
          border: Border.all(
            color: accent ? Pal.ember.withOpacity(0.4) : Pal.lineStrong,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: accent ? Pal.ember : Pal.textMuted),
            const SizedBox(width: 5),
            Text(
              label,
              style: Txt.meta.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: accent ? Pal.ember : Pal.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeploySheet extends StatefulWidget {
  const _DeploySheet({required this.project});

  final Project project;

  @override
  State<_DeploySheet> createState() => _DeploySheetState();
}

class _DeploySheetState extends State<_DeploySheet> {
  late final AppState _state;
  late final TextEditingController _name;
  bool _loaded = false;
  bool _busy = false;
  String? _error;
  String? _cfError;
  String? _vercelError;
  IntegrationResult? _result;
  List<IntegrationAccount> _accounts = const [];
  IntegrationAccount? _account;
  List<IntegrationAccount> _cfAccounts = const [];
  IntegrationAccount? _cfAccount;
  List<CloudflarePagesProject> _projects = const [];
  CloudflarePagesProject? _project;
  List<VercelProject> _vercelProjects = const [];
  VercelProject? _vercelProject;
  bool _createVercelProject = true;
  bool _loadingVercel = false;
  bool _creatingProject = false;
  IntegrationKind _platform = IntegrationKind.vercel;
  String _environment = 'production';
  int _fileCount = 0;
  DeployProgress? _progress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _state = AppScope.of(context);
    _name = TextEditingController(
      text: widget.project.name
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9-]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), ''),
    );
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _remember(String platform, String value) {
    if (value.isEmpty) return;
    unawaited(_state.rememberDeployChoice(
      _state.projectById(widget.project.id),
      platform,
      value,
    ));
  }

  void _restorePagesChoice(List<CloudflarePagesProject> projects) {
    final saved = _state.deployChoice(
      _state.projectById(widget.project.id),
      'cloudflare',
    );
    if (saved == null || saved.isEmpty) return;
    for (final project in projects) {
      if (project.name == saved) {
        _project = project;
        return;
      }
    }
  }

  void _restoreVercelChoice(List<VercelProject> projects) {
    final saved = _state.deployChoice(
      _state.projectById(widget.project.id),
      'vercel',
    );
    if (saved == null || saved.isEmpty || saved == 'new') return;
    for (final project in projects) {
      if (project.id == saved) {
        _vercelProject = project;
        _createVercelProject = false;
        _name.text = project.name;
        return;
      }
    }
  }

  Future<void> _load() async {
    final accounts = _state.integrations.ofKind(IntegrationKind.vercel);
    final cfAccounts = _state.integrations.ofKind(IntegrationKind.cloudflare);
    final entries =
        await _state.fsFor(widget.project).list(includeHidden: true);
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _cfAccounts = cfAccounts;
      _account =
          _state.activeVercel ?? (accounts.isEmpty ? null : accounts.first);
      _cfAccount = _state.integrations.activeFor(IntegrationKind.cloudflare);
      _fileCount = entries.where((entry) => !entry.isDir).length;
      if (accounts.isEmpty && cfAccounts.isNotEmpty) {
        _platform = IntegrationKind.cloudflare;
      }
    });
    if (_account != null) await _loadVercelProjects(_account!);
    if (_cfAccount != null) await _loadProjects(_cfAccount!);
  }

  Future<void> _loadVercelProjects(IntegrationAccount account) async {
    setState(() => _loadingVercel = true);
    try {
      final projects = await VercelClient(
        account.token,
        client: _state.httpClient,
      ).projects();
      if (!mounted || _account?.id != account.id) return;
      setState(() {
        _vercelProjects = projects;
        _vercelProject = null;
        _createVercelProject = true;
        _vercelError = null;
        _restoreVercelChoice(projects);
      });
    } catch (error) {
      if (mounted) setState(() => _vercelError = '$error');
    } finally {
      if (mounted) setState(() => _loadingVercel = false);
    }
  }

  Future<void> _createPagesProject() async {
    final account = _cfAccount;
    if (account == null || _creatingProject) return;
    final controller = TextEditingController(text: _name.text.trim());
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: const Text('Create a Pages project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: Txt.body,
          cursorColor: Pal.ember,
          decoration: appField('my-project', label: 'Project name'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    setState(() {
      _creatingProject = true;
      _error = null;
    });
    try {
      final created = await _state.createCloudflareProject(
        account,
        name: name,
        branch: widget.project.branch,
      );
      if (!mounted) return;
      setState(() {
        _projects = [..._projects, created];
        _project = created;
        _cfError = null;
      });
      _remember('cloudflare', created.name);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _creatingProject = false);
    }
  }

  Future<void> _loadProjects(IntegrationAccount account) async {
    try {
      final projects = await CloudflarePagesClient(
        account.token,
        accountId: account.accountId,
        client: _state.httpClient,
      ).projects();
      if (!mounted || _cfAccount?.id != account.id) return;
      setState(() {
        _projects = projects;
        _project = projects.isEmpty ? null : projects.first;
        _cfError = null;
        _restorePagesChoice(projects);
      });
    } catch (error) {
      // Keep provider errors apart. A Cloudflare failure used to appear under
      // the Vercel tab and looked like the Vercel account was broken.
      if (mounted) setState(() => _cfError = '$error');
    }
  }

  void _selectPlatform(IntegrationKind value) {
    setState(() {
      _platform = value;
      _result = null;
      _error = null;
    });
    if (value == IntegrationKind.vercel &&
        _account != null &&
        _vercelProjects.isEmpty) {
      _loadVercelProjects(_account!);
    }
    if (value == IntegrationKind.cloudflare &&
        _cfAccount != null &&
        _projects.isEmpty) {
      _loadProjects(_cfAccount!);
    }
  }

  void _addAccount() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const IntegrationsScreen()),
    );
  }

  void _onDeployProgress(DeployProgress progress) {
    if (mounted) setState(() => _progress = progress);
  }

  Future<void> _deploy() async {
    final selectedVercel = _createVercelProject ? null : _vercelProject;
    final name = selectedVercel?.name ?? _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Choose a project or enter a new project name.');
      return;
    }
    if (_platform == IntegrationKind.vercel && _account == null) return;
    if (_platform == IntegrationKind.cloudflare &&
        (_cfAccount == null || _project == null)) {
      setState(() => _error = 'Choose or create a Pages project first.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _progress = null;
    });
    try {
      final result = _platform == IntegrationKind.vercel
          ? await _state.deployToVercel(
              _state.projectById(widget.project.id),
              _account!,
              name: name,
              projectId: selectedVercel?.id,
              environment: _environment,
              onProgress: _onDeployProgress,
            )
          : await _state.deployToCloudflare(
              _state.projectById(widget.project.id),
              _cfAccount!,
              projectName: _project!.name,
              environment: _environment,
              branch: widget.project.branch,
              onProgress: _onDeployProgress,
            );
      if (mounted) {
        setState(() => _result = result);
        _remember(
          _platform == IntegrationKind.cloudflare ? 'cloudflare' : 'vercel',
          _platform == IntegrationKind.cloudflare
              ? _project!.name
              : (selectedVercel?.id ?? 'new'),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final platformError =
        _platform == IntegrationKind.cloudflare ? _cfError : _vercelError;
    final activeError = _error ?? platformError;
    return AnimatedPadding(
      duration: Motion.fast,
      padding: EdgeInsets.only(bottom: insets),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.x3, Sp.x2),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Deploy', style: Txt.headline),
                        const SizedBox(height: 2),
                        Text(
                          'A static deployment of the project as it is now.',
                          style: Txt.meta,
                        ),
                      ],
                    ),
                  ),
                  IconAction(
                    icon: Icons.close_rounded,
                    tooltip: 'Close',
                    onTap: () => Navigator.of(context).pop(_result != null),
                  ),
                ],
              ),
            ),
            const Hairline(),
            Padding(
              padding: const EdgeInsets.all(Sp.page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PlatformPicker(
                    value: _platform,
                    onChanged: _selectPlatform,
                  ),
                  const SizedBox(height: Sp.x4),
                  if ((_platform == IntegrationKind.vercel
                          ? _accounts
                          : _cfAccounts)
                      .isEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        EmptyState(
                          icon: Icons.link_off_rounded,
                          title: 'No ${_platform.label} account',
                          body: 'Connect ${_platform.label} once, then deploy '
                              'this project without leaving Praxis.',
                        ),
                        const SizedBox(height: Sp.x3),
                        EmberButton(
                          label: 'Add ${_platform.label} account',
                          icon: Icons.add_link_rounded,
                          onTap: _addAccount,
                        ),
                      ],
                    )
                  else ...[
                    if ((_platform == IntegrationKind.vercel
                                ? _accounts
                                : _cfAccounts)
                            .length >
                        1) ...[
                      const _Label('ACCOUNT'),
                      _AccountDropdown(
                        accounts: _platform == IntegrationKind.vercel
                            ? _accounts
                            : _cfAccounts,
                        value: _platform == IntegrationKind.vercel
                            ? _account
                            : _cfAccount,
                        onChanged: (value) {
                          setState(() {
                            if (_platform == IntegrationKind.vercel) {
                              _account = value;
                              _vercelProjects = const [];
                              _vercelProject = null;
                              _createVercelProject = true;
                            } else {
                              _cfAccount = value;
                              _projects = const [];
                              _project = null;
                            }
                            _result = null;
                          });
                          if (value != null) {
                            if (_platform == IntegrationKind.vercel) {
                              _loadVercelProjects(value);
                            } else {
                              _loadProjects(value);
                            }
                          }
                        },
                      ),
                      const SizedBox(height: Sp.x3),
                    ],
                    _DetailRow(
                      label: 'Account',
                      value:
                          '@${_platform == IntegrationKind.vercel ? (_account?.username ?? '—') : (_cfAccount?.username ?? '—')}',
                    ),
                    if (_platform == IntegrationKind.cloudflare)
                      _DetailRow(
                        label: 'Account ID',
                        value: _cfAccount?.accountId.isEmpty ?? true
                            ? 'Auto-detected'
                            : _cfAccount!.accountId,
                      ),
                    _DetailRow(
                      label: 'Files',
                      value: '$_fileCount project files',
                    ),
                    if (_platform == IntegrationKind.cloudflare) ...[
                      const _Label('PAGES PROJECT'),
                      if (_projects.isEmpty)
                        Text(
                          'No Pages projects found. Create one here or in the '
                          'Cloudflare dashboard.',
                          style: Txt.meta.copyWith(fontSize: 10),
                        )
                      else
                        _ProjectDropdown(
                          projects: _projects,
                          value: _project,
                          onChanged: (value) {
                            setState(() {
                              _project = value;
                              _result = null;
                            });
                            if (value != null) {
                              _remember('cloudflare', value.name);
                            }
                          },
                        ),
                      const SizedBox(height: 2),
                      TextButton.icon(
                        onPressed:
                            _creatingProject ? null : _createPagesProject,
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: Text(_creatingProject
                            ? 'Creating…'
                            : 'Create new Pages project'),
                      ),
                    ] else ...[
                      const _Label('VERCEL PROJECT'),
                      if (_vercelProjects.isNotEmpty) ...[
                        if (!_createVercelProject)
                          _VercelProjectDropdown(
                            projects: _vercelProjects,
                            value: _vercelProject,
                            onChanged: (value) {
                              setState(() {
                                _vercelProject = value;
                                _createVercelProject = value == null;
                                if (value != null) {
                                  _name.text = value.name;
                                }
                                _result = null;
                              });
                              _remember('vercel', value?.id ?? 'new');
                            },
                          ),
                        TextButton.icon(
                          onPressed: _loadingVercel
                              ? null
                              : () {
                                  setState(() {
                                    _createVercelProject =
                                        !_createVercelProject;
                                    _result = null;
                                  });
                                  _remember(
                                      'vercel',
                                      _createVercelProject
                                          ? 'new'
                                          : (_vercelProject?.id ?? 'new'));
                                },
                          icon: Icon(
                            _createVercelProject
                                ? Icons.list_alt_rounded
                                : Icons.add_rounded,
                            size: 16,
                          ),
                          label: Text(
                            _createVercelProject
                                ? 'Select an existing project'
                                : 'Create a new project instead',
                          ),
                        ),
                      ],
                      if (_createVercelProject)
                        _Field(
                          controller: _name,
                          label: 'New project name',
                          hint: 'my-project',
                        ),
                    ],
                    const SizedBox(height: Sp.x3),
                    const _Label('ENVIRONMENT'),
                    Wrap(
                      spacing: 7,
                      children: [
                        for (final value in const ['production', 'preview'])
                          _TargetChoice(
                            label: value == 'production'
                                ? 'Production'
                                : 'Preview',
                            active: _environment == value,
                            onTap: () => setState(() {
                              _environment = value;
                              _result = null;
                            }),
                          ),
                      ],
                    ),
                    if (activeError != null) ...[
                      const SizedBox(height: 12),
                      _ErrorNote(text: activeError),
                    ],
                    if (_busy) ...[
                      const SizedBox(height: 12),
                      _DeployProgressView(
                        platform: _platform,
                        progress: _progress,
                      ),
                    ],
                    if (_result != null) ...[
                      const SizedBox(height: 12),
                      _DeploymentSuccess(result: _result!),
                    ],
                    const SizedBox(height: Sp.x4),
                    EmberButton(
                      label: _result == null ? 'Deploy' : 'Deployed',
                      icon: Icons.rocket_launch_outlined,
                      loading: _busy,
                      onTap: _busy || _result != null ? null : _deploy,
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

class _DeploymentSuccess extends StatelessWidget {
  const _DeploymentSuccess({required this.result});

  final IntegrationResult result;

  @override
  Widget build(BuildContext context) {
    final url = result.url;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Pal.mint.withOpacity(0.08),
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.mint.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline_rounded,
                  size: 16, color: Pal.mint),
              const SizedBox(width: 7),
              Expanded(
                child: Text(result.message,
                    style: Txt.meta.copyWith(color: Pal.mint, height: 1.4)),
              ),
            ],
          ),
          if (url != null && url.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              url,
              style: Txt.code.copyWith(fontSize: 10.5, color: Pal.text),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Deployment URL copied')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('Copy'),
                ),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: const Text('Open'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DeployProgressView extends StatelessWidget {
  const _DeployProgressView({required this.platform, required this.progress});

  final IntegrationKind platform;
  final DeployProgress? progress;

  List<String> get _stages => platform == IntegrationKind.vercel
      ? const ['Preparing', 'Uploading', 'Building', 'Live']
      : const ['Preparing', 'Uploading', 'Deploying', 'Live'];

  @override
  Widget build(BuildContext context) {
    final stages = _stages;
    final found = progress == null ? 0 : stages.indexOf(progress!.stage);
    final active = found < 0 ? 0 : found;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < stages.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == stages.length - 1 ? 0 : 6,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: Center(
                      child: active > index
                          ? Icon(Icons.check_rounded, size: 12, color: Pal.mint)
                          : active == index
                              ? const SizedBox(
                                  width: 9,
                                  height: 9,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.4),
                                )
                              : Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: Pal.textDim.withOpacity(0.45),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      stages[index],
                      style: Txt.meta.copyWith(
                        fontSize: 10.5,
                        color: active >= index ? Pal.text : Pal.textMuted,
                        fontWeight:
                            active == index ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (active == index && (progress?.detail ?? '').isNotEmpty)
                    Flexible(
                      child: Text(
                        progress!.detail,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.meta.copyWith(
                          fontSize: 9,
                          color: Pal.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (progress?.value != null) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: Rd.pill,
              child: LinearProgressIndicator(
                value: progress!.value!.clamp(0.0, 1.0).toDouble(),
                minHeight: 2.5,
                backgroundColor: Pal.line,
                color: Pal.ember,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VercelProjectDropdown extends StatelessWidget {
  const _VercelProjectDropdown({
    required this.projects,
    required this.value,
    required this.onChanged,
  });

  final List<VercelProject> projects;
  final VercelProject? value;
  final ValueChanged<VercelProject?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<VercelProject>(
          value: value,
          isExpanded: true,
          dropdownColor: Pal.raised,
          icon: Icon(Icons.unfold_more_rounded, size: 17, color: Pal.textDim),
          style: Txt.body.copyWith(fontSize: 13),
          items: [
            for (final project in projects)
              DropdownMenuItem(
                value: project,
                child: Text(project.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _PlatformPicker extends StatelessWidget {
  const _PlatformPicker({required this.value, required this.onChanged});

  final IntegrationKind value;
  final ValueChanged<IntegrationKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final kind in const [
          IntegrationKind.vercel,
          IntegrationKind.cloudflare,
        ])
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: kind == IntegrationKind.vercel ? 7 : 0,
              ),
              child: GestureDetector(
                onTap: () => onChanged(kind),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color:
                        value == kind ? Pal.ember.withOpacity(0.1) : Pal.raised,
                    borderRadius: Rd.sm,
                    border: Border.all(
                      color: value == kind
                          ? Pal.ember.withOpacity(0.55)
                          : Pal.line,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        kind == IntegrationKind.vercel
                            ? Icons.change_history_rounded
                            : Icons.cloud_outlined,
                        size: 19,
                        color: value == kind ? Pal.ember : Pal.textMuted,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        kind.label,
                        style: Txt.label.copyWith(
                          fontSize: 11,
                          color: value == kind ? Pal.ember : Pal.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TargetChoice extends StatelessWidget {
  const _TargetChoice({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Pal.ember.withOpacity(0.12) : Pal.raised,
          borderRadius: Rd.sm,
          border: Border.all(
            color: active ? Pal.ember.withOpacity(0.5) : Pal.line,
          ),
        ),
        child: Text(
          label,
          style: Txt.label.copyWith(
            fontSize: 11,
            color: active ? Pal.ember : Pal.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ProjectDropdown extends StatelessWidget {
  const _ProjectDropdown({
    required this.projects,
    required this.value,
    required this.onChanged,
  });

  final List<CloudflarePagesProject> projects;
  final CloudflarePagesProject? value;
  final ValueChanged<CloudflarePagesProject?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<CloudflarePagesProject>(
          value: value,
          isExpanded: true,
          dropdownColor: Pal.raised,
          icon: Icon(Icons.unfold_more_rounded, size: 17, color: Pal.textDim),
          style: Txt.body.copyWith(fontSize: 13),
          items: [
            for (final project in projects)
              DropdownMenuItem(
                value: project,
                child: Text(project.name),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: Txt.body.copyWith(fontSize: 13),
      cursorColor: Pal.ember,
      decoration: appField(hint, label: label),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: Txt.overline.copyWith(fontSize: 9)),
      );
}

class _AccountDropdown extends StatelessWidget {
  const _AccountDropdown({
    required this.accounts,
    required this.value,
    required this.onChanged,
  });

  final List<IntegrationAccount> accounts;
  final IntegrationAccount? value;
  final ValueChanged<IntegrationAccount?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: Pal.raised,
        borderRadius: Rd.sm,
        border: Border.all(color: Pal.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<IntegrationAccount>(
          value: value,
          isExpanded: true,
          dropdownColor: Pal.raised,
          icon: Icon(Icons.unfold_more_rounded, size: 17, color: Pal.textDim),
          style: Txt.body.copyWith(fontSize: 13),
          items: [
            for (final account in accounts)
              DropdownMenuItem(
                value: account,
                child: Row(
                  children: [
                    Icon(Icons.account_circle_outlined,
                        size: 16, color: Pal.textDim),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        account.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: Txt.body.copyWith(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: Txt.meta.copyWith(fontSize: 10)),
          ),
          Expanded(
            child: Text(
              value,
              style: Txt.body.copyWith(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Pal.rose.withOpacity(0.08),
          borderRadius: Rd.sm,
          border: Border.all(color: Pal.rose.withOpacity(0.35)),
        ),
        child: Text(
          text,
          style: Txt.bodySoft.copyWith(fontSize: 11, color: Pal.rose),
        ),
      );
}

class _BranchPickerSheet extends StatelessWidget {
  const _BranchPickerSheet({
    required this.title,
    required this.branches,
    required this.current,
  });

  final String title;
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
                Text(title, style: Txt.headline.copyWith(fontSize: 21)),
                const SizedBox(height: 3),
                Text(
                  'Choose the branch used for comparison and push.',
                  style: Txt.meta,
                ),
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
                  title: Text(
                    branch,
                    style: Txt.code.copyWith(fontSize: 12.5),
                  ),
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
