import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/file_types.dart';
import 'package:praxis/core/integrations.dart';
import 'package:praxis/core/push_state.dart';
import 'package:praxis/core/store.dart';
import 'package:praxis/models.dart';
import 'package:praxis/state/app_state.dart';

void main() {
  test('a branch comparison fetches only changed text and reuses it', () async {
    final temp = await Directory.systemTemp.createTemp('praxis_push_baseline_');
    final readmeHash = gitBlobSha(utf8.encode('# Base\n'));
    final mainHash = gitBlobSha(utf8.encode('void main() {}\n'));
    final imageHash = gitBlobSha([0, 1, 2]);
    final requests = <String>[];
    final state = AppState(
      root: temp,
      store: MemoryStore(),
      seedWelcome: false,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        requests.add(path);
        if (path.endsWith('/git/refs/heads/master') ||
            path.endsWith('/git/refs/heads/main')) {
          return http.Response(
            jsonEncode({
              'object': {'sha': 'commit-head'},
            }),
            200,
          );
        }
        if (path.endsWith('/git/trees/commit-head')) {
          return http.Response(
            jsonEncode({
              'sha': 'tree-head',
              'tree': [
                {
                  'path': 'README.md',
                  'type': 'blob',
                  'sha': readmeHash,
                  'size': 7,
                },
                {
                  'path': 'lib/main.dart',
                  'type': 'blob',
                  'sha': mainHash,
                  'size': 16,
                },
                {
                  'path': 'assets/logo.png',
                  'type': 'blob',
                  'sha': imageHash,
                  'size': 3,
                },
              ],
            }),
            200,
          );
        }
        if (path.endsWith('/git/blobs/$readmeHash')) {
          return http.Response(
            jsonEncode({'content': base64Encode(utf8.encode('# Base\n'))}),
            200,
          );
        }
        if (path.endsWith('/contents/lib/main.dart')) {
          return http.Response('void main() {}\n', 200);
        }
        fail('unexpected GitHub request: ${request.method} $path');
      }),
    );
    addTearDown(() async {
      state.dispose();
      await temp.delete(recursive: true);
    });
    await state.init();
    final project = await state.createProject(
      'baseline',
      ProjectKind.node,
      persistChat: false,
    );
    final fs = state.fsFor(project);
    await fs.write('README.md', '# Changed\n');
    await fs.write('lib/main.dart', 'void main() {}\n');
    await fs.writeBytes('assets/logo.png', [0, 1, 2]);
    const account = IntegrationAccount(
      id: 'github-account',
      kind: IntegrationKind.github,
      label: '',
      username: 'acme',
      token: 'token',
    );

    final master = await state.syncPushBaseline(
      project,
      account,
      owner: 'acme',
      repo: 'demo',
      branch: 'master',
    );
    expect(master.hashes['README.md'], readmeHash);
    expect(master.baseline['README.md'], '# Base\n');
    expect(master.baseline.containsKey('lib/main.dart'), isFalse);
    expect(
      requests.where((path) => path.contains('/git/blobs/')),
      hasLength(1),
    );

    final changes = await state.changesFor(project);
    final readme = changes.firstWhere((change) => change.path == 'README.md');
    expect(readme.before, '# Base\n');
    expect(readme.after, '# Changed\n');
    expect(
      changes.map((change) => change.path),
      isNot(contains('lib/main.dart')),
    );

    final main = await state.syncPushBaseline(
      project,
      account,
      owner: 'acme',
      repo: 'demo',
      branch: 'main',
    );
    expect(main.baseline['README.md'], '# Base\n');
    expect(
      requests.where((path) => path.contains('/git/blobs/')),
      hasLength(1),
    );

    await state.syncPushBaseline(
      project,
      account,
      owner: 'acme',
      repo: 'demo',
      branch: 'main',
      force: true,
    );
    expect(
      requests.where((path) => path.contains('/git/trees/')),
      hasLength(3),
    );
    expect(
      requests.where((path) => path.contains('/git/blobs/')),
      hasLength(1),
    );

    await fs.write('lib/main.dart', 'void main() { print(1); }\n');
    final edited = await state.changesFor(
      project,
      beforeText: (path) => state.githubFileText(
        account,
        owner: 'acme',
        repo: 'demo',
        branch: 'main',
        path: path,
      ),
    );
    final dart = edited.firstWhere((change) => change.path == 'lib/main.dart');
    expect(dart.before, 'void main() {}\n');
    expect(dart.added, 1);
    expect(dart.removed, 1);
  });

  test('a file changed only on GitHub is not reported as a local change',
      () async {
    final temp = await Directory.systemTemp.createTemp('praxis_push_remote_');
    final state = AppState(
      root: temp,
      store: MemoryStore(),
      seedWelcome: false,
    );
    addTearDown(() async {
      state.dispose();
      await temp.delete(recursive: true);
    });
    await state.init();
    final project = await state.createProject(
      'remote-only',
      ProjectKind.node,
      persistChat: false,
    );
    final fs = state.fsFor(project);
    await fs.write('README.md', '# Base\n');
    final baseHash = gitBlobSha(utf8.encode('# Base\n'));
    final remoteHash = gitBlobSha(utf8.encode('# Edited on GitHub\n'));
    await state.savePushState(
      project,
      PushState(
        owner: 'acme',
        repo: 'demo',
        branch: 'main',
        hashes: {'README.md': remoteHash},
        baseHashes: {'README.md': baseHash},
        baseline: {'README.md': '# Base\n'},
        synced: true,
      ),
    );

    final changes = await state.changesFor(project);
    expect(changes.map((change) => change.path), isNot(contains('README.md')));
    expect(await state.remoteDriftFor(project), ['README.md']);

    // A real local edit is still detected against the same merge base.
    await fs.write('README.md', '# Local edit\n');
    final edited = await state.changesFor(project);
    final readme = edited.firstWhere((change) => change.path == 'README.md');
    expect(readme.before, '# Base\n');
    expect(readme.after, '# Local edit\n');
  });

  test('a file deleted after a sync becomes a deleted change', () async {
    final temp = await Directory.systemTemp.createTemp('praxis_push_delete_');
    final state = AppState(
      root: temp,
      store: MemoryStore(),
      seedWelcome: false,
    );
    addTearDown(() async {
      state.dispose();
      await temp.delete(recursive: true);
    });
    await state.init();
    final project = await state.createProject(
      'delete',
      ProjectKind.node,
      persistChat: false,
    );
    final fs = state.fsFor(project);
    await fs.write('README.md', '# Base\n');
    final hash = gitBlobSha(utf8.encode('# Base\n'));
    await state.savePushState(
      project,
      PushState(
        owner: 'acme',
        repo: 'demo',
        branch: 'main',
        hashes: {'README.md': hash},
        baseHashes: {'README.md': hash},
        baseline: {'README.md': '# Base\n'},
        synced: true,
      ),
    );

    await fs.delete('README.md');
    final changes = await state.changesFor(project);
    final removed = changes.firstWhere((change) => change.path == 'README.md');
    expect(removed.status, RepoChangeStatus.deleted);
    expect(removed.removed, greaterThan(0));
  });

  test('a locally deleted file changed on GitHub stops the pull', () async {
    final temp = await Directory.systemTemp.createTemp('praxis_pull_conflict_');
    final remoteBytes = utf8.encode('# Changed on GitHub\n');
    final archive = Archive()
      ..addFile(ArchiveFile(
        'demo-main/README.md',
        remoteBytes.length,
        remoteBytes,
      ));
    final zip = ZipEncoder().encode(archive)!;
    final state = AppState(
      root: temp,
      store: MemoryStore(),
      seedWelcome: false,
      httpClient: MockClient((request) async {
        if (request.url.host == 'codeload.github.com') {
          return http.Response.bytes(zip, 200);
        }
        fail('unexpected GitHub request: ${request.method} ${request.url}');
      }),
    );
    addTearDown(() async {
      state.dispose();
      await temp.delete(recursive: true);
    });
    await state.init();
    final project = await state.createProject(
      'conflict',
      ProjectKind.node,
      persistChat: false,
    );
    final fs = state.fsFor(project);
    await fs.write('README.md', '# Base\n');
    final base = gitBlobSha(utf8.encode('# Base\n'));
    await state.savePushState(
      project,
      PushState(
        owner: 'acme',
        repo: 'demo',
        branch: 'main',
        hashes: {'README.md': base},
        baseHashes: {'README.md': base},
        baseline: {'README.md': '# Base\n'},
        synced: true,
      ),
    );
    await fs.delete('README.md');
    const account = IntegrationAccount(
      id: 'github-account',
      kind: IntegrationKind.github,
      label: '',
      username: 'acme',
      token: 'token',
    );

    await expectLater(
      state.pullProject(
        project,
        account,
        owner: 'acme',
        repo: 'demo',
        branch: 'main',
      ),
      throwsA(isA<IntegrationException>().having(
        (error) => error.message,
        'message',
        allOf(
          contains('README.md'),
          contains('changed locally and on GitHub'),
        ),
      )),
    );
    expect(await fs.exists('README.md'), isFalse);
  });
}
