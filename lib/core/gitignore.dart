import 'vfs.dart';

/// The project's `.gitignore` rules, including nested ignore files.
///
/// Git itself is not available in every Praxis runtime, so this is a small,
/// dependency-free matcher for the common ignore syntax. The context prefetch
/// uses it to keep generated files out of the first model request.
class GitIgnoreSet {
  const GitIgnoreSet._(this._rules);

  static const empty = GitIgnoreSet._([]);

  final List<_GitIgnoreRule> _rules;

  static Future<GitIgnoreSet> load(ProjectFs fs) async {
    List<FileEntry> entries;
    try {
      entries = await fs.list(includeHidden: true);
    } on FsError {
      return empty;
    }
    final files = entries
        .where((entry) => !entry.isDir && entry.path.endsWith('.gitignore'))
        .toList()
      ..sort(
        (a, b) => a.path.split('/').length.compareTo(b.path.split('/').length),
      );
    final rules = <_GitIgnoreRule>[];
    for (final entry in files) {
      try {
        rules.addAll(_parse(
          await fs.read(entry.path),
          base: _directoryOf(entry.path),
        ));
      } on FsError {
        // A deleted or unreadable ignore file must not block prefetch.
      }
    }
    return rules.isEmpty ? empty : GitIgnoreSet._(rules);
  }

  /// Whether [path] is ignored. [isDir] is needed for rules ending in `/`.
  bool ignores(String path, {bool isDir = false}) {
    if (_rules.isEmpty) return false;
    final normalized = path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^\./'), '')
        .replaceAll(RegExp(r'/+'), '/')
        .replaceAll(RegExp(r'^/|/$'), '');
    if (normalized.isEmpty) return false;

    final parts = normalized.split('/');
    final candidates = <_IgnoreCandidate>[];
    for (var index = 1; index <= parts.length; index++) {
      candidates.add(_IgnoreCandidate(
        parts.take(index).join('/'),
        isDir: index < parts.length || isDir,
      ));
    }

    var ignored = false;
    for (final rule in _rules) {
      for (final candidate in candidates) {
        if (rule.matches(candidate.path, candidate.isDir)) {
          ignored = !rule.negated;
          break;
        }
      }
    }
    return ignored;
  }
}

class _IgnoreCandidate {
  const _IgnoreCandidate(this.path, {required this.isDir});

  final String path;
  final bool isDir;
}

class _GitIgnoreRule {
  const _GitIgnoreRule({
    required this.base,
    required this.regex,
    required this.anchored,
    required this.directoryOnly,
    required this.negated,
  });

  final String base;
  final RegExp regex;
  final bool anchored;
  final bool directoryOnly;
  final bool negated;

  bool matches(String path, bool isDir) {
    if (directoryOnly && !isDir) return false;
    var relative = path;
    if (base.isNotEmpty) {
      if (path == base || !path.startsWith('$base/')) return false;
      relative = path.substring(base.length + 1);
    }
    if (relative.isEmpty) return false;
    if (anchored) return regex.hasMatch(relative);
    return regex.hasMatch(relative.split('/').last);
  }
}

List<_GitIgnoreRule> _parse(String content, {required String base}) {
  final rules = <_GitIgnoreRule>[];
  for (var raw in content.split('\n')) {
    var line = raw.replaceAll('\r', '').trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    var negated = false;
    if (line.startsWith('!')) {
      negated = true;
      line = line.substring(1);
    } else if (line.startsWith(r'\!') || line.startsWith(r'\#')) {
      line = line.substring(1);
    }
    if (line.isEmpty) continue;

    var directoryOnly = false;
    if (line.endsWith('/')) {
      directoryOnly = true;
      line = line.substring(0, line.length - 1);
    }
    var anchored = line.startsWith('/');
    if (anchored) line = line.substring(1);
    if (line.isEmpty) continue;
    if (!anchored && line.contains('/')) anchored = true;

    final pattern = _globToRegExp(line);
    if (pattern == null) continue;
    rules.add(_GitIgnoreRule(
      base: base,
      regex: pattern,
      anchored: anchored,
      directoryOnly: directoryOnly,
      negated: negated,
    ));
  }
  return rules;
}

RegExp? _globToRegExp(String pattern) {
  final out = StringBuffer('^');
  for (var index = 0; index < pattern.length; index++) {
    final char = pattern[index];
    if (char == r'\') {
      if (index + 1 < pattern.length) {
        out.write(RegExp.escape(pattern[++index]));
      } else {
        out.write(r'\\');
      }
      continue;
    }
    if (char == '*') {
      if (index + 1 < pattern.length && pattern[index + 1] == '*') {
        if (index + 2 < pattern.length && pattern[index + 2] == '/') {
          out.write('(?:.*/)?');
          index += 2;
        } else {
          out.write('.*');
          index += 1;
        }
      } else {
        out.write('[^/]*');
      }
      continue;
    }
    if (char == '?') {
      out.write('[^/]');
      continue;
    }
    if (char == '[') {
      final close = pattern.indexOf(']', index + 1);
      if (close == -1) {
        out.write(r'\[');
        continue;
      }
      var content = pattern.substring(index + 1, close);
      if (content.startsWith('!')) content = '^${content.substring(1)}';
      out.write('[$content]');
      index = close;
      continue;
    }
    out.write(RegExp.escape(char));
  }
  out.write(r'$');
  try {
    return RegExp(out.toString());
  } on FormatException {
    return null;
  }
}

String _directoryOf(String path) {
  final parts = path.split('/');
  return parts.length <= 1 ? '' : parts.sublist(0, parts.length - 1).join('/');
}
