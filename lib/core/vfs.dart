import 'dart:io';

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

  Future<void> ensureRoot() => root.create(recursive: true);

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

  Future<String> read(String path) async {
    final rel = normalize(path);
    if (rel.isEmpty) throw FsError('Is a directory: /');
    final file = File(absolute(rel));
    if (!await file.exists()) throw FsError('No such file: $rel');
    return file.readAsString();
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
    final rel = normalize(path);
    if (rel.isEmpty) throw FsError('Not a file: /');
    final file = File(absolute(rel));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return content.length;
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
    final content = await File(absolute(source)).readAsString();
    await write(target, content);
  }

  Future<List<FileEntry>> list({
    String path = '',
    bool recursive = true,
  }) async {
    final rel = normalize(path);
    final dir = Directory(absolute(rel));
    if (!await dir.exists()) {
      throw FsError('No such directory: ${rel.isEmpty ? '/' : rel}');
    }
    final entries = <FileEntry>[];
    await for (final entity
        in dir.list(recursive: recursive, followLinks: false)) {
      if (entity.path.contains('/.')) continue;
      final relative =
          entity.path.substring(root.path.length + 1).replaceAll('\\', '/');
      final name = relative.split('/').last;
      if (name.startsWith('.')) continue;
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

  /// Text files small enough to push to an integration.
  Future<Map<String, String>> textFiles({int maxBytes = 200000}) async {
    final entries = await list();
    final result = <String, String>{};
    for (final entry in entries) {
      if (entry.isDir || entry.size > maxBytes) continue;
      if (_binaryExtensions.contains(_extension(entry.path))) continue;
      result[entry.path] = await read(entry.path);
    }
    return result;
  }

  static String _extension(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static const _binaryExtensions = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'ico',
    'ttf',
    'otf',
    'woff',
    'woff2',
    'zip',
    'gz',
    'xz',
    'apk',
    'so',
    'jar',
    'mp3',
    'mp4',
    'pdf',
  };
}
