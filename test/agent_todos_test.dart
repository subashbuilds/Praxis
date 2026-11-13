import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/agent.dart';
import 'package:praxis/core/agent_todos.dart';
import 'package:praxis/core/ai.dart';
import 'package:praxis/core/shell.dart';
import 'package:praxis/core/vfs.dart';
import 'package:praxis/models.dart';

void main() {
  late Directory temp;
  late ProjectFs fs;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('praxis_todos_');
    fs = ProjectFs(temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  ProviderConfig provider() => const ProviderConfig(
        id: 'openai',
        name: 'Test',
        icon: 'x',
        baseUrl: 'https://example.test/v1',
        model: 'model',
        flavor: ApiFlavor.openai,
        keys: ['key'],
      );

  http.Response jsonResponse(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );

  test('the checklist survives a save and reload', () async {
    await ProjectTodosStore.save(fs, const [
      AgentTodo(text: 'Inspect the project'),
      AgentTodo(text: 'Add the route', status: AgentTodoStatus.inProgress),
      AgentTodo(text: 'Run the checks', status: AgentTodoStatus.completed),
    ]);

    final loaded = await ProjectTodosStore.load(fs);

    expect(loaded.map((todo) => todo.text), [
      'Inspect the project',
      'Add the route',
      'Run the checks',
    ]);
    expect(loaded[1].status, AgentTodoStatus.inProgress);
    expect(loaded[2].done, isTrue);
  });

  test('the agent can create and complete checklist items', () async {
    var requests = 0;
    final bodies = <String>[];
    final client = MockClient((request) async {
      requests++;
      bodies.add(request.body);
      if (requests == 1) {
        return jsonResponse({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  {
                    'id': 'todos-1',
                    'type': 'function',
                    'function': {
                      'name': 'update_todos',
                      'arguments': jsonEncode({
                        'todos': [
                          {'text': 'Inspect routes', 'status': 'completed'},
                          {'text': 'Add the endpoint', 'status': 'in_progress'},
                          {'text': 'Run tests', 'status': 'pending'},
                        ],
                      }),
                    },
                  },
                ],
              },
            },
          ],
        });
      }
      return jsonResponse({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'Endpoint planned.'},
          },
        ],
      });
    });

    List<AgentTodo>? updated;
    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: (_) {},
      initialTodos: const [AgentTodo(text: 'Old checklist item')],
      onTodosChanged: (todos) => updated = todos,
    ).run(history: const [], prompt: 'Plan the endpoint');

    expect(updated, isNotNull);
    expect(updated!.map((todo) => todo.text), [
      'Inspect routes',
      'Add the endpoint',
      'Run tests',
    ]);
    expect(updated![0].done, isTrue);
    expect(updated![1].status, AgentTodoStatus.inProgress);
    expect(bodies.first, contains('Old checklist item'));
  });
}
