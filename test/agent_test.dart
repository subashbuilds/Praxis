import 'dart:convert';
import 'dart:io';

import 'package:praxis/core/agent.dart';
import 'package:praxis/core/ai.dart';
import 'package:praxis/core/shell.dart';
import 'package:praxis/core/vfs.dart';
import 'package:praxis/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory temp;
  late ProjectFs fs;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('devnest_agent_');
    fs = ProjectFs(temp);
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

  test('agent calls write_file, then reports the final text', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.headers['Authorization'], 'Bearer test-key');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['tools'], isA<List>());
      if (calls == 1) {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': 'Writing the file.',
                  'tool_calls': [
                    {
                      'id': 'call_1',
                      'type': 'function',
                      'function': {
                        'name': 'write_file',
                        'arguments': jsonEncode({
                          'path': 'lib/hello.txt',
                          'content': 'hello from the agent',
                        }),
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': 'Done — file written.'
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final events = <AgentEvent>[];
    final agent = Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: events.add,
    );

    await agent.run(history: const [], prompt: 'create lib/hello.txt');

    expect(calls, 2);
    expect(await fs.read('lib/hello.txt'), 'hello from the agent');
    expect(
        events.any(
            (e) => e.kind == AgentEventKind.tool && e.tool == 'write_file'),
        isTrue);
    expect(events.last.kind, AgentEventKind.text);
    expect(events.last.text, contains('Done'));
  });

  test('a read_file tool call returns file contents', () async {
    await fs.write('README.md', '# project');
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '',
                  'tool_calls': [
                    {
                      'id': 'call_1',
                      'type': 'function',
                      'function': {
                        'name': 'read_file',
                        'arguments': jsonEncode({'path': 'README.md'}),
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'It is a readme.'},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final events = <AgentEvent>[];
    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: events.add,
    ).run(history: const [], prompt: 'what is in the readme?');

    final tool = events.firstWhere((e) => e.kind == AgentEventKind.tool);
    expect(tool.text, contains('# project'));
  });

  test('a bad key surfaces a readable provider error', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'message': 'Incorrect API key provided'},
        }),
        401,
        headers: {'content-type': 'application/json'},
      );
    });

    expect(
      () => AiClient(client: client).complete(
        provider: provider(),
        system: 'test',
        turns: const [AiTurn.user('hi')],
        tools: const [],
      ),
      throwsA(isA<AiProviderException>().having(
        (error) => error.message,
        'message',
        allOf(contains('API key rejected'), contains('Incorrect API key')),
      )),
    );
  });

  test('agent keeps going past six tool rounds', () async {
    await fs.write(
      'README.md',
      List.generate(40, (index) => 'line ${index + 1}').join('\n'),
    );
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls <= 8) {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '',
                  'tool_calls': [
                    {
                      'id': 'call_$calls',
                      'type': 'function',
                      'function': {
                        'name': 'read_file',
                        'arguments':
                            jsonEncode({'path': 'README.md', 'offset': calls}),
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': 'Finished after a longer investigation.',
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final events = <AgentEvent>[];
    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: events.add,
    ).run(history: const [], prompt: 'investigate thoroughly');

    expect(calls, 9);
    expect(
        events.where((event) => event.kind == AgentEventKind.tool).length, 8);
    expect(events.any((event) => event.kind == AgentEventKind.error), isFalse);
    expect(events.last.text, contains('Finished'));
  });

  test('stops a model that repeats the same read call', () async {
    await fs.write('README.md', '# project');
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  {
                    'id': 'call_$calls',
                    'type': 'function',
                    'function': {
                      'name': 'read_file',
                      'arguments': jsonEncode({'path': 'README.md'}),
                    },
                  },
                ],
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final events = <AgentEvent>[];
    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: events.add,
    ).run(history: const [], prompt: 'read it forever');

    expect(calls, 4);
    expect(
        events.where((event) => event.kind == AgentEventKind.tool).length, 3);
    expect(
      events.any((event) =>
          event.kind == AgentEventKind.error &&
          event.text.contains('four times')),
      isTrue,
    );
  });

  test('installs a folder skill that is available to later prompts', () async {
    var calls = 0;
    String? secondSystem;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '',
                  'tool_calls': [
                    {
                      'id': 'call_skill',
                      'type': 'function',
                      'function': {
                        'name': 'install_skill',
                        'arguments': jsonEncode({
                          'name': 'Telegram voice notes',
                          'description':
                              'Use when adding voice note support to a bot.',
                          'instructions':
                              'Prefer OGG/Opus and verify the duration field.',
                        }),
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (calls == 2) {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'Skill installed.'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      secondSystem =
          (messages.first as Map<String, dynamic>)['content'] as String;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'Ready.'},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: (_) {},
    ).run(history: const [], prompt: 'install a Telegram skill');

    final file = await fs.read('.praxis/skills/telegram-voice-notes/SKILL.md');
    expect(file, contains('name: Telegram voice notes'));
    expect(file, contains('Prefer OGG/Opus'));

    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: (_) {},
    ).run(history: const [], prompt: 'add voice notes');

    expect(secondSystem, contains('Telegram voice notes'));
    expect(secondSystem, contains('Prefer OGG/Opus'));
  });
}
