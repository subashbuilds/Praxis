import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/agent.dart';
import 'package:praxis/core/ai.dart';
import 'package:praxis/core/phase1_flags.dart';
import 'package:praxis/core/round_log.dart';
import 'package:praxis/core/shell.dart';
import 'package:praxis/core/vfs.dart';
import 'package:praxis/models.dart';

/// These are deterministic scripted-provider measurements, not live model
/// measurements. They prove the wiring and give a reproducible round count on
/// the same task; they must not be reported as real provider numbers.
void main() {
  late Directory temp;
  late ProjectFs fs;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('praxis_measure_');
    fs = ProjectFs(temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  ProviderConfig provider({String id = 'openai'}) => ProviderConfig(
        id: id,
        name: 'Scripted',
        icon: 'x',
        baseUrl: 'https://example.test/v1',
        model: 'scripted-model',
        flavor: ApiFlavor.openai,
        keys: const ['key'],
      );

  http.Response jsonResponse(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );

  Map<String, Object> call(
    String name,
    Map<String, Object?> arguments, {
    String id = 'call',
  }) =>
      {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': jsonEncode(arguments)},
      };

  test('scripted prefetch measurement: 3 rounds off, 2 rounds on', () async {
    await fs.write('README.md', '# Project');
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      final user = messages.lastWhere((m) => m['role'] == 'user');
      final hasPrefetch = (user['content'] as String).contains('PROJECT TREE');
      if (calls == 1) {
        return jsonResponse({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  hasPrefetch
                      ? call('write_file', {
                          'path': 'README.md',
                          'content': '# Updated',
                        })
                      : call('read_file', {'path': 'README.md'}),
                ],
              },
            },
          ],
        });
      }
      if (!hasPrefetch && calls == 2) {
        return jsonResponse({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  call('write_file', {
                    'path': 'README.md',
                    'content': '# Updated',
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
            'message': {'role': 'assistant', 'content': 'Updated.'},
          },
        ],
      });
    });

    Future<int> run(bool prefetch) async {
      calls = 0;
      final log = MemoryRoundLog();
      await Agent(
        client: AiClient(client: client),
        provider: provider(),
        fs: fs,
        shell: Shell(fs),
        skills: const [],
        onEvent: (_) {},
        flags: Phase1Flags(contextPrefetch: prefetch),
        roundLog: log,
        taskId: prefetch ? 'prefetch-on' : 'prefetch-off',
      ).run(history: const [], prompt: 'update README');
      final tasks = await log.loadTasks();
      return tasks.single.totalRounds;
    }

    final off = await run(false);
    final on = await run(true);
    expect(off, 3);
    expect(on, 2);
  });

  test('scripted compound measurement: 4 rounds off, 3 rounds on', () async {
    await fs.write('a.txt', 'alpha');
    await fs.write('b.txt', 'beta');
    var calls = 0;
    var readB = false;
    final client = MockClient((request) async {
      calls++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final tools = (body['tools'] as List)
          .whereType<Map>()
          .map((tool) => (tool['function'] as Map)['name'])
          .toList();
      final hasReadFiles = tools.contains('read_files');
      if (calls == 1) {
        return jsonResponse({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  hasReadFiles
                      ? call('read_files', {
                          'paths': ['a.txt', 'b.txt']
                        })
                      : call('read_file', {'path': 'a.txt'}),
                ],
              },
            },
          ],
        });
      }
      if (!hasReadFiles && !readB) {
        readB = true;
        return jsonResponse({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  call('read_file', {'path': 'b.txt'})
                ],
              },
            },
          ],
        });
      }
      if (calls == (hasReadFiles ? 2 : 3)) {
        return jsonResponse({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  call('write_file', {
                    'path': 'a.txt',
                    'content': 'alpha updated',
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
            'message': {'role': 'assistant', 'content': 'Updated a.txt.'},
          },
        ],
      });
    });

    Future<int> run(bool compound) async {
      calls = 0;
      readB = false;
      final log = MemoryRoundLog();
      await Agent(
        client: AiClient(client: client),
        provider: provider(),
        fs: fs,
        shell: Shell(fs),
        skills: const [],
        onEvent: (_) {},
        flags: Phase1Flags(compoundTools: compound),
        roundLog: log,
        taskId: compound ? 'compound-on' : 'compound-off',
      ).run(history: const [], prompt: 'use both files');
      final tasks = await log.loadTasks();
      return tasks.single.totalRounds;
    }

    final off = await run(false);
    final on = await run(true);
    expect(off, 4);
    expect(on, 3);
  });

  test('scripted loop-guard measurement: 8 rounds off, 3 rounds on', () async {
    await fs.write('README.md', '# Project');
    final client = MockClient((request) async {
      return jsonResponse({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                call('read_file', {'path': 'README.md'}),
              ],
            },
          },
        ],
      });
    });

    Future<int> run(bool guards) async {
      final log = MemoryRoundLog();
      await Agent(
        client: AiClient(client: client),
        provider: provider(),
        fs: fs,
        shell: Shell(fs),
        skills: const [],
        onEvent: (_) {},
        flags: Phase1Flags(loopGuards: guards),
        maxRounds: 8,
        roundLog: log,
        taskId: guards ? 'guards-on' : 'guards-off',
      ).run(history: const [], prompt: 'read it forever');
      final tasks = await log.loadTasks();
      return tasks.single.totalRounds;
    }

    final off = await run(false);
    final on = await run(true);
    expect(off, 8);
    expect(on, 3);
  });
}
