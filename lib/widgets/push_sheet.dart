import 'package:flutter/material.dart';

import '../core/diff.dart';
import '../core/integrations.dart';
import '../core/push_state.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

class PushSheet extends StatefulWidget {
  const PushSheet({super.key, required this.project});

  final Project project;

  @override
  State<PushSheet> createState() => _PushSheetState();
}

class _PushSheetState extends State<PushSheet> {
  final _owner = TextEditingController();
  final _repo = TextEditingController();
  final _branch = TextEditingController();
  final _message = TextEditingController();
  final _scroll = ScrollController();
  final _messageKey = GlobalKey();
  final _repoFocus = FocusNode();
  bool _repoHadFocus = false;

  AppState? _state;
  bool _loading = true;
  bool _commitBusy = false;
  bool _pushBusy = false;
  bool _loadingBranches = false;
  bool _loadingRepos = false;
  bool _creatingBranch = false;
  bool _syncing = false;
  bool _loadedOnce = false;
  String? _error;
  String? _status;
  String? _messageError;
  String? _compareNote;
  List<RepoChange> _changes = const [];
  List<IntegrationAccount> _accounts = const [];
  List<GitHubRepo> _repos = const [];
  List<String> _branches = const [];
  IntegrationAccount? _account;
  PushState _push = const PushState();
  final Set<String> _selected = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedOnce) return;
    _loadedOnce = true;
    _state = AppScope.of(context);
    _owner.addListener(_recount);
    _repo.addListener(_recount);
    _branch.addListener(_recount);
    _message.addListener(_clearMessageError);
    _repoFocus.addListener(_onRepoFocus);
    _load();
  }

  @override
  void dispose() {
    _owner.dispose();
    _repo.dispose();
    _branch.dispose();
    _message.dispose();
    _scroll.dispose();
    _repoFocus.dispose();
    super.dispose();
  }

  void _recount() {
    if (mounted) setState(() {});
  }

  void _onRepoFocus() {
    final hasFocus = _repoFocus.hasFocus;
    if (_repoHadFocus && !hasFocus) _syncBaseline();
    _repoHadFocus = hasFocus;
  }

  void _clearMessageError() {
    if (_messageError != null && _message.text.trim().isNotEmpty && mounted) {
      setState(() => _messageError = null);
    }
  }

  String get _ownerText => _owner.text.trim();
  String get _repoText => _repo.text.trim();
  String get _branchText =>
      _branch.text.trim().isEmpty ? 'main' : _branch.text.trim();
  int get _pendingForTarget =>
      _push.pendingFor(_ownerText, _repoText, _branchText);
  bool get _targetReady => _ownerText.isNotEmpty && _repoText.isNotEmpty;

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
            : widget.project.repo.isEmpty
                ? ''
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
    if (_targetReady) {
      await _loadBranches();
      if (widget.project.repo.isNotEmpty || push.owner.isNotEmpty) {
        await _syncBaseline();
      }
    }
  }

  Future<void> _loadBranches() async {
    final state = _state;
    final account = _account;
    if (state == null || account == null || !_targetReady) return;
    setState(() => _loadingBranches = true);
    try {
      final branches =
          await state.githubBranches(account, _ownerText, _repoText);
      if (!mounted) return;
      setState(() {
        _branches = branches;
        if (_branch.text.trim().isEmpty && branches.isNotEmpty) {
          _branch.text = branches.contains('main') ? 'main' : branches.first;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _branches = const []);
    } finally {
      if (mounted) setState(() => _loadingBranches = false);
    }
  }

  Future<void> _loadRepos({bool quiet = true}) async {
    final state = _state;
    final account = _account;
    if (state == null || account == null || _loadingRepos) return;
    setState(() => _loadingRepos = true);
    try {
      final repos = await state.githubRepositories(account);
      if (!mounted) return;
      setState(() => _repos = repos);
    } catch (error) {
      if (mounted && !quiet) {
        setState(() => _compareNote = 'Could not load repositories: $error');
      }
    } finally {
      if (mounted) setState(() => _loadingRepos = false);
    }
  }

  Future<void> _syncBaseline() async {
    final state = _state;
    final account = _account;
    if (state == null || account == null || !_targetReady || _syncing) return;
    final alreadyCompared = _push.owner == _ownerText &&
        _push.repo == _repoText &&
        _push.branch == _branchText &&
        _push.baseline.isNotEmpty;
    if (alreadyCompared) return;
    setState(() {
      _syncing = true;
      _compareNote = null;
    });
    try {
      final next = await state.syncPushBaseline(
        widget.project,
        account,
        owner: _ownerText,
        repo: _repoText,
        branch: _branchText,
      );
      final changes = await state.changesFor(widget.project);
      if (!mounted) return;
      setState(() {
        _push = next;
        _changes = changes;
        _selected
          ..clear()
          ..addAll(changes.map((change) => change.path));
        _compareNote = next.baseline.isEmpty
            ? 'Compared with the remote branch. It has no text files yet.'
            : changes.isEmpty
                ? 'Compared with $_ownerText/$_repoText · $_branchText. No local changes.'
                : 'Compared with $_ownerText/$_repoText · $_branchText.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _compareNote =
            'Could not compare with GitHub, so new files cannot be identified yet. $error');
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _selectAccount(IntegrationAccount? account) {
    if (account == null) return;
    final previous = _account?.username ?? '';
    setState(() {
      _account = account;
      _repos = const [];
      if (_owner.text.trim().isEmpty || _owner.text.trim() == previous) {
        _owner.text = account.username;
      }
    });
    _loadBranches();
  }

  Future<void> _pickOwner() async {
    final account = _account;
    if (account == null) return;
    if (_repos.isEmpty) await _loadRepos();
    if (!mounted) return;
    final owners = <String>{
      account.username,
      if (_ownerText.isNotEmpty) _ownerText,
      for (final repo in _repos) repo.owner,
    }.toList()
      ..sort();
    final chosen = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      builder: (_) => _TextChoiceSheet(
        title: 'Username or organisation',
        subtitle: 'Choose the account that owns the repository.',
        values: owners,
        current: _ownerText,
        icon: Icons.person_outline_rounded,
      ),
    );
    if (chosen != null && mounted) {
      _owner.text = chosen;
      _repos = const [];
      await _loadBranches();
    }
  }

  Future<void> _pickRepo() async {
    final state = _state;
    final account = _account;
    if (state == null || account == null) return;
    if (_repos.isEmpty) await _loadRepos(quiet: false);
    if (!mounted) return;
    if (_repos.isEmpty) {
      setState(() => _compareNote =
          'No repositories could be loaded. Check the account token, or type a name directly.');
      return;
    }
    final chosen = await showModalBottomSheet<GitHubRepo>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      builder: (_) => _RepoPickerSheet(
        repos: _repos,
        current: _repoText,
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _owner.text = chosen.owner;
      _repo.text = chosen.name;
      _branch.text = chosen.defaultBranch;
      _changes = const [];
      _selected.clear();
    });
    await _loadBranches();
    await _syncBaseline();
  }

  Future<void> _pickBranch() async {
    if (_loadingBranches) return;
    if (_branches.isEmpty) await _loadBranches();
    if (!mounted) return;
    final options = _branches.isEmpty ? [_branchText] : _branches;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      builder: (_) => _BranchChoiceSheet(
        branches: options,
        current: _branchText,
        canCreate: true,
      ),
    );
    if (chosen == null || !mounted) return;
    if (chosen == _BranchChoiceSheet.createValue) {
      await _createBranch();
      return;
    }
    if (chosen == _branchText) return;
    setState(() => _branch.text = chosen);
    await _syncBaseline();
  }

  Future<void> _createBranch() async {
    final state = _state;
    final account = _account;
    if (state == null || account == null || !_targetReady || _creatingBranch) {
      return;
    }
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: const Text('Create a branch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create a new branch from $_branchText, then commit and push to it.',
              style: Txt.bodySoft,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              style: Txt.code.copyWith(fontSize: 13),
              cursorColor: Pal.ember,
              decoration: appField('feature/new-idea', label: 'Branch name'),
              onSubmitted: (value) =>
                  Navigator.of(dialogContext).pop(value.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Create branch'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    setState(() {
      _creatingBranch = true;
      _error = null;
      _status = null;
    });
    try {
      await state.createGithubBranch(
        account,
        owner: _ownerText,
        repo: _repoText,
        branch: name,
        from: _branchText,
      );
      if (!mounted) return;
      setState(() {
        _branch.text = name;
        if (!_branches.contains(name)) {
          _branches = [..._branches, name];
        }
        _status = 'Created $name from $_branchText.';
      });
      await _syncBaseline();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _creatingBranch = false);
    }
  }

  Future<void> _commit() async {
    final state = _state;
    final account = _account;
    if (state == null || account == null || _commitBusy) return;
    if (!_targetReady) {
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
      setState(() {
        _messageError = 'Commit message is required.';
        _error = null;
        _status = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final field = _messageKey.currentContext;
        if (field != null) {
          Scrollable.ensureVisible(
            field,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: 0.2,
          );
        }
      });
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
          .withBaseline(files)
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
      final changes = await state.changesFor(widget.project);
      if (!mounted) return;
      setState(() {
        _push = next;
        _changes = changes;
        _selected
          ..clear()
          ..addAll(changes.map((change) => change.path));
        _message.clear();
        _messageError = null;
        _status =
            'Committed ${commit.sha.substring(0, 7)}. Commit again only when new changes appear.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _commitBusy = false);
    }
  }

  Future<bool> _confirmPush() async {
    final commits = _push.pending
        .where((commit) => commit.matches(_ownerText, _repoText, _branchText))
        .toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: const Text('Push to GitHub?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Check the destination before anything leaves this device.',
              style: Txt.bodySoft,
            ),
            const SizedBox(height: 14),
            _ConfirmRow(label: 'Username', value: _ownerText),
            _ConfirmRow(label: 'Repository', value: _repoText),
            _ConfirmRow(label: 'Branch', value: _branchText),
            _ConfirmRow(
              label: 'Commits',
              value: '${commits.length}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Push now'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _pushCommits() async {
    final state = _state;
    final account = _account;
    if (state == null || account == null || _pushBusy) return;
    final last = _push.lastPendingFor(_ownerText, _repoText, _branchText);
    if (last == null) return;
    final pending = _push.pending
        .where((commit) => commit.matches(_ownerText, _repoText, _branchText))
        .toList();
    final confirmed = await _confirmPush();
    if (!confirmed || !mounted) return;
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
      final changes = await state.changesFor(widget.project);
      if (!mounted) return;
      setState(() {
        _push = next;
        _changes = changes;
        _selected
          ..clear()
          ..addAll(changes.map((change) => change.path));
        _status = 'Pushed to github.com/$_ownerText/$_repoText/$_branchText';
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _pushBusy = false);
    }
  }

  Future<void> _showDiff(RepoChange change) => showDialog<void>(
        context: context,
        builder: (_) => _PushDiffDialog(change: change),
      );

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
                          'Compare with the branch, commit locally, then push.',
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
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
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
                  controller: _scroll,
                  padding:
                      const EdgeInsets.fromLTRB(Sp.page, Sp.x3, Sp.page, Sp.x3),
                  children: [
                    if (_accounts.length > 1) ...[
                      const _SheetLabel('ACCOUNT'),
                      _AccountSelect(
                        accounts: _accounts,
                        value: account,
                        onChanged: _selectAccount,
                      ),
                      const SizedBox(height: Sp.x3),
                    ],
                    _PushField(
                      controller: _owner,
                      label: 'Username or organisation',
                      hint: 'octocat',
                      suffix: IconAction(
                        icon: Icons.expand_more_rounded,
                        tooltip: 'Choose an owner',
                        size: 18,
                        onTap: _pickOwner,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _PushField(
                      controller: _repo,
                      focusNode: _repoFocus,
                      label: 'Repository',
                      hint: 'my-project',
                      onSubmitted: (_) => _syncBaseline(),
                      suffix: _loadingRepos
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 1.5),
                            )
                          : IconAction(
                              icon: Icons.folder_open_rounded,
                              tooltip: 'Choose a repository',
                              size: 18,
                              onTap: _pickRepo,
                            ),
                    ),
                    const SizedBox(height: 10),
                    _BranchField(
                      branch: _branchText,
                      loading: _loadingBranches,
                      onTap: _pickBranch,
                    ),
                    if (_targetReady) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (_syncing)
                            const SizedBox(
                              width: 11,
                              height: 11,
                              child:
                                  CircularProgressIndicator(strokeWidth: 1.5),
                            )
                          else
                            Icon(Icons.compare_arrows_rounded,
                                size: 13, color: Pal.textDim),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _syncing
                                  ? 'Comparing with $_ownerText/$_repoText · $_branchText…'
                                  : _compareNote ??
                                      'Changes are measured against the remote branch.',
                              style: Txt.meta.copyWith(
                                fontSize: 9,
                                color: _compareNote != null &&
                                        _compareNote!.startsWith('Could not')
                                    ? Pal.amber
                                    : Pal.textDim,
                                height: 1.35,
                              ),
                            ),
                          ),
                          if (!_syncing)
                            TextButton(
                              onPressed: _syncBaseline,
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                minimumSize: const Size(0, 26),
                              ),
                              child: Text(
                                'Compare',
                                style: Txt.meta.copyWith(
                                  fontSize: 9,
                                  color: Pal.ember,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    _PushField(
                      key: _messageKey,
                      controller: _message,
                      label: 'Commit message',
                      hint: 'Describe this change',
                      lines: 2,
                      errorText: _messageError,
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
                          TextButton(
                            onPressed: () => setState(() {
                              if (_selected.length == _changes.length) {
                                _selected.clear();
                              } else {
                                _selected.addAll(
                                    _changes.map((change) => change.path));
                              }
                            }),
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              minimumSize: const Size(0, 30),
                            ),
                            child: Text(
                              _selected.length == _changes.length
                                  ? 'None'
                                  : 'All',
                              style: Txt.meta.copyWith(color: Pal.ember),
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
                                _pendingForTarget > 0
                                    ? 'Everything is committed. Push the waiting commit when ready.'
                                    : 'Working tree clean. New edits will appear here.',
                                style: Txt.bodySoft,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      for (final change in _changes) ...[
                        _PushFileRow(
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
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Pal.amber.withOpacity(0.07),
                          borderRadius: Rd.sm,
                          border:
                              Border.all(color: Pal.amber.withOpacity(0.28)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.commit_rounded,
                                size: 15, color: Pal.amber),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$_pendingForTarget commit${_pendingForTarget == 1 ? '' : 's'} waiting to push.',
                                style: Txt.meta.copyWith(color: Pal.amber),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      _PushError(text: _error!),
                    ],
                    if (_status != null) ...[
                      const SizedBox(height: 10),
                      _PushSuccess(text: _status!),
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
                        onTap: _commitBusy || _pushBusy || _changes.isEmpty
                            ? null
                            : _commit,
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
                                        ? 'Push ($_pendingForTarget)'
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

class _PushField extends StatelessWidget {
  const _PushField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.lines = 1,
    this.suffix,
    this.errorText,
    this.onSubmitted,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int lines;
  final Widget? suffix;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      style: Txt.body.copyWith(fontSize: 13),
      cursorColor: Pal.ember,
      onSubmitted: onSubmitted,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines,
      autocorrect: false,
      enableSuggestions: false,
      decoration: appField(hint, label: label, suffix: suffix).copyWith(
        errorText: errorText,
        errorMaxLines: 2,
        errorStyle: Txt.meta.copyWith(color: Pal.rose, fontSize: 10),
        enabledBorder: errorText == null
            ? null
            : OutlineInputBorder(
                borderRadius: Rd.sm,
                borderSide: BorderSide(color: Pal.rose, width: 1.2),
              ),
        focusedBorder: errorText == null
            ? null
            : OutlineInputBorder(
                borderRadius: Rd.sm,
                borderSide: BorderSide(color: Pal.rose, width: 1.2),
              ),
      ),
    );
  }
}

class _BranchField extends StatelessWidget {
  const _BranchField({
    required this.branch,
    required this.loading,
    required this.onTap,
  });

  final String branch;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Branch, $branch. Tap to choose.',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: InputDecorator(
          decoration: appField('', label: 'Branch').copyWith(
            suffixIcon: loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  )
                : Icon(Icons.unfold_more_rounded, size: 18, color: Pal.textDim),
          ),
          child: Row(
            children: [
              Icon(Icons.account_tree_outlined, size: 15, color: Pal.textDim),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  branch,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Txt.code.copyWith(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountSelect extends StatelessWidget {
  const _AccountSelect({
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
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

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: Txt.overline.copyWith(fontSize: 9)),
      );
}

class _PushFileRow extends StatelessWidget {
  const _PushFileRow({
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

class _PushDiffDialog extends StatelessWidget {
  const _PushDiffDialog({required this.change});

  final RepoChange change;

  @override
  Widget build(BuildContext context) {
    final diff = computeDiff(change.before, change.after);
    final rows =
        diff.rows.where((row) => row.kind != DiffKind.context).toList();
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
              padding:
                  const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: 4),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Pal.line)),
              ),
              child: Row(
                children: [
                  Text('Only changed lines are shown',
                      style: Txt.meta.copyWith(fontSize: 9)),
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

class _TextChoiceSheet extends StatelessWidget {
  const _TextChoiceSheet({
    required this.title,
    required this.subtitle,
    required this.values,
    required this.current,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final List<String> values;
  final String current;
  final IconData icon;

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
                Text(subtitle, style: Txt.meta),
              ],
            ),
          ),
          const Hairline(),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: values.length,
              itemBuilder: (context, index) {
                final value = values[index];
                final active = value == current;
                return ListTile(
                  dense: true,
                  leading: Icon(icon,
                      size: 18, color: active ? Pal.ember : Pal.textDim),
                  title: Text(value, style: Txt.body.copyWith(fontSize: 13)),
                  trailing: active
                      ? Icon(Icons.check_rounded, size: 17, color: Pal.ember)
                      : null,
                  onTap: () => Navigator.of(context).pop(value),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RepoPickerSheet extends StatefulWidget {
  const _RepoPickerSheet({required this.repos, required this.current});

  final List<GitHubRepo> repos;
  final String current;

  @override
  State<_RepoPickerSheet> createState() => _RepoPickerSheetState();
}

class _RepoPickerSheetState extends State<_RepoPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final repos = widget.repos
        .where((repo) =>
            query.isEmpty || repo.fullName.toLowerCase().contains(query))
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Column(
        children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose repository',
                    style: Txt.headline.copyWith(fontSize: 21)),
                const SizedBox(height: 3),
                Text('Only repositories this account can access are listed.',
                    style: Txt.meta),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  autofocus: true,
                  style: Txt.body.copyWith(fontSize: 13),
                  cursorColor: Pal.ember,
                  onChanged: (_) => setState(() {}),
                  decoration: appField(
                    'Search repositories',
                    suffix: Icon(Icons.search_rounded,
                        size: 17, color: Pal.textDim),
                  ),
                ),
              ],
            ),
          ),
          const Hairline(),
          Expanded(
            child: repos.isEmpty
                ? Center(
                    child:
                        Text('No matching repositories.', style: Txt.bodySoft),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: repos.length,
                    itemBuilder: (context, index) {
                      final repo = repos[index];
                      final active = repo.name == widget.current;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          repo.private
                              ? Icons.lock_outline_rounded
                              : Icons.folder_open_rounded,
                          size: 18,
                          color: active ? Pal.ember : Pal.textDim,
                        ),
                        title: Text(repo.fullName,
                            style: Txt.body.copyWith(fontSize: 13)),
                        subtitle: Text(repo.defaultBranch,
                            style: Txt.meta.copyWith(fontSize: 9.5)),
                        trailing: active
                            ? Icon(Icons.check_rounded,
                                size: 17, color: Pal.ember)
                            : null,
                        onTap: () => Navigator.of(context).pop(repo),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _BranchChoiceSheet extends StatelessWidget {
  const _BranchChoiceSheet({
    required this.branches,
    required this.current,
    this.canCreate = false,
  });

  static const createValue = '__create_branch__';

  final List<String> branches;
  final String current;
  final bool canCreate;

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
                Text('Choose branch',
                    style: Txt.headline.copyWith(fontSize: 21)),
                const SizedBox(height: 3),
                Text('The branch used for comparison, commit and push.',
                    style: Txt.meta),
              ],
            ),
          ),
          const Hairline(),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                for (final branch in branches)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.account_tree_outlined,
                        size: 18,
                        color: branch == current ? Pal.ember : Pal.textDim),
                    title:
                        Text(branch, style: Txt.code.copyWith(fontSize: 12.5)),
                    trailing: branch == current
                        ? Icon(Icons.check_rounded, size: 17, color: Pal.ember)
                        : null,
                    onTap: () => Navigator.of(context).pop(branch),
                  ),
                if (canCreate) ...[
                  const Hairline(),
                  ListTile(
                    dense: true,
                    leading:
                        Icon(Icons.add_rounded, size: 18, color: Pal.ember),
                    title: Text('Create new branch',
                        style:
                            Txt.body.copyWith(fontSize: 13, color: Pal.ember)),
                    subtitle: Text('Branches from $current',
                        style: Txt.meta.copyWith(fontSize: 9.5)),
                    onTap: () => Navigator.of(context).pop(createValue),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 82,
              child: Text(label, style: Txt.meta.copyWith(fontSize: 10)),
            ),
            Expanded(
              child: Text(value, style: Txt.body.copyWith(fontSize: 12.5)),
            ),
          ],
        ),
      );
}

class _PushError extends StatelessWidget {
  const _PushError({required this.text});
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
        child: Text(text,
            style: Txt.bodySoft.copyWith(fontSize: 11, color: Pal.rose)),
      );
}

class _PushSuccess extends StatelessWidget {
  const _PushSuccess({required this.text});
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
        child: Text(text,
            style: Txt.bodySoft.copyWith(fontSize: 11, color: Pal.mint)),
      );
}
