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

  test('a folder with an existing name merges from its real contents',
      () async {
    final project = await Directory.systemTemp.createTemp('praxis_existing_');
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

  test('a same-name folder import through AppState reports merged files',
      () async {
    final project =
        await Directory.systemTemp.createTemp('praxis_existing_ui_');
    final source = await Directory.systemTemp.createTemp('praxis_source_ui_');
    addTearDown(() => project.delete(recursive: true));
    addTearDown(() => source.delete(recursive: true));
    final state =
        AppState(root: project, store: MemoryStore(), seedWelcome: false);
    addTearDown(state.dispose);
    await state.init();
    final target =
        await state.createProject('import-target', ProjectKind.blank);
    final fs = state.fsFor(target);

    await fs.write('folder/updated.txt', 'old');
    final sourceFolder = Directory('${source.path}/folder');
    await sourceFolder.create(recursive: true);
    await File('${sourceFolder.path}/updated.txt').writeAsString('new');
    await File('${sourceFolder.path}/added.txt').writeAsString('added');

    final summary = await state.importIntoProject(
      target,
      [
        ImportEntry(
          path: 'folder',
          sourcePath: '${sourceFolder.path}/',
          isDir: true,
        ),
      ],
      onConflict: (_) async => true,
    );

    expect(summary.merged, 1);
    expect(summary.created, 1);
    expect(summary.replaced, 1);
    expect(summary.changed, 2);
    expect(summary.message, isNot('Nothing was imported.'));
    expect(summary.message, contains('merged'));
    expect(await fs.read('folder/updated.txt'), 'new');
    expect(await fs.read('folder/added.txt'), 'added');
  });

  test('projects with the latest conversation sort first', () async {
    final temp = await Directory.systemTemp.createTemp('praxis_order_');
    addTearDown(() => temp.delete(recursive: true));
    final state =
        AppState(root: temp, store: MemoryStore(), seedWelcome: false);
    addTearDown(state.dispose);
    await state.init();

    final older = await state.createProject('older', ProjectKind.blank);
    final newer = await state.createProject('newer', ProjectKind.blank);
    expect(state.projectsByActivity.first.id, newer.id);

    state.threadOf(older.id).add(ChatEntry(
          id: 'latest',
          role: ChatRole.assistant,
          text: 'A newer conversation message.',
          at: DateTime.now().add(const Duration(minutes: 1)),
        ));

    expect(state.projectsByActivity.first.id, older.id);
  });

  test('reset removes saved project transcripts as well as project files',
      () async {
    final temp = await Directory.systemTemp.createTemp('praxis_reset_');
    final store = MemoryStore();
    final state = AppState(root: temp, store: store, seedWelcome: false);
    addTearDown(() async {
      state.dispose();
      await temp.delete(recursive: true);
    });
    await state.init();
    final project = await state.createProject('reset', ProjectKind.blank);
    await store.write('praxis.chat.${project.id}', '[{"text":"private"}]');
    await store.write('praxis.liveDraft', '{"text":"private"}');

    await state.resetEverything();

    expect(store.read('praxis.chat.${project.id}'), isNull);
    expect(store.read('praxis.liveDraft'), isNull);
    expect(
      await Directory('${temp.path}/projects/${project.id}').exists(),
      isFalse,
    );
    // Reset starts over with the welcome project, not an empty project list.
    expect(state.projects.single.name, 'hello-praxis');
  });

  test('a final answer with no mutation completes without a forced edit',
      () async {
    final temp = await Directory.systemTemp.createTemp('praxis_no_edit_');
    addTearDown(() => temp.delete(recursive: true));
    final fs = ProjectFs(temp);
    await fs.write('README.md', '# Project');

    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': 'No changes were needed: README.md is already '
                    'correct and the request is satisfied.',
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    var discarded = 0;
    String? paused;
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
      onPause: (message) => paused = message,
    ).run(history: const [], prompt: 'update the README');

    expect(calls, 1);
    expect(discarded, 0);
    expect(await fs.read('README.md'), '# Project');
    expect(events.last.kind, AgentEventKind.text);
    expect(events.last.text, contains('No changes were needed'));
    expect(events.any((event) => event.kind == AgentEventKind.error), isFalse);
    expect(paused, isNull);
  });

  test('a closing offer to run checks is a complete answer', () async {
    final temp = await Directory.systemTemp.createTemp('praxis_closing_');
    addTearDown(() => temp.delete(recursive: true));
    final fs = ProjectFs(temp);
    await fs.write('README.md', '# Project');

    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': 'No changes were needed: README.md is already '
                    'correct. Let me know if you want me to run the tests.',
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    var discarded = 0;
    String? paused;
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
      onPause: (message) => paused = message,
    ).run(history: const [], prompt: 'update the README');

    expect(calls, 1);
    expect(discarded, 0);
    expect(events.last.text, contains('Let me know'));
    expect(events.any((event) => event.kind == AgentEventKind.error), isFalse);
    expect(paused, isNull);
  });

  test('an explanation question is not pushed into editing files', () async {
    final temp = await Directory.systemTemp.createTemp('praxis_explain_');
    addTearDown(() => temp.delete(recursive: true));
    final fs = ProjectFs(temp);
    await fs.write('README.md', '# Project');

    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': 'Let me walk through it. The update flow reads '
                    'README.md, sends it to GitHub, then writes the returned '
                    'version back.',
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
    ).run(history: const [], prompt: 'explain how the update flow works');

    expect(calls, 1);
    expect(discarded, 0);
    expect(await fs.read('README.md'), '# Project');
    expect(events.last.text, contains('Let me walk through it'));
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
