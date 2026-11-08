import 'vfs.dart';

class PatchException implements Exception {
  PatchException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PatchResult {
  const PatchResult(this.changedPaths, this.summary);
  final List<String> changedPaths;
  final String summary;
}

/// Applies the compact `*** Begin Patch` format used by coding agents as well
/// as ordinary unified diffs. Every write goes through [ProjectFs], so the
/// existing path sandbox still applies.
Future<PatchResult> applyPatch(ProjectFs fs, String raw) async {
  final patch = raw.replaceAll('\r\n', '\n');
  if (patch.trim().isEmpty) throw PatchException('The patch is empty.');
  final changed = <String>[];
  if (patch.contains('*** Begin Patch')) {
    final sections = _sections(patch);
    for (final section in sections) {
      await _applySection(fs, section);
      changed.add(section.path);
    }
  } else {
    final files = _unifiedFiles(patch);
    for (final file in files) {
      await _applyFile(fs, file.path, file.hunks, createIfMissing: false);
      changed.add(file.path);
    }
  }
  if (changed.isEmpty) throw PatchException('No file changes were found.');
  final unique = changed.toSet().toList();
  return PatchResult(
    unique,
    'Applied patch to ${unique.length} file${unique.length == 1 ? '' : 's'}: '
    '${unique.join(', ')}',
  );
}

class _Section {
  _Section(this.kind, this.path, this.body);
  final _SectionKind kind;
  final String path;
  final List<String> body;
}

enum _SectionKind { update, add, delete }

List<_Section> _sections(String patch) {
  final lines = patch.split('\n');
  final result = <_Section>[];
  var index = 0;
  while (index < lines.length) {
    final line = lines[index];
    if (line.startsWith('*** Update File: ')) {
      final path = line.substring('*** Update File: '.length).trim();
      index++;
      final body = <String>[];
      while (index < lines.length && !lines[index].startsWith('*** ')) {
        body.add(lines[index]);
        index++;
      }
      result.add(_Section(_SectionKind.update, path, body));
      continue;
    }
    if (line.startsWith('*** Add File: ')) {
      final path = line.substring('*** Add File: '.length).trim();
      index++;
      final body = <String>[];
      while (index < lines.length && !lines[index].startsWith('*** ')) {
        final value = lines[index];
        if (value.startsWith('+')) body.add(value.substring(1));
        index++;
      }
      result.add(_Section(_SectionKind.add, path, body));
      continue;
    }
    if (line.startsWith('*** Delete File: ')) {
      result.add(_Section(
        _SectionKind.delete,
        line.substring('*** Delete File: '.length).trim(),
        const [],
      ));
    }
    index++;
  }
  return result;
}

Future<void> _applySection(ProjectFs fs, _Section section) async {
  if (section.path.isEmpty) throw PatchException('A patch path is empty.');
  switch (section.kind) {
    case _SectionKind.add:
      if (await fs.exists(section.path)) {
        throw PatchException('${section.path} already exists.');
      }
      await fs.write(section.path, '${section.body.join('\n')}\n');
    case _SectionKind.delete:
      if (!await fs.exists(section.path)) {
        throw PatchException('${section.path} does not exist.');
      }
      await fs.delete(section.path);
    case _SectionKind.update:
      await _applyFile(fs, section.path, section.body, createIfMissing: false);
  }
}

class _UnifiedFile {
  _UnifiedFile(this.path, this.hunks);
  final String path;
  final List<String> hunks;
}

List<_UnifiedFile> _unifiedFiles(String patch) {
  final lines = patch.split('\n');
  final files = <_UnifiedFile>[];
  String? path;
  var body = <String>[];
  void finish() {
    if (path != null && body.isNotEmpty) {
      files.add(_UnifiedFile(path!, body));
    }
    path = null;
    body = <String>[];
  }

  for (final line in lines) {
    if (line.startsWith('+++ ')) {
      if (path != null) finish();
      var value = line.substring(4).trim().split('\t').first;
      if (value.startsWith('b/')) value = value.substring(2);
      path = value;
      body = <String>[];
      continue;
    }
    if (path != null) body.add(line);
  }
  finish();
  if (files.isEmpty) {
    throw PatchException(
      'Patch format not recognized. Use *** Begin Patch sections or a '
      'unified diff with --- and +++ headers.',
    );
  }
  return files;
}

Future<void> _applyFile(
  ProjectFs fs,
  String path,
  List<String> lines, {
  required bool createIfMissing,
}) async {
  if (path.isEmpty) throw PatchException('A patch path is empty.');
  if (!createIfMissing && !await fs.exists(path)) {
    throw PatchException('$path does not exist.');
  }
  final before = await fs.read(path);
  final original = before.split('\n');
  final output = <String>[];
  var cursor = 0;
  var index = 0;
  var foundHunk = false;

  while (index < lines.length) {
    final line = lines[index];
    if (!line.startsWith('@@')) {
      index++;
      continue;
    }
    foundHunk = true;
    final header = RegExp(r'^@@\s+-\d+(?:,\d+)?\s+\+(\d+)').firstMatch(line);
    final target = header == null ? null : int.tryParse(header.group(1)!);
    if (target != null && target > 0) {
      final start = target - 1;
      if (start > original.length) {
        throw PatchException('Hunk starts past the end of $path.');
      }
      while (cursor < start && cursor < original.length) {
        output.add(original[cursor++]);
      }
    }
    index++;
    final hunkLines = <String>[];
    while (index < lines.length && !lines[index].startsWith('@@')) {
      final current = lines[index];
      if (current.startsWith('*** ') ||
          current.startsWith('--- ') ||
          current.startsWith('+++ ')) {
        break;
      }
      hunkLines.add(current);
      index++;
    }
    _applyHunk(path, original, output, hunkLines, () => cursor, (value) {
      cursor = value;
    });
  }

  if (!foundHunk) {
    throw PatchException('No @@ hunks found for $path.');
  }
  while (cursor < original.length) {
    output.add(original[cursor++]);
  }
  // A trailing newline in the source should not become a forged extra line.
  var after = output.join('\n');
  if (before.endsWith('\n') && !after.endsWith('\n')) after += '\n';
  await fs.write(path, after);
}

void _applyHunk(
  String path,
  List<String> original,
  List<String> output,
  List<String> hunk,
  int Function() getCursor,
  void Function(int) setCursor,
) {
  final oldLines = <String>[];
  final newLines = <String>[];
  for (final line in hunk) {
    if (line.startsWith('+')) {
      newLines.add(line.substring(1));
    } else if (line.startsWith('-')) {
      oldLines.add(line.substring(1));
    } else {
      final text = line.startsWith(' ') ? line.substring(1) : line;
      oldLines.add(text);
      newLines.add(text);
    }
  }
  var cursor = getCursor();
  var match = -1;
  for (var candidate = cursor;
      candidate <= original.length - oldLines.length;
      candidate++) {
    var same = true;
    for (var offset = 0; offset < oldLines.length; offset++) {
      if (original[candidate + offset] != oldLines[offset]) {
        same = false;
        break;
      }
    }
    if (same) {
      match = candidate;
      break;
    }
  }
  if (match < 0) {
    throw PatchException(
      'Could not apply the hunk in $path. Re-read the file and produce a '
      'patch from its current contents.',
    );
  }
  while (cursor < match) {
    output.add(original[cursor++]);
  }
  output.addAll(newLines);
  setCursor(match + oldLines.length);
}
