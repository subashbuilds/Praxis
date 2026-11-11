import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'file_types.dart';

class FsError implements Exception {
  FsError(this.message);
  final String message;

  @override
  String toString() => message;
}

class FileEntry {
  const FileEntry({
    required this.path,
    required this.name,
    required this.isDir,
    required this.size,
  });

  final String path;
  final String name;
  final bool isDir;
  final int size;
}

/// A deployable file with its raw bytes. Static hosts need both text and
/// binary assets, so deployments must never be built from text alone.
class DeploymentFile {
  const DeploymentFile({
    required this.path,
    required this.bytes,
    required this.mime,
  });

  final String path;
  final Uint8List bytes;
  final String mime;

  bool get isText => classifyFile(path, bytes: bytes).kind == FileKind.text;
  String get text => utf8.decode(bytes, allowMalformed: true);
}

/// Text content plus a Git object id for every file. Built in one pass so
/// cloning and pulling never decode binary files as UTF-8.
class LocalSnapshot {
  const LocalSnapshot({
    required this.texts,
    required this.hashes,
    required this.sizes,
  });

  final Map<String, String> texts;
  final Map<String, String> hashes;
  final Map<String, int> sizes;
}

/// A sandboxed view of one project directory. Every path is normalised and
/// `..` is rejected, so neither the agent nor the shell can leave the project.
class ProjectFs {
  ProjectFs(this.root);

  final Directory root;

  String get rootPath => root.path;

