import 'package:flutter/material.dart';

import '../core/push_state.dart';
import '../core/vfs.dart';
import '../models.dart';
import '../screens/editor.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/project_actions.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/ui.dart';

class FilesTab extends StatefulWidget {
  const FilesTab({super.key, required this.project});

  final Project project;

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  Future<_FilesData>? _future;
  final Set<String> _expanded = {};

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
    if (mounted) {
      setState(() => _expanded.add(name));
      _refresh();
    }
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
    if (entry.isDir) {
      setState(() {
        if (!_expanded.remove(entry.path)) _expanded.add(entry.path);
      });
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorScreen(project: widget.project, path: entry.path),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _delete(FileEntry entry) async {
    final state = AppScope.of(context);
    final confirmed = await showPraxisConfirm(
      context,
      title: 'Delete ${entry.name}?',
      body: entry.isDir
          ? 'The folder and every file inside it is removed from the device. This cannot be undone.'
          : 'The file is removed from the device. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
      details: [ConfirmDetail('Path', entry.path)],
    );
    if (confirmed && mounted) {
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
                'since last commit',
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
              final rows = _treeRows(data);
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: Sp.x2),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final entry = row.entry;
                  final change = data.changes[entry.path];
                  final folderChanges = entry.isDir
                      ? data.changes.keys
                          .where((path) => path.startsWith('${entry.path}/'))
                          .length
                      : 0;
                  return InkWell(
                    onTap: () => _open(entry),
                    onLongPress: () => _delete(entry),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        Sp.x3 + (row.depth * 15),
                        8,
                        Sp.x3,
                        8,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            child: entry.isDir
                                ? Icon(
                                    _expanded.contains(entry.path)
                                        ? Icons.keyboard_arrow_down_rounded
                                        : Icons.keyboard_arrow_right_rounded,
                                    size: 15,
                                    color: Pal.textDim,
                                  )
                                : null,
                          ),
                          Icon(
                            entry.isDir
                                ? _expanded.contains(entry.path)
                                    ? Icons.folder_open_rounded
                                    : Icons.folder_rounded
                                : _fileIcon(entry.name),
                            size: 16,
                            color: entry.isDir ? Pal.amber : Pal.textDim,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Txt.code.copyWith(
                                fontSize: 11.5,
                                color: entry.isDir ? Pal.textMuted : Pal.text,
                                fontWeight: entry.isDir
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (change != null) ...[
                            _ChangeBadge(change: change),
                            const SizedBox(width: 7),
                          ] else if (folderChanges > 0) ...[
                            Text(
                              '$folderChanges',
                              style: Txt.meta.copyWith(
                                fontSize: 9,
                                color: Pal.amber,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 7),
                          ],
                          if (!entry.isDir)
                            Text(
                              humanSize(entry.size),
                              style: Txt.meta.copyWith(fontSize: 9.5),
                            ),
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
                    ? '$pending unpushed commit${pending == 1 ? '' : 's'} · tap to open · long-press to delete'
                    : 'tap folders to expand · tap files to edit · long-press to delete',
                style: Txt.meta.copyWith(fontSize: 9.5),
              );
            },
          ),
        ),
      ],
    );
  }

  List<_TreeRow> _treeRows(_FilesData data) {
    final children = <String, List<FileEntry>>{};
    for (final entry in data.files) {
      final slash = entry.path.lastIndexOf('/');
      final parent = slash < 0 ? '' : entry.path.substring(0, slash);
      children.putIfAbsent(parent, () => []).add(entry);
    }
    for (final list in children.values) {
      list.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }
    final rows = <_TreeRow>[];
    void walk(String parent, int depth) {
      for (final entry in children[parent] ?? const <FileEntry>[]) {
        rows.add(_TreeRow(entry, depth));
        if (entry.isDir && _expanded.contains(entry.path)) {
          walk(entry.path, depth + 1);
        }
      }
    }

    walk('', 0);
    return rows;
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

class _TreeRow {
  const _TreeRow(this.entry, this.depth);
  final FileEntry entry;
  final int depth;
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
      message: added ? 'New since last commit' : 'Modified since last commit',
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
