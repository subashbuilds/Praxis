import 'dart:convert';
import 'dart:io';

import 'vfs.dart';

/// One file exactly as it existed immediately before a single agent mutation.
///
/// A task keeps one of these per write, not one per path: reverting the pill
/// for the second edit of a file must put back the text the first edit left,
/// while undoing the whole task walks the snapshots backwards to the state
/// before the task started.
class FileChange {
  const FileChange({
    required this.id,
    required this.path,
    required this.before,
    required this.existed,
    this.binary = false,
    this.reverted = false,
  });

  final String id;
  final String path;

  /// Text, or base64 bytes when [binary] is true. Empty when [existed] is
  /// false; reverting then removes the file the agent created.
  final String before;
  final bool existed;
  final bool binary;
  final bool reverted;

  FileChange copyWith({bool? reverted}) => FileChange(
        id: id,
        path: path,
        before: before,
        existed: existed,
        binary: binary,
        reverted: reverted ?? this.reverted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'before': before,
        'existed': existed,
        'binary': binary,
        'reverted': reverted,
      };

  static FileChange? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = '${json['id'] ?? ''}';
    final path = '${json['path'] ?? ''}';
    if (id.isEmpty || path.isEmpty) return null;
    return FileChange(
      id: id,
      path: path,
      before: '${json['before'] ?? ''}',
      existed: json['existed'] == true,
      binary: json['binary'] == true,
      reverted: json['reverted'] == true,
    );
  }
}

/// What a revert changed, plus a short sentence for the transcript.
class UndoOutcome {
  const UndoOutcome(this.message, {this.changeIds = const []});

  final String message;
  final List<String> changeIds;

  bool get changedAnything => changeIds.isNotEmpty;
}

/// Every change one agent run made to the project, oldest first.
class UndoTask {
  const UndoTask({
    required this.id,
    required this.label,
    required this.at,
    required this.changes,
  });

  final String id;
  final String label;
  final DateTime at;
  final List<FileChange> changes;

  bool get isEmpty => changes.isEmpty;

  List<FileChange> get pending =>
      changes.where((change) => !change.reverted).toList(growable: false);

  Set<String> get paths => changes.map((change) => change.path).toSet();

  int get fileCount => paths.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'at': at.toIso8601String(),
        'changes': changes.map((change) => change.toJson()).toList(),
      };

  static UndoTask? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = '${json['id'] ?? ''}';
    if (id.isEmpty) return null;
    return UndoTask(
      id: id,
      label: '${json['label'] ?? ''}',
      at: DateTime.tryParse('${json['at'] ?? ''}') ?? DateTime.now(),
      changes: [
        for (final item in json['changes'] as List? ?? const [])
          if (FileChange.fromJson(item) case final change?) change,
      ],
    );
  }
}

/// Snapshots project files before the agent changes them, so a single write or
/// a whole task can be put back from the transcript.
///
/// Snapshots live in `.praxis/undo` inside the project: they are app state, so
/// they are excluded from the file list, the agent prompt, export and push.
/// A file larger than [maxBytes] is not snapshotted; the write still happens
/// and the transcript simply offers no revert for it.
class UndoStore {
  UndoStore(this.fs);

  final ProjectFs fs;

  static const directory = '.praxis/undo';
  static const maxBytes = 512 * 1024;

  /// Older task snapshots are pruned so the folder cannot grow without bound.
  static const maxTasks = 20;

  String _fileFor(String taskId) => '$directory/${_safeName(taskId)}.json';

