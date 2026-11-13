import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis/core/agent.dart';
import 'package:praxis/core/ai.dart';
import 'package:praxis/core/project_env.dart';
import 'package:praxis/core/deploy_logs.dart';
import 'package:praxis/core/shell.dart';
import 'package:praxis/core/vfs.dart';
import 'package:praxis/models.dart';

void main() {
  late Directory temp;
  late ProjectFs fs;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('praxis_env_');
    fs = ProjectFs(temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  ProviderConfig provider() => const ProviderConfig(
        id: 'openai',
        name: 'Test',
        icon: 'x',
        baseUrl: 'https://example.test/v1',
        model: 'model',
        flavor: ApiFlavor.openai,
        keys: ['key'],
      );

  http.Response reply(String content) => http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': content},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );

  test('secret values never enter the model request, but names do', () async {
    await fs.write('README.md', '# Project');
    await ProjectEnvStore.save(fs, const [
      ProjectEnvEntry(
        name: 'PUBLIC_API_URL',
        value: 'https://public.example.test',
      ),
      ProjectEnvEntry(
        name: 'PRIVATE_TOKEN',
        value: 's3cr3t-value-that-must-not-leak',
        secret: true,
      ),
    ]);

    final bodies = <String>[];
    final client = MockClient((request) async {
      bodies.add(request.body);
      return reply('Project ready.');
    });

    await Agent(
      client: AiClient(client: client),
      provider: provider(),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: (_) {},
    ).run(history: const [], prompt: 'Summarize this project');

    final request = bodies.join('\n');
    expect(request, contains('PUBLIC_API_URL'));
    expect(request, contains('https://public.example.test'));
    expect(request, contains('PRIVATE_TOKEN'));
    expect(request, isNot(contains('s3cr3t-value-that-must-not-leak')));
  });

  test('every secret value is masked, including repeated occurrences', () {
    const entries = [
      ProjectEnvEntry(name: 'PUBLIC', value: 'public-value'),
      ProjectEnvEntry(name: 'TOKEN', value: 'token-value', secret: true),
      ProjectEnvEntry(
          name: 'LONG_TOKEN', value: 'token-value-extra', secret: true),
    ];
    const logs = 'public-value token-value token-value token-value-extra';

    final masked = maskSecretValues(logs, entries);

    expect(masked, contains('public-value'));
    expect(masked, contains('[secret:TOKEN]'));
    expect(masked, contains('[secret:LONG_TOKEN]'));
    expect(masked, isNot(contains('token-value')));
    expect(masked, isNot(contains('token-value-extra')));
  });

  test('the environment store round-trips values and secret flags', () async {
    await ProjectEnvStore.save(fs, const [
      ProjectEnvEntry(name: 'PORT', value: '3000'),
      ProjectEnvEntry(name: 'TOKEN', value: 'hidden', secret: true),
    ]);

    final loaded = await ProjectEnvStore.load(fs);

    expect(loaded.map((entry) => entry.name), ['PORT', 'TOKEN']);
    expect(loaded.first.value, '3000');
    expect(loaded.last.secret, isTrue);
    expect(ProjectEnvStore.values(loaded), {
      'PORT': '3000',
      'TOKEN': 'hidden',
    });
  });

  test('last deploy logs round-trip through the project store', () async {
    final record = LastDeployLog(
      runtime: 'Cloudflare Pages',
      message: 'Deployed 4 files',
      logs: 'line one\nline two',
      at: DateTime.utc(2026, 11, 12, 12),
      url: 'https://example.pages.dev',
      deploymentId: 'deploy-1',
      success: false,
    );

    await DeployLogStore.save(fs, record);
    final loaded = await DeployLogStore.load(fs);

    expect(loaded, isNotNull);
    expect(loaded!.runtime, 'Cloudflare Pages');
    expect(loaded.logs, 'line one\nline two');
    expect(loaded.deploymentId, 'deploy-1');
    expect(loaded.success, isFalse);
  });
}
