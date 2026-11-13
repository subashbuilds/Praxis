import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/integrations.dart';

void main() {
  test('lists existing Workers for the selected Cloudflare account', () async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://api.cloudflare.com/client/v4/accounts/'
        'account-123/workers/scripts?per_page=100',
      );
      expect(request.headers['Authorization'], 'Bearer cf-token');
      return http.Response(
        jsonEncode({
          'success': true,
          'result': [
            {'id': 'zebra-worker', 'modified_on': '2026-01-02T00:00:00Z'},
            {'id': 'api-worker', 'modified_on': '2026-01-01T00:00:00Z'},
            {'name': 'fallback-name'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final workers = await CloudflarePagesClient(
      'cf-token',
      accountId: 'account-123',
      client: client,
    ).workers();

    expect(workers.map((worker) => worker.name), [
      'api-worker',
      'fallback-name',
      'zebra-worker',
    ]);
    expect(workers.first.modifiedOn, '2026-01-01T00:00:00Z');
  });

  test('reports a Workers listing error instead of returning an empty list',
      () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'success': false,
            'errors': [
              {'message': 'Authentication error'}
            ],
          }),
          403,
          headers: {'content-type': 'application/json'},
        ));

    expect(
      () => CloudflarePagesClient(
        'bad-token',
        accountId: 'account-123',
        client: client,
      ).workers(),
      throwsA(isA<IntegrationException>()),
    );
  });
}
