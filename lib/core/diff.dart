import 'dart:convert';

enum DiffKind { added, removed, context }

class DiffRow {
  const DiffRow({
    required this.kind,
    required this.text,
    this.oldLine,
    this.newLine,
  });

  final DiffKind kind;
  final String text;
  final int? oldLine;
  final int? newLine;

  Map<String, dynamic> toJson() => {
        'k': kind.name,
        't': text,
        'o': oldLine,
        'n': newLine,
      };

  static DiffRow fromJson(Map<String, dynamic> json) => DiffRow(
        kind: DiffKind.values.firstWhere(
          (value) => value.name == json['k'],
          orElse: () => DiffKind.context,
        ),
        text: json['t'] as String? ?? '',
        oldLine: json['o'] as int?,
        newLine: json['n'] as int?,
      );
}

/// A whole-file diff with both old and new line numbers, small enough to keep
/// in a chat transcript. Files above [maxLines] fall back to a replace-all
/// diff so a huge model write cannot stall the UI.
class FileDiff {
  const FileDiff({
    required this.rows,
    required this.added,
    required this.removed,
  });

  final List<DiffRow> rows;
  final int added;
  final int removed;

  bool get isEmpty => added == 0 && removed == 0;

  String toJson() => jsonEncode({
        'added': added,
        'removed': removed,
        'rows': rows.map((row) => row.toJson()).toList(),
      });

  static FileDiff? decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final rows = <DiffRow>[];
      for (final item in (data['rows'] as List? ?? const [])) {
        if (item is Map) {
          rows.add(DiffRow.fromJson(item.cast<String, dynamic>()));
        }
      }
      return FileDiff(
        rows: rows,
        added: data['added'] as int? ?? 0,
        removed: data['removed'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

const _maxLines = 700;
const _maxStoredRows = 480;

FileDiff computeDiff(String before, String after) {
  if (before == after) {
    return const FileDiff(rows: [], added: 0, removed: 0);
  }
  final oldLines = before.isEmpty ? <String>[] : before.split('\n');
  final newLines = after.isEmpty ? <String>[] : after.split('\n');

  if (oldLines.length > _maxLines || newLines.length > _maxLines) {
    return _replaceAll(oldLines, newLines);
  }

  final rows = <DiffRow>[];
  var added = 0;
  var removed = 0;

  if (oldLines.isEmpty) {
    for (var j = 0; j < newLines.length; j++) {
      rows.add(
          DiffRow(kind: DiffKind.added, text: newLines[j], newLine: j + 1));
      added++;
    }
    return FileDiff(rows: rows, added: added, removed: removed);
  }

  // Classic LCS table. The line cap above keeps this allocation small.
  final n = oldLines.length;
  final m = newLines.length;
  final table = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      table[i][j] = oldLines[i] == newLines[j]
          ? table[i + 1][j + 1] + 1
          : (table[i + 1][j] >= table[i][j + 1]
              ? table[i + 1][j]
              : table[i][j + 1]);
    }
  }

  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (oldLines[i] == newLines[j]) {
      rows.add(DiffRow(
        kind: DiffKind.context,
        text: oldLines[i],
        oldLine: i + 1,
        newLine: j + 1,
      ));
      i++;
      j++;
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      rows.add(DiffRow(
        kind: DiffKind.removed,
        text: oldLines[i],
        oldLine: i + 1,
      ));
      removed++;
      i++;
    } else {
      rows.add(DiffRow(
        kind: DiffKind.added,
        text: newLines[j],
        newLine: j + 1,
      ));
      added++;
      j++;
    }
  }
  while (i < n) {
    rows.add(DiffRow(
      kind: DiffKind.removed,
      text: oldLines[i],
      oldLine: i + 1,
    ));
    removed++;
    i++;
  }
  while (j < m) {
    rows.add(DiffRow(
      kind: DiffKind.added,
      text: newLines[j],
      newLine: j + 1,
    ));
    added++;
    j++;
  }

  // Context lines are useful, but a chat transcript is not a patch file.
  final stored = rows.length <= _maxStoredRows
      ? rows
      : rows.where((row) => row.kind != DiffKind.context).toList();
  return FileDiff(rows: stored, added: added, removed: removed);
}

FileDiff _replaceAll(List<String> oldLines, List<String> newLines) {
  final rows = <DiffRow>[
    for (var i = 0; i < oldLines.length; i++)
      DiffRow(kind: DiffKind.removed, text: oldLines[i], oldLine: i + 1),
    for (var j = 0; j < newLines.length; j++)
      DiffRow(kind: DiffKind.added, text: newLines[j], newLine: j + 1),
  ];
  return FileDiff(
    rows: rows.length <= _maxStoredRows
        ? rows
        : [
            ...rows.take(_maxStoredRows ~/ 2),
            ...rows.skip(rows.length - _maxStoredRows ~/ 2),
          ],
    added: newLines.length,
    removed: oldLines.length,
  );
}
