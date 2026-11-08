import 'dart:math' as math;

import 'gitignore.dart';
import 'sensitive_paths.dart';
import 'system_shell.dart';
import 'vfs.dart';

class PrefetchResult {
  const PrefetchResult({
    required this.text,
    required this.trivial,
    required this.filesScanned,
    required this.keywords,
    required this.truncated,
  });

  final String text;
  final bool trivial;
  final int filesScanned;
  final List<String> keywords;
  final bool truncated;

  bool get included => !trivial && text.trim().isNotEmpty;
}

/// Builds the first-message context for a task: a capped tree, git state, the
/// open file and local search hits for identifiers in the request.
class ContextPrefetch {
  const ContextPrefetch({
    required this.fs,
    this.shell,
    this.activeFile,
    this.maxCharacters = 24000,
  });

  final ProjectFs fs;
  final SystemShell? shell;
  final String? activeFile;
  final int maxCharacters;

  static const _maxTreeEntries = 120;
  static const _maxTreeCharacters = 8000;
  static const _maxSearchFiles = 120;
  static const _maxSearchHits = 24;
  static const _maxOpenFileCharacters = 7000;

  Future<PrefetchResult> build(String prompt) async {
    final trimmed = prompt.trim();
    if (_isTrivial(trimmed)) {
      return const PrefetchResult(
        text: '',
        trivial: true,
        filesScanned: 0,
        keywords: [],
        truncated: false,
      );
    }

    final keywords = _keywords(trimmed);
    final gitignore = await GitIgnoreSet.load(fs);
    final entries = await _entries(gitignore);
    final sections = <String>[];
    var filesScanned = 0;
    var truncated = false;
    var used = 0;

    String addSection(String title, String body, {int reserve = 200}) {
      final available = maxCharacters - used - reserve;
      if (available <= 0 || body.trim().isEmpty) {
        truncated = true;
        return '';
      }
      final clipped = body.length <= available
          ? body
          : '${body.substring(0, math.max(0, available - 80)).trimRight()}\n'
              '[Section capped at ${maxCharacters ~/ 1000}K characters; '
              'use list_files/read_files for the rest.]';
      if (clipped.length < body.length) truncated = true;
      final section = '$title\n$clipped';
      used += section.length;
      sections.add(section);
      return section;
    }

    final tree = StringBuffer();
    for (final entry in entries.take(_maxTreeEntries)) {
      tree.writeln(entry.isDir
          ? '${entry.path}/'
          : '${entry.path} (${_size(entry.size)})');
    }
    final omitted = entries.length - math.min(entries.length, _maxTreeEntries);
    addSection(
      'PROJECT TREE (${entries.length} visible entries${omitted > 0 ? ', $omitted omitted' : ''})',
      tree.length > _maxTreeCharacters
          ? tree.toString().substring(0, _maxTreeCharacters)
          : tree.toString(),
    );

    final git = await _gitState();
    if (git.isNotEmpty) addSection('GIT STATE', git);

    final open = activeFile?.trim() ?? '';
    if (open.isNotEmpty && !isIgnoredPath(open) && !gitignore.ignores(open)) {
      try {
        final content = await fs.read(open);
        final lines = content.split('\n');
        final shown = lines.take(90).join('\n');
        final suffix = lines.length > 90
            ? '\n[Open file capped at 90 of ${lines.length} lines; read $open '
                'with offset=91 for the rest.]'
            : '';
        final clipped = shown.length > _maxOpenFileCharacters
            ? '${shown.substring(0, _maxOpenFileCharacters)}\n'
                '[Open file character cap reached; use read_file with an '
                'offset to continue.]'
            : shown;
        if (clipped.length < shown.length) truncated = true;
        addSection(
          'CURRENTLY OPEN FILE: $open ${lines.length} lines',
          '$clipped$suffix',
        );
      } on FsError {
        // The file may have been deleted between opening it and this request.
      }
    }

    if (keywords.isNotEmpty) {
      final hits = StringBuffer();
      var hitCount = 0;
      var scanned = 0;
      final lowerWords = keywords.map((word) => word.toLowerCase()).toList();
      for (final entry in entries) {
        if (entry.isDir || entry.size > 120000) continue;
        if (isIgnoredPath(entry.path) || looksLikeSecret(entry.path)) continue;
        if (scanned >= _maxSearchFiles) {
          truncated = true;
          break;
        }
        scanned++;
        String text;
        try {
          if (!await fs.isTextFile(entry.path)) continue;
          text = await fs.read(entry.path);
        } on FsError {
          continue;
        }
        final lines = text.split('\n');
        for (var line = 0; line < lines.length; line++) {
          final lower = lines[line].toLowerCase();
          if (!lowerWords.any(lower.contains)) continue;
          hitCount++;
          if (hitCount > _maxSearchHits) {
            truncated = true;
            break;
          }
          final start = math.max(0, line - 1);
          final end = math.min(lines.length - 1, line + 1);
          hits.writeln('${entry.path}:${line + 1}');
          for (var context = start; context <= end; context++) {
            final snippet = lines[context].length > 220
                ? '${lines[context].substring(0, 220)}…'
                : lines[context];
            hits.writeln('  ${context + 1} | $snippet');
          }
        }
        if (hitCount > _maxSearchHits) break;
      }
      filesScanned = scanned;
      if (hitCount > 0) {
        addSection(
          'LOCAL SEARCH: ${keywords.join(', ')} '
          '($hitCount${truncated ? '+' : ''} hits in $scanned files)',
          hits.toString(),
        );
      }
    }

    if (sections.isEmpty) {
      return PrefetchResult(
        text: '',
        trivial: false,
        filesScanned: filesScanned,
        keywords: keywords,
        truncated: truncated,
      );
    }
    return PrefetchResult(
      text: sections.join('\n\n'),
      trivial: false,
      filesScanned: filesScanned,
      keywords: keywords,
      truncated: truncated,
    );
  }

