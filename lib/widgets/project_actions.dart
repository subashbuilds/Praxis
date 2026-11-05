import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/diff.dart';
import '../core/integrations.dart';
import '../core/push_state.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

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
  int _changes = 0;
  int _pending = 0;
  bool _exporting = false;

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
      final changes = await state.changesFor(project);
      final pending = await state.pendingCommitsFor(project);
      if (!mounted) return;
      setState(() {
        _changes = changes.length;
        _pending = pending;
      });
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

  Future<void> _editBranch() async {
    final state = AppScope.of(context);
    final project = state.projectById(widget.project.id);
    final controller = TextEditingController(text: project.branch);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: const Text('Project branch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The branch used by Push and Deploy. It also sets the base branch '
              'for changes shown in Files.',
              style: Txt.bodySoft,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              style: Txt.body,
              cursorColor: Pal.ember,
              decoration: appField('main'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(
                controller.text.trim().isEmpty
                    ? 'main'
                    : controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
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
      builder: (_) => _PushSheet(project: widget.project),
    );
    if (!mounted) return;
    await _refreshMeta();
    widget.onChanged?.call();
    if (result == true) _snack('Branch pushed to GitHub.');
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
    if (!mounted) return;
    widget.onChanged?.call();
    if (result == true) _snack('Deployment sent to Vercel.');
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
      padding: const EdgeInsets.fromLTRB(Sp.x3, Sp.x2, Sp.x2, Sp.x2),
      decoration: BoxDecoration(
        color: Pal.surface,
        border: Border(bottom: BorderSide(color: Pal.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _editBranch,
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  color: Pal.raised,
                  borderRadius: Rd.sm,
                  border: Border.all(color: Pal.line),
                ),
                child: Row(
                  children: [
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
          if (_changes > 0) ...[
            const SizedBox(width: 7),
            Text(
              '$_changes changed',
              style: Txt.meta.copyWith(fontSize: 8.5, color: Pal.amber),
            ),
          ],
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
          _BarButton(
            icon: Icons.commit_rounded,
            label: _pending > 0 ? 'Push (${superscript(_pending)})' : 'Push',
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
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 9),
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

class _PushSheet extends StatefulWidget {
  const _PushSheet({required this.project});

  final Project project;

  @override
  State<_PushSheet> createState() => _PushSheetState();
}

class _PushSheetState extends State<_PushSheet> {
  final _owner = TextEditingController();
  final _repo = TextEditingController();
  final _branch = TextEditingController();
  final _message = TextEditingController();

  AppState? _state;
  bool _loading = true;
  bool _commitBusy = false;
  bool _pushBusy = false;
  String? _error;
  String? _status;
  List<RepoChange> _changes = const [];
  List<IntegrationAccount> _accounts = const [];
  IntegrationAccount? _account;
  PushState _push = const PushState();
  final Set<String> _selected = {};
  List<String> _branches = const [];
  bool _loadingBranches = false;
  bool _loadedOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedOnce) return;
    _loadedOnce = true;
    _state = AppScope.of(context);
    for (final controller in [_owner, _repo, _branch]) {
      controller.addListener(_recount);
    }
    _load();
  }

  @override
  void dispose() {
    for (final controller in [_owner, _repo, _branch]) {
      controller.removeListener(_recount);
    }
    _owner.dispose();
    _repo.dispose();
    _branch.dispose();
    _message.dispose();
    super.dispose();
  }

  void _recount() {
    if (mounted) setState(() {});
  }

  String get _ownerText => _owner.text.trim();
  String get _repoText => _repo.text.trim();
  String get _branchText =>
      _branch.text.trim().isEmpty ? 'main' : _branch.text.trim();

  int get _pendingForTarget =>
      _push.pendingFor(_ownerText, _repoText, _branchText);

  Future<void> _load() async {
    final state = _state;
    if (state == null) return;
    final push = await state.pushStateFor(widget.project);
    final changes = await state.changesFor(widget.project);
    if (!mounted) return;
    final accounts = state.integrations.ofKind(IntegrationKind.github);
    final account =
        state.activeGithub ?? (accounts.isEmpty ? null : accounts.first);
    final parts = widget.project.repo.split('/');
    _owner.text = push.owner.isNotEmpty
        ? push.owner
        : parts.length == 2
            ? parts.first
            : account?.username ?? '';
    _repo.text = push.repo.isNotEmpty
        ? push.repo
        : parts.length == 2
            ? parts.last
            : widget.project.name;
    _branch.text = widget.project.branch;
    setState(() {
      _push = push;
      _changes = changes;
      _accounts = accounts;
      _account = account;
      _selected
        ..clear()
        ..addAll(changes.map((change) => change.path));
      _loading = false;
    });
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    final state = _state;
    final account = _account;
    if (state == null ||
        account == null ||
        _ownerText.isEmpty ||
        _repoText.isEmpty) {
      return;
    }
    setState(() => _loadingBranches = true);
    try {
      final branches =
          await state.githubBranches(account, _ownerText, _repoText);
      if (!mounted) return;
      setState(() => _branches = branches);
    } catch (_) {
      // A brand new repository has no branches yet; the text field still works.
      if (mounted) setState(() => _branches = const []);
    } finally {
      if (mounted) setState(() => _loadingBranches = false);
    }
  }

  void _selectAccount(IntegrationAccount? account) {
    if (account == null) return;
    final previous = _account?.username ?? '';
    setState(() {
      _account = account;
      if (_owner.text.trim().isEmpty || _owner.text.trim() == previous) {
        _owner.text = account.username;
      }
    });
    _loadBranches();
  }

  Future<void> _commit() async {
    final state = _state;
    final account = _account;
    if (state == null || account == null) return;
    if (_ownerText.isEmpty || _repoText.isEmpty) {
      setState(() => _error = 'Add the GitHub username and repository name.');
      return;
    }
    final files = <String, String>{
      for (final change in _changes)
        if (_selected.contains(change.path)) change.path: change.after,
    };
    if (files.isEmpty) {
      setState(() => _error = 'Select at least one file for the commit.');
      return;
    }
    if (_message.text.trim().isEmpty) {
      setState(() => _error = 'Write a commit message.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _commitBusy = true;
      _error = null;
      _status = null;
    });
    try {
      final parent = _push.lastPendingFor(_ownerText, _repoText, _branchText);
      final commit = await state.createGithubCommit(
        account,
        owner: _ownerText,
        repo: _repoText,
        branch: _branchText,
        message: _message.text.trim(),
        files: files,
        parentSha: parent?.sha,
      );
      final next = _push
          .copyWith(
            owner: _ownerText,
            repo: _repoText,
            branch: _branchText,
          )
          .withPending(PendingCommit(
            sha: commit.sha,
            message: _message.text.trim(),
            at: DateTime.now(),
            owner: _ownerText,
            repo: _repoText,
            branch: _branchText,
            files: files,
          ));
      await state.savePushState(widget.project, next);
      await state.updateProjectGit(
        state.projectById(widget.project.id),
        repo: '$_ownerText/$_repoText',
        branch: _branchText,
      );
      if (!mounted) return;
      setState(() {
        _push = next;
        _message.clear();
        _status = 'Commit ${commit.sha.substring(0, 7)} is ready to push.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _commitBusy = false);
    }
  }

  Future<void> _pushCommits() async {
    final state = _state;
    final account = _account;
    if (state == null || account == null) return;
    final last = _push.lastPendingFor(_ownerText, _repoText, _branchText);
    if (last == null) return;
    final pending = _push.pending
        .where((commit) => commit.matches(_ownerText, _repoText, _branchText))
        .toList();
    final pushedFiles = <String, String>{};
    for (final commit in pending) {
      pushedFiles.addAll(commit.files);
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _pushBusy = true;
      _error = null;
      _status = null;
    });
    try {
      await state.pushGithubRef(
        account,
        owner: _ownerText,
        repo: _repoText,
        branch: _branchText,
        sha: last.sha,
      );
      final next = _push
          .withBaseline(pushedFiles)
          .withoutPending(pending.map((commit) => commit.sha))
          .copyWith(
            owner: _ownerText,
            repo: _repoText,
            branch: _branchText,
          );
      await state.savePushState(widget.project, next);
      await state.updateProjectGit(
        state.projectById(widget.project.id),
        repo: '$_ownerText/$_repoText',
        branch: _branchText,
      );
      final updatedChanges = await state.changesFor(widget.project);
      if (!mounted) return;
      setState(() {
        _push = next;
        _changes = updatedChanges;
        _selected
          ..clear()
          ..addAll(updatedChanges.map((change) => change.path));
        _status = 'Pushed to github.com/$_ownerText/$_repoText/$_branchText';
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _pushBusy = false);
    }
  }

  Future<void> _showDiff(RepoChange change) => showDialog<void>(
      context: context, builder: (_) => _DiffDialog(change: change));

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final height = (MediaQuery.sizeOf(context).height - insets - 20)
        .clamp(360.0, MediaQuery.sizeOf(context).height * 0.93);
    final account = _account;
    return AnimatedPadding(
      duration: Motion.fast,
      padding: EdgeInsets.only(bottom: insets),
      child: SizedBox(
        height: height.toDouble(),
        child: Column(
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
                        Text('Push to GitHub', style: Txt.headline),
                        const SizedBox(height: 2),
                        Text(
                          'Commit locally first, then update the branch. Nothing '
                          'leaves this device until you push.',
                          style: Txt.meta.copyWith(height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  IconAction(
                    icon: Icons.close_rounded,
                    tooltip: 'Close',
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            const Hairline(),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_accounts.isEmpty)
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.all(Sp.page),
                  child: EmptyState(
                    icon: Icons.link_off_rounded,
                    title: 'No GitHub account',
                    body:
                        'Add a GitHub token in Settings → Integrations to commit and push.',
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.fromLTRB(Sp.page, Sp.x3, Sp.page, Sp.x3),
                  children: [
                    if (_accounts.length > 1) ...[
                      const _Label('ACCOUNT'),
                      _AccountDropdown(
                        accounts: _accounts,
                        value: account,
                        onChanged: _selectAccount,
                      ),
                      const SizedBox(height: Sp.x3),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: _Field(
                            controller: _owner,
                            label: 'Username or org',
                            hint: 'octocat',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Field(
                            controller: _repo,
                            label: 'Repository',
                            hint: 'my-project',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _Field(
                            controller: _branch,
                            label: 'Branch',
                            hint: 'main',
                          ),
                        ),
                        const SizedBox(width: 4),
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: PopupMenuButton<String>(
                            tooltip: 'Load branches',
                            color: Pal.raised,
                            onOpened: _loadBranches,
                            onSelected: (value) => setState(() {
                              _branch.text = value;
                            }),
                            itemBuilder: (_) => [
                              if (_loadingBranches)
                                const PopupMenuItem(
                                  enabled: false,
                                  child: Text('Loading branches…'),
                                ),
                              for (final branch in _branches)
                                PopupMenuItem(
                                  value: branch,
                                  child: Text(branch),
                                ),
                              if (_branches.isEmpty && !_loadingBranches)
                                const PopupMenuItem(
                                  enabled: false,
                                  child: Text('No branches found'),
                                ),
                            ],
                            child: Container(
                              height: 42,
                              width: 42,
                              decoration: BoxDecoration(
                                color: Pal.raised,
                                borderRadius: Rd.sm,
                                border: Border.all(color: Pal.line),
                              ),
                              child: _loadingBranches
                                  ? const Padding(
                                      padding: EdgeInsets.all(13),
                                      child: CircularProgressIndicator(
                                          strokeWidth: 1.5),
                                    )
                                  : Icon(Icons.unfold_more_rounded,
                                      size: 18, color: Pal.textMuted),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _Field(
                      controller: _message,
                      label: 'Commit message',
                      hint: 'Describe this change',
                      lines: 2,
                    ),
                    const SizedBox(height: Sp.x4),
                    Row(
                      children: [
                        Text('FILES IN THIS COMMIT', style: Txt.overline),
                        const SizedBox(width: 8),
                        Text(
                          '${_selected.length}/${_changes.length}',
                          style: Txt.meta,
                        ),
                        const Spacer(),
                        if (_changes.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() {
                              if (_selected.length == _changes.length) {
                                _selected.clear();
                              } else {
                                _selected.addAll(
                                    _changes.map((change) => change.path));
                              }
                            }),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 5),
                              child: Text(
                                _selected.length == _changes.length
                                    ? 'None'
                                    : 'All',
                                style: Txt.meta.copyWith(
                                  color: Pal.ember,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    if (_changes.isEmpty)
                      Panel(
                        padding: const EdgeInsets.all(Sp.x3),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline_rounded,
                                size: 17, color: Pal.mint),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Working tree clean. Changes from the last push '
                                'will appear here.',
                                style: Txt.bodySoft,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      for (final change in _changes) ...[
                        _ChangedFileRow(
                          change: change,
                          selected: _selected.contains(change.path),
                          onToggle: () => setState(() {
                            if (!_selected.remove(change.path)) {
                              _selected.add(change.path);
                            }
                          }),
                          onOpen: () => _showDiff(change),
                        ),
                        const SizedBox(height: 6),
                      ],
                    if (_pendingForTarget > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.commit_rounded,
                              size: 14, color: Pal.amber),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              '$_pendingForTarget commit${_pendingForTarget == 1 ? '' : 's'} '
                              'waiting to be pushed.',
                              style: Txt.meta.copyWith(color: Pal.amber),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      _ErrorNote(text: _error!),
                    ],
                    if (_status != null) ...[
                      const SizedBox(height: 10),
                      _SuccessNote(text: _status!),
                    ],
                    const SizedBox(height: Sp.x5),
                  ],
                ),
              ),
            if (!_loading && _accounts.isNotEmpty)
              Container(
                padding: EdgeInsets.fromLTRB(
                  Sp.page,
                  Sp.x2,
                  Sp.page,
                  Sp.x3 + MediaQuery.paddingOf(context).bottom,
                ),
                decoration: BoxDecoration(
                  color: Pal.surface,
                  border: Border(top: BorderSide(color: Pal.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        label: 'Commit',
                        icon: Icons.commit_rounded,
                        onTap: _commitBusy || _pushBusy ? null : _commit,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Opacity(
                        opacity: _pendingForTarget > 0 ? 1 : 0.38,
                        child: GestureDetector(
                          onTap: _pendingForTarget > 0 && !_pushBusy
                              ? _pushCommits
                              : null,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Pal.ember,
                              borderRadius: Rd.sm,
                            ),
                            child: _pushBusy
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _pendingForTarget > 0
                                        ? 'Push (${superscript(_pendingForTarget)})'
                                        : 'Push',
                                    style: Txt.label.copyWith(
                                      color: Pal.onEmber,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ),
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
  IntegrationResult? _result;
  List<IntegrationAccount> _accounts = const [];
  IntegrationAccount? _account;
  int _fileCount = 0;

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

  Future<void> _load() async {
    final accounts = _state.integrations.ofKind(IntegrationKind.vercel);
    final files = await _state.fsFor(widget.project).textFiles();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _account =
          _state.activeVercel ?? (accounts.isEmpty ? null : accounts.first);
      _fileCount = files.length;
    });
  }

  Future<void> _deploy() async {
    final account = _account;
    if (account == null || _name.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _state.deployToVercel(
        _state.projectById(widget.project.id),
        account,
        name: _name.text.trim(),
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
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
                        Text('Deploy to Vercel', style: Txt.headline),
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
                  if (_accounts.isEmpty)
                    const EmptyState(
                      icon: Icons.link_off_rounded,
                      title: 'No Vercel account',
                      body:
                          'Add a Vercel token in Settings → Integrations before deploying.',
                    )
                  else ...[
                    if (_accounts.length > 1) ...[
                      const _Label('ACCOUNT'),
                      _AccountDropdown(
                        accounts: _accounts,
                        value: _account,
                        onChanged: (value) => setState(() => _account = value),
                      ),
                      const SizedBox(height: Sp.x3),
                    ],
                    _DetailRow(
                      label: 'Account',
                      value: _account == null
                          ? '—'
                          : '@${_account!.username}${_account!.label.isEmpty ? '' : ' · ${_account!.label}'}',
                    ),
                    _DetailRow(
                      label: 'Project',
                      value: widget.project.name,
                    ),
                    _DetailRow(
                      label: 'Files',
                      value: '$_fileCount text files',
                    ),
                    const _DetailRow(label: 'Target', value: 'Production'),
                    const SizedBox(height: Sp.x3),
                    _Field(
                      controller: _name,
                      label: 'Deployment name',
                      hint: 'my-project',
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _ErrorNote(text: _error!),
                    ],
                    if (_result != null) ...[
                      const SizedBox(height: 12),
                      _SuccessNote(
                        text: _result!.url == null
                            ? _result!.message
                            : '${_result!.message}\n${_result!.url}',
                      ),
                    ],
                    const SizedBox(height: Sp.x4),
                    EmberButton(
                      label: _result == null ? 'Deploy' : 'Deploy again',
                      icon: Icons.rocket_launch_outlined,
                      loading: _busy,
                      onTap: _busy || _account == null ? null : _deploy,
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

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.lines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: Txt.body.copyWith(fontSize: 13),
      cursorColor: Pal.ember,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines,
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

class _ChangedFileRow extends StatelessWidget {
  const _ChangedFileRow({
    required this.change,
    required this.selected,
    required this.onToggle,
    required this.onOpen,
  });

  final RepoChange change;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final added = change.status == RepoChangeStatus.added;
    final tint = added ? Pal.mint : Pal.amber;
    return GestureDetector(
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(2, 5, 6, 5),
        decoration: BoxDecoration(
          color: selected ? Pal.raised : Colors.transparent,
          borderRadius: Rd.sm,
          border: Border.all(
            color: selected ? Pal.line : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: onToggle,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 34,
                height: 34,
                child: Center(
                  child: Container(
                    width: 17,
                    height: 17,
                    decoration: BoxDecoration(
                      color: selected
                          ? tint.withOpacity(0.16)
                          : Colors.transparent,
                      borderRadius: const BorderRadius.all(Radius.circular(4)),
                      border: Border.all(
                        color: selected ? tint : Pal.lineStrong,
                      ),
                    ),
                    child: selected
                        ? Icon(Icons.check_rounded, size: 12, color: tint)
                        : null,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Text(
                change.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Txt.code.copyWith(fontSize: 11.5),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              change.status.letter,
              style: Txt.meta.copyWith(
                fontSize: 9,
                color: tint,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              '+${change.added}',
              style: Txt.meta.copyWith(fontSize: 9, color: Pal.ghAddText),
            ),
            const SizedBox(width: 4),
            Text(
              '-${change.removed}',
              style: Txt.meta.copyWith(fontSize: 9, color: Pal.ghDelText),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 15, color: Pal.textDim),
          ],
        ),
      ),
    );
  }
}

class _DiffDialog extends StatelessWidget {
  const _DiffDialog({required this.change});

  final RepoChange change;

  @override
  Widget build(BuildContext context) {
    final diff = computeDiff(change.before, change.after);
    final rows = diff.rows
        .where((row) => row.kind != DiffKind.context)
        .toList(growable: false);
    return Dialog(
      backgroundColor: Pal.surface,
      insetPadding: const EdgeInsets.all(Sp.x3),
      shape: const RoundedRectangleBorder(borderRadius: Rd.md),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x3, Sp.x2, Sp.x2),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          change.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.code.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${change.status.label} · +${change.added} −${change.removed}',
                          style: Txt.meta.copyWith(fontSize: 9.5),
                        ),
                      ],
                    ),
                  ),
                  IconAction(
                    icon: Icons.close_rounded,
                    tooltip: 'Close diff',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Hairline(),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text('No textual changes.', style: Txt.bodySoft),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final added = row.kind == DiffKind.added;
                        return Container(
                          color: added ? Pal.ghAddBg : Pal.ghDelBg,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 27,
                                child: Text(
                                  row.oldLine?.toString() ?? '',
                                  textAlign: TextAlign.right,
                                  style: Txt.meta.copyWith(
                                    fontSize: 8.5,
                                    height: 1.5,
                                    color: Pal.ghMuted,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 27,
                                child: Text(
                                  row.newLine?.toString() ?? '',
                                  textAlign: TextAlign.right,
                                  style: Txt.meta.copyWith(
                                    fontSize: 8.5,
                                    height: 1.5,
                                    color: Pal.ghMuted,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 9,
                                child: Text(
                                  added ? '+' : '-',
                                  style: Txt.meta.copyWith(
                                    fontSize: 9,
                                    height: 1.45,
                                    color:
                                        added ? Pal.ghAddText : Pal.ghDelText,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  row.text.isEmpty ? ' ' : row.text,
                                  style: Txt.code.copyWith(
                                    fontSize: 10,
                                    height: 1.45,
                                    color: Pal.ghText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x4, Sp.x2),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Pal.line)),
              ),
              child: Row(
                children: [
                  Text(
                    'Only changed lines are shown',
                    style: Txt.meta.copyWith(fontSize: 9),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
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

class _SuccessNote extends StatelessWidget {
  const _SuccessNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Pal.mint.withOpacity(0.07),
          borderRadius: Rd.sm,
          border: Border.all(color: Pal.mint.withOpacity(0.3)),
        ),
        child: Text(
          text,
          style: Txt.bodySoft.copyWith(fontSize: 11, color: Pal.mint),
        ),
      );
}

const _superscripts = {
  '0': '⁰',
  '1': '¹',
  '2': '²',
  '3': '³',
  '4': '⁴',
  '5': '⁵',
  '6': '⁶',
  '7': '⁷',
  '8': '⁸',
  '9': '⁹',
};

String superscript(int number) =>
    '$number'.split('').map((char) => _superscripts[char] ?? char).join();
