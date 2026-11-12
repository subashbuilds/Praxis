import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/file_import.dart';
import '../core/file_types.dart';
import '../core/import_picker.dart';
import '../core/project_search.dart';
import '../core/push_state.dart';
import '../core/vfs.dart';
import '../models.dart';
import '../screens/editor.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/project_actions.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/file_glyph.dart';
import '../widgets/ui.dart';

class FilesTab extends StatefulWidget {
  const FilesTab({super.key, required this.project});

  final Project project;

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  Future<_FilesData>? _future;
  _FilesData? _lastData;
  final Set<String> _expanded = {};
  final Set<String> _loadedDirs = {};
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _searchOpen = false;
  bool _searching = false;
  String _searchQuery = '';
  ProjectSearchResult? _searchResult;
  String? _searchError;
  bool _importing = false;
  bool _refreshing = false;
  final Set<String> _collapsedMatches = {};
  int _loadToken = 0;
  DateTime? _changesLoadedAt;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    final state = AppScope.of(context);
    final token = ++_loadToken;
    final future = _load(state);
    setState(() {
      _future = future;
      _refreshing = true;
    });
    future.then<void>(
      (data) {
        if (!mounted || token != _loadToken) return;
        setState(() {
          _lastData = data;
          _refreshing = false;
        });
      },
      onError: (Object error, StackTrace stack) {
        if (!mounted || token != _loadToken) return;
        setState(() => _refreshing = false);
      },
    );
  }

  Future<_FilesData> _load(AppState state) async {
    // Only the root is read here. Folders are listed when they are opened, so
    // a portfolio with thousands of files never blocks the first frame.
    final fs = state.fsFor(widget.project);
    final files = <FileEntry>[
      ...await fs.list(recursive: false),
    ];
    // A refresh should not collapse folders the user is already inside.
    _loadedDirs
      ..clear()
      ..add('');
    for (final path in _expanded) {
      if (path.isEmpty) continue;
      try {
        files.addAll(await fs.list(path: path, recursive: false));
        _loadedDirs.add(path);
      } catch (_) {
        // A deleted folder is dropped from the next tree.
      }
    }
    final data = _FilesData(
      files,
      const {},
      await state.pendingCommitsFor(widget.project),
    );
    final token = _loadToken;
    unawaited(Future<void>.delayed(
      const Duration(milliseconds: 600),
      () => _loadChanges(state, token),
    ));
    return data;
  }

  Future<void> _loadChanges(AppState state, int token) async {
    // Change badges walk the whole project. Re-reading a large tree every time
    // the editor closes made tab switches and file opens stutter, so badges
    // refresh at most once every eight seconds.
    final last = _changesLoadedAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 8)) {
      return;
    }
    try {
      final changes = await state.changesFor(widget.project);
      if (!mounted || token != _loadToken || _lastData == null) return;
      _changesLoadedAt = DateTime.now();
      setState(() {
        _lastData = _FilesData(
          _lastData!.files,
          {for (final change in changes) change.path: change},
          _lastData!.pending,
        );
      });
    } catch (_) {
      // Change badges are secondary; the tree remains usable without them.
    }
  }

  Future<void> _newFile() async {
    final action = await _showAddSheet(
      title: 'Add to the project',
      body:
          'Create something new, or bring files and folders in from this device.',
      createLabel: 'Create a file',
    );
    if (!mounted) return;
    switch (action) {
      case _AddAction.create:
        await _createNewFile();
      case _AddAction.importFiles:
        await _importFiles();
      case _AddAction.importFolder:
        await _importFolder();
      case null:
        break;
    }
  }

  Future<void> _newFolder() async {
    final action = await _showAddSheet(
      title: 'Add to the project',
      body:
          'Create an empty folder, or merge files and folders from this device.',
      createLabel: 'Create a folder',
    );
    if (!mounted) return;
    switch (action) {
      case _AddAction.create:
        await _createNewFolder();
      case _AddAction.importFiles:
        await _importFiles();
      case _AddAction.importFolder:
        await _importFolder();
      case null:
        break;
    }
  }

  Future<_AddAction?> _showAddSheet({
    required String title,
    required String body,
    required String createLabel,
  }) =>
      showModalBottomSheet<_AddAction>(
        context: context,
        useSafeArea: true,
        backgroundColor: Pal.surface,
        builder: (sheetContext) => SafeArea(
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
                    const SizedBox(height: 4),
                    Text(body, style: Txt.bodySoft),
                  ],
                ),
              ),
              const Hairline(),
              ListTile(
                leading: Icon(Icons.add_rounded, color: Pal.ember),
                title: Text(createLabel, style: Txt.body),
                subtitle: Text('Starts empty and opens in the editor.',
                    style: Txt.meta),
                onTap: () => Navigator.of(sheetContext).pop(_AddAction.create),
              ),
              ListTile(
                leading: Icon(Icons.upload_file_outlined, color: Pal.mint),
                title: Text('Import files', style: Txt.body),
                subtitle: Text(
                  'Pick one or more files. The originals stay untouched.',
                  style: Txt.meta,
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_AddAction.importFiles),
              ),
              ListTile(
                leading:
                    Icon(Icons.drive_folder_upload_outlined, color: Pal.mint),
                title: Text('Import a folder', style: Txt.body),
                subtitle: Text(
                  'Copies the folder and every file inside it.',
                  style: Txt.meta,
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_AddAction.importFolder),
              ),
              const SizedBox(height: Sp.x2),
            ],
          ),
        ),
      );

  Future<void> _createNewFile() async {
    final state = AppScope.of(context);
    final navigator = Navigator.of(context);
    final name = await _askName('New file', 'lib/example.dart');
    if (name == null || !mounted) return;
    await state.createFile(widget.project, name);
    if (!mounted) return;
    _refresh();
    final changed = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) => EditorScreen(project: widget.project, path: name),
      ),
    );
    // Only rescan the tree when the editor actually wrote a file. Closing an
    // untouched file used to walk the whole project again.
    if (mounted && changed == true) _refresh();
  }

  Future<void> _createNewFolder() async {
    final state = AppScope.of(context);
    final name = await _askName('New folder', 'src');
    if (name == null || !mounted) return;
    await state.createFolder(widget.project, name);
    if (mounted) {
      setState(() => _expanded.add(name));
      _refresh();
    }
  }

  Future<void> _importFiles({String destination = ''}) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
    } catch (error) {
      _showMessage('Could not open the file picker: $error');
      return;
    }
    final paths = result?.files
            .map((file) => file.path)
            .whereType<String>()
            .where((path) => path.isNotEmpty)
            .toList() ??
        const <String>[];
    if (paths.isEmpty || !mounted) return;
    await _runImport(
      [
        for (final path in paths)
          ImportEntry(
            path: _joinPath(
              destination,
              path.replaceAll('\\', '/').split('/').last,
            ),
            sourcePath: path,
            isDir: false,
          ),
      ],
      expand: destination.isEmpty ? const [] : [destination],
    );
  }

  Future<void> _importFolder({String destination = ''}) async {
    String? rootPath;
    try {
      rootPath = await ImportPicker.pickFolder();
    } catch (error) {
      _showMessage('Could not open the folder picker: $error');
      return;
    }
    if (rootPath == null || rootPath.isEmpty || !mounted) return;
    final root = Directory(rootPath);
    if (!await root.exists()) {
      _showMessage('That folder can no longer be read.');
      return;
    }
    final name = rootPath
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty)
        .last;
    // The import service expands the folder from disk. Passing only the root
    // means a folder whose name already exists is still merged correctly.
    // Expand the destination afterwards: a merged folder with collapsed
    // children looked like an empty import even when every file was copied.
    final target = _joinPath(destination, name);
    try {
      await _runImport(
        [
          ImportEntry(path: target, sourcePath: rootPath, isDir: true),
        ],
        expand: target.split('/'),
      );
    } finally {
      await ImportPicker.cleanup();
    }
  }

  String _joinPath(String parent, String name) =>
      parent.isEmpty ? name : '$parent/$name';

  Future<void> _runImport(
    List<ImportEntry> entries, {
    List<String> expand = const [],
  }) async {
    if (entries.isEmpty) return;
    setState(() => _importing = true);
    try {
      final summary = await AppScope.of(context).importIntoProject(
        widget.project,
        entries,
        onConflict: _askImportConflict,
      );
      if (!mounted) return;
      setState(() {
        for (final path in expand) {
          var current = '';
          for (final part in path.split('/').where((part) => part.isNotEmpty)) {
            current = current.isEmpty ? part : '$current/$part';
            _expanded.add(current);
          }
        }
      });
      _refresh();
      final failed = summary.failed.isEmpty
          ? ''
          : ' · ${summary.failed.first}${summary.failed.length > 1 ? ' (+${summary.failed.length - 1} more)' : ''}';
      _showMessage('${summary.message}$failed');
    } catch (error) {
      _showMessage('Import failed: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<bool> _askImportConflict(ImportConflict conflict) async {
    if (!mounted) return false;
    final incoming = conflict.incomingIsDir ? 'folder' : 'file';
    final existing = conflict.existingIsDir ? 'folder' : 'file';
    final fs = AppScope.of(context).fsFor(widget.project);
    final importedDetail = await _describePath(
      conflict.sourcePath,
      conflict.path,
      conflict.incomingIsDir,
    );
    final existingDetail = await _describePath(
      fs.absolute(conflict.path),
      conflict.path,
      conflict.existingIsDir,
    );
    if (!mounted) return false;
    final detail = switch ((conflict.incomingIsDir, conflict.existingIsDir)) {
      (false, false) =>
        'The imported bytes replace the current file. This cannot be undone.',
      (true, false) =>
        'The imported folder replaces the file. The file is deleted and the folder is created.',
      (false, true) =>
        'The imported file replaces the folder. The folder and everything inside it are deleted.',
      (true, true) => 'Merge the folder contents.',
    };
    return showPraxisConfirm(
      context,
      title: 'Replace existing $existing?',
      body:
          '$incoming at ${conflict.path} would replace an existing $existing. $detail',
      confirmLabel: 'Replace',
      cancelLabel: 'Keep existing',
      destructive: true,
      icon: Icons.swap_horiz_rounded,
      details: [
        ConfirmDetail('Path', conflict.path),
        ConfirmDetail('Imported', importedDetail),
        ConfirmDetail('Existing', existingDetail),
      ],
    );
  }

  Future<String> _describePath(
    String path,
    String displayPath,
    bool isDir,
  ) async {
    if (isDir) return 'folder';
    final file = File(path);
    if (!await file.exists()) return 'file · unavailable';
    final size = await file.length();
    if (classifyFile(displayPath).isText) {
      try {
        final lines = await _countLines(file, size);
        return '${humanFileSize(size)} · $lines ${lines == 1 ? 'line' : 'lines'}';
      } catch (_) {
        // The size is still useful if the file disappeared mid-dialog.
      }
    }
    return humanFileSize(size);
  }

  Future<int> _countLines(File file, int size) async {
    if (size == 0) return 1;
    var newlines = 0;
    var last = 0;
    final reader = await file.open();
    try {
      while (true) {
        final chunk = await reader.read(64 * 1024);
        if (chunk.isEmpty) break;
        last = chunk.last;
        for (final byte in chunk) {
          if (byte == 10) newlines++;
        }
      }
    } finally {
      await reader.close();
    }
    return last == 10 ? newlines : newlines + 1;
  }

  void _showMessage(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // A queued message from an earlier import must not make a completed merge
    // look like it failed. Show this operation's result immediately.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<String?> _askName(
    String title,
    String hint, {
    String initial = '',
    String confirmLabel = 'Create',
  }) {
    final controller = TextEditingController(text: initial);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: initial.length,
    );
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
            child: Text(confirmLabel),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _showActions(FileEntry entry) async {
    final action = await showModalBottomSheet<_EntryAction>(
      context: context,
      useSafeArea: true,
      backgroundColor: Pal.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.page, 0, Sp.page, Sp.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.isDir ? 'Folder actions' : 'File actions',
                    style: Txt.headline.copyWith(fontSize: 21),
                  ),
                  const SizedBox(height: 4),
                  Text(entry.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Txt.meta),
                ],
              ),
            ),
            const Hairline(),
            if (entry.isDir) ...[
              ListTile(
                leading: Icon(Icons.upload_file_outlined, color: Pal.mint),
                title: Text('Import files here', style: Txt.body),
                subtitle: Text('Copy files from this device into the folder.',
                    style: Txt.meta),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_EntryAction.importFiles),
              ),
              ListTile(
                leading:
                    Icon(Icons.drive_folder_upload_outlined, color: Pal.mint),
                title: Text('Import a folder here', style: Txt.body),
                subtitle: Text(
                    'Merge a folder from this device below this one.',
                    style: Txt.meta),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_EntryAction.importFolder),
              ),
            ],
            ListTile(
              leading: Icon(Icons.drive_file_rename_outline_rounded,
                  color: Pal.textMuted),
              title: Text('Rename', style: Txt.body),
              subtitle: Text('Keep the contents and choose a new path.',
                  style: Txt.meta),
              onTap: () => Navigator.of(sheetContext).pop(_EntryAction.rename),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: Pal.rose),
              title: Text('Delete', style: Txt.body.copyWith(color: Pal.rose)),
              subtitle: Text(
                entry.isDir
                    ? 'Remove the folder and everything inside it.'
                    : 'Remove the file from this device.',
                style: Txt.meta,
              ),
              onTap: () => Navigator.of(sheetContext).pop(_EntryAction.delete),
            ),
            const SizedBox(height: Sp.x2),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _EntryAction.importFiles:
        await _importFiles(destination: entry.path);
        break;
      case _EntryAction.importFolder:
        await _importFolder(destination: entry.path);
        break;
      case _EntryAction.rename:
        await _rename(entry);
        break;
      case _EntryAction.delete:
        await _delete(entry);
        break;
    }
  }

  Future<void> _rename(FileEntry entry) async {
    final current = entry.path;
    final proposed = await _askName(
      'Rename ${entry.name}',
      current,
      initial: current,
      confirmLabel: 'Rename',
    );
    if (proposed == null || proposed.isEmpty || !mounted) return;
    var target = proposed.replaceAll('\\', '/');
    if (!target.contains('/')) {
      final slash = current.lastIndexOf('/');
      target = slash < 0 ? target : '${current.substring(0, slash + 1)}$target';
    }
    target = target.replaceFirst(RegExp(r'^/+'), '');
    if (target == current) return;
    final state = AppScope.of(context);
    if (await state.fsFor(widget.project).exists(target)) {
      if (mounted) _showMessage('A file or folder already exists at $target.');
      return;
    }
    try {
      await state.renamePath(widget.project, current, target);
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) _showMessage('Could not rename: $error');
    }
  }

  Future<void> _open(
    FileEntry entry, {
    int? line,
    String? highlight,
  }) async {
    if (entry.isDir) {
      if (_expanded.remove(entry.path)) {
        setState(() {});
        return;
      }
      setState(() => _expanded.add(entry.path));
      if (_loadedDirs.contains(entry.path)) return;
      _loadedDirs.add(entry.path);
      try {
        final children = await AppScope.of(context).fsFor(widget.project).list(
              path: entry.path,
              recursive: false,
            );
        if (!mounted || _lastData == null) return;
        final unique = <String, FileEntry>{
          for (final item in _lastData!.files) item.path: item,
          for (final item in children) item.path: item,
        };
        setState(() {
          _lastData = _FilesData(
            unique.values.toList(),
            _lastData!.changes,
            _lastData!.pending,
          );
        });
      } catch (error) {
        _loadedDirs.remove(entry.path);
        _showMessage('Could not open ${entry.path}: $error');
      }
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          project: widget.project,
          path: entry.path,
          initialLine: line,
          highlight: highlight,
        ),
      ),
    );
    if (mounted && changed == true) _refresh();
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

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchController.clear();
        _searchDebounce?.cancel();
        _searchQuery = '';
        _searchResult = null;
        _searchError = null;
        _searching = false;
      }
    });
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = query;
      _searchError = null;
      if (query.length < 3) {
        _searchResult = null;
        _searching = false;
      } else {
        _searching = true;
      }
    });
    if (query.length < 3) return;
    _searchDebounce = Timer(const Duration(milliseconds: 280), () async {
      final token = ++_loadToken;
      try {
        final result =
            await AppScope.of(context).searchProject(widget.project, query);
        if (!mounted || token != _loadToken || _searchQuery != query) return;
        setState(() {
          _searchResult = result;
          _searching = false;
        });
      } catch (error) {
        if (!mounted || token != _loadToken) return;
        setState(() {
          _searching = false;
          _searchError = '$error';
        });
      }
    });
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
        if (_importing || _refreshing)
          LinearProgressIndicator(minHeight: 2, color: Pal.mint),
        Container(
          padding: const EdgeInsets.fromLTRB(Sp.x4, 5, Sp.x2, 5),
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
                icon: _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                tooltip: _searchOpen ? 'Close search' : 'Search files',
                size: 18,
                onTap: _toggleSearch,
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
        if (_searchOpen)
          Container(
            padding: const EdgeInsets.fromLTRB(Sp.x3, 6, Sp.x3, 7),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Pal.line)),
            ),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: Txt.body.copyWith(fontSize: 12),
              cursorColor: Pal.ember,
              onChanged: _onSearchChanged,
              decoration: appField(
                'Search filenames and code (min. 3 characters)',
                suffix: _searching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : Icon(Icons.search_rounded, size: 17, color: Pal.textDim),
              ),
            ),
          ),
        if (_searchOpen)
          Expanded(child: _searchBody(state))
        else
          Expanded(
            child: FutureBuilder<_FilesData>(
              future: _future ??= _load(state),
              builder: (context, snapshot) {
                if (_lastData == null && snapshot.hasData) {
                  _lastData = snapshot.data;
                }
                final data = _lastData ?? snapshot.data;
                if (data == null &&
                    snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                if (snapshot.hasError && data == null) {
                  return Padding(
                    padding: const EdgeInsets.all(Sp.page),
                    child: Text(
                      'Could not read the project: ${snapshot.error}',
                      style: Txt.bodySoft.copyWith(color: Pal.rose),
                    ),
                  );
                }
                final rowsData = data ?? const _FilesData([], {}, 0);
                if (rowsData.files.isEmpty) {
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
                final rows = _treeRows(rowsData);
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: Sp.x2),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final entry = row.entry;
                    final change = rowsData.changes[entry.path];
                    final folderChanges = entry.isDir
                        ? rowsData.changes.keys
                            .where((path) => path.startsWith('${entry.path}/'))
                            .length
                        : 0;
                    return InkWell(
                      onTap: () => _open(entry),
                      onLongPress: () => _showActions(entry),
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
                            FileGlyph(
                              name: entry.name,
                              isDir: entry.isDir,
                              expanded: _expanded.contains(entry.path),
                              size: 16,
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
                              SizedBox(
                                width: 19,
                                child: Text(
                                  '$folderChanges',
                                  textAlign: TextAlign.center,
                                  style: Txt.meta.copyWith(
                                    fontSize: 9,
                                    height: 1,
                                    color: Pal.amber,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                            ],
                            if (!entry.isDir)
                              SizedBox(
                                width: 38,
                                child: Text(
                                  humanSize(entry.size),
                                  textAlign: TextAlign.right,
                                  style: Txt.meta.copyWith(fontSize: 9.5),
                                ),
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
          padding: const EdgeInsets.fromLTRB(Sp.x4, 6, Sp.x4, 6),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Pal.line)),
          ),
          child: Text(
            _lastData != null && _lastData!.pending > 0
                ? '${_lastData!.pending} unpushed commit${_lastData!.pending == 1 ? '' : 's'} · tap to open · long-press for actions'
                : 'tap to edit · long-press for rename or delete · long-press a folder to import',
            style: Txt.meta.copyWith(fontSize: 9.5),
          ),
        ),
      ],
    );
  }

  Widget _searchBody(AppState state) {
    if (_searchQuery.length < 3) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Sp.page),
          child: Text(
            'Type at least 3 characters to search file names and file contents.',
            textAlign: TextAlign.center,
            style: Txt.bodySoft,
          ),
        ),
      );
    }
    if (_searching && _searchResult == null) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_searchError != null) {
      return Padding(
        padding: const EdgeInsets.all(Sp.page),
        child:
            Text(_searchError!, style: Txt.bodySoft.copyWith(color: Pal.rose)),
      );
    }
    final result = _searchResult;
    if (result == null) return const SizedBox.shrink();
    if (result.files.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Sp.page),
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No matches for “${result.query}”',
            body: 'Try a shorter name or a code fragment.',
          ),
        ),
      );
    }
    // Flatten file headers and every match into one list so a file with 50
    // hits renders lazily instead of building a tall Column up front.
    final rows = <_SearchRow>[];
    for (final file in result.files) {
      rows.add(_SearchRow.header(file));
      if (_collapsedMatches.contains(file.path)) continue;
      for (final match in file.matches) {
        rows.add(_SearchRow.match(file, match));
      }
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: Sp.x4),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            padding: const EdgeInsets.fromLTRB(Sp.x4, 8, Sp.x4, 7),
            child: Text(
              '${result.totalMatches} match${result.totalMatches == 1 ? '' : 'es'} '
              'in ${result.files.length} file${result.files.length == 1 ? '' : 's'}'
              '${result.truncated ? ' · limited' : ''}',
              style: Txt.meta.copyWith(fontSize: 9.5, color: Pal.mint),
            ),
          );
        }
        final row = rows[index - 1];
        final file = row.file;
        final match = row.match;
        if (match == null) {
          final collapsed = _collapsedMatches.contains(file.path);
          return InkWell(
            onTap: () => _open(
              FileEntry(
                path: file.path,
                name: file.path.split('/').last,
                isDir: false,
                size: 0,
              ),
              line: file.matches.isEmpty ? null : file.matches.first.line,
              highlight: result.query,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Sp.x4, 7, Sp.x2, 6),
              child: Row(
                children: [
                  FileGlyph(name: file.path.split('/').last, size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.path.split('/').last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.code.copyWith(fontSize: 11.5),
                        ),
                        Text(
                          file.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Txt.meta.copyWith(fontSize: 8.5),
                        ),
                      ],
                    ),
                  ),
                  if (file.nameMatch)
                    MonoChip('NAME',
                        tint: Pal.mint, icon: Icons.text_fields_rounded),
                  const SizedBox(width: 4),
                  Text('${file.count}', style: Txt.meta.copyWith(fontSize: 9)),
                  if (file.matches.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() {
                        if (!_collapsedMatches.remove(file.path)) {
                          _collapsedMatches.add(file.path);
                        }
                      }),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 4, 2, 4),
                        child: Icon(
                          collapsed
                              ? Icons.keyboard_arrow_right_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 17,
                          color: Pal.textDim,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }
        return InkWell(
          onTap: () => _open(
            FileEntry(
              path: file.path,
              name: file.path.split('/').last,
              isDir: false,
              size: 0,
            ),
            line: match.line,
            highlight: result.query,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Sp.x4 + 23, 4, Sp.x4, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${match.line}',
                    textAlign: TextAlign.right,
                    style: Txt.code.copyWith(
                      fontSize: 9,
                      color: Pal.textDim,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MatchText(
                    text: searchLinePreview(match.text),
                    query: result.query,
                    maxLines: 2,
                    style: Txt.code.copyWith(
                      fontSize: 9.5,
                      color: Pal.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
}

enum _AddAction { create, importFiles, importFolder }

enum _EntryAction { importFiles, importFolder, rename, delete }

class _TreeRow {
  const _TreeRow(this.entry, this.depth);
  final FileEntry entry;
  final int depth;
}

class _SearchRow {
  const _SearchRow.header(this.file) : match = null;
  const _SearchRow.match(this.file, this.match);

  final FileSearchResult file;
  final CodeSearchMatch? match;
}

class _FilesData {
  const _FilesData(this.files, this.changes, this.pending);
  final List<FileEntry> files;
  final Map<String, RepoChange> changes;
  final int pending;
}

/// Renders text with every case-insensitive occurrence of the query marked,
/// so a search result shows why it matched.
class _MatchText extends StatelessWidget {
  const _MatchText({
    required this.text,
    required this.query,
    required this.style,
    this.maxLines = 1,
  });

  final String text;
  final String query;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final needle = query.trim();
    final lower = text.toLowerCase();
    final target = needle.toLowerCase();
    if (needle.isEmpty || !lower.contains(target)) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final spans = <TextSpan>[];
    var from = 0;
    while (true) {
      final at = lower.indexOf(target, from);
      if (at < 0) break;
      if (at > from) spans.add(TextSpan(text: text.substring(from, at)));
      spans.add(TextSpan(
        text: text.substring(at, at + needle.length),
        style: style.copyWith(
          backgroundColor: Pal.amber.withOpacity(0.3),
          color: Pal.text,
          fontWeight: FontWeight.w700,
        ),
      ));
      from = at + needle.length;
    }
    if (from < text.length) spans.add(TextSpan(text: text.substring(from)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
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