  String normalize(String path) {
    final cleaned = path.trim().replaceAll('\\', '/');
    final parts = <String>[];
    for (final segment in cleaned.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (parts.isEmpty) throw FsError('Path escapes the project');
        parts.removeLast();
        continue;
      }
      parts.add(segment);
    }
    return parts.join('/');
  }

  String absolute(String path) {
    final rel = normalize(path);
    return rel.isEmpty ? root.path : '${root.path}/$rel';
  }

  Future<void> ensureRoot() async {
    await root.create(recursive: true);
    // `.praxis` is app state, not project content, but the shell and skill
    // tooling expect the folder to exist in every project, including blank
    // projects that were not cloned from a repository.
    await Directory('${root.path}/.praxis').create(recursive: true);
  }

  Future<bool> exists(String path) async {
    final rel = normalize(path);
    if (rel.isEmpty) return true;
    return FileSystemEntity.typeSync(absolute(rel)) !=
        FileSystemEntityType.notFound;
  }

  Future<bool> isDirectory(String path) async {
    final rel = normalize(path);
    if (rel.isEmpty) return true;
    return FileSystemEntity.typeSync(absolute(rel)) ==
        FileSystemEntityType.directory;
  }

  Future<Uint8List> readBytes(String path) async {
    final rel = normalize(path);
    if (rel.isEmpty) throw FsError('Is a directory: /');
    final file = File(absolute(rel));
    if (!await file.exists()) throw FsError('No such file: $rel');
    return file.readAsBytes();
  }

  Future<String> read(String path) async {
    final rel = normalize(path);
    final bytes = await readBytes(rel);
    final text = decodeUtf8(bytes, allowEmpty: true);
    if (text == null) {
      throw FsError(
        '$rel is a binary file (${humanFileSize(bytes.length)}). '
        'Open it in Files to preview it instead of the text editor.',
      );
    }
    return text;
  }

  /// Reads only what is needed to distinguish a text source from a binary
  /// asset. Known text extensions do not pay for a disk read.
  Future<bool> isTextFile(String path) async {
    final rel = normalize(path);
    final known = classifyFile(rel);
    if (known.known) return known.isText;
    final file = File(absolute(rel));
    if (!await file.exists()) throw FsError('No such file: $rel');
    final length = await file.length();
    if (length == 0) return true;
    final handle = await file.open();
    try {
      final sample = await handle.read(math.min(8192, length));
      return classifyFile(rel, bytes: sample).isText;
    } finally {
      await handle.close();
    }
  }

  /// Copies a file that lives outside the project (a picker result) into it.
  Future<void> copyFromOutside(File source, String path) async {
    final rel = normalize(path);
    if (rel.isEmpty) throw FsError('Not a file: /');
    final target = File(absolute(rel));
    await target.parent.create(recursive: true);
    await source.copy(target.path);
  }

  Future<int> write(String path, String content) async {
    final bytes = utf8.encode(content);
    await writeBytes(path, bytes);
    return bytes.length;
  }

  Future<int> writeBytes(String path, List<int> bytes) async {
    final rel = normalize(path);
    if (rel.isEmpty) throw FsError('Not a file: /');
    final file = File(absolute(rel));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return bytes.length;
  }

  /// Everything the user can see, including binary assets, as a ZIP. Hidden
  /// app state (`.praxis`) is intentionally excluded.
  Future<Uint8List> zipBytes() async {
    final entries = await list(includeHidden: true);
    final archive = Archive();
    for (final entry in entries) {
      if (entry.isDir) continue;
      final bytes = await readBytes(entry.path);
      archive.addFile(ArchiveFile(entry.path, bytes.length, bytes));
    }
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) throw FsError('Could not build the archive');
    return Uint8List.fromList(encoded);
  }

  Future<void> createDir(String path) async {
    final rel = normalize(path);
    if (rel.isEmpty) return;
    await Directory(absolute(rel)).create(recursive: true);
  }

  Future<void> delete(String path, {bool recursive = true}) async {
    final rel = normalize(path);
    if (rel.isEmpty) throw FsError('Refusing to delete the project root');
    final entity = FileSystemEntity.typeSync(absolute(rel));
    if (entity == FileSystemEntityType.notFound) {
      throw FsError('No such file or directory: $rel');
    }
    if (entity == FileSystemEntityType.directory) {
      final dir = Directory(absolute(rel));
      if (recursive) {
        await dir.delete(recursive: true);
      } else {
        await dir.delete();
      }
    } else {
      await File(absolute(rel)).delete();
    }
  }

  Future<void> rename(String from, String to) async {
    final source = normalize(from);
    final target = normalize(to);
    if (source.isEmpty || target.isEmpty) throw FsError('Invalid path');
    final type = FileSystemEntity.typeSync(absolute(source));
    if (type == FileSystemEntityType.notFound) {
      throw FsError('No such file: $source');
    }
    await Directory(absolute(target)).parent.create(recursive: true);
    if (type == FileSystemEntityType.directory) {
      await Directory(absolute(source)).rename(absolute(target));
    } else {
      await File(absolute(source)).rename(absolute(target));
    }
  }

  Future<void> copy(String from, String to) async {
    final source = normalize(from);
    final target = normalize(to);
    final type = FileSystemEntity.typeSync(absolute(source));
    if (type != FileSystemEntityType.file) {
      throw FsError('Only files can be copied: $source');
    }
    final bytes = await File(absolute(source)).readAsBytes();
    await writeBytes(target, bytes);
  }

  Future<List<FileEntry>> list({
    String path = '',
    bool recursive = true,
    bool includeHidden = false,
  }) async {
    final rel = normalize(path);
    final dir = Directory(absolute(rel));
    if (!await dir.exists()) {
      throw FsError('No such directory: ${rel.isEmpty ? '/' : rel}');
    }
    final entries = <FileEntry>[];
    await for (final entity
        in dir.list(recursive: recursive, followLinks: false)) {
      final relative =
          entity.path.substring(root.path.length + 1).replaceAll('\\', '/');
      // App state is never part of the project's content. Everything else,
      // including .github and .gitignore, is preserved when hidden files are
      // requested for snapshots and export.
      if (relative == '.project.json' ||
          relative == '.praxis' ||
          relative.startsWith('.praxis/') ||
          relative == '.git' ||
          relative.startsWith('.git/')) {
        continue;
      }
      final name = relative.split('/').last;
      if (!includeHidden &&
          (entity.path.contains('/.') || name.startsWith('.'))) {
        continue;
      }
      // Dependency and tool caches are not project content and are huge. They
      // still appear as a folder, and opening one lists it normally, but
      // recursive walks (search, diffs, deploy, export) skip their contents.
      final generated = relative.startsWith('node_modules/') ||
          relative.startsWith('.dart_tool/') ||
          relative.startsWith('.gradle/') ||
          relative.startsWith('.next/cache/');
      if (generated) {
        final rootSegment = relative.split('/').first;
        final explicitlyOpened =
            rel == rootSegment || rel.startsWith('$rootSegment/');
        if (!explicitlyOpened) continue;
      }
      final type = await FileSystemEntity.type(entity.path);
      entries.add(FileEntry(
        path: relative,
        name: name,
        isDir: type == FileSystemEntityType.directory,
        size: type == FileSystemEntityType.file
            ? await File(entity.path).length()
            : 0,
      ));
    }
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.path.compareTo(b.path);
    });
    return entries;
  }

  /// Text files small enough to push to an integration. A file that claims a
  /// text extension but contains invalid UTF-8 is skipped instead of aborting
  /// the entire operation.
  Future<Map<String, String>> textFiles({int maxBytes = 200000}) async {
    final entries = await list(includeHidden: true);
    final result = <String, String>{};
    for (final entry in entries) {
      if (entry.isDir || entry.size > maxBytes) continue;
      if (!await isTextFile(entry.path)) continue;
      try {
        result[entry.path] = await read(entry.path);
      } on FsError {
        // A malformed text file is not a reason to fail a deploy or baseline.
      }
    }
    return result;
  }

  /// Every project file as raw bytes, including images and other binaries.
  /// Text files beyond the editor's inline limit are included as bytes too so
  /// a static deployment matches the folder the user sees.
  Future<List<DeploymentFile>> deploymentFiles({String from = ''}) async {
    final base = normalize(from);
    final entries = await list(path: base, includeHidden: true);
    final result = <DeploymentFile>[];
    for (final entry in entries) {
      if (entry.isDir) continue;
      final relative =
          base.isEmpty ? entry.path : entry.path.substring(base.length + 1);
      final lower = relative.toLowerCase();
      // `.next` is generated output, not source. Uploading it bloats a Pages
      // deployment and was the main source of failed asset uploads.
      if (lower == '.next' ||
          lower.startsWith('.next/') ||
          lower == 'node_modules' ||
          lower.startsWith('node_modules/') ||
          lower.startsWith('.dart_tool/') ||
          lower.startsWith('.gradle/')) {
        continue;
      }
      try {
        final bytes = await readBytes(entry.path);
        result.add(DeploymentFile(
          path: relative,
          bytes: bytes,
          mime: classifyFile(entry.path, bytes: bytes).mime ??
              'application/octet-stream',
        ));
      } on FsError {
        // A file removed while the tree was being walked is not fatal.
      }
    }
    return result;
  }

  Future<LocalSnapshot> localSnapshot({int maxTextBytes = 200000}) async {
    final entries = await list(includeHidden: true);
    final texts = <String, String>{};
    final hashes = <String, String>{};
    final sizes = <String, int>{};
    for (final entry in entries) {
      if (entry.isDir) continue;
      final bytes = await readBytes(entry.path);
      hashes[entry.path] = gitBlobSha(bytes);
      sizes[entry.path] = bytes.length;
      if (bytes.length <= maxTextBytes && await isTextFile(entry.path)) {
        final text = decodeUtf8(bytes, allowEmpty: true);
        if (text != null) texts[entry.path] = text;
      }
    }
    return LocalSnapshot(texts: texts, hashes: hashes, sizes: sizes);
  }
}
