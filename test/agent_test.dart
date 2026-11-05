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
}
