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
    required this.incomingIsDir,
    required this.existingIsDir,
  });

  final String path;
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

/// Copies picked files and folders into a project. Folder-to-folder collisions
/// merge recursively; only the individual files that actually collide prompt
/// the user. Existing folders are never deleted as a shortcut.
Future<ImportSummary> importEntries(
  ProjectFs fs,
  List<ImportEntry> entries, {
  required ImportConflictResolver onConflict,
}) async {
  if (entries.isEmpty) return const ImportSummary();

  final ordered = [...entries]..sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      final depth =
          a.path.split('/').length.compareTo(b.path.split('/').length);
      if (depth != 0) return depth;
      return a.path.compareTo(b.path);
    });

  var created = 0;
  var replaced = 0;
  var skipped = 0;
  final failed = <String>[];
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
    }
  }

  return ImportSummary(
    created: created,
    replaced: replaced,
    skipped: skipped,
    failed: failed,
  );
}
