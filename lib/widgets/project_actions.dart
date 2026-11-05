import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/integrations.dart';
import '../models.dart';
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
  int _changes = 0;
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
    if (!mounted) return;
    await _refreshMeta();
    widget.onChanged?.call();
    if (result == true) _snack('Branch pushed to GitHub.');
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
              onTap: _selectBranch,
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
