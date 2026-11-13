import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/integrations.dart';

void main() {
  http.Response jsonResponse(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );

  test('Pages deployment logs use the real history/logs endpoint', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return jsonResponse({
        'success': true,
        'result': {
          'data': [
            {'line': 'Building the site', 'ts': '2026-11-12T10:00:00Z'},
            {'line': 'Deployment complete', 'ts': '2026-11-12T10:00:05Z'},
          ],
        },
      });
    });
    final pages = CloudflarePagesClient(
      'token',
      accountId: 'account-1',
      client: client,
    );

    final logs = await pages.deploymentLogs(
      project: 'my-site',
      deploymentId: 'deploy-1',
      secrets: const [],
    );

    expect(requests.single.path,
        '/client/v4/accounts/account-1/pages/projects/my-site/deployments/deploy-1/history/logs');
    expect(logs, contains('Building the site'));
    expect(logs, contains('Deployment complete'));
    expect(logs, contains('2026-11-12T10:00:05Z'));
  });

  test('Pages log responses with top-level data are accepted', () async {
    final client = MockClient((request) async => jsonResponse({
          'data': [
            {'line': 'Built successfully'},
          ],
        }));
    final pages = CloudflarePagesClient(
      'token',
      accountId: 'account-1',
      client: client,
    );

    expect(
      await pages.deploymentLogs(
        project: 'my-site',
        deploymentId: 'deploy-1',
        secrets: const [],
      ),
      'Built successfully',
    );
  });

  test('latest Pages deployment id comes from the deployments endpoint',
      () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return jsonResponse({
        'result': [
          {'id': 'deploy-latest'},
        ],
      });
    });
    final pages = CloudflarePagesClient(
      'token',
      accountId: 'account-1',
      client: client,
    );

    expect(await pages.latestDeploymentId('my-site'), 'deploy-latest');
    expect(requests.single.path,
        '/client/v4/accounts/account-1/pages/projects/my-site/deployments');
    expect(requests.single.queryParameters['per_page'], '1');
  });

  test('Pages log errors are surfaced without hiding the status', () async {
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'errors': [
              {'message': 'Invalid deployment id'},
            ],
          }),
          404,
        ));
    final pages = CloudflarePagesClient(
      'token',
      accountId: 'account-1',
      client: client,
    );

    await expectLater(
      pages.deploymentLogs(
        project: 'my-site',
        deploymentId: 'missing',
        secrets: const [],
      ),
      throwsA(isA<IntegrationException>().having(
        (error) => error.message,
        'message',
        contains('404'),
      )),
    );
  });
}
