import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/agent.dart';
import 'package:praxis/core/agent_todos.dart';
import 'package:praxis/core/ai.dart';
import 'package:praxis/core/phase1_flags.dart';
import 'package:praxis/core/shell.dart';
import 'package:praxis/core/vfs.dart';
import 'package:praxis/models.dart';

void main() {
  late Directory temp;
  late ProjectFs fs;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('praxis_phase4_');
    fs = ProjectFs(temp);
    await fs.ensureRoot();
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  ProviderConfig provider({
    String id = 'openai',
    ApiFlavor flavor = ApiFlavor.openai,
  }) =>
      ProviderConfig(
        id: id,
        name: 'Test provider',
        icon: 'x',
        baseUrl: 'https://example.test/v1',
        model: 'test-model',
        flavor: flavor,
        keys: const ['test-key'],
      );

  http.Response toolReply(String id, String name, Map<String, Object?> args) =>
      http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  {
                    'id': id,
                    'type': 'function',
                    'function': {
                      'name': name,
                      'arguments': jsonEncode(args),
                    },
                  },
                ],
              },
              'finish_reason': 'tool_calls',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );

  http.Response textReply(String text) => http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': text},
              'finish_reason': 'stop',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );

  test('finish_task ends the run with its summary and no extra round',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return calls == 1
          ? toolReply('f1', 'finish_task', {
              'summary': 'Added the notes file and verified it.',
            })
          : textReply('This extra reply must never be requested.');
    });
    final texts = <String>[];
    final tools = <AgentEvent>[];

    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      taskId: 'finish-1',
      onEvent: (event) {
        if (event.kind == AgentEventKind.text) texts.add(event.text);
        if (event.kind == AgentEventKind.tool) tools.add(event);
      },
    ).run(history: const [], prompt: 'write the release notes');

    expect(calls, 1);
    expect(tools.single.tool, 'finish_task');
    expect(texts, ['Added the notes file and verified it.']);
  });

  test('finish_task refuses while a checklist step is open', () async {
    await fs.write('README.md', '# Project\n');
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return calls == 1
          ? toolReply('f1', 'finish_task', {'summary': 'All done.'})
          : textReply('I could not finish.');
    });
    final tools = <AgentEvent>[];

    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      taskId: 'finish-2',
      initialTodos: const [
        AgentTodo(text: 'Update the README'),
      ],
      onEvent: (event) {
        if (event.kind == AgentEventKind.tool) tools.add(event);
      },
    ).run(history: const [], prompt: 'update the README');

    expect(calls, 2);
    expect(tools.first.tool, 'finish_task');
    expect(tools.first.text, contains('still open'));
  });

  test('the finish_task tool is absent when the Phase 4 flag is off', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return calls == 1
          ? toolReply('f1', 'finish_task', {'summary': 'All done.'})
          : textReply('The task is complete.');
    });
    final tools = <AgentEvent>[];

    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      flags: Phase1Flags.disabled,
      taskId: 'finish-3',
      onEvent: (event) {
        if (event.kind == AgentEventKind.tool) tools.add(event);
      },
    ).run(history: const [], prompt: 'write the release notes');

    expect(tools.first.text, contains('Unknown tool'));
  });

  test('Anthropic requests cache the stable system and tool prefix', () async {
    Map<String, dynamic>? body;
    final ai = AiClient(
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
            'stop_reason': 'end_turn',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await ai.complete(
      provider: provider(id: 'anthropic', flavor: ApiFlavor.anthropic),
      system: 'You are a coding agent.',
      turns: const [AiTurn.user('hi')],
      tools: const [
        AiToolSpec(name: 'read_file', description: 'Read', parameters: {}),
        AiToolSpec(name: 'write_file', description: 'Write', parameters: {}),
      ],
      maxTokens: 32,
    );

    final system = body!['system'];
    expect(system, isA<List>());
    expect((system as List).single['cache_control'], {'type': 'ephemeral'});
    final tools = body!['tools'] as List;
    expect(tools.first.containsKey('cache_control'), isFalse);
    expect(tools.last['cache_control'], {'type': 'ephemeral'});
  });
}
