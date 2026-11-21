import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/agent.dart';
import 'package:praxis/core/agent_todos.dart';
import 'package:praxis/core/ai.dart';
import 'package:praxis/core/shell.dart';
import 'package:praxis/core/store.dart';
import 'package:praxis/core/vfs.dart';
import 'package:praxis/models.dart';
import 'package:praxis/state/app_state.dart';

void main() {
  late Directory temp;
  late ProjectFs fs;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('praxis_flow_');
    fs = ProjectFs(temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  ProviderConfig provider() => const ProviderConfig(
        id: 'openai',
        name: 'Test provider',
        icon: 'x',
        baseUrl: 'https://example.test/v1',
        model: 'test-model',
        flavor: ApiFlavor.openai,
        keys: ['test-key'],
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
          },
        ],
      });

  test('an announced step after a write is executed instead of stopping',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return switch (calls) {
        1 => callReply(
            'w1',
            'write_file',
            {
              'path': 'a.txt',
              'content': 'alpha',
            },
            text: 'Writing a.txt.'),
        2 => textReply('Let me write b.txt now.'),
        3 => callReply('t1', 'update_todos', {
            'todos': [
              {'text': 'Create a.txt', 'status': 'completed'},
              {'text': 'Create b.txt', 'status': 'in_progress'},
            ],
          }),
        4 => callReply('w2', 'write_file', {
            'path': 'b.txt',
            'content': 'beta',
          }),
        5 => callReply('t2', 'update_todos', {
            'todos': [
              {'text': 'Create a.txt', 'status': 'completed'},
              {'text': 'Create b.txt', 'status': 'completed'},
            ],
          }),
        _ => textReply('Created a.txt and b.txt, and checked both files.'),
      };
    });

    String? paused;
    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: (_) {},
      onPause: (message) => paused = message,
    ).run(history: const [], prompt: 'create both text files');

    expect(calls, 6);
    expect(await fs.read('a.txt'), 'alpha');
    expect(await fs.read('b.txt'), 'beta');
    expect(paused, isNull);
  });

  test('a question refuses file changes and answers in prose', () async {
    var calls = 0;
    final events = <AgentEvent>[];
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return callReply('w1', 'write_file', {
          'path': 'notes.txt',
          'content': 'unrequested',
        });
      }
      return textReply(
          'It reads README.md, sends it to GitHub, then saves it.');
    });

    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: events.add,
    ).run(history: const [], prompt: 'what does the update flow do?');

    expect(calls, 2);
    expect(await fs.exists('notes.txt'), isFalse);
    expect(
      events.any((event) =>
          event.kind == AgentEventKind.tool &&
          event.text.contains('asks for an answer')),
      isTrue,
    );
    expect(events.last.kind, AgentEventKind.text);
    expect(events.last.text, contains('README.md'));
  });

  test(
      'a change request answered without an edit completes instead of erroring',
      () async {
    var calls = 0;
    final events = <AgentEvent>[];
    String? paused;
    final client = MockClient((request) async {
      calls++;
      return textReply(
          'No change is needed: the patch already handles every import. I '
          'verified each module against the patch list without a compiler.');
    });

    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: events.add,
      onPause: (message) => paused = message,
    ).run(
        history: const [],
        prompt: 'fix the patch if anything is wrong, otherwise verify it');

    expect(calls, 1);
    expect(events.any((event) => event.kind == AgentEventKind.error), isFalse);
    expect(events.last.kind, AgentEventKind.text);
    expect(events.last.text, contains('No change is needed'));
    expect(paused, isNull);
  });

  test('a multi-file edit gets one summary nudge when no file is named',
      () async {
    var calls = 0;
    final events = <AgentEvent>[];
    final client = MockClient((request) async {
      calls++;
      return switch (calls) {
        1 => callReply('t1', 'update_todos', {
            'todos': [
              {'text': 'Create a.txt', 'status': 'in_progress'},
              {'text': 'Create b.txt', 'status': 'pending'},
            ],
          }),
        2 => callReply('w1', 'write_files', {
            'files': [
              {'path': 'a.txt', 'content': 'alpha'},
              {'path': 'b.txt', 'content': 'beta'},
            ],
          }),
        3 => callReply('t2', 'update_todos', {
            'todos': [
              {'text': 'Create a.txt', 'status': 'completed'},
              {'text': 'Create b.txt', 'status': 'completed'},
            ],
          }),
        4 => textReply('Done.'),
        _ => textReply('Changed a.txt and b.txt, and verified both files.'),
      };
    });

    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: events.add,
    ).run(history: const [], prompt: 'create a.txt and b.txt');

    expect(calls, 5);
    expect(events.last.kind, AgentEventKind.text);
    expect(events.last.text, contains('a.txt'));
  });

  test('a multi-file change creates a checklist before writing', () async {
    var calls = 0;
    List<AgentTodo>? updated;
    final client = MockClient((request) async {
      calls++;
      return switch (calls) {
        1 => callReply('w1', 'write_files', {
            'files': [
              {'path': 'a.txt', 'content': 'alpha'},
              {'path': 'b.txt', 'content': 'beta'},
            ],
          }),
        2 => callReply('t1', 'update_todos', {
            'todos': [
              {'text': 'Create the first file', 'status': 'in_progress'},
              {'text': 'Create the second file', 'status': 'pending'},
              {'text': 'Verify both files', 'status': 'pending'},
            ],
          }),
        3 => callReply('w2', 'write_files', {
            'files': [
              {'path': 'a.txt', 'content': 'alpha'},
              {'path': 'b.txt', 'content': 'beta'},
            ],
          }),
        4 => callReply('t2', 'update_todos', {
            'todos': [
              {'text': 'Create the first file', 'status': 'completed'},
              {'text': 'Create the second file', 'status': 'completed'},
              {'text': 'Verify both files', 'status': 'completed'},
            ],
          }),
        _ => textReply('Created a.txt and b.txt and checked both files.'),
      };
    });

    final produced = <AgentEvent>[];
    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: produced.add,
      onTodosChanged: (todos) => updated = todos,
    ).run(history: const [], prompt: 'create a.txt and b.txt with the values');

    expect(calls, 5);
    expect(await fs.read('a.txt'), 'alpha');
    expect(await fs.read('b.txt'), 'beta');
    expect(updated?.map((todo) => todo.text), [
      'Create the first file',
      'Create the second file',
      'Verify both files',
    ]);
    expect(
      produced.any((event) => event.text.contains('update_todos first')),
      isTrue,
    );
  });

  test('a task with an open checklist pauses instead of claiming completion',
      () async {
    var calls = 0;
    String? paused;
    final client = MockClient((request) async {
      calls++;
      return switch (calls) {
        1 => callReply('t1', 'update_todos', {
            'todos': [
              {'text': 'Write the entry point', 'status': 'in_progress'},
              {'text': 'Wire the route', 'status': 'pending'},
            ],
          }),
        2 => callReply('w1', 'write_file', {
            'path': 'main.txt',
            'content': 'entry',
          }),
        _ => textReply('Done.'),
      };
    });

    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: (_) {},
      onPause: (message) => paused = message,
    ).run(history: const [], prompt: 'create the app entry point and route');

    expect(calls, 5);
    expect(paused, isNotNull);
    expect(paused, contains('unfinished'));
    expect(paused, contains('continue'));
  });

  test('sending continue without a checkpoint resumes from the transcript',
      () async {
    final store = MemoryStore();
    final requests = <Map<String, dynamic>>[];

    final setup = AppState(root: temp, store: store, seedWelcome: false);
    await setup.init();
    final project =
        await setup.createProject('continue-flow', ProjectKind.blank);
    setup.dispose();

    final client = MockClient((request) async {
      requests.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
      if (requests.length == 1) {
        return callReply('w1', 'write_file', {
          'path': 'continued.txt',
          'content': 'resumed',
        });
      }
      return textReply('Created continued.txt from the last unfinished step.');
    });

    final state = AppState(
      root: temp,
      store: store,
      seedWelcome: false,
      httpClient: client,
    );
    addTearDown(state.dispose);
    await state.init();
    await state.saveProvider(provider());

    final thread = state.threadOf(project.id);
    thread.add(ChatEntry(
      id: 'earlier-user',
      role: ChatRole.user,
      text: 'Implement the saved feature.',
      at: DateTime.now().subtract(const Duration(minutes: 2)),
    ));
    thread.add(ChatEntry(
      id: 'earlier-assistant',
      role: ChatRole.assistant,
      text: 'Read the existing config.',
      at: DateTime.now().subtract(const Duration(minutes: 1)),
    ));

    await state.send(project.id, 'continue');

    final contents = (requests.first['messages'] as List)
        .whereType<Map>()
        .map((message) => '${message['content']}')
        .toList();
    expect(contents.any((text) => text.contains('CONTINUE THE PREVIOUS TASK')),
        isTrue);
    expect(
        contents.any((text) => text.contains('Implement the saved feature.')),
        isTrue);
    expect(contents, isNot(contains('continue')));
    expect(await state.fsFor(project).read('continued.txt'), 'resumed');
    expect(
      state.threadOf(project.id).any(
            (entry) => entry.text.contains('Continuing the previous task'),
          ),
      isTrue,
    );
  });

  test('a long conversation is persisted without losing the middle', () async {
    final store = MemoryStore();
    final setup = AppState(root: temp, store: store, seedWelcome: false);
    await setup.init();
    final project = await setup.createProject('long-chat', ProjectKind.blank);
    setup.dispose();

    final client = MockClient((request) async => textReply('Hello.'));
    final state = AppState(
      root: temp,
      store: store,
      seedWelcome: false,
      httpClient: client,
    );
    addTearDown(state.dispose);
    await state.init();
    await state.saveProvider(provider());

    final thread = state.threadOf(project.id);
    for (var index = 0; index < 300; index++) {
      thread.add(ChatEntry(
        id: 'seed-$index',
        role: index.isEven ? ChatRole.user : ChatRole.assistant,
        text: 'message number $index with enough text to matter',
        at: DateTime.now().subtract(Duration(minutes: 300 - index)),
      ));
    }

    await state.send(project.id, 'hello');

    final raw = store.read('praxis.chat.${project.id}');
    expect(raw, isNotNull);
    final decoded = (jsonDecode(raw!) as List).cast<Map>();
    expect(decoded, hasLength(state.threadOf(project.id).length));
    expect(decoded.any((entry) => entry['id'] == 'seed-150'), isTrue);
  });

  test('a provider failure shows its error before the provider picker',
      () async {
    final store = MemoryStore();
    final setup = AppState(root: temp, store: store, seedWelcome: false);
    await setup.init();
    final project =
        await setup.createProject('provider-flow', ProjectKind.blank);
    setup.dispose();

    const first = ProviderConfig(
      id: 'openai',
      name: 'Primary',
      icon: 'x',
      baseUrl: 'https://a.test/v1',
      model: 'primary-model',
      flavor: ApiFlavor.openai,
      keys: ['bad-key'],
    );
    const second = ProviderConfig(
      id: 'deepseek',
      name: 'Backup',
      icon: 'x',
      baseUrl: 'https://b.test/v1',
      model: 'backup-model',
      flavor: ApiFlavor.openai,
      keys: ['good-key'],
    );

    final client = MockClient((request) async {
      if (request.url.host == 'a.test') {
        return http.Response(
          jsonEncode({
            'error': {'message': 'invalid api key sent-401'}
          }),
          401,
          headers: {'content-type': 'application/json'},
        );
      }
      return textReply('Answered by the backup provider.');
    });

    final state = AppState(
      root: temp,
      store: store,
      seedWelcome: false,
      httpClient: client,
    );
    addTearDown(state.dispose);
    await state.init();
    await state.saveProvider(first);
    await state.saveProvider(second);

    String? shownReason;
    state.providerChoicePrompt = (current, providers, reason) async {
      shownReason = reason;
      return ProviderChoice(providers.first, providers.first.model);
    };

    await state.send(project.id, 'hello');

    expect(shownReason, isNotNull);
    expect(shownReason, contains('invalid api key sent-401'));
    expect(
      state.threadOf(project.id).any(
            (entry) =>
                entry.role == ChatRole.note &&
                entry.text.contains('invalid api key sent-401'),
          ),
      isTrue,
    );
    expect(
      state.threadOf(project.id).last.role,
      isNot(ChatRole.error),
    );
  });
}
