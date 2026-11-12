import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/agent.dart';
import 'package:praxis/core/ai.dart';
import 'package:praxis/core/context_prefetch.dart';
import 'package:praxis/core/phase1_flags.dart';
import 'package:praxis/core/round_log.dart';
import 'package:praxis/core/shell.dart';
import 'package:praxis/core/store.dart';
import 'package:praxis/core/system_shell.dart';
import 'package:praxis/core/vfs.dart';
import 'package:praxis/models.dart';
import 'package:praxis/state/app_state.dart';

void main() {
  late Directory temp;
  late ProjectFs fs;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('praxis_phase1_');
    fs = ProjectFs(temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  ProviderConfig provider({String id = 'openai'}) => ProviderConfig(
        id: id,
        name: 'Test',
        icon: 'x',
        baseUrl: 'https://example.test/v1',
        model: 'model',
        flavor: ApiFlavor.openai,
        keys: const ['key'],
      );

  http.Response jsonResponse(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );

  Map<String, Object> call(
    String id,
    String name,
    Map<String, Object?> arguments,
  ) =>
      {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': jsonEncode(arguments)},
      };

  test('prefetch excludes secrets and generated folders', () async {
    await fs.write('lib/main.dart', 'void main() {}');
    await fs.write('.env', 'OPENAI_API_KEY=do-not-send');
    await fs.write('id_rsa', 'private key material');
    await fs.write('node_modules/pkg/index.js', 'generated');
    await fs.write('build/out.js', 'generated');
    await fs.write('README.md', 'A small project.');

    final result = await ContextPrefetch(fs: fs).build('fix the parser');
    expect(result.included, isTrue);
    expect(result.text, contains('lib/main.dart'));
    expect(result.text, isNot(contains('do-not-send')));
    expect(result.text, isNot(contains('private key material')));
    expect(result.text, isNot(contains('node_modules')));
    expect(result.text, isNot(contains('build/out.js')));

    final greeting = await ContextPrefetch(fs: fs).build('hello');
    expect(greeting.included, isFalse);
    expect(greeting.trivial, isTrue);
  });

  test('prefetch respects root and nested gitignore rules', () async {
    await fs.write('.gitignore', '''
ignored/
*.log
!keep.log
/sub-only
''');
    await fs.write('ignored/generated.txt', 'generated');
    await fs.write('debug.log', 'generated');
    await fs.write('keep.log', 'visible');
    await fs.write('sub-only', 'visible');
    await fs.write('sub/.gitignore', '*.tmp\n');
    await fs.write('sub/temp.tmp', 'generated');
    await fs.write('sub/keep.txt', 'visible');

    final result = await ContextPrefetch(fs: fs).build('fix the parser');
    expect(result.included, isTrue);
    expect(result.text, contains('keep.log'));
    expect(result.text, contains('sub/keep.txt'));
    expect(result.text, isNot(contains('ignored/')));
    expect(result.text, isNot(contains('debug.log')));
    expect(result.text, isNot(contains('sub/temp.tmp')));
  });

  test('read_files returns multiple files in one tool result', () async {
    await fs.write('a.txt', 'alpha');
    await fs.write('b.txt', 'beta');
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return jsonResponse({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  call('read_both', 'read_files', {
                    'paths': ['a.txt', 'b.txt'],
                  }),
                ],
              },
            },
          ],
        });
      }
      return jsonResponse({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'Both files read.'},
          },
        ],
      });
    });
    final events = <AgentEvent>[];
    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: events.add,
    ).run(history: const [], prompt: 'compare a and b');

    expect(calls, 2);
    final tool =
        events.firstWhere((event) => event.kind == AgentEventKind.tool);
    expect(tool.tool, 'read_files');
    expect(tool.text, contains('alpha'));
    expect(tool.text, contains('beta'));
  });

  test('independent reads are batched and keep result ordering', () async {
    await fs.write('a.txt', 'alpha');
    await fs.write('b.txt', 'beta');
    var calls = 0;
    List<Map<String, dynamic>> toolMessages = const [];
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return jsonResponse({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  call('read_a', 'read_file', {'path': 'a.txt'}),
                  call('read_b', 'read_file', {'path': 'b.txt'}),
                ],
              },
            },
          ],
        });
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      toolMessages = messages
          .whereType<Map>()
          .where((message) => message['role'] == 'tool')
          .map((message) => message.cast<String, dynamic>())
          .toList();
      return jsonResponse({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'Read in parallel.'},
          },
        ],
      });
    });

    await Agent(
      client: AiClient(client: client),
      provider: provider(id: 'openai'),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: (_) {},
      flags: const Phase1Flags(),
    ).run(history: const [], prompt: 'compare a and b');

    expect(calls, 2);
    expect(toolMessages.length, 2);
    expect(toolMessages[0]['content'], contains('alpha'));
    expect(toolMessages[1]['content'], contains('beta'));
  });

  test('destructive compound command approval lists every command', () async {
    var calls = 0;
    String? approvalBody;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return jsonResponse({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  call('commands', 'run_commands', {
                    'commands': [
                      'rm -rf build/old',
                      "printf 'one'",
                      "printf 'two'",
                    ],
                  }),
                ],
              },
            },
          ],
        });
      }
      return jsonResponse({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'Commands finished.'},
          },
        ],
      });
    });
    final events = <AgentEvent>[];
    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      deviceShell: SystemShell(fs),
      skills: const [],
      onEvent: events.add,
      toolApproval: (title, body, label) async {
        approvalBody = body;
        return true;
      },
    ).run(history: const [], prompt: 'run the checks');

    expect(approvalBody, isNotNull);
    expect(approvalBody, contains('rm -rf build/old'));
    expect(approvalBody, contains("printf 'one'"));
    expect(approvalBody, contains("printf 'two'"));
    final tool =
        events.firstWhere((event) => event.kind == AgentEventKind.tool);
    expect(tool.tool, 'run_commands');
    expect(tool.text, contains('one'));
    expect(tool.text, contains('two'));
  });

  test('log export contains counts but no prompt text', () async {
    final state = AppState(
      root: temp,
      store: MemoryStore(),
      roundLog: MemoryRoundLog(),
      seedWelcome: false,
    );
    addTearDown(state.dispose);
    await state.init();
    await state.roundLog!.appendRound(AgentRound(
      taskId: 'export-task',
      roundIndex: 0,
      at: DateTime.utc(2026, 11, 8),
      provider: 'openai',
      model: 'model',
      toolNames: const ['read_file'],
      type: RoundType.explore,
      repeatedCall: false,
    ));
    await state.roundLog!.finishTask('export-task', AgentOutcome.completed);

    final json = await state.exportAgentLogJson();
    expect(json, contains('"modelRequests": 1'));
    expect(json, contains('export-task'));
    expect(json, contains('completed'));
    expect(json, isNot(contains('prompt')));
    expect(json, isNot(contains('arguments')));
  });

  test('a schema error is returned to the model in one round', () async {
    await fs.write('README.md', '# Project');
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return jsonResponse({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  call('missing_content', 'write_file', {'path': 'README.md'}),
                ],
              },
            },
          ],
        });
      }
      if (calls == 2) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = body['messages'] as List;
        expect(messages.any((message) => message['role'] == 'tool'), isTrue);
        return jsonResponse({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  call('correct_write', 'write_file', {
                    'path': 'README.md',
                    'content': '# Corrected',
                  }),
                ],
              },
            },
          ],
        });
      }
      return jsonResponse({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'Done.'},
          },
        ],
      });
    });

    final events = <AgentEvent>[];
    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: events.add,
    ).run(history: const [], prompt: 'update README');

    expect(calls, 3);
    expect(await fs.read('README.md'), '# Corrected');
    expect(
      events.any((event) =>
          event.kind == AgentEventKind.tool && event.text.contains('content')),
      isTrue,
    );
  });
}
