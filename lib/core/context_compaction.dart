import 'dart:math' as math;

import 'ai.dart';

enum ContextCompactionLevel { none, cheap, summarize }

class ContextCompactionResult {
  const ContextCompactionResult({
    required this.turns,
    required this.changed,
    required this.characterSavings,
  });

  final List<AiTurn> turns;
  final bool changed;
  final int characterSavings;
}

class ContextSplit {
  const ContextSplit({
    required this.headEnd,
    required this.tailStart,
  });

  /// Everything before this index is the preserved opening request.
  final int headEnd;

  /// Everything from this index onward is preserved verbatim.
  final int tailStart;

  bool get canCompact => tailStart > headEnd;
}

/// Keeps context management independent from the provider transport so the
/// threshold behavior is deterministic and testable.
class ContextCompactor {
  const ContextCompactor._();

  static const double cheapAt = 0.60;
  static const double summarizeAt = 0.75;
  static const int keepTailTurns = 6;

  static ContextCompactionLevel levelFor({
    required int usedTokens,
    required int limitTokens,
  }) {
    if (limitTokens <= 0 || usedTokens <= 0) {
      return ContextCompactionLevel.none;
    }
    final ratio = usedTokens / limitTokens;
    if (ratio >= summarizeAt) return ContextCompactionLevel.summarize;
    if (ratio >= cheapAt) return ContextCompactionLevel.cheap;
    return ContextCompactionLevel.none;
  }

  /// Deliberately conservative. Most providers tokenize prose at roughly four
  /// characters per token; JSON and code can be denser, so this intentionally
  /// rounds upward.
  static int estimateTokens({
    required String system,
    required Iterable<AiTurn> turns,
  }) {
    var characters = system.length;
    var overhead = 8;
    for (final turn in turns) {
      characters += turn.text.length;
      characters += turn.toolName.length + turn.toolCallId.length;
      for (final call in turn.calls) {
        characters += call.name.length + 48;
        for (final value in call.arguments.values) {
          characters += value.toString().length;
        }
      }
      overhead += 4;
    }
    return (characters / 4).ceil() + overhead;
  }

  /// Preserves the first user request and the newest turns, moving the tail
  /// boundary back when it would otherwise begin halfway through a tool pair.
  static ContextSplit split(
    List<AiTurn> turns, {
    int keepTail = keepTailTurns,
  }) {
    if (turns.isEmpty) {
      return const ContextSplit(headEnd: 0, tailStart: 0);
    }
    final firstUser = turns.indexWhere((turn) => turn.role == 'user');
    final headEnd = firstUser < 0 ? 0 : firstUser + 1;
    var tailStart = math.max(headEnd, turns.length - keepTail);
    while (tailStart > headEnd && turns[tailStart].role == 'tool') {
      tailStart--;
    }
    return ContextSplit(headEnd: headEnd, tailStart: tailStart);
  }

  /// Replaces old, large tool output with one-line stubs. Tool calls and their
  /// matching results stay paired; only the result body shrinks.
  static ContextCompactionResult compactToolResults(
    List<AiTurn> turns, {
    int keepTail = keepTailTurns,
  }) {
    final split = ContextCompactor.split(turns, keepTail: keepTail);
    if (!split.canCompact) {
      return ContextCompactionResult(
        turns: turns,
        changed: false,
        characterSavings: 0,
      );
    }

    final seen = <String>{};
    var savings = 0;
    var changed = false;
    final compacted = <AiTurn>[];
    for (var index = 0; index < turns.length; index++) {
      final turn = turns[index];
      if (index < split.headEnd || index >= split.tailStart) {
        compacted.add(turn);
        continue;
      }
      if (turn.role != 'tool') {
        compacted.add(turn);
        continue;
      }

      final header = _headerFor(turn.text);
      final key = '${_kind(turn.toolName)}:${header.path}';
      final duplicate = !seen.add(key);
      final shouldStub =
          duplicate || turn.toolName == 'list_files' || turn.text.length > 600;
      if (!shouldStub) {
        compacted.add(turn);
        continue;
      }

      final stub = _stubFor(turn, header: header, duplicate: duplicate);
      if (stub.length >= turn.text.length) {
        compacted.add(turn);
        continue;
      }
      savings += turn.text.length - stub.length;
      changed = true;
      compacted.add(AiTurn.tool(turn.toolCallId, turn.toolName, stub));
    }

    if (!changed) {
      return ContextCompactionResult(
        turns: turns,
        changed: false,
        characterSavings: 0,
      );
    }
    return ContextCompactionResult(
      turns: compacted,
      changed: true,
      characterSavings: savings,
    );
  }

  /// A bounded transcript for the summarization request. It intentionally
  /// caps each message so the compaction call cannot recreate the problem.
  static String summaryInput(List<AiTurn> turns) {
    final output = StringBuffer();
    var characters = 0;
    const cap = 14000;
    for (var index = 0; index < turns.length; index++) {
      final turn = turns[index];
      final calls = turn.calls.isEmpty
          ? ''
          : ' calls=${turn.calls.map((call) => call.name).join(',')}';
      final text = turn.text.length > 1800
          ? '${turn.text.substring(0, 1800).trimRight()}\n[...truncated]'
          : turn.text;
      final block = '${turn.role}$calls\n$text\n';
      if (characters + block.length > cap) {
        output.writeln('[Earlier turns omitted from the summary request.]');
        break;
      }
      output.write(block);
      characters += block.length;
    }
    return output.toString().trim();
  }

  static String _kind(String toolName) {
    if (toolName == 'read_file' || toolName == 'read_files') return 'read';
    if (toolName == 'list_files') return 'list';
    if (toolName == 'search_and_read') return 'search';
    return toolName;
  }

  static _ToolHeader _headerFor(String text) {
    final firstLine = text.split('\n').first.trim();
    final bracket = RegExp(r'^\[([^\]]+)').firstMatch(firstLine);
    var path = bracket?.group(1)?.trim() ?? '';
    if (path.contains(' · ')) path = path.split(' · ').first.trim();
    if (path.isEmpty) path = firstLine;
    if (path.length > 80) path = '${path.substring(0, 77)}...';

    final lines =
        RegExp(r'lines\s+\d+[–-]\d+\s+of\s+(\d+)').firstMatch(text)?.group(1);
    return _ToolHeader(path: path, totalLines: int.tryParse(lines ?? ''));
  }

  static String _stubFor(
    AiTurn turn, {
    required _ToolHeader header,
    required bool duplicate,
  }) {
    if (duplicate) {
      return '${turn.toolName} ${header.path} - older duplicate omitted';
    }
    if (turn.toolName == 'list_files') {
      return 'list_files ${header.path} - old directory listing omitted';
    }
    if (turn.toolName == 'read_file' || turn.toolName == 'read_files') {
      final suffix =
          header.totalLines == null ? '' : ' - ${header.totalLines} lines';
      return '${turn.toolName} ${header.path}$suffix - see file';
    }
    if (turn.toolName == 'search_and_read') {
      return 'search_and_read ${header.path} - earlier results compacted';
    }
    return '${turn.toolName} ${header.path} - result compacted';
  }
}

class _ToolHeader {
  const _ToolHeader({required this.path, required this.totalLines});

  final String path;
  final int? totalLines;
}
