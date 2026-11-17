import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/store.dart';
import 'package:praxis/models.dart';
import 'package:praxis/state/app_state.dart';

void main() {
  test('the agent can read Tavily, Supabase and Expo integrations', () async {
    final temp = await Directory.systemTemp.createTemp('praxis_agent_int_');
    addTearDown(() => temp.delete(recursive: true));
    final client = MockClient((request) async {
      final host = request.url.host;
      if (host == 'api.tavily.com') {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'title': 'Docs result',
                'url': 'https://docs.example/page',
                'content': 'A useful page about Flutter text fields.',
              },
            ],
          }),
          200,
        );
      }
      if (host == 'api.supabase.com') {
        return http.Response(
          jsonEncode([
            {
              'name': 'my-db',
              'ref': 'abcdefghijklmnopqrst',
              'region': 'us-east-1',
              'status': 'ACTIVE_HEALTHY',
              'database': {'host': 'db.example.com'},
            },
          ]),
          200,
        );
      }
      if (host == 'api.expo.dev') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final query = '${body['query']}';
        if (query.contains('Builds(')) {
          return http.Response(
            jsonEncode({
              'data': {
                'app': {
                  'byId': {
                    'id': 'app-1',
                    'name': 'My App',
                    'slug': 'my-app',
                    'builds': [
                      {
                        'id': 'BUILD-1',
                        'platform': 'ANDROID',
                        'status': 'FINISHED',
                        'createdAt': '2026-01-02T03:04:05Z',
                        'error': null,
                        'artifacts': {
                          'buildUrl': 'https://expo.dev/build/BUILD-1',
                        },
                      },
                    ],
                  },
                },
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'data': {
              'meActor': {
                '__typename': 'UserActor',
                'username': 'subash',
                'accounts': [
                  {
                    'id': 'acct-1',
                    'name': 'team',
                    'apps': [
                      {'id': 'app-1', 'name': 'My App', 'slug': 'my-app'},
                    ],
                  },
                ],
              },
            },
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });

    final state = AppState(
      root: temp,
      store: MemoryStore(),
      seedWelcome: false,
      httpClient: client,
    );
    addTearDown(state.dispose);
    await state.init();
    final project =
        await state.createProject('integrations', ProjectKind.blank);
    await state.fsFor(project).write(
          'app.json',
          jsonEncode({
            'extra': {
              'eas': {'projectId': 'app-1'},
            },
          }),
        );
    await state.saveIntegrations(const Integrations(
      accounts: [
        IntegrationAccount(
          id: 'tavily-1',
          kind: IntegrationKind.tavily,
          label: 'Tavily',
          username: 'Search',
          token: 'tvly-test',
        ),
        IntegrationAccount(
          id: 'supabase-1',
          kind: IntegrationKind.supabase,
          label: 'Supabase',
          username: 'subash',
          token: 'sbp-test',
        ),
        IntegrationAccount(
          id: 'expo-1',
          kind: IntegrationKind.expo,
          label: 'Expo',
          username: 'subash',
          token: 'expo-test',
        ),
      ],
      activeTavilyId: 'tavily-1',
      activeSupabaseId: 'supabase-1',
      activeExpoId: 'expo-1',
    ));

    final tavily = await state.integrationStatusForAgent(
      project,
      'tavily',
      'search',
      'flutter text field',
    );
    expect(tavily, contains('Docs result'));
    expect(tavily, contains('https://docs.example/page'));

    final supabase = await state.integrationStatusForAgent(
      project,
      'supabase',
      'projects',
      'my-db',
    );
    expect(supabase, contains('my-db'));
    expect(supabase, contains('abcdefghijklmnopqrst'));

    final expoBuilds = await state.integrationStatusForAgent(
      project,
      'expo',
      'builds',
      '',
    );
    expect(expoBuilds, contains('BUILD-1'));
    expect(expoBuilds, contains('FINISHED'));
    expect(expoBuilds, contains('https://expo.dev/build/BUILD-1'));

    final expoProjects = await state.integrationStatusForAgent(
      project,
      'expo',
      'projects',
      '',
    );
    expect(expoProjects, contains('My App'));
  });
}
