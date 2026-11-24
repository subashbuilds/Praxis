import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/agent.dart';
import 'package:praxis/core/ai.dart';
import 'package:praxis/core/shell.dart';
import 'package:praxis/core/store.dart';
import 'package:praxis/core/vfs.dart';
import 'package:praxis/state/app_state.dart';
import 'package:praxis/models.dart';

void main() {
  late Directory temp;
  late ProjectFs fs;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('praxis_reliable_');
    fs = ProjectFs(temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  ProviderConfig provider({String id = 'openai'}) => ProviderConfig(
        id: id,
        name: 'Test provider',
        icon: 'x',
        baseUrl: 'https://example.test/v1',
        model: 'test-model',
        flavor: ApiFlavor.openai,
        keys: const ['test-key'],
      );

  http.Response jsonResponse(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );

  http.Response textReply(String text) => jsonResponse({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': text},
            'finish_reason': 'stop',
          },
        ],
      });

  http.Response callReply(
    String id,
    String name,
    Map<String, Object?> arguments, {
    String text = '',
  }) =>
      jsonResponse({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': text,
              'tool_calls': [
                {
                  'id': id,
                  'type': 'function',
                  'function': {
                    'name': name,
                    'arguments': jsonEncode(arguments),
                  },
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
      });

  http.StreamedResponse sse(List<String> payloads) => http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(
          payloads.map((payload) => 'data: $payload\n\n').join(),
        )),
        200,
        headers: {'content-type': 'text/event-stream'},
      );

  String chunk(String text) => jsonEncode({
        'choices': [
          {
            'delta': {'content': text},
          },
        ],
      });

  Agent agent(
    http.Client client, {
    required String prompt,
    void Function(AgentEvent event)? onEvent,
    void Function(String message)? onPause,
    String providerId = 'openai',
    int maxTransientRetries = 0,
  }) =>
      Agent(
        client: AiClient(client: client),
        provider: provider(id: providerId),
        fs: fs,
        shell: Shell(fs),
        skills: const [],
        onEvent: onEvent ?? (_) {},
        onPause: onPause,
        retryDelay: const Duration(milliseconds: 1),
        maxTransientRetries: maxTransientRetries,
      );

  test('visible text is committed before a corrective nudge', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return calls == 1
          ? textReply('Let me read the README now.')
          : textReply('The README explains the app.');
    });
    final texts = <String>[];

    await agent(
      client,
      prompt: 'fix the README',
      onEvent: (event) {
        if (event.kind == AgentEventKind.text) texts.add(event.text);
      },
    ).run(history: const [], prompt: 'fix the README');

    expect(calls, 2);
    expect(texts, [
      'Let me read the README now.',
      'The README explains the app.',
    ]);
  });

  test('an announcement is nudged when the prompt has no change verb',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return switch (calls) {
        1 => callReply('r1', 'read_file', {'path': 'README.md'}),
        2 => textReply('Let me write the fix now.'),
        _ => textReply('Nothing else is needed.'),
      };
    });
    await fs.write('README.md', '# Project\n');

    await agent(
      client,
      prompt: 'investigate why the build fails',
    ).run(history: const [], prompt: 'investigate why the build fails');

    expect(calls, 3);
  });

  test('a long streak of announcements pauses instead of completing', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return textReply('Let me read the next file.');
    });
    String? paused;

    await agent(
      client,
      prompt: 'fix the README',
      onPause: (message) => paused = message,
    ).run(history: const [], prompt: 'fix the README');

    expect(paused, isNotNull);
    expect(paused, contains('announc'));
    expect(calls, lessThanOrEqualTo(10));
  });

  test('a truncated stream is retried and never treated as an answer',
      () async {
    var calls = 0;
    final client = MockClient.streaming((request, body) async {
      calls++;
      if (calls == 1) return sse([chunk('Partial answer')]);
      return http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode(jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'Complete answer.'},
                'finish_reason': 'stop',
              },
            ],
          })),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final events = <AgentEvent>[];

    await agent(
      client,
      prompt: 'fix the README',
      maxTransientRetries: 1,
      onEvent: events.add,
    ).run(history: const [], prompt: 'fix the README');

    expect(calls, 2);
    expect(events.any((event) => event.kind == AgentEventKind.retry), isTrue);
    expect(events.last.text, 'Complete answer.');
  });

  test('a mid-stream connection reset is retried', () async {
    var calls = 0;
    final client = MockClient.streaming((request, body) async {
      calls++;
      if (calls == 1) {
        Stream<List<int>> broken() async* {
          yield utf8.encode('data: ${chunk('Half')}\n\n');
          throw http.ClientException('Connection reset by peer');
        }

        return http.StreamedResponse(
          broken(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }
      return http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode(jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'Recovered.'},
                'finish_reason': 'stop',
              },
            ],
          })),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final events = <AgentEvent>[];

    await agent(
      client,
      prompt: 'fix the README',
      maxTransientRetries: 1,
      onEvent: events.add,
    ).run(history: const [], prompt: 'fix the README');

    expect(calls, 2);
    expect(events.any((event) => event.kind == AgentEventKind.retry), isTrue);
    expect(events.last.text, 'Recovered.');
  });

  test('cut-off tool arguments are never executed', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return jsonResponse({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': 'Writing the file.',
                'tool_calls': [
                  {
                    'id': 'w1',
                    'type': 'function',
                    'function': {
                      'name': 'write_file',
                      'arguments': '{"path": "a.txt", "content": "hello',
                    },
                  },
                ],
              },
              'finish_reason': 'length',
            },
          ],
        });
      }
      return textReply('The call was not run.');
    });
    final toolResults = <String>[];

    await agent(
      client,
      prompt: 'fix the README',
      onEvent: (event) {
        if (event.kind == AgentEventKind.tool) toolResults.add(event.text);
      },
    ).run(history: const [], prompt: 'fix the README');

    expect(calls, 2);
    expect(await fs.exists('a.txt'), isFalse);
    expect(toolResults.join('\n'), contains('arguments were cut off'));
  });

  test('identical calls hint at three and pause at five', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return callReply('r$calls', 'read_file', {'path': 'README.md'});
    });
    await fs.write('README.md', '# Project\n');
    String? paused;

    await agent(
      client,
      prompt: 'read the README',
      onPause: (message) => paused = message,
    ).run(history: const [], prompt: 'read the README');

    expect(paused, isNotNull);
    expect(paused, contains('repeated'));
    expect(calls, 5);
  });

  test('the corrective round asks the provider for a tool call', () async {
    var calls = 0;
    final choices = <String?>[];
    final client = MockClient((request) async {
      calls++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      choices.add(body['tool_choice'] as String?);
      return calls == 1
          ? textReply('Let me read the README now.')
          : textReply('The README explains the app.');
    });

    await agent(client, prompt: 'fix the README')
        .run(history: const [], prompt: 'fix the README');

    expect(calls, 2);
    expect(choices, ['auto', 'required']);
  });

  test('the system prompt avoids the plan/announcement contradiction',
      () async {
    String system = '';
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      system = (body['messages'] as List).first['content'] as String;
      return textReply('Looks fine.');
    });

    await agent(client, prompt: 'fix the README')
        .run(history: const [], prompt: 'fix the README');

    expect(system, isNot(contains('Context policy')));
    expect(system, isNot(contains('Do not narrate a plan before acting')));
    expect(
      system,
      contains('A response with no tool call is your FINAL answer'),
    );
  });

  test('the app keeps the partial reply when a run fails', () async {
    final store = MemoryStore();
    final httpClient = MockClient.streaming((request, body) async {
      Stream<List<int>> blocked() async* {
        yield utf8.encode(
          'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': 'Working on the fix'},
                  },
                ],
              })}\n\n',
        );
        yield utf8.encode(
          'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': ' and checking the result.'},
                    'finish_reason': 'content_filter',
                  },
                ],
              })}\n\n',
        );
      }

      return http.StreamedResponse(
        blocked(),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });

    final setup = AppState(root: temp, store: store, seedWelcome: false);
    await setup.init();
    final project =
        await setup.createProject('partial-reply', ProjectKind.blank);
    setup.dispose();

    final state = AppState(
      root: temp,
      store: store,
      seedWelcome: false,
      httpClient: httpClient,
    );
    addTearDown(state.dispose);
    await state.init();
    await state.saveProvider(provider());
    await state.send(project.id, 'fix the README');

    final thread = state.threadOf(project.id);
    expect(
      thread.where((entry) =>
          entry.role == ChatRole.assistant &&
          entry.text.contains('Working on the fix')),
      isNotEmpty,
      reason: 'the text the user already read belongs in the transcript',
    );
    expect(
      thread.where((entry) => entry.role == ChatRole.error),
      isNotEmpty,
    );
  });

  test('the visible reply is kept when the run fails', () async {
    var calls = 0;
    final client = MockClient.streaming((request, body) async {
      calls++;
      return sse([chunk('A partial explanation')]);
    });
    final events = <AgentEvent>[];

    await expectLater(
      agent(
        client,
        prompt: 'fix the README',
        maxTransientRetries: 0,
        onEvent: events.add,
      ).run(history: const [], prompt: 'fix the README'),
      throwsA(isA<AiProviderException>()),
    );

    expect(calls, 1);
    expect(
      events.where((event) => event.kind == AgentEventKind.text),
      isEmpty,
      reason: 'the partial text still lives in the live draft until the host '
          'commits it on failure',
    );
  });
}
