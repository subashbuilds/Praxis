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
}
