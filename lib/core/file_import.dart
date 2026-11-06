import 'dart:io';

import 'vfs.dart';

/// One path selected by the system picker. Directories are represented too so
/// empty folders survive an import.
class ImportEntry {
  const ImportEntry({
    required this.path,
    required this.sourcePath,
    required this.isDir,
  });

  /// Destination relative to the project root.
  final String path;

  /// Absolute path on the device.
  final String sourcePath;
  final bool isDir;
}

class ImportConflict {
  const ImportConflict({
    required this.path,
    required this.sourcePath,
    required this.incomingIsDir,
    required this.existingIsDir,
  });

  final String path;

  /// Absolute source path, used to show line counts and sizes in the dialog.
  final String sourcePath;
  final bool incomingIsDir;
  final bool existingIsDir;
}

/// Returning true replaces the existing path. False keeps it and skips the
/// incoming entry.
typedef ImportConflictResolver = Future<bool> Function(ImportConflict conflict);

class ImportSummary {
  const ImportSummary({
    this.created = 0,
    this.replaced = 0,
    this.skipped = 0,
    this.failed = const [],
  });

  final int created;
  final int replaced;
  final int skipped;
  final List<String> failed;

  int get changed => created + replaced;
  int get files => created + replaced;

  String get message {
    final parts = <String>[
      if (created > 0) '$created imported',
      if (replaced > 0) '$replaced replaced',
      if (skipped > 0) '$skipped kept',
      if (failed.isNotEmpty) '${failed.length} skipped after an error',
    ];
    return parts.isEmpty ? 'Nothing was imported.' : parts.join(' · ');
  }
}

/// Copies picked files and folders into a project. Folder entries are expanded
/// from their real source contents here rather than trusting a picker to list
/// every child. Existing folders are always merged; only individual collisions
/// prompt the user. A declined folder replacement blocks its descendants.
Future<ImportSummary> importEntries(
  ProjectFs fs,
  List<ImportEntry> entries, {
  required ImportConflictResolver onConflict,
}) async {
  if (entries.isEmpty) return const ImportSummary();

  final expansion = await _expandEntries(fs, entries);
  final ordered = [...expansion.entries]..sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      final depth =
          a.path.split('/').length.compareTo(b.path.split('/').length);
      if (depth != 0) return depth;
      return a.path.compareTo(b.path);
    });

  var created = 0;
  var replaced = 0;
  var skipped = 0;
  final failed = [...expansion.failed];
  final blockedDirectories = <String>{};

  for (final entry in ordered) {
    String path;
    try {
      path = fs.normalize(entry.path);
    } on FsError catch (error) {
      failed.add('${entry.path}: ${error.message}');
      continue;
    }
    if (path.isEmpty) continue;
    if (blockedDirectories
        .any((blocked) => path == blocked || path.startsWith('$blocked/'))) {
      skipped++;
      continue;
    }

    FileSystemEntityType sourceType;
    try {
      sourceType = FileSystemEntity.typeSync(entry.sourcePath);
    } catch (error) {
      failed.add('${entry.path}: $error');
      continue;
    }
    if (entry.isDir && sourceType != FileSystemEntityType.directory) {
      skipped++;
      blockedDirectories.add(path);
      continue;
    }
    if (!entry.isDir && sourceType != FileSystemEntityType.file) {
      skipped++;
      continue;
    }

    FileSystemEntityType existingType;
    try {
      existingType = FileSystemEntity.typeSync(fs.absolute(path));
    } catch (error) {
      failed.add('$path: $error');
      continue;
    }
    if (existingType != FileSystemEntityType.notFound) {
      final existingIsDir = existingType == FileSystemEntityType.directory;
      if (entry.isDir && existingIsDir) {
        // Merge into the existing tree. Files inside are handled individually.
        continue;
      }
      final replace = await onConflict(ImportConflict(
        path: path,
        sourcePath: entry.sourcePath,
        incomingIsDir: entry.isDir,
        existingIsDir: existingIsDir,
      ));
      if (!replace) {
        skipped++;
        if (entry.isDir) blockedDirectories.add(path);
        continue;
      }
      try {
        await fs.delete(path);
      } catch (error) {
        failed.add('$path: $error');
        if (entry.isDir) blockedDirectories.add(path);
        continue;
      }
    }

    try {
      if (entry.isDir) {
        await fs.createDir(path);
        created++;
      } else {
        await fs.copyFromOutside(File(entry.sourcePath), path);
        if (existingType == FileSystemEntityType.notFound) {
          created++;
        } else {
          replaced++;
        }
      }
    } catch (error) {
      failed.add('$path: $error');
      if (entry.isDir) blockedDirectories.add(path);
    }
  }

  return ImportSummary(
    created: created,
    replaced: replaced,
    skipped: skipped,
    failed: failed,
  );
}

class _ExpandedEntries {
  const _ExpandedEntries(this.entries, this.failed);
  final List<ImportEntry> entries;
  final List<String> failed;
}

/// Expands each selected directory into its real descendants. Explicit entries
/// win over generated ones, so callers can still supply a pre-built tree.
Future<_ExpandedEntries> _expandEntries(
  ProjectFs fs,
  List<ImportEntry> entries,
) async {
  final byPath = <String, ImportEntry>{};
  final failed = <String>[];

  void add(ImportEntry entry) {
    try {
      final path = fs.normalize(entry.path);
      if (path.isEmpty) return;
      byPath.putIfAbsent(
        path,
        () => ImportEntry(
          path: path,
          sourcePath: entry.sourcePath,
          isDir: entry.isDir,
        ),
      );
    } on FsError catch (error) {
      failed.add('${entry.path}: ${error.message}');
    }
  }

  for (final entry in entries) {
    add(entry);
    if (!entry.isDir) continue;
    final root = Directory(entry.sourcePath);
    if (!await root.exists()) continue;
    try {
      await for (final entity
          in root.list(recursive: true, followLinks: false)) {
        final relative = _relativeTo(root.path, entity.path);
        if (relative.isEmpty || _skipDescendant(relative)) continue;
        final path = '${entry.path}/$relative';
        if (entity is Directory) {
          add(ImportEntry(path: path, sourcePath: entity.path, isDir: true));
        } else if (entity is File) {
          add(ImportEntry(path: path, sourcePath: entity.path, isDir: false));
        }
      }
    } catch (error) {
      failed.add('${entry.path}: could not read folder: $error');
    }
  }

  return _ExpandedEntries(byPath.values.toList(), failed);
}

String _relativeTo(String parent, String child) {
  var root = parent.replaceAll('\\', '/');
  while (root.endsWith('/') && root.length > 1) {
    root = root.substring(0, root.length - 1);
  }
  final path = child.replaceAll('\\', '/');
  if (path == root) return '';
  if (path.startsWith('$root/')) return path.substring(root.length + 1);
  return '';
}

bool _skipDescendant(String relative) {
  final parts = relative.split('/');
  final name = parts.last;
  if (name == '.DS_Store') return true;
  if (relative == '.project.json') return true;
  return parts.any((part) => part == '.git' || part == '.praxis');
}
