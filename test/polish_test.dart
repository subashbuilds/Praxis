import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/agent.dart';
import 'package:praxis/core/ai.dart';
import 'package:praxis/core/file_import.dart';
import 'package:praxis/core/integrations.dart';
import 'package:praxis/core/shell.dart';
import 'package:praxis/core/store.dart';
import 'package:praxis/core/vfs.dart';
import 'package:praxis/models.dart';
import 'package:praxis/state/app_state.dart';

void main() {
  test('composer drafts survive a new AppState and app restart', () async {
    final temp = await Directory.systemTemp.createTemp('praxis_draft_');
    addTearDown(() => temp.delete(recursive: true));
    final store = MemoryStore();

    final first = AppState(root: temp, store: store, seedWelcome: false);
    await first.init();
    final project =
        await first.createProject('draft-project', ProjectKind.python);
    first.setPromptDraft(project.id, 'keep this prompt across tabs');
    await Future<void>.delayed(Duration.zero);
    first.dispose();

    final reopened = AppState(root: temp, store: store, seedWelcome: false);
    await reopened.init();
    expect(
      reopened.promptDraftFor(project.id),
      'keep this prompt across tabs',
    );
    reopened.setPromptDraft(project.id, 'updated draft');
    await Future<void>.delayed(Duration.zero);

    final third = AppState(root: temp, store: store, seedWelcome: false);
    await third.init();
    expect(third.promptDraftFor(project.id), 'updated draft');
    third.dispose();
    reopened.dispose();
  });

  test('importing a folder merges and asks only for colliding files', () async {
    final project = await Directory.systemTemp.createTemp('praxis_import_');
    final source = await Directory.systemTemp.createTemp('praxis_source_');
    addTearDown(() => project.delete(recursive: true));
    addTearDown(() => source.delete(recursive: true));
    final fs = ProjectFs(project);

    await fs.write('folder/keep.txt', 'keep me');
    await fs.write('folder/collision.txt', 'old');

    final sourceFolder = Directory('${source.path}/folder');
    await sourceFolder.create(recursive: true);
    await File('${sourceFolder.path}/collision.txt').writeAsString('new');
    await File('${sourceFolder.path}/added.txt').writeAsString('added');
    final nested = Directory('${sourceFolder.path}/nested');
    await nested.create();
    await File('${nested.path}/deep.txt').writeAsString('deep');

    final conflicts = <String>[];
    final summary = await importEntries(
      fs,
      [
        ImportEntry(
          path: 'folder',
          sourcePath: sourceFolder.path,
          isDir: true,
        ),
        ImportEntry(
          path: 'folder/collision.txt',
          sourcePath: '${sourceFolder.path}/collision.txt',
          isDir: false,
        ),
        ImportEntry(
          path: 'folder/added.txt',
          sourcePath: '${sourceFolder.path}/added.txt',
          isDir: false,
        ),
        ImportEntry(
          path: 'folder/nested',
          sourcePath: nested.path,
          isDir: true,
        ),
        ImportEntry(
          path: 'folder/nested/deep.txt',
          sourcePath: '${nested.path}/deep.txt',
          isDir: false,
        ),
      ],
      onConflict: (conflict) async {
        conflicts.add(conflict.path);
        return true;
      },
    );

    expect(conflicts, ['folder/collision.txt']);
    expect(await fs.read('folder/keep.txt'), 'keep me');
    expect(await fs.read('folder/collision.txt'), 'new');
    expect(await fs.read('folder/added.txt'), 'added');
    expect(await fs.read('folder/nested/deep.txt'), 'deep');
    expect(summary.created, 3);
    expect(summary.replaced, 1);
    expect(summary.skipped, 0);
  });

  test('a file can replace a folder and a folder can replace a file', () async {
    final project = await Directory.systemTemp.createTemp('praxis_replace_');
    final source = await Directory.systemTemp.createTemp('praxis_source_');
    addTearDown(() => project.delete(recursive: true));
    addTearDown(() => source.delete(recursive: true));
    final fs = ProjectFs(project);

    await fs.write('assets/old.txt', 'old directory content');
    final fileReplacement = File('${source.path}/assets');
    await fileReplacement.writeAsString('now a file');

    var prompts = 0;
    await importEntries(
      fs,
      [
        ImportEntry(
          path: 'assets',
          sourcePath: fileReplacement.path,
          isDir: false,
        ),
      ],
      onConflict: (_) async {
        prompts++;
        return true;
      },
    );
    expect(prompts, 1);
    expect(await fs.read('assets'), 'now a file');

    await fs.write('notes', 'old file');
    final folderReplacement = Directory('${source.path}/notes');
    await folderReplacement.create();
    await File('${folderReplacement.path}/inside.txt').writeAsString('inside');

    await importEntries(
      fs,
      [
        ImportEntry(
          path: 'notes',
          sourcePath: folderReplacement.path,
          isDir: true,
        ),
        ImportEntry(
          path: 'notes/inside.txt',
          sourcePath: '${folderReplacement.path}/inside.txt',
          isDir: false,
        ),
      ],
      onConflict: (_) async {
        prompts++;
        return true;
      },
    );
    expect(prompts, 2);
    expect(await fs.isDirectory('notes'), isTrue);
    expect(await fs.read('notes/inside.txt'), 'inside');
  });

  test('declining a folder conflict skips that folder\'s children', () async {
    final project = await Directory.systemTemp.createTemp('praxis_keep_');
    final source = await Directory.systemTemp.createTemp('praxis_source_');
    addTearDown(() => project.delete(recursive: true));
    addTearDown(() => source.delete(recursive: true));
    final fs = ProjectFs(project);

    await fs.write('assets', 'keep the existing file');
    final folder = Directory('${source.path}/assets');
    await folder.create();
    await File('${folder.path}/inside.txt').writeAsString('do not import');

    var prompts = 0;
    final summary = await importEntries(
      fs,
      [
        ImportEntry(
          path: 'assets',
          sourcePath: folder.path,
          isDir: true,
        ),
        ImportEntry(
          path: 'assets/inside.txt',
          sourcePath: '${folder.path}/inside.txt',
          isDir: false,
        ),
      ],
      onConflict: (_) async {
        prompts++;
        return false;
      },
    );

    expect(prompts, 1);
    expect(summary.skipped, 2);
    expect(summary.failed, isEmpty);
    expect(await fs.read('assets'), 'keep the existing file');
  });

  test('a final answer with no mutation gets one corrective round', () async {
    final temp = await Directory.systemTemp.createTemp('praxis_nudge_');
    addTearDown(() => temp.delete(recursive: true));
    final fs = ProjectFs(temp);
    await fs.write('README.md', '# Project');

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
                  'content': 'Done — no changes were needed.',
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
                'message': {
                  'role': 'assistant',
                  'content': '',
                  'tool_calls': [
                    {
                      'id': 'edit_1',
                      'type': 'function',
                      'function': {
                        'name': 'edit_file',
                        'arguments': jsonEncode({
                          'path': 'README.md',
                          'old_text': '# Project',
                          'new_text': '# Project\n\nUpdated.',
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
                'content': 'Updated the README.',
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    var discarded = 0;
    final events = <AgentEvent>[];
    await Agent(
      client: AiClient(client: client),
      provider: const ProviderConfig(
        id: 'test',
        name: 'Test',
        icon: 'x',
        baseUrl: 'https://example.test/v1',
        model: 'model',
        flavor: ApiFlavor.openai,
        keys: ['key'],
      ),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: events.add,
      onDiscardLive: () => discarded++,
    ).run(history: const [], prompt: 'update the README');

    expect(calls, 3);
    expect(discarded, 1);
    expect(await fs.read('README.md'), contains('Updated.'));
    expect(events.last.text, contains('Updated the README'));
    expect(
      events.any((event) =>
          event.kind == AgentEventKind.text &&
          event.text.contains('no changes were needed')),
      isFalse,
    );
  });

  test('a missing branch in a non-empty repository is not seeded', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      final path = request.url.path;
      requests.add('${request.method} $path');
      if (request.method == 'GET' && path.endsWith('/git/refs/heads/main')) {
        return http.Response('{}', 404);
      }
      if (request.method == 'GET' && path == '/repos/acme/demo') {
        return http.Response(jsonEncode({'default_branch': 'master'}), 200);
      }
      if (request.method == 'GET' && path.endsWith('/git/refs/heads/master')) {
        return http.Response(
          jsonEncode({
            'object': {'sha': 'existing-head'},
          }),
          200,
        );
      }
      fail('unexpected GitHub request: ${request.method} $path');
    });

    await expectLater(
      GitHubClient('token', client: client).createCommit(
        owner: 'acme',
        repo: 'demo',
        branch: 'main',
        message: 'change',
        files: {'README.md': utf8.encode('# hello')},
      ),
      throwsA(isA<IntegrationException>().having(
        (error) => error.message,
        'message',
        contains('Branch main does not exist'),
      )),
    );
    expect(requests.where((request) => request.startsWith('PUT')), isEmpty);
  });

  test('an empty GitHub repository is seeded by the Contents API', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      final path = request.url.path;
      requests.add('${request.method} $path');
      if (request.method == 'GET' && path.endsWith('/git/refs/heads/main')) {
        return http.Response('{}', 409);
      }
      if (request.method == 'GET' && path == '/repos/acme/demo') {
        return http.Response('{}', 200);
      }
      if (request.method == 'PUT' &&
          path == '/repos/acme/demo/contents/README.md') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['message'], 'initial commit');
        expect(body['content'], base64Encode(utf8.encode('# hello')));
        return http.Response(
          jsonEncode({
            'commit': {
              'sha': 'seed-sha',
              'tree': {'sha': 'seed-tree'},
            },
          }),
          201,
        );
      }
      fail('unexpected GitHub request: ${request.method} $path');
    });

    final commit = await GitHubClient('token', client: client).createCommit(
      owner: 'acme',
      repo: 'demo',
      branch: 'main',
      message: 'initial commit',
      files: {'README.md': utf8.encode('# hello')},
    );

    expect(commit.sha, 'seed-sha');
    expect(commit.treeSha, 'seed-tree');
    expect(requests, contains('PUT /repos/acme/demo/contents/README.md'));
    expect(
        requests.where((request) => request.contains('/git/blobs')), isEmpty);
  });
}
