import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/agent.dart';
import 'package:praxis/core/ai.dart';
import 'package:praxis/core/round_log.dart';
import 'package:praxis/core/shell.dart';
import 'package:praxis/core/vfs.dart';
import 'package:praxis/models.dart';

void main() {
  late Directory temp;
  late ProjectFs fs;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('praxis_rounds_');
    fs = ProjectFs(temp);
    await fs.write('README.md', '# Project\n');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  ProviderConfig provider() => const ProviderConfig(
        id: 'test',
        name: 'Test provider',
        icon: 'assets/icons/openai.svg',
        baseUrl: 'https://example.test/v1',
        model: 'test-model',
        flavor: ApiFlavor.openai,
        keys: ['test-key'],
      );

  http.Response response(Map<String, dynamic> message,
          {Map<String, dynamic>? usage}) =>
      http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', ...message},
              'finish_reason': 'tool_calls',
            },
          ],
          if (usage != null) 'usage': usage,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );

  test('records one entry per request and classifies explore then edit',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return response(
          {
            'content': '',
            'tool_calls': [
              {
                'id': 'read_1',
                'type': 'function',
                'function': {
                  'name': 'read_file',
                  'arguments': jsonEncode({'path': 'README.md'}),
                },
              },
            ],
          },
          usage: {'prompt_tokens': 11, 'completion_tokens': 3},
        );
      }
      if (calls == 2) {
        return response({
          'content': '',
          'tool_calls': [
            {
              'id': 'write_1',
              'type': 'function',
              'function': {
                'name': 'write_file',
                'arguments': jsonEncode({
                  'path': 'README.md',
                  'content': '# Updated\n',
                }),
              },
            },
          ],
        });
      }
      return response({'content': 'Updated the README.'});
    });

    final log = MemoryRoundLog();
    final events = <AgentEvent>[];
    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: events.add,
      roundLog: log,
      taskId: 'task-one',
    ).run(history: const [], prompt: 'update the README');

    final tasks = await log.loadTasks();
    expect(tasks, hasLength(1));
    final task = tasks.single;
    expect(task.outcome, AgentOutcome.completed);
    expect(task.rounds, hasLength(3));
    expect(task.rounds.map((round) => round.type), [
      RoundType.explore,
      RoundType.edit,
      RoundType.other,
    ]);
    expect(task.rounds[0].toolNames, ['read_file']);
    expect(task.rounds[1].toolNames, ['write_file']);
    expect(task.rounds[2].toolNames, isEmpty);
    expect(task.rounds[0].inputTokens, 11);
    expect(task.rounds[0].outputTokens, 3);
    expect(task.rounds[1].inputTokens, isNull);
    expect(task.rounds[1].outputTokens, isNull);
    expect(task.rounds.any((round) => round.repeatedCall), isFalse);
    expect(task.firstEditIndex, 1);
    expect(task.roundsBeforeFirstEdit, 1);
    expect(task.repeatedCalls, 0);
    expect(events.last.text, contains('Updated'));
  });

  test('marks a call that repeats an earlier call in the task', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls <= 2) {
        return response({
          'content': '',
          'tool_calls': [
            {
              'id': 'read_$calls',
              'type': 'function',
              'function': {
                'name': 'read_file',
                'arguments': jsonEncode({'path': 'README.md'}),
              },
            },
          ],
        });
      }
      if (calls == 3) {
        return response({
          'content': '',
          'tool_calls': [
            {
              'id': 'write_1',
              'type': 'function',
              'function': {
                'name': 'write_file',
                'arguments': jsonEncode({
                  'path': 'README.md',
                  'content': '# Changed\n',
                }),
              },
            },
          ],
        });
      }
      return response({'content': 'Done.'});
    });

    final log = MemoryRoundLog();
    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: (_) {},
      roundLog: log,
      taskId: 'task-repeat',
    ).run(history: const [], prompt: 'update the README');

    final task = (await log.loadTasks()).single;
    expect(task.rounds[1].repeatedCall, isTrue);
    expect(task.repeatedCalls, 1);
    expect(task.rounds[0].repeatedCall, isFalse);
  });

  test('records a quota failure as a task outcome', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'message': 'quota exceeded'},
        }),
        429,
      );
    });

    final log = MemoryRoundLog();
    await expectLater(
      Agent(
        client: AiClient(client: client),
        provider: provider(),
        fs: fs,
        shell: Shell(fs),
        skills: const [],
        onEvent: (_) {},
        roundLog: log,
        taskId: 'task-quota',
      ).run(history: const [], prompt: 'update the README'),
      throwsA(isA<AiProviderException>()),
    );

    final task = (await log.loadTasks()).single;
    expect(task.outcome, AgentOutcome.quotaError);
    expect(task.rounds, hasLength(1));
    expect(task.rounds.single.toolNames, isEmpty);
    expect(task.rounds.single.inputTokens, isNull);
    expect(task.rounds.single.finishReason, 'error');
  });

  test('file round log persists rounds and task outcome as JSONL', () async {
    final log = FileRoundLog(Directory('${temp.path}/logs'));
    await log.prepare();
    final at = DateTime.utc(2026, 11, 7, 10, 30);
    await log.appendRound(AgentRound(
      taskId: 'persisted',
      roundIndex: 0,
      at: at,
      provider: 'p',
      model: 'm',
      toolNames: const ['read_file'],
      type: RoundType.explore,
      repeatedCall: false,
      inputTokens: 5,
      outputTokens: 2,
    ));
    await log.appendRound(AgentRound(
      taskId: 'persisted',
      roundIndex: 1,
      at: at.add(const Duration(seconds: 1)),
      provider: 'p',
      model: 'm',
      toolNames: const ['write_file'],
      type: RoundType.edit,
      repeatedCall: false,
    ));
    await log.finishTask('persisted', AgentOutcome.completed);

    final tasks = await log.loadTasks();
    expect(tasks, hasLength(1));
    expect(tasks.single.totalRounds, 2);
    expect(tasks.single.outcome, AgentOutcome.completed);
    expect(tasks.single.firstEditIndex, 1);
    expect(tasks.single.inputTokens, 5);
    expect(tasks.single.outputTokens, 2);

    await log.clear();
    expect(await log.loadTasks(), isEmpty);
  });
}
