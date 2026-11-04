import 'dart:convert';
import 'dart:io';

import 'package:devnest/core/agent.dart';
import 'package:devnest/core/ai.dart';
import 'package:devnest/core/diff.dart';
import 'package:devnest/core/shell.dart';
import 'package:devnest/core/system_shell.dart';
import 'package:devnest/core/vfs.dart';
import 'package:devnest/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('diff', () {
    test('tracks added and removed lines with line numbers', () {
      final diff = computeDiff('a\nb\nc', 'a\nB\nc\nd');
      expect(diff.added, 2);
      expect(diff.removed, 1);
      final added = diff.rows.where((row) => row.kind == DiffKind.added);
      expect(added.map((row) => row.text), containsAll(['B', 'd']));
      final removed = diff.rows.where((row) => row.kind == DiffKind.removed);
      expect(removed.single.text, 'b');
      expect(removed.single.oldLine, 2);
      final roundTrip = FileDiff.decode(diff.toJson());
      expect(roundTrip?.added, 2);
      expect(roundTrip?.rows.length, diff.rows.length);
    });

    test('an identical file produces no rows', () {
      final diff = computeDiff('same', 'same');
      expect(diff.isEmpty, isTrue);
      expect(diff.rows, isEmpty);
    });
  });

  group('provider keys', () {
    test('legacy apiKey loads as the first key', () {
      final provider = ProviderConfig.fromJson({
        'id': 'old',
        'name': 'Old',
        'icon': 'x',
        'baseUrl': 'https://example.test/v1',
        'model': 'm',
        'flavor': 'openai',
        'apiKey': 'legacy-key',
      });
      expect(provider.keys, ['legacy-key']);
      expect(provider.apiKey, 'legacy-key');
      expect(provider.ready, isTrue);
      expect(provider.hasMoreKeys, isFalse);
    });

    test('the active key follows keyIndex', () {
      const provider = ProviderConfig(
        id: 'p',
        name: 'P',
        icon: 'x',
        baseUrl: 'https://example.test/v1',
        model: 'm',
        flavor: ApiFlavor.openai,
        keys: ['one', 'two'],
        keyIndex: 1,
      );
      expect(provider.apiKey, 'two');
      expect(provider.hasMoreKeys, isFalse);
    });
  });

  group('provider responses', () {
    test('reasoning is parsed into thinking text', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': 'Done.',
                    'reasoning_content': 'Checked the file first.',
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final reply = await AiClient(client: client).complete(
        provider: const ProviderConfig(
          id: 'p',
          name: 'P',
          icon: 'x',
          baseUrl: 'https://example.test/v1',
          model: 'm',
          flavor: ApiFlavor.openai,
          keys: ['k'],
        ),
        system: 's',
        turns: const [AiTurn.user('hi')],
        tools: const [],
      );
      expect(reply.text, 'Done.');
      expect(reply.thinking, 'Checked the file first.');
    });

    test('model list is cleaned and sorted', () async {
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/models'));
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'zeta'},
              {'id': 'alpha'},
              {'id': 'models/beta'},
            ],
          }),
          200,
        );
      });
      final models = await AiClient(client: client).listModels(
        const ProviderConfig(
          id: 'p',
          name: 'P',
          icon: 'x',
          baseUrl: 'https://example.test/v1',
          model: 'm',
          flavor: ApiFlavor.openai,
          keys: ['k'],
        ),
      );
      expect(models, ['alpha', 'beta', 'zeta']);
    });
  });

  test('a quota error fails over to the second key', () async {
    final auths = <String>[];
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      auths.add(request.headers['Authorization'] ?? '');
      if (calls == 1) {
        return http.Response(
          jsonEncode({
            'error': {'message': 'quota exceeded for this key'},
          }),
          429,
        );
      }
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'Recovered.'},
            },
          ],
        }),
        200,
      );
    });
    final temp = await Directory.systemTemp.createTemp('devnest_keys_');
    addTearDown(() => temp.delete(recursive: true));
    final fs = ProjectFs(temp);
    final events = <AgentEvent>[];

    await Agent(
      client: AiClient(client: client),
      provider: const ProviderConfig(
        id: 'p',
        name: 'P',
        icon: 'x',
        baseUrl: 'https://example.test/v1',
        model: 'm',
        flavor: ApiFlavor.openai,
        keys: ['first', 'second'],
      ),
      fs: fs,
      shell: Shell(fs),
      skills: const [],
      onEvent: events.add,
      onProviderLimit: (current, error) async => current.copyWith(keyIndex: 1),
    ).run(history: const [], prompt: 'hello');

    expect(calls, 2);
    expect(auths.last, 'Bearer second');
    expect(events.last.text, 'Recovered.');
  });

  test('the device shell runs real commands in the project folder', () async {
    if (Platform.isAndroid) return;
    final temp = await Directory.systemTemp.createTemp('devnest_sh_');
    addTearDown(() => temp.delete(recursive: true));
    final fs = ProjectFs(temp);
    final shell = SystemShell(fs);

    final echo = await shell.run('echo hello');
    expect(echo.output.trim(), 'hello');
    expect(echo.exitCode, 0);

    await Directory('${temp.path}/sub').create();
    final cd = await shell.run('cd sub');
    expect(cd.exitCode, 0);
    final pwd = await shell.run('pwd');
    expect(pwd.output.trim(), endsWith('/sub'));

    final failure = await shell.run('false');
    expect(failure.exitCode, isNot(0));
  });
}