  String _safeName(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');

  Future<UndoTask?> task(String taskId) async {
    if (taskId.trim().isEmpty) return null;
    final path = _fileFor(taskId);
    try {
      if (!await fs.exists(path)) return null;
      return UndoTask.fromJson(jsonDecode(await fs.read(path)));
    } catch (_) {
      return null;
    }
  }

  /// The most recently written task snapshot, or null when the project has no
  /// undo history yet.
  Future<UndoTask?> latest() async {
    // `.praxis` is app state and ProjectFs.list deliberately hides it, so the
    // snapshot folder is read directly. Sorting by modification time avoids
    // parsing every snapshot, each of which can hold a large file.
    final files = await _snapshotFiles();
    if (files.isEmpty) return null;
    final newest = await _newestSnapshot(files);
    if (newest == null) return null;
    try {
      return UndoTask.fromJson(jsonDecode(await File(newest).readAsString()));
    } catch (_) {
      return null;
    }
  }

  Future<String?> _newestSnapshot(List<String> files) async {
    String? newest;
    DateTime? newestAt;
    for (final path in files) {
      try {
        final modified = (await File(path).stat()).modified;
        if (newestAt == null || modified.isAfter(newestAt)) {
          newest = path;
          newestAt = modified;
        }
      } catch (_) {
        // A snapshot removed mid-walk is simply skipped.
      }
    }
    return newest;
  }

  /// Records [path] before the agent changes it. Returns the change that the
  /// transcript can offer to revert, or null when the file cannot be
  /// snapshotted (too large, unreadable, or outside the project).
  Future<FileChange?> snapshot({
    required String taskId,
    required String path,
    required String label,
  }) async {
    if (taskId.trim().isEmpty) return null;
    final String rel;
    try {
      rel = fs.normalize(path);
    } on FsError {
      return null;
    }
    if (rel.isEmpty || rel == '.praxis' || rel.startsWith('.praxis/')) {
      return null;
    }

    var existed = false;
    var binary = false;
    var content = '';
    try {
      existed = await fs.exists(rel);
      if (existed) {
        if (await fs.isTextFile(rel)) {
          content = await fs.read(rel);
          if (content.length > maxBytes) return null;
        } else {
          final bytes = await fs.readBytes(rel);
          if (bytes.length > maxBytes) return null;
          binary = true;
          content = base64Encode(bytes);
        }
      }
    } on FsError {
      return null;
    }

    final task = await this.task(taskId) ??
        UndoTask(
          id: taskId,
          label: label,
          at: DateTime.now(),
          changes: const [],
        );
    final change = FileChange(
      id: '${DateTime.now().microsecondsSinceEpoch}'
          '-${task.changes.length}',
      path: rel,
      before: content,
      existed: existed,
      binary: binary,
    );
    await _save(UndoTask(
      id: task.id,
      label: task.label,
      at: task.at,
      changes: [...task.changes, change],
    ));
    return change;
  }

  /// Puts [change] back. The file is removed when it did not exist before the
  /// write, and rewritten byte-for-byte otherwise.
  Future<UndoOutcome> revert(UndoTask task, FileChange change) async {
    await _restore(change);
    final updated = UndoTask(
      id: task.id,
      label: task.label,
      at: task.at,
      changes: [
        for (final item in task.changes)
          item.id == change.id ? item.copyWith(reverted: true) : item,
      ],
    );
    await _save(updated);
    return UndoOutcome(
      change.existed ? 'restored ${change.path}' : 'removed ${change.path}',
      changeIds: [change.id],
    );
  }

  /// Reverts exactly the changes named by [ids].
  ///
  /// Restoring a snapshot overwrites the file, so a change that a later write
  /// to the same file replaced is not reverted on its own: doing so would
  /// silently discard the newer edit. The outcome says so, and the whole task
  /// can still be undone from the transcript bar.
  Future<UndoOutcome> revertIds(List<String> ids) async {
    final wanted = ids.toSet();
    if (wanted.isEmpty) return const UndoOutcome('Nothing to revert.');
    for (final path in await _snapshotFiles()) {
      final UndoTask? task;
      try {
        task = UndoTask.fromJson(jsonDecode(await File(path).readAsString()));
      } catch (_) {
        continue;
      }
      if (task == null) continue;
      final selected = task.changes
          .where((change) => wanted.contains(change.id) && !change.reverted)
          .toList(growable: false);
      if (selected.isEmpty) continue;
      final shadowed = <String>{};
      for (final change in selected) {
        final position =
            task.changes.indexWhere((item) => item.id == change.id);
        final later = task.changes.skip(position + 1).any((item) =>
            !item.reverted &&
            item.path == change.path &&
            !selected.any((done) => done.id == item.id));
        if (later) shadowed.add(change.path);
      }
      if (shadowed.isNotEmpty) {
        return UndoOutcome(
          'a later change to ${shadowed.join(', ')} replaced it. Undo the last '
          'task to go back further.',
        );
      }
      final restored = <String>{};
      final removed = <String>{};
      for (final change in selected.reversed) {
        await _restore(change);
        if (change.existed) {
          restored.add(change.path);
        } else {
          removed.add(change.path);
        }
      }
      await _save(UndoTask(
        id: task.id,
        label: task.label,
        at: task.at,
        changes: [
          for (final item in task.changes)
            selected.any((done) => done.id == item.id)
                ? item.copyWith(reverted: true)
                : item,
        ],
      ));
      final parts = <String>[
        if (restored.isNotEmpty) '${restored.length} restored',
        if (removed.isNotEmpty) '${removed.length} removed',
      ];
      return UndoOutcome(
        parts.join(', '),
        changeIds: [for (final change in selected) change.id],
      );
    }
    return const UndoOutcome('These changes were already reverted.');
  }

  /// Reverts the whole task, newest change first, so a file written several
  /// times ends at the content it had before the task started.
  Future<UndoOutcome> undo(UndoTask task) async {
    final pending = task.pending.reversed.toList(growable: false);
    if (pending.isEmpty) {
      return const UndoOutcome('nothing left to undo');
    }
    final restored = <String>{};
    final removed = <String>{};
    final failed = <String>[];
    for (final change in pending) {
      try {
        await _restore(change);
        if (change.existed) {
          restored.add(change.path);
        } else {
          removed.add(change.path);
        }
      } catch (_) {
        failed.add(change.path);
      }
    }
    await _save(UndoTask(
      id: task.id,
      label: task.label,
      at: task.at,
      changes: [
        for (final item in task.changes)
          pending.any((done) => done.id == item.id)
              ? item.copyWith(reverted: true)
              : item,
      ],
    ));
    final parts = <String>[
      if (restored.isNotEmpty) '${restored.length} restored',
      if (removed.isNotEmpty) '${removed.length} removed',
      if (failed.isNotEmpty) '${failed.length} could not be reverted',
    ];
    return UndoOutcome(
      parts.isEmpty ? 'nothing to undo' : parts.join(', '),
      changeIds: [
        for (final change in pending) change.id,
      ],
    );
  }

  Future<void> _restore(FileChange change) async {
    if (change.existed) {
      if (change.binary) {
        await fs.writeBytes(change.path, base64Decode(change.before));
      } else {
        await fs.write(change.path, change.before);
      }
      return;
    }
    if (await fs.exists(change.path)) {
      await fs.delete(change.path);
    }
  }

  Future<void> _save(UndoTask task) async {
    await fs.write(_fileFor(task.id), jsonEncode(task.toJson()));
    await _prune();
  }

  Future<List<String>> _snapshotFiles() async {
    try {
      final folder = Directory(fs.absolute(directory));
      if (!await folder.exists()) return const [];
      return [
        for (final entity in folder.listSync())
          if (entity is File && entity.path.endsWith('.json')) entity.path,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _prune() async {
    try {
      final files = await _snapshotFiles();
      if (files.length <= maxTasks) return;
      final tasks = <({String path, DateTime at})>[];
      for (final path in files) {
        try {
          final parsed =
              UndoTask.fromJson(jsonDecode(await File(path).readAsString()));
          tasks.add((
            path: path,
            at: parsed?.at ?? DateTime.fromMillisecondsSinceEpoch(0),
          ));
        } catch (_) {
          // A corrupt snapshot is deleted below like an old one.
          tasks.add((
            path: path,
            at: DateTime.fromMillisecondsSinceEpoch(0),
          ));
        }
      }
      tasks.sort((a, b) => b.at.compareTo(a.at));
      for (final stale in tasks.skip(maxTasks)) {
        try {
          await File(stale.path).delete();
        } catch (_) {
          // Pruning is best effort; it must never fail a write.
        }
      }
    } catch (_) {
      // Pruning is best effort.
    }
  }
}
