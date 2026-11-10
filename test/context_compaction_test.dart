import 'package:flutter_test/flutter_test.dart';
import 'package:praxis/core/ai.dart';
import 'package:praxis/core/context_compaction.dart';

void main() {
  test('context levels follow the 60/75 percent policy', () {
    expect(
      ContextCompactor.levelFor(usedTokens: 599, limitTokens: 1000),
      ContextCompactionLevel.none,
    );
    expect(
      ContextCompactor.levelFor(usedTokens: 600, limitTokens: 1000),
      ContextCompactionLevel.cheap,
    );
    expect(
      ContextCompactor.levelFor(usedTokens: 750, limitTokens: 1000),
      ContextCompactionLevel.summarize,
    );
    expect(
      ContextCompactor.levelFor(usedTokens: 50, limitTokens: 0),
      ContextCompactionLevel.none,
    );
  });

  test('cheap compaction preserves the opening request and recent tool pair',
      () {
    final longResult = '[lib/auth.dart · lines 1–400 of 412]\n'
        '${'const value = 1;\n' * 80}';
    final turns = <AiTurn>[
      const AiTurn.user('Original request'),
      for (var index = 0; index < 8; index++) ...[
        AiTurn.assistant(
          '',
          [
            AiToolCall(
              id: 'call-$index',
              name: 'read_file',
              arguments: {'path': 'lib/file_$index.dart'},
            ),
          ],
        ),
        AiTurn.tool('call-$index', 'read_file', longResult),
      ],
      const AiTurn.user('Latest request'),
    ];

    final split = ContextCompactor.split(turns);
    expect(split.headEnd, 1);
    expect(turns[split.tailStart].role, isNot('tool'));
    expect(turns.sublist(split.tailStart).length, greaterThanOrEqualTo(6));

    final result = ContextCompactor.compactToolResults(turns);
    expect(result.changed, isTrue);
    expect(result.turns.first.text, 'Original request');
    expect(result.turns.length, turns.length);
    expect(result.turns[1].role, 'assistant');
    expect(result.turns[2].role, 'tool');
    expect(result.turns[2].text, contains('412 lines - see file'));
    expect(result.turns[2].toolCallId, 'call-0');
    expect(
        result.turns.sublist(split.tailStart), turns.sublist(split.tailStart));
  });

  test('duplicate old reads collapse to a one-line stub', () {
    final shared = '[lib/app.dart · lines 1–200 of 240]\n${'x' * 900}';
    final turns = <AiTurn>[
      const AiTurn.user('Original request'),
      const AiTurn.assistant(
        '',
        [
          AiToolCall(
            id: 'a',
            name: 'read_file',
            arguments: {'path': 'lib/app.dart'},
          ),
        ],
      ),
      AiTurn.tool('a', 'read_file', shared),
      const AiTurn.assistant(
        '',
        [
          AiToolCall(
            id: 'b',
            name: 'read_file',
            arguments: {'path': 'lib/app.dart'},
          ),
        ],
      ),
      AiTurn.tool('b', 'read_file', shared),
      for (var index = 0; index < 6; index++)
        AiTurn.user('Recent message $index'),
    ];

    final result = ContextCompactor.compactToolResults(turns);
    expect(result.changed, isTrue);
    expect(result.turns[4].text, contains('older duplicate omitted'));
  });
}
