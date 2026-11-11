import 'vfs.dart';

/// One line in a file whose text matched a query.
class CodeSearchMatch {
  const CodeSearchMatch({
    required this.line,
    required this.text,
  });

  final int line;
  final String text;
}

/// One file returned by a project search. A name match can exist without any
/// content matches; both are shown in the interface.
class FileSearchResult {
  FileSearchResult({
    required this.path,
    required this.nameMatch,
    required this.matches,
  });

  final String path;
  final bool nameMatch;
  final List<CodeSearchMatch> matches;

  int get count => matches.length;
}

class ProjectSearchResult {
  const ProjectSearchResult({
    required this.query,
    required this.files,
    required this.truncated,
  });

  final String query;
  final List<FileSearchResult> files;
  final bool truncated;

  int get fileMatches => files.where((file) => file.nameMatch).length;
  int get codeMatches =>
      files.fold<int>(0, (total, file) => total + file.matches.length);
  int get totalMatches => fileMatches + codeMatches;
}

class ProjectSearch {
  const ProjectSearch._();

  static Future<ProjectSearchResult> run(
    ProjectFs fs,
    String raw, {
    int maxFiles = 300,
    int maxMatches = 500,
  }) async {
    final query = raw.trim();
    if (query.length < 4) {
      return ProjectSearchResult(
        query: query,
        files: const [],
        truncated: false,
      );
    }
    final lower = query.toLowerCase();
    final entries = await fs.list(includeHidden: true);
    final files = <FileSearchResult>[];
    var matches = 0;
    var truncated = false;
    for (final entry in entries) {
      if (entry.isDir || files.length >= maxFiles || matches >= maxMatches) {
        if (files.length >= maxFiles || matches >= maxMatches) truncated = true;
        break;
      }
      if (entry.path.startsWith('.praxis/') || entry.path == '.praxis') {
        continue;
      }
      final nameMatch = entry.name.toLowerCase().contains(lower);
      final fileMatches = <CodeSearchMatch>[];
      if (entry.size <= 400000 && await fs.isTextFile(entry.path)) {
        String text;
        try {
          text = await fs.read(entry.path);
        } on FsError {
          text = '';
        }
        if (text.isNotEmpty) {
          final lines = text.split('\n');
          for (var index = 0; index < lines.length; index++) {
            if (!lines[index].toLowerCase().contains(lower)) continue;
            fileMatches.add(CodeSearchMatch(
              line: index + 1,
              text: lines[index].trim().length > 240
                  ? '${lines[index].trim().substring(0, 240)}…'
                  : lines[index].trim(),
            ));
            matches++;
            if (matches >= maxMatches) {
              truncated = true;
              break;
            }
          }
        }
      }
      if (nameMatch || fileMatches.isNotEmpty) {
        files.add(FileSearchResult(
          path: entry.path,
          nameMatch: nameMatch,
          matches: fileMatches,
        ));
      }
    }
    files.sort((a, b) {
      if (a.nameMatch != b.nameMatch) return a.nameMatch ? -1 : 1;
      if (a.count != b.count) return b.count.compareTo(a.count);
      return a.path.compareTo(b.path);
    });
    return ProjectSearchResult(
      query: query,
      files: files,
      truncated: truncated,
    );
  }
}

String searchLinePreview(String text) => text.replaceAll(RegExp(r'\s+'), ' ');