  Future<List<FileEntry>> _entries(GitIgnoreSet gitignore) async {
    try {
      final listed = await fs.list(includeHidden: true);
      return listed
          .where((entry) =>
              !isIgnoredPath(entry.path) &&
              !looksLikeSecret(entry.path) &&
              !gitignore.ignores(entry.path, isDir: entry.isDir))
          .toList();
    } on FsError {
      return const [];
    }
  }

  Future<String> _gitState() async {
    final processShell = shell;
    if (processShell == null) return '';
    try {
      final result = await processShell.run(
        'git status --porcelain=v1 -b',
        timeout: const Duration(seconds: 5),
      );
      if (result.exitCode != 0) return '';
      final lines = result.output
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .where((line) => !line
              .split(RegExp(r'\s+'))
              .any((part) => isIgnoredPath(part) || looksLikeSecret(part)))
          .take(80)
          .join('\n');
      return lines.isEmpty ? '' : lines;
    } catch (_) {
      return '';
    }
  }

  static bool _isTrivial(String prompt) {
    if (prompt.isEmpty) return true;
    final lower = prompt.toLowerCase();
    if (RegExp(
      r'^(hi|hello|hey|thanks|thank you|good (morning|evening|afternoon)|ok|okay|cool|nice)[!. ]*$',
    ).hasMatch(lower)) {
      return true;
    }
    if (prompt.length > 160) return false;
    return RegExp(
          r'^(what|who|when|where|why|how|explain|tell me about|define|is|are|can you explain)\b',
        ).hasMatch(lower) &&
        !RegExp(r'(file|project|code|repo|fix|add|change|implement|error|bug|class|function|path|this|that)')
            .hasMatch(lower);
  }

  static List<String> _keywords(String prompt) {
    const stop = {
      'the',
      'and',
      'for',
      'with',
      'this',
      'that',
      'from',
      'into',
      'your',
      'please',
      'make',
      'change',
      'update',
      'add',
      'fix',
      'need',
      'want',
      'should',
      'could',
      'would',
      'when',
      'where',
      'what',
      'why',
      'how',
      'there',
      'here',
      'then',
      'than',
      'also',
      'about',
      'using',
      'use',
      'file',
      'files',
      'project',
      'code',
      'it',
      'is',
      'to',
      'of',
      'in',
      'on',
      'a',
      'an',
      'or',
      'if',
      'we',
      'you',
      'me',
      'my',
      'our',
      'be',
      'do',
      'does',
      'not',
      'all',
    };
    final words = RegExp(r'[A-Za-z_][A-Za-z0-9_]{2,}')
        .allMatches(prompt)
        .map((match) => match.group(0)!)
        .where((word) => !stop.contains(word.toLowerCase()))
        .where((word) =>
            !RegExp(r'^(false|true|null|return|const|final)$').hasMatch(word))
        .toList();
    final unique = <String>[];
    for (final word in words) {
      if (unique
          .any((existing) => existing.toLowerCase() == word.toLowerCase())) {
        continue;
      }
      unique.add(word);
      if (unique.length == 5) break;
    }
    return unique;
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
