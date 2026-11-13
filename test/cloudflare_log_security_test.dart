import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/deploy_logs.dart';
import 'package:praxis/core/integrations.dart';
import 'package:praxis/core/project_env.dart';
import 'package:praxis/core/store.dart';
import 'package:praxis/models.dart';
import 'package:praxis/state/app_state.dart';

void main() {
  http.Response jsonResponse(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );

  CloudflarePagesClient pagesClient(http.Client client) =>
      CloudflarePagesClient(
        'token',
        accountId: 'account-1',
        client: client,
      );

  Future<Directory> tempRoot() async {
    final root = await Directory.systemTemp.createTemp('praxis_cf_logs_');
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

  test('Pages masks a secret before the 40k log cutoff', () async {
    const secret = 'CUTOFF-SECRET-MARKER';
    final line = '${'a' * 5}$secret${'b' * 39990}';
    final client = MockClient((_) async => jsonResponse({
          'result': {
            'data': [
              {'line': line},
            ],
          },
        }));

    final logs = await pagesClient(client).deploymentLogs(
      project: 'my-site',
      deploymentId: 'deploy-1',
      secrets: const [
        ProjectEnvEntry(name: 'TOKEN', value: secret, secret: true),
      ],
    );

    expect(logs, isNot(contains(secret)));
    expect(logs, isNot(contains('RET-MARKER')));
  });

  test('agent Cloudflare logs mask a secret across the excerpt cutoff',
      () async {
    const secret = 'AGENT-SECRET-MARKER';
    final line = '${'a' * 5}$secret${'b' * 11990}';
    final root = await tempRoot();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/deployments')) {
        return jsonResponse({
          'result': [
            {'id': 'deploy-1'},
          ],
        });
      }
      return jsonResponse({
        'result': {
          'data': [
            {'line': line},
          ],
        },
      });
    });
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
          id: 'cf-1',
          kind: IntegrationKind.cloudflare,
          label: 'Cloudflare',
          username: 'owner',
          token: 'token',
          accountId: 'account-1',
        ),
      ],
      activeCloudflareId: 'cf-1',
    );
    final target = project();
    await ProjectEnvStore.save(
      state.fsFor(target),
      const [
        ProjectEnvEntry(name: 'TOKEN', value: secret, secret: true),
      ],
    );

    final result = await state.integrationStatusForAgent(
      target,
      'cloudflare',
      'logs',
      'my-site',
    );

    expect(
        result, contains('Cloudflare Pages build logs for my-site/deploy-1:'));
    expect(result, isNot(contains(secret)));
    expect(result, isNot(contains('MARKER')));
  });

  test('failed deploy logs are persisted without a raw secret', () async {
    const secret = 'FAILURE-SECRET-VALUE';
    final root = await tempRoot();
    final state = AppState(
      root: root,
      store: MemoryStore(),
      seedWelcome: false,
    );
    addTearDown(state.dispose);
    final target = project();
    final fs = state.fsFor(target);
    await ProjectEnvStore.save(
      fs,
      const [
        ProjectEnvEntry(name: 'TOKEN', value: secret, secret: true),
      ],
    );

    final record = await state.rememberDeployFailure(
      target,
      runtime: 'Cloudflare Pages',
      message: 'The build failed.',
      logs: 'before $secret after',
      deploymentId: 'deploy-failed',
    );

    final stored = await fs.read(DeployLogStore.path);
    expect(stored, isNot(contains(secret)));
    expect(stored, contains('[secret:TOKEN]'));

    final loaded = await state.lastDeployLogFor(target);
    expect(record.success, isFalse);
    expect(loaded, isNotNull);
    expect(loaded!.success, isFalse);
    expect(loaded.deploymentId, 'deploy-failed');
    expect(loaded.logs, contains('[secret:TOKEN]'));
    expect(loaded.logs, isNot(contains(secret)));
  });
}
