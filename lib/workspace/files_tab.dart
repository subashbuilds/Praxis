import 'package:flutter/material.dart';

import '../core/push_state.dart';
import '../core/vfs.dart';
import '../models.dart';
import '../screens/editor.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/project_actions.dart';
import '../widgets/ui.dart';

class FilesTab extends StatefulWidget {
  const FilesTab({super.key, required this.project});

  final Project project;

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  Future<_FilesData>? _future;

  void _refresh() {
    final state = AppScope.of(context);
    setState(() {
      _future = _load(state);
    });
  }

  Future<_FilesData> _load(AppState state) async {
    final files = await state.filesOf(widget.project);
    final changes = await state.changesFor(widget.project);
    return _FilesData(
      files,
      {for (final change in changes) change.path: change},
      await state.pendingCommitsFor(widget.project),
    );
  }

  Future<void> _newFile() async {
    final state = AppScope.of(context);
    final navigator = Navigator.of(context);
    final name = await _askName('New file', 'lib/example.dart');
    if (name == null || !mounted) return;
    await state.createFile(widget.project, name);
    if (!mounted) return;
    _refresh();
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => EditorScreen(project: widget.project, path: name),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _newFolder() async {
    final state = AppScope.of(context);
    final name = await _askName('New folder', 'src');
    if (name == null || !mounted) return;
    await state.createFolder(widget.project, name);
    if (mounted) _refresh();
  }

  Future<String?> _askName(String title, String hint) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: Txt.body,
          cursorColor: Pal.ember,
          decoration: appField(hint),
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
    ).whenComplete(controller.dispose);
  }

  Future<void> _open(FileEntry entry) async {
    if (entry.isDir) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorScreen(project: widget.project, path: entry.path),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _delete(FileEntry entry) async {
    final state = AppScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Pal.surface,
        title: Text('Delete ${entry.name}?'),
        content: Text(
          entry.isDir
              ? 'The folder and everything inside it is removed from disk.'
              : 'The file is removed from disk.',
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
    if ((confirmed ?? false) && mounted) {
      await state.deletePath(widget.project, entry.path);
      if (mounted) _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final project = state.projectById(widget.project.id);
    return Column(
      children: [
        ProjectActionsBar(
          project: project,
          onChanged: _refresh,
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x2, Sp.x2),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Pal.line)),
          ),
          child: Row(
            children: [
              Text(
                'EXPLORER',
                style: Txt.overline.copyWith(fontSize: 9.5),
              ),
              const SizedBox(width: 8),
              Text(
                'changes since last push',
                style: Txt.meta.copyWith(fontSize: 8.5),
              ),
              const Spacer(),
              IconAction(
                icon: Icons.note_add_outlined,
                tooltip: 'New file',
                size: 18,
                onTap: _newFile,
              ),
              IconAction(
                icon: Icons.create_new_folder_outlined,
                tooltip: 'New folder',
                size: 18,
                onTap: _newFolder,
              ),
              IconAction(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh',
                size: 18,
                onTap: _refresh,
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<_FilesData>(
            future: _future ??= _load(state),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(Sp.page),
                  child: Text(
                    'Could not read the project: ${snapshot.error}',
                    style: Txt.bodySoft.copyWith(color: Pal.rose),
                  ),
                );
              }
              final data = snapshot.data ?? const _FilesData([], {}, 0);
              if (data.files.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(Sp.page),
                  child: EmptyState(
                    icon: Icons.folder_off_outlined,
                    title: 'Empty project',
                    body:
                        'Create a file to get started, or ask the agent to write one.',
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: Sp.x2),
                itemCount: data.files.length,
                itemBuilder: (context, index) {
                  final entry = data.files[index];
                  final change = data.changes[entry.path];
                  return InkWell(
                    onTap: () => _open(entry),
                    onLongPress: () => _delete(entry),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Sp.x4, 9, Sp.x3, 9),
                      child: Row(
                        children: [
                          Icon(
                            entry.isDir
                                ? Icons.folder_rounded
                                : _fileIcon(entry.name),
                            size: 16,
                            color: entry.isDir ? Pal.amber : Pal.textDim,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              entry.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Txt.code.copyWith(
                                fontSize: 11.5,
                                color: entry.isDir ? Pal.textMuted : Pal.text,
                              ),
                            ),
                          ),
                          if (change != null) ...[
                            _ChangeBadge(change: change),
                            const SizedBox(width: 7),
                          ],
                          if (!entry.isDir)
                            Text(humanSize(entry.size),
                                style: Txt.meta.copyWith(fontSize: 9.5)),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x4, Sp.x2),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Pal.line)),
          ),
          child: FutureBuilder<_FilesData>(
            future: _future,
            builder: (context, snapshot) {
              final pending = snapshot.data?.pending ?? 0;
              return Text(
                pending > 0
                    ? '$pending unpushed commit${pending == 1 ? '' : 's'} · tap to edit · long-press to delete'
                    : 'tap to edit · long-press to delete',
                style: Txt.meta.copyWith(fontSize: 9.5),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' => Icons.flutter_dash,
      'html' || 'htm' => Icons.language_rounded,
      'css' => Icons.brush_outlined,
      'js' || 'ts' || 'json' => Icons.data_object_rounded,
      'md' => Icons.article_outlined,
      'py' => Icons.code_rounded,
      'yaml' || 'yml' => Icons.tune_rounded,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}

class _FilesData {
  const _FilesData(this.files, this.changes, this.pending);
  final List<FileEntry> files;
  final Map<String, RepoChange> changes;
  final int pending;
}

class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({required this.change});

  final RepoChange change;

  @override
  Widget build(BuildContext context) {
    final added = change.status == RepoChangeStatus.added;
    final color = added ? Pal.mint : Pal.amber;
    return Tooltip(
      message: added ? 'New since last push' : 'Modified since last push',
      child: Container(
        width: 19,
        height: 19,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: const BorderRadius.all(Radius.circular(5)),
          border: Border.all(color: color.withOpacity(0.42)),
        ),
        child: Text(
          change.status.letter,
          style: Txt.meta.copyWith(
            fontSize: 9,
            height: 1,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
