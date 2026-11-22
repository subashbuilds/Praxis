import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/store.dart';
import 'package:praxis/models.dart';
import 'package:praxis/state/app_state.dart';

void main() {
  http.Response jsonResponse(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );

  Future<Directory> tempRoot() async {
    final root = await Directory.systemTemp.createTemp('praxis_gh_logs_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    return root;
  }

  Project project() => Project(
        id: 'project-1',
        name: 'Project',
        kind: ProjectKind.web,
        createdAt: DateTime.utc(2026, 11, 12),
      );

  test('GitHub logs resolve a run URL and download failing job logs', () async {
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/actions/runs/42/jobs')) {
        return jsonResponse({
          'jobs': [
            {
              'id': 10,
              'name': 'build',
              'status': 'completed',
              'conclusion': 'failure',
              'steps': [
                {
                  'name': 'Compile',
                  'conclusion': 'failure',
                },
              ],
            },
          ],
        });
      }
      if (path.endsWith('/actions/jobs/10/logs')) {
        return http.Response('compile failed: missing dependency\n', 200);
      }
      return http.Response('not found', 404);
    });
    final root = await tempRoot();
    final state = AppState(
      root: root,
      store: MemoryStore(),
      httpClient: client,
      seedWelcome: false,
    );
    addTearDown(state.dispose);
    state.integrations = const Integrations(
      accounts: [
        IntegrationAccount(
          id: 'gh-1',
          kind: IntegrationKind.github,
          label: 'GitHub',
          username: 'owner',
          token: 'token',
        ),
      ],
      activeGithubId: 'gh-1',
    );

    final result = await state.integrationStatusForAgent(
      project(),
      'github',
      'logs',
      'https://github.com/owner/repo/actions/runs/42',
    );

    expect(result, contains('GitHub Actions run 42 in owner/repo'));
    expect(result, contains('Compile'));
    expect(result, contains('compile failed: missing dependency'));
    expect(result, isNot(contains('Pass the numeric')));
  });

  test('GitHub logs can target any job by id or name', () async {
    final requested = <String>[];
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/actions/runs/42/jobs')) {
        return jsonResponse({
          'jobs': [
            {
              'id': 10,
              'name': 'build',
              'status': 'completed',
              'conclusion': 'failure',
            },
            {
              'id': 11,
              'name': 'test',
              'status': 'completed',
              'conclusion': 'failure',
            },
            {
              'id': 12,
              'name': 'lint (ubuntu-latest)',
              'status': 'completed',
              'conclusion': 'success',
            },
            {
              'id': 14,
              'name': 'test (integration)',
              'status': 'completed',
              'conclusion': 'failure',
            },
          ],
        });
      }
      final jobLog = RegExp(r'/actions/jobs/(\d+)/logs').firstMatch(path);
      if (jobLog != null) {
        final id = jobLog.group(1)!;
        requested.add(id);
        return http.Response('log from job $id\n', 200);
      }
      return http.Response('not found', 404);
    });
    final root = await tempRoot();
    final state = AppState(
      root: root,
      store: MemoryStore(),
      httpClient: client,
      seedWelcome: false,
    );
    addTearDown(state.dispose);
    state.integrations = const Integrations(
      accounts: [
        IntegrationAccount(
          id: 'gh-1',
          kind: IntegrationKind.github,
          label: 'GitHub',
          username: 'owner',
          token: 'token',
        ),
      ],
      activeGithubId: 'gh-1',
    );

    final failing = await state.integrationStatusForAgent(
      project(),
      'github',
      'logs',
      'https://github.com/owner/repo/actions/runs/42',
    );
    expect(requested, ['10', '11']);
    expect(failing, contains('log from job 10'));
    expect(failing, contains('log from job 11'));
    expect(failing, isNot(contains('log from job 12')));
    expect(failing, contains('lint (ubuntu-latest) (job 12)'));
    expect(failing, contains('To read another job from this run'));

    requested.clear();
    final byId = await state.integrationStatusForAgent(
      project(),
      'github',
      'logs',
      'https://github.com/owner/repo/actions/runs/42/job/12',
    );
    expect(requested, ['12']);
    expect(byId, contains('log from job 12'));
    expect(byId, isNot(contains('log from job 10')));

    requested.clear();
    final byName = await state.integrationStatusForAgent(
      project(),
      'github',
      'logs',
      'owner/repo/actions/runs/42/job/lint',
    );
    expect(byName, contains('log from job 12'), reason: byName);
    expect(requested, ['12']);

    // A full job name wins over another job whose name only contains it.
    requested.clear();
    final exactName = await state.integrationStatusForAgent(
      project(),
      'github',
      'logs',
      'owner/repo/actions/runs/42/job/test',
    );
    expect(exactName, contains('log from job 11'));
    expect(exactName, isNot(contains('log from job 14')));
    expect(requested, ['11']);

    // A bare run id with a job query also works.
    requested.clear();
    final byQuery = await state.integrationStatusForAgent(
      project(),
      'github',
      'logs',
      'owner/repo/actions/runs/42?job=12',
    );
    expect(byQuery, contains('log from job 12'));
    expect(requested, ['12']);

    requested.clear();
    final missing = await state.integrationStatusForAgent(
      project(),
      'github',
      'logs',
      'owner/repo/actions/runs/42/job/deploy',
    );
    expect(requested, isEmpty);
    expect(missing, contains('No job matched "deploy"'));
  });

  test('a long GitHub job log is readable from end to start with offsets',
      () async {
    final fullLog = StringBuffer('FIRST-LINE-OF-BUILD\n');
    for (var index = 0; index < 1500; index++) {
      fullLog.writeln('build line $index ${'x' * 24}');
    }
    fullLog.write('REAL-FAILURE: missing dependency\n');
    expect(fullLog.length, greaterThan(48000));

    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/actions/runs/9/jobs')) {
        return jsonResponse({
          'jobs': [
            {
              'id': 77,
              'name': 'android',
              'status': 'completed',
              'conclusion': 'failure',
              'steps': [
                {'name': 'Assemble', 'conclusion': 'failure'},
              ],
            },
          ],
        });
      }
      if (path.endsWith('/actions/jobs/77/logs')) {
        return http.Response(fullLog.toString(), 200);
      }
      return http.Response('not found', 404);
    });
    final root = await tempRoot();
    final state = AppState(
      root: root,
      store: MemoryStore(),
      httpClient: client,
      seedWelcome: false,
    );
    addTearDown(state.dispose);
    state.integrations = const Integrations(
      accounts: [
        IntegrationAccount(
          id: 'gh-1',
          kind: IntegrationKind.github,
          label: 'GitHub',
          username: 'owner',
          token: 'token',
        ),
      ],
      activeGithubId: 'gh-1',
    );

    final end = await state.integrationStatusForAgent(
      project(),
      'github',
      'logs',
      'owner/repo/actions/runs/9',
    );
    expect(end, contains('REAL-FAILURE'));
    expect(end, contains('Earlier log: call with offset 0.'));
    expect(end, isNot(contains('FIRST-LINE-OF-BUILD')));

    final start = await state.integrationStatusForAgent(
      project(),
      'github',
      'logs',
      'owner/repo/actions/runs/9',
      offset: 0,
    );
    expect(start, contains('FIRST-LINE-OF-BUILD'));
    expect(start, contains('[log continues at offset 16000]'));
  });
}
