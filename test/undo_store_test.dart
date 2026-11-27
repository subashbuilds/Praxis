import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/agent.dart';
import 'package:praxis/core/ai.dart';
import 'package:praxis/core/shell.dart';
import 'package:praxis/core/undo_store.dart';
import 'package:praxis/core/vfs.dart';
import 'package:praxis/models.dart';

void main() {
  late Directory temp;
  late ProjectFs fs;
  late UndoStore undo;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('praxis_undo_');
    fs = ProjectFs(temp);
    await fs.ensureRoot();
    undo = UndoStore(fs);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('a snapshot puts the file back after a write', () async {
    await fs.write('lib/main.dart', 'old line\n');
    final change = await undo.snapshot(
      taskId: 'task-1',
      path: 'lib/main.dart',
      label: 'Fix the counter',
    );
    expect(change, isNotNull);
    expect(change!.existed, isTrue);

    await fs.write('lib/main.dart', 'new line\n');
    final task = await undo.task('task-1');
    expect(task, isNotNull);
    expect(task!.label, 'Fix the counter');
    expect(task.changes.single.path, 'lib/main.dart');

    final outcome = await undo.revertIds([change.id]);
    expect(outcome.changedAnything, isTrue);
    expect(await fs.read('lib/main.dart'), 'old line\n');

    // A second revert is a no-op instead of restoring stale content.
    final again = await undo.revertIds([change.id]);
    expect(again.changedAnything, isFalse);
  });

  test('reverting a file the task created removes it', () async {
    final change = await undo.snapshot(
      taskId: 'task-create',
      path: 'notes/todo.md',
      label: 'Add notes',
    );
    expect(change, isNotNull);
    expect(change!.existed, isFalse);

    await fs.write('notes/todo.md', '- ship it\n');
    final outcome = await undo.revertIds([change.id]);

    expect(outcome.message, contains('removed'));
    expect(await fs.exists('notes/todo.md'), isFalse);
  });

  test('undoing a task walks every write back to the original', () async {
    await fs.write('app.js', 'one\n');
    await undo.snapshot(taskId: 'task-2', path: 'app.js', label: 'Refactor');
    await fs.write('app.js', 'two\n');
    await undo.snapshot(taskId: 'task-2', path: 'app.js', label: 'Refactor');
    await fs.write('app.js', 'three\n');
    await undo.snapshot(taskId: 'task-2', path: 'style.css', label: 'Refactor');
    await fs.write('style.css', 'body {}\n');

    final task = await undo.task('task-2');
    final outcome = await undo.undo(task!);

    expect(outcome.changeIds, hasLength(3));
    expect(outcome.message, contains('restored'));
    expect(outcome.message, contains('removed'));
    expect(await fs.read('app.js'), 'one\n');
    expect(await fs.exists('style.css'), isFalse);
  });

  test('a change a later write replaced is not reverted on its own', () async {
    await fs.write('a.txt', 'first\n');
    final first = await undo.snapshot(
      taskId: 'task-3',
      path: 'a.txt',
      label: 'Edits',
    );
    await fs.write('a.txt', 'second\n');
    final second = await undo.snapshot(
      taskId: 'task-3',
      path: 'a.txt',
      label: 'Edits',
    );
    await fs.write('a.txt', 'third\n');

    // Restoring the first snapshot would silently throw away the newer write,
    // so it is refused and the file is untouched.
    final blocked = await undo.revertIds([first!.id]);
    expect(blocked.changedAnything, isFalse);
    expect(blocked.message, contains('later change'));
    expect(await fs.read('a.txt'), 'third\n');

    // The newest change can always be reverted.
    final ok = await undo.revertIds([second!.id]);
    expect(ok.changedAnything, isTrue);
    expect(await fs.read('a.txt'), 'second\n');

    // Once the later change is reverted, the earlier one is free again.
    await undo.revertIds([first.id]);
    expect(await fs.read('a.txt'), 'first\n');
  });

  test('binary files are restored byte for byte', () async {
    final original = [0, 1, 2, 250, 251, 252];
    await fs.writeBytes('assets/logo.png', original);
    final change = await undo.snapshot(
      taskId: 'task-4',
      path: 'assets/logo.png',
      label: 'Replace the logo',
    );
    expect(change, isNotNull);
    expect(change!.binary, isTrue);

    await fs.writeBytes('assets/logo.png', [9, 9, 9]);
    await undo.revertIds([change.id]);

    expect(await fs.readBytes('assets/logo.png'), original);
  });

  test('latest returns the newest task and ignores reverted ones', () async {
    await fs.write('a.txt', 'a\n');
    await undo.snapshot(taskId: 'older', path: 'a.txt', label: 'Older');
    await fs.write('a.txt', 'b\n');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await fs.write('b.txt', 'b\n');
    await undo.snapshot(taskId: 'newer', path: 'b.txt', label: 'Newer');

    final latest = await undo.latest();
    expect(latest?.id, 'newer');

    await undo.undo(latest!);
    expect((await undo.latest())?.id, 'newer');
    expect((await undo.latest())!.pending, isEmpty);
  });

  test('a write tool reports the snapshot ids it created', () async {
    await fs.write('README.md', '# Old\n');
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
                      'id': 'w1',
                      'type': 'function',
                      'function': {
                        'name': 'write_file',
                        'arguments': jsonEncode({
                          'path': 'README.md',
                          'content': '# New\n',
                        }),
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
      }
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': 'Updated README.md and verified it.',
              },
              'finish_reason': 'stop',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final toolEvents = <AgentEvent>[];
    await Agent(
      client: AiClient(client: client),
      provider: const ProviderConfig(
        id: 'openai',
        name: 'Test provider',
        icon: 'x',
        baseUrl: 'https://example.test/v1',
        model: 'test-model',
        flavor: ApiFlavor.openai,
        keys: ['test-key'],
      ),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      undo: undo,
      taskId: 'task-write',
      onEvent: (event) {
        if (event.kind == AgentEventKind.tool) toolEvents.add(event);
      },
    ).run(history: const [], prompt: 'fix the README');

    expect(await fs.read('README.md'), '# New\n');
    final write = toolEvents.firstWhere((event) => event.tool == 'write_file');
    expect(write.undoIds, hasLength(1));

    final outcome = await undo.revertIds(write.undoIds);
    expect(outcome.changedAnything, isTrue);
    expect(await fs.read('README.md'), '# Old\n');
  });

  test('a patch is snapshotted before it runs, so a revert restores', () async {
    await fs.write('README.md', '# Old\n');
    http.Response tool(
            String id, String name, Map<String, Object?> arguments) =>
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
                        'arguments': jsonEncode(arguments),
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
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      switch (calls) {
        case 1:
          return tool('t1', 'update_todos', {
            'todos': [
              {'text': 'Rename the heading', 'status': 'in_progress'},
            ],
          });
        case 2:
          return tool('p1', 'apply_patch', {
            'patch': '*** Begin Patch\n'
                '*** Update File: README.md\n'
                '@@\n'
                '-# Old\n'
                '+# New\n'
                '*** End Patch',
          });
        default:
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': 'Patched README.md and verified it.',
                  },
                  'finish_reason': 'stop',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
      }
    });
    final toolEvents = <AgentEvent>[];
    await Agent(
      client: AiClient(client: client),
      provider: const ProviderConfig(
        id: 'openai',
        name: 'Test provider',
        icon: 'x',
        baseUrl: 'https://example.test/v1',
        model: 'test-model',
        flavor: ApiFlavor.openai,
        keys: ['test-key'],
      ),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      undo: undo,
      taskId: 'task-patch',
      onEvent: (event) {
        if (event.kind == AgentEventKind.tool) toolEvents.add(event);
      },
    ).run(history: const [], prompt: 'rename the heading');

    expect(await fs.read('README.md'), '# New\n');
    final patch = toolEvents.firstWhere((event) => event.tool == 'apply_patch');
    expect(patch.undoIds, hasLength(1));

    final outcome = await undo.revertIds(patch.undoIds);
    expect(outcome.changedAnything, isTrue);
    expect(await fs.read('README.md'), '# Old\n');
  });
}
